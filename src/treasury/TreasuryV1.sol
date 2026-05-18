pragma solidity ^0.8.24;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TreasuryV1 is Initializable, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant FUND_MANAGER_ROLE = keccak256("FUND_MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    uint256 public totalETHWithdrawn;
    mapping(address => uint256) public totalERC20Withdrawn;

    uint256[48] private __gap;

    error ZeroAddress();
    error InsufficientBalance();
    error ETHTransferFailed();

    function initialize(address admin) public initializer {
        __AccessControl_init();
        __Pausable_init();

        if (admin == address(0)) revert ZeroAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    receive() external payable {}

    function withdrawETH(address to, uint256 amount) external onlyRole(FUND_MANAGER_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (address(this).balance < amount) revert InsufficientBalance();

        totalETHWithdrawn += amount;

        (bool success, ) = to.call{value: amount}("");
        if (!success) revert ETHTransferFailed();
    }

    function withdrawERC20(address token, address to, uint256 amount) external onlyRole(FUND_MANAGER_ROLE) whenNotPaused {
        if (to == address(0)) revert ZeroAddress();
        if (IERC20(token).balanceOf(address(this)) < amount) revert InsufficientBalance();

        totalERC20Withdrawn[token] += amount;
        IERC20(token).safeTransfer(to, amount);
    }

    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function balanceOfETH() external view returns (uint256) {
        return address(this).balance;
    }

    function balanceOfERC20(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}