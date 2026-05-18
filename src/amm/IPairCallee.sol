// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IPairCallee
/// @notice Callback interface for Pair flash swaps.
interface IPairCallee {
    /// @param sender    Original msg.sender of the swap call.
    /// @param amount0   token0 amount sent optimistically to the callee.
    /// @param amount1   token1 amount sent optimistically to the callee.
    /// @param data      Arbitrary bytes passed through by the swap caller.
    function pairCall(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
