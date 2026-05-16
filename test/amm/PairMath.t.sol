// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { PairMathYul } from "../../src/amm/PairMathYul.sol";

/// @dev External harness so `vm.expectRevert` can observe reverts from the
///      otherwise-internal (inlined) library functions at a deeper call frame.
contract PairMathHarness {
    function yul(uint256 a, uint256 rIn, uint256 rOut) external pure returns (uint256) {
        return PairMathYul.getAmountOut(a, rIn, rOut);
    }

    function sol(uint256 a, uint256 rIn, uint256 rOut) external pure returns (uint256) {
        return PairMathYul.getAmountOutSol(a, rIn, rOut);
    }
}

/// @notice Unit tests for the constant-product math library. Covers the
///         ZeroInput revert branches (the gas benchmark only exercises the
///         happy path) and asserts the Yul and Solidity implementations agree.
contract PairMathTest is Test {
    PairMathHarness internal h;

    function setUp() public {
        h = new PairMathHarness();
    }

    function test_yulAndSolAgree() public view {
        uint256 amountIn = 1000e18;
        uint256 reserveIn = 500_000e18;
        uint256 reserveOut = 750_000e18;

        uint256 outYul = h.yul(amountIn, reserveIn, reserveOut);
        uint256 outSol = h.sol(amountIn, reserveIn, reserveOut);

        assertEq(outYul, outSol, "yul/sol mismatch");
        uint256 expected = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997);
        assertEq(outYul, expected, "wrong amountOut");
    }

    function test_yul_revertsOnZeroAmountIn() public {
        vm.expectRevert(PairMathYul.ZeroInput.selector);
        h.yul(0, 1e18, 1e18);
    }

    function test_yul_revertsOnZeroReserveIn() public {
        vm.expectRevert(PairMathYul.ZeroInput.selector);
        h.yul(1e18, 0, 1e18);
    }

    function test_yul_revertsOnZeroReserveOut() public {
        vm.expectRevert(PairMathYul.ZeroInput.selector);
        h.yul(1e18, 1e18, 0);
    }

    function test_sol_revertsOnZeroAmountIn() public {
        vm.expectRevert(PairMathYul.ZeroInput.selector);
        h.sol(0, 1e18, 1e18);
    }

    function test_sol_revertsOnZeroReserveOut() public {
        vm.expectRevert(PairMathYul.ZeroInput.selector);
        h.sol(1e18, 1e18, 0);
    }

    function testFuzz_yulMatchesSol(uint96 amountIn, uint96 reserveIn, uint96 reserveOut) public view {
        vm.assume(amountIn > 0 && reserveIn > 0 && reserveOut > 0);
        assertEq(h.yul(amountIn, reserveIn, reserveOut), h.sol(amountIn, reserveIn, reserveOut));
    }
}
