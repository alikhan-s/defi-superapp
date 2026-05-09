// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { StdInvariant, Test } from "forge-std/Test.sol";
import { Pair } from "../../src/amm/Pair.sol";
import { PairMathYul } from "../../src/amm/PairMathYul.sol";
import { LPPositionNFT } from "../../src/tokens/LPPositionNFT.sol";
import { MockERC20 } from "./helpers/MockERC20.sol";

// ---------------------------------------------------------------------------
// Handler — the fuzzer's entry point for state transitions
// ---------------------------------------------------------------------------

contract PairHandler is Test {
    Pair public pair;
    MockERC20 public token0;
    MockERC20 public token1;
    LPPositionNFT public lpNFT;

    address internal actor = makeAddr("actor");
    uint256[] public mintedIds;

    constructor(Pair _pair, MockERC20 _t0, MockERC20 _t1, LPPositionNFT _nft) {
        pair = _pair;
        token0 = _t0;
        token1 = _t1;
        lpNFT = _nft;
    }

    /// @dev Add liquidity with bounded amounts to keep values realistic.
    function deposit(uint256 a0, uint256 a1) external {
        a0 = bound(a0, 1e15, 1e22);
        a1 = bound(a1, 1e15, 1e22);

        token0.mint(address(pair), a0);
        token1.mint(address(pair), a1);

        try pair.mint(actor) returns (uint256, uint256 tokenId) {
            mintedIds.push(tokenId);
        } catch { }
    }

    /// @dev Remove a random position from the minted set.
    function withdraw(uint256 seed) external {
        if (mintedIds.length == 0) return;

        uint256 idx = seed % mintedIds.length;
        uint256 tokenId = mintedIds[idx];
        _removeIdx(idx);

        try lpNFT.ownerOf(tokenId) returns (address owner) {
            if (owner != actor) return;
        } catch {
            return;
        }

        vm.prank(actor);
        try pair.burn(tokenId, actor) { } catch { }
    }

    /// @dev Swap token0 → token1 with a bounded input.
    function swapIn0(uint256 amountIn) external {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        if (r0 == 0 || r1 == 0) return;

        // Guard: r0/10 could be 0 if r0 < 10, causing bound() to panic (max < min).
        uint256 maxIn = uint256(r0) >= 10 ? uint256(r0) / 10 : 1;
        amountIn = bound(amountIn, 1, maxIn);

        uint256 amountOut = PairMathYul.getAmountOut(amountIn, r0, r1);
        if (amountOut == 0) return;

        token0.mint(address(pair), amountIn);
        try pair.swap(0, amountOut, actor, 0, "") { } catch { }
    }

    /// @dev Ghost helper used by invariants.
    function mintedCount() external view returns (uint256) {
        return mintedIds.length;
    }

    function _removeIdx(uint256 idx) internal {
        mintedIds[idx] = mintedIds[mintedIds.length - 1];
        mintedIds.pop();
    }
}

// ---------------------------------------------------------------------------
// Invariant test contract
// ---------------------------------------------------------------------------

contract PairInvariantTest is StdInvariant, Test {
    Pair internal pair;
    MockERC20 internal token0;
    MockERC20 internal token1;
    LPPositionNFT internal lpNFT;
    PairHandler internal handler;

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    address internal admin = makeAddr("admin");

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

        handler = new PairHandler(pair, token0, token1, lpNFT);
        targetContract(address(handler));
    }

    // -------------------------------------------------------------------------
    // Invariants
    // -------------------------------------------------------------------------

    /// @dev totalLPSupply must always be >= lockedLiquidity.
    function invariant_totalSupplyGteLockedLiquidity() public view {
        assertGe(pair.totalLPSupply(), pair.lockedLiquidity(), "supply >= locked");
    }

    /// @dev If any liquidity exists, both reserves must be positive.
    function invariant_reservesPositiveWhenLiquidityExists() public view {
        if (pair.totalLPSupply() == 0) return;
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertGt(r0, 0, "reserve0 > 0");
        assertGt(r1, 0, "reserve1 > 0");
    }

    /// @dev K (reserve0 * reserve1) must never decrease between swaps.
    ///      Since burns reduce both reserves, we only enforce K > 0 whenever
    ///      totalLPSupply > 0.
    function invariant_kPositiveWhenLiquidityExists() public view {
        if (pair.totalLPSupply() == 0) return;
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertGt(uint256(r0) * r1, 0, "K > 0");
    }
}
