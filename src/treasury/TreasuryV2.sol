pragma solidity ^0.8.24;
import { TreasuryV1 } from "./TreasuryV1.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TreasuryV2 is TreasuryV1 {
    using SafeERC20 for IERC20;

    uint256 public lastBatchTimestamp;

    event BatchWithdrawal(address indexed to, uint256 tokensCount, uint256 timestamp);

    function batchWithdrawERC20(address[] calldata tokens, address to, uint256[] calldata amounts)
        external
        onlyRole(FUND_MANAGER_ROLE)
        whenNotPaused
    {
        if (tokens.length != amounts.length) revert("Length mismatch");
        if (to == address(0)) revert ZeroAddress();

        for (uint256 i = 0; i < tokens.length; i++) {
            if (IERC20(tokens[i]).balanceOf(address(this)) < amounts[i]) revert InsufficientBalance();
            totalERC20Withdrawn[tokens[i]] += amounts[i];
            IERC20(tokens[i]).safeTransfer(to, amounts[i]);
        }

        lastBatchTimestamp = block.timestamp;
        emit BatchWithdrawal(to, tokens.length, block.timestamp);
    }
}
