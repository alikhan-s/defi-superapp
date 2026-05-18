// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { Pair } from "../../src/amm/Pair.sol";
import { PairMathYul } from "../../src/amm/PairMathYul.sol";
import { LPPositionNFT } from "../../src/tokens/LPPositionNFT.sol";
import { MockERC20 } from "./helpers/MockERC20.sol";

/// @dev External wrapper needed because vm.expectRevert cannot intercept
///      reverts inside internal library calls (same EVM call depth).
contract MathWrapper {
    function getAmountOut(uint256 a, uint256 b, uint256 c) external pure returns (uint256) {
        return PairMathYul.getAmountOut(a, b, c);
    }
}

contract PairFuzzTest is Test {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    Pair internal pair;
    MockERC20 internal token0;
    MockERC20 internal token1;
    LPPositionNFT internal lpNFT;
    MathWrapper internal mathWrapper;

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        MockERC20 tA = new MockERC20("A", "A", 18);
        MockERC20 tB = new MockERC20("B", "B", 18);

        if (address(tA) < address(tB)) {
            token0 = tA;
            token1 = tB;
        } else {
            token0 = tB;
            token1 = tA;
        }

        lpNFT = new LPPositionNFT(admin);
        pair = new Pair(address(token0), address(token1), address(lpNFT), admin);

        vm.prank(admin);
        lpNFT.grantRole(MINTER_ROLE, address(pair));

        mathWrapper = new MathWrapper();

        // Seed initial liquidity
        _addLiquidity(alice, 1_000_000e18, 1_000_000e18);
    }

    function _addLiquidity(address to, uint256 a0, uint256 a1) internal {
        token0.mint(address(pair), a0);
        token1.mint(address(pair), a1);
        pair.mint(to);
    }

    // -------------------------------------------------------------------------
    // Fuzz tests
    // -------------------------------------------------------------------------

    /// @dev Output amount from the formula must always be strictly less than reserveOut.
    function testFuzz_getAmountOut_neverExceedsReserveOut(uint256 amountIn) public view {
        (uint112 r0, uint112 r1,) = pair.getReserves();

        amountIn = bound(amountIn, 1, uint256(r0) - 1);

        uint256 amountOut = PairMathYul.getAmountOut(amountIn, r0, r1);
        assertLt(amountOut, r1, "output must be less than reserve");
    }

    /// @dev Yul and Solidity implementations must agree for all valid inputs.
    function testFuzz_getAmountOut_yulMatchesSol(uint128 amountIn, uint112 rIn, uint112 rOut) public pure {
        vm.assume(amountIn > 0 && rIn > 0 && rOut > 0);

        uint256 yul = PairMathYul.getAmountOut(amountIn, rIn, rOut);
        uint256 sol = PairMathYul.getAmountOutSol(amountIn, rIn, rOut);
        assertEq(yul, sol, "Yul and Solidity outputs must match");
    }

    /// @dev A swap using the formula amount should always satisfy the K invariant.
    function testFuzz_swap_kInvariantHolds(uint256 amountIn) public {
        (uint112 r0, uint112 r1,) = pair.getReserves();

        // Bound to at most 10% of reserve to keep swap sane
        amountIn = bound(amountIn, 1, uint256(r0) / 10);

        uint256 amountOut = PairMathYul.getAmountOut(amountIn, r0, r1);
        if (amountOut == 0) return;

        uint256 kBefore = uint256(r0) * r1;

        token0.mint(address(pair), amountIn);
        pair.swap(0, amountOut, alice, 0, "");

        (uint112 nr0, uint112 nr1,) = pair.getReserves();
        assertGe(uint256(nr0) * nr1, kBefore, "K must not decrease after swap");
    }

    /// @dev Minting then burning should return proportional amounts (minus rounding).
    function testFuzz_mint_burn_returnsProportion(uint96 a0, uint96 a1) public {
        // Non-trivial amounts that won't hit MINIMUM_LIQUIDITY guard
        a0 = uint96(bound(a0, 1000e18, 1e24));
        a1 = uint96(bound(a1, 1000e18, 1e24));

        uint256 totalBefore = pair.totalLPSupply();

        token0.mint(address(pair), a0);
        token1.mint(address(pair), a1);
        (, uint256 tokenId) = pair.mint(alice);

        uint256 liq = pair.liquidityOf(tokenId);

        uint256 bal0Before = token0.balanceOf(address(pair));
        uint256 bal1Before = token1.balanceOf(address(pair));
        uint256 supplyBefore = pair.totalLPSupply();

        vm.prank(alice);
        (uint256 out0, uint256 out1) = pair.burn(tokenId, alice);

        uint256 expectedOut0 = (liq * bal0Before) / supplyBefore;
        uint256 expectedOut1 = (liq * bal1Before) / supplyBefore;

        assertEq(out0, expectedOut0, "token0 proportion");
        assertEq(out1, expectedOut1, "token1 proportion");

        // totalLPSupply returns to pre-mint value
        assertEq(pair.totalLPSupply(), totalBefore);
        // Note: reserves don't necessarily return to r0/r1 — unbalanced deposits
        // leave excess tokens in the pool (standard V2 behaviour).
    }

    /// @dev getAmountOut reverts with ZeroInput when amountIn == 0.
    function testFuzz_getAmountOut_zeroInputRevertsOnYul(uint112 rIn, uint112 rOut) public {
        vm.assume(rIn > 0 && rOut > 0);
        // Use external wrapper: vm.expectRevert cannot intercept internal library calls.
        vm.expectRevert(PairMathYul.ZeroInput.selector);
        mathWrapper.getAmountOut(0, rIn, rOut);
    }
}
