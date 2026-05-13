// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC4626 } from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

interface ILendingPool {
    function supply(uint256 amount) external;
    function withdrawAssets(uint256 amount) external returns (uint256 shares);
    function getSupplyValue(address user) external view returns (uint256);
}

contract YieldVault is ERC4626, ReentrancyGuard, Pausable, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant STRATEGY_MANAGER_ROLE = keccak256("STRATEGY_MANAGER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    ILendingPool public immutable lendingPool;
    uint256 public principalSupplied;

    event Harvest(uint256 yieldHarvested);

    constructor(IERC20 _asset, ILendingPool _lendingPool, string memory _name, string memory _symbol, address _admin)
        ERC4626(_asset)
        ERC20(_name, _symbol)
    {
        lendingPool = _lendingPool;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(STRATEGY_MANAGER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    function totalAssets() public view override returns (uint256) {
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));
        uint256 suppliedAssets = lendingPool.getSupplyValue(address(this));
        return idleAssets + suppliedAssets;
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function maxDeposit(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    function maxWithdraw(address owner) public view override returns (uint256) {
        return paused() ? 0 : super.maxWithdraw(owner);
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        return paused() ? 0 : super.maxRedeem(owner);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
        whenNotPaused
    {
        super._deposit(caller, receiver, assets, shares);

        IERC20(asset()).safeIncreaseAllowance(address(lendingPool), assets);
        lendingPool.supply(assets);
        principalSupplied += assets;
    }

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        virtual
        override
        nonReentrant
        whenNotPaused
    {
        uint256 idleAssets = IERC20(asset()).balanceOf(address(this));
        if (idleAssets < assets) {
            uint256 shortfall = assets - idleAssets;
            lendingPool.withdrawAssets(shortfall);

            if (principalSupplied >= shortfall) {
                principalSupplied -= shortfall;
            } else {
                principalSupplied = 0;
            }
        }

        super._withdraw(caller, receiver, owner, assets, shares);
    }

    function harvest() external onlyRole(STRATEGY_MANAGER_ROLE) {
        uint256 currentSupplyValue = lendingPool.getSupplyValue(address(this));
        if (currentSupplyValue > principalSupplied) {
            uint256 yieldToHarvest = currentSupplyValue - principalSupplied;
            lendingPool.withdrawAssets(yieldToHarvest);
            emit Harvest(yieldToHarvest);
        }
    }
}
