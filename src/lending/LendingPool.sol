// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IPriceOracle } from "../oracle/IPriceOracle.sol";

contract LendingPool is ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address public immutable collateralAsset;
    address public immutable debtAsset;
    IPriceOracle public immutable oracle;

    uint256 public immutable liquidationThreshold;
    uint256 public immutable liquidationBonus;
    uint256 public immutable baseRate;
    uint256 public immutable slope1;

    uint8 public immutable collateralDecimals;
    uint8 public immutable debtDecimals;

    uint256 public constant SECONDS_PER_YEAR = 365 days;
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant WAD = 1e18; // 100%

    struct Position {
        uint256 collateral;
        uint256 debtShares;
        uint256 lastInterestIndex;
    }

    mapping(address => Position) public positions;

    uint256 public totalDebt;
    uint256 public totalDebtShares;
    uint256 public totalCollateral;
    uint256 public borrowIndex;
    uint256 public lastUpdate;

    uint256 public totalLiquidityShares;
    mapping(address => uint256) public liquidityShares;

    error InsufficientCollateral();
    error HealthFactorTooLow();
    error NotLiquidatable();
    error ZeroAmount();
    error TransferFailed();

    event CollateralDeposited(address indexed user, uint256 amount);
    event CollateralWithdrawn(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount, uint256 shares);
    event Repaid(address indexed user, uint256 amount, uint256 shares);
    event Liquidated(
        address indexed liquidator, address indexed user, uint256 debtCovered, uint256 collateralLiquidated
    );
    event InterestAccrued(uint256 newTotalDebt, uint256 newBorrowIndex);
    event LiquiditySupplied(address indexed user, uint256 amount, uint256 shares);
    event LiquidityWithdrawn(address indexed user, uint256 amount, uint256 shares);

    constructor(
        address _collateralAsset,
        address _debtAsset,
        address _oracle,
        uint256 _liquidationThreshold,
        uint256 _liquidationBonus,
        uint256 _baseRate,
        uint256 _slope1,
        address _admin
    ) {
        collateralAsset = _collateralAsset;
        debtAsset = _debtAsset;
        oracle = IPriceOracle(_oracle);
        liquidationThreshold = _liquidationThreshold;
        liquidationBonus = _liquidationBonus;
        baseRate = _baseRate;
        slope1 = _slope1;

        if (_collateralAsset == address(0)) {
            collateralDecimals = 18;
        } else {
            collateralDecimals = IERC20Metadata(_collateralAsset).decimals();
        }
        debtDecimals = IERC20Metadata(_debtAsset).decimals();

        borrowIndex = WAD;
        lastUpdate = block.timestamp;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function accrueInterest() public {
        if (block.timestamp == lastUpdate) return;
        uint256 dt = block.timestamp - lastUpdate;
        lastUpdate = block.timestamp;

        if (totalDebt == 0) return;

        uint256 availableLiquidity = IERC20(debtAsset).balanceOf(address(this));
        uint256 utilizationRate = 0;
        if (availableLiquidity + totalDebt > 0) {
            utilizationRate = (totalDebt * WAD) / (availableLiquidity + totalDebt);
        }

        uint256 borrowRateBPS = baseRate + (utilizationRate * slope1) / WAD;
        uint256 interestFactor = (borrowRateBPS * WAD * dt) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);

        uint256 newDebt = totalDebt + (totalDebt * interestFactor) / WAD;
        borrowIndex = borrowIndex + (borrowIndex * interestFactor) / WAD;
        totalDebt = newDebt;

        emit InterestAccrued(totalDebt, borrowIndex);
    }

    function supply(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();

        uint256 poolAssets = IERC20(debtAsset).balanceOf(address(this)) + totalDebt;
        uint256 shares = totalLiquidityShares == 0 ? amount : (amount * totalLiquidityShares) / poolAssets;

        liquidityShares[msg.sender] += shares;
        totalLiquidityShares += shares;

        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), amount);
        emit LiquiditySupplied(msg.sender, amount, shares);
    }

    function withdraw(uint256 shares) external nonReentrant whenNotPaused returns (uint256 amount) {
        if (shares == 0) revert ZeroAmount();
        accrueInterest();

        uint256 poolAssets = IERC20(debtAsset).balanceOf(address(this)) + totalDebt;
        amount = (shares * poolAssets) / totalLiquidityShares;

        liquidityShares[msg.sender] -= shares;
        totalLiquidityShares -= shares;

        if (IERC20(debtAsset).balanceOf(address(this)) < amount) revert TransferFailed();

        IERC20(debtAsset).safeTransfer(msg.sender, amount);
        emit LiquidityWithdrawn(msg.sender, amount, shares);
    }

    function withdrawAssets(uint256 amount) external nonReentrant whenNotPaused returns (uint256 shares) {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();

        uint256 poolAssets = IERC20(debtAsset).balanceOf(address(this)) + totalDebt;
        shares = (amount * totalLiquidityShares + poolAssets - 1) / poolAssets; // round up shares

        liquidityShares[msg.sender] -= shares;
        totalLiquidityShares -= shares;

        if (IERC20(debtAsset).balanceOf(address(this)) < amount) revert TransferFailed();

        IERC20(debtAsset).safeTransfer(msg.sender, amount);
        emit LiquidityWithdrawn(msg.sender, amount, shares);
    }

    function getSupplyValue(address user) public view returns (uint256) {
        if (totalLiquidityShares == 0) return 0;
        
        uint256 simulatedTotalDebt = totalDebt;
        if (block.timestamp > lastUpdate && totalDebt > 0) {
            uint256 dt = block.timestamp - lastUpdate;
            uint256 availableLiquidity = IERC20(debtAsset).balanceOf(address(this));
            uint256 utilizationRate = 0;
            if (availableLiquidity + totalDebt > 0) {
                utilizationRate = (totalDebt * WAD) / (availableLiquidity + totalDebt);
            }
            uint256 borrowRateBPS = baseRate + (utilizationRate * slope1) / WAD;
            uint256 interestFactor = (borrowRateBPS * WAD * dt) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);
            simulatedTotalDebt += (totalDebt * interestFactor) / WAD;
        }

        uint256 poolAssets = IERC20(debtAsset).balanceOf(address(this)) + simulatedTotalDebt;
        return (liquidityShares[user] * poolAssets) / totalLiquidityShares;
    }

    function depositCollateral(uint256 amount) external payable nonReentrant whenNotPaused {
        if (collateralAsset == address(0)) {
            amount = msg.value;
        }
        if (amount == 0) revert ZeroAmount();

        accrueInterest();

        positions[msg.sender].collateral += amount;
        totalCollateral += amount;

        if (collateralAsset != address(0)) {
            if (msg.value > 0) revert TransferFailed(); // cannot send ETH when depositing ERC20
            IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), amount);
        }

        emit CollateralDeposited(msg.sender, amount);
    }

    function withdrawCollateral(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();

        Position storage pos = positions[msg.sender];
        if (pos.collateral < amount) revert InsufficientCollateral();

        pos.collateral -= amount;
        totalCollateral -= amount;

        if (pos.debtShares > 0) {
            if (healthFactor(msg.sender) < WAD) revert HealthFactorTooLow();
        }

        _transferCollateral(msg.sender, amount);

        emit CollateralWithdrawn(msg.sender, amount);
    }

    function borrow(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();

        Position storage pos = positions[msg.sender];

        uint256 shares = totalDebtShares == 0 ? amount : (amount * totalDebtShares) / totalDebt;

        pos.debtShares += shares;
        totalDebtShares += shares;
        totalDebt += amount;

        if (healthFactor(msg.sender) < WAD) revert HealthFactorTooLow();

        IERC20(debtAsset).safeTransfer(msg.sender, amount);

        emit Borrowed(msg.sender, amount, shares);
    }

    function repay(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        accrueInterest();

        Position storage pos = positions[msg.sender];
        if (pos.debtShares == 0) return;

        uint256 userDebt = (pos.debtShares * totalDebt) / totalDebtShares;
        uint256 sharesToBurn;

        if (amount >= userDebt) {
            amount = userDebt;
            sharesToBurn = pos.debtShares;
        } else {
            sharesToBurn = (amount * totalDebtShares) / totalDebt;
        }

        pos.debtShares -= sharesToBurn;
        totalDebtShares -= sharesToBurn;
        totalDebt -= amount;

        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), amount);

        emit Repaid(msg.sender, amount, sharesToBurn);
    }

    function liquidate(address user, uint256 debtToCover) external nonReentrant whenNotPaused {
        if (debtToCover == 0) revert ZeroAmount();
        accrueInterest();

        if (healthFactor(user) >= WAD) revert NotLiquidatable();

        Position storage pos = positions[user];
        uint256 userDebt = (pos.debtShares * totalDebt) / totalDebtShares;

        uint256 sharesToBurn;
        if (debtToCover >= userDebt) {
            debtToCover = userDebt;
            sharesToBurn = pos.debtShares;
        } else {
            sharesToBurn = (debtToCover * totalDebtShares) / totalDebt;
        }

        uint256 priceCollateral = oracle.getPriceSafe(collateralAsset, 86_400);
        uint256 priceDebt = oracle.getPriceSafe(debtAsset, 86_400);

        uint256 debtValueToCover = (debtToCover * priceDebt) / (10 ** debtDecimals);
        uint256 requiredCollateralValue = (debtValueToCover * (BPS_DENOMINATOR + liquidationBonus)) / BPS_DENOMINATOR;
        uint256 collateralToLiquidate = (requiredCollateralValue * (10 ** collateralDecimals)) / priceCollateral;

        if (collateralToLiquidate > pos.collateral) {
            collateralToLiquidate = pos.collateral;
        }

        pos.debtShares -= sharesToBurn;
        totalDebtShares -= sharesToBurn;
        totalDebt -= debtToCover;

        pos.collateral -= collateralToLiquidate;
        totalCollateral -= collateralToLiquidate;

        IERC20(debtAsset).safeTransferFrom(msg.sender, address(this), debtToCover);
        _transferCollateral(msg.sender, collateralToLiquidate);

        emit Liquidated(msg.sender, user, debtToCover, collateralToLiquidate);
    }

    function healthFactor(address user) public view returns (uint256) {
        Position storage pos = positions[user];
        if (pos.debtShares == 0) return type(uint256).max;

        uint256 userDebt = (pos.debtShares * (totalDebt == 0 ? 0 : totalDebt)) / totalDebtShares;
        if (userDebt == 0) return type(uint256).max;

        uint256 priceCollateral = oracle.getPriceSafe(collateralAsset, 86_400);
        uint256 priceDebt = oracle.getPriceSafe(debtAsset, 86_400);

        uint256 collateralValue = (pos.collateral * priceCollateral) / (10 ** collateralDecimals);
        uint256 debtValue = (userDebt * priceDebt) / (10 ** debtDecimals);

        if (debtValue == 0) return type(uint256).max;

        uint256 collateralValueDiscounted = (collateralValue * liquidationThreshold) / BPS_DENOMINATOR;
        return (collateralValueDiscounted * WAD) / debtValue;
    }

    function _transferCollateral(address to, uint256 amount) internal {
        if (collateralAsset == address(0)) {
            (bool success,) = to.call{ value: amount }("");
            if (!success) revert TransferFailed();
        } else {
            IERC20(collateralAsset).safeTransfer(to, amount);
        }
    }
}
