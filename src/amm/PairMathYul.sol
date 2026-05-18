// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title PairMathYul
/// @notice Constant-product AMM math with a 0.3 % swap fee.
///         `getAmountOut` is implemented in inline Yul for gas efficiency;
///         `getAmountOutSol` is the equivalent pure-Solidity version used
///         in gas-comparison benchmarks.
library PairMathYul {
    error ZeroInput();

    /// @notice Pure-Solidity reference implementation of getAmountOut.
    ///         Exists solely for gas benchmarking against the Yul version.
    function getAmountOutSol(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) revert ZeroInput();
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @notice Compute the output amount for a constant-product swap using inline Yul.
    /// @dev    Formula: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
    ///         Overflow safety: with reserves bounded to uint112 (≤ 5.19 × 10³³) and amountIn
    ///         similarly bounded, the maximum numerator is ≈ 997 × 2¹¹² × 2¹¹² ≈ 2²³⁴ < 2²⁵⁶.
    ///         Input validation is performed in Solidity before entering the assembly block so
    ///         that a proper custom error is propagated on invalid input.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) revert ZeroInput();
        assembly {
            let amountInWithFee := mul(amountIn, 997)
            let numerator := mul(amountInWithFee, reserveOut)
            let denominator := add(mul(reserveIn, 1000), amountInWithFee)
            amountOut := div(numerator, denominator)
        }
    }
}
