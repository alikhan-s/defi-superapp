// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { Pair } from "../../src/amm/Pair.sol";
import { LPPositionNFT } from "../../src/tokens/LPPositionNFT.sol";
import { MockERC20 } from "./helpers/MockERC20.sol";

contract PairTest is Test {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    Pair internal pair;
    MockERC20 internal token0;
    MockERC20 internal token1;
    LPPositionNFT internal lpNFT;

    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    address internal admin = makeAddr("admin");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant INIT_AMOUNT = 100_000e18;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        MockERC20 tA = new MockERC20("TokenA", "TA", 18);
        MockERC20 tB = new MockERC20("TokenB", "TB", 18);

        // Ensure sorted order (token0 < token1)
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
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    function _addLiquidity(address to, uint256 a0, uint256 a1) internal returns (uint256 liquidity, uint256 tokenId) {
        token0.mint(address(pair), a0);
        token1.mint(address(pair), a1);
        (liquidity, tokenId) = pair.mint(to);
    }

    // -------------------------------------------------------------------------
    // 1. Constructor guards
    // -------------------------------------------------------------------------

    function test_constructor_rejectsZeroToken0() public {
        vm.expectRevert(Pair.ZeroAddress.selector);
        new Pair(address(0), address(token1), address(lpNFT), admin);
    }

    function test_constructor_rejectsZeroToken1() public {
        vm.expectRevert(Pair.ZeroAddress.selector);
        new Pair(address(token0), address(0), address(lpNFT), admin);
    }

    function test_constructor_rejectsZeroNFT() public {
        vm.expectRevert(Pair.ZeroAddress.selector);
        new Pair(address(token0), address(token1), address(0), admin);
    }

    function test_constructor_rejectsZeroAdmin() public {
        vm.expectRevert(Pair.ZeroAddress.selector);
        new Pair(address(token0), address(token1), address(lpNFT), address(0));
    }

    // -------------------------------------------------------------------------
    // 2. mint — first mint
    // -------------------------------------------------------------------------

    function test_mint_firstMint_mintsNFTAndLocksMinLiquidity() public {
        (uint256 liq, uint256 tokenId) = _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        assertEq(lpNFT.ownerOf(tokenId), alice, "alice should own NFT");
        assertEq(pair.liquidityOf(tokenId), liq);
        assertEq(pair.lockedLiquidity(), pair.MINIMUM_LIQUIDITY());
        assertEq(pair.totalLPSupply(), liq + pair.MINIMUM_LIQUIDITY());
    }

    function test_mint_firstMint_setsReserves() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, INIT_AMOUNT);
        assertEq(r1, INIT_AMOUNT);
    }

    function test_mint_zeroAddressReverts() public {
        token0.mint(address(pair), INIT_AMOUNT);
        token1.mint(address(pair), INIT_AMOUNT);
        vm.expectRevert(Pair.ZeroAddress.selector);
        pair.mint(address(0));
    }

    function test_mint_tooSmallAmountReverts() public {
        // amount so small that sqrt(a0*a1) <= MINIMUM_LIQUIDITY
        token0.mint(address(pair), 10);
        token1.mint(address(pair), 10);
        vm.expectRevert(Pair.InsufficientLiquidity.selector);
        pair.mint(alice);
    }

    // -------------------------------------------------------------------------
    // 3. mint — subsequent mint
    // -------------------------------------------------------------------------

    function test_mint_subsequentMint_proportional() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        uint256 supplyBefore = pair.totalLPSupply();
        (uint112 r0Before,,) = pair.getReserves();

        uint256 add0 = 10_000e18;
        uint256 add1 = 10_000e18;
        (uint256 liq2,) = _addLiquidity(bob, add0, add1);

        uint256 expectedLiq = (add0 * supplyBefore) / r0Before;
        assertEq(liq2, expectedLiq, "proportional liquidity");
        assertEq(pair.totalLPSupply(), supplyBefore + liq2);
    }

    // -------------------------------------------------------------------------
    // 4. burn
    // -------------------------------------------------------------------------

    function test_burn_returnsTokensAndBurnsNFT() public {
        (uint256 liq, uint256 tokenId) = _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        uint256 supplyBefore = pair.totalLPSupply();
        uint256 b0Before = token0.balanceOf(address(pair));
        uint256 b1Before = token1.balanceOf(address(pair));

        vm.prank(alice);
        (uint256 out0, uint256 out1) = pair.burn(tokenId, alice);

        assertGt(out0, 0, "token0 returned");
        assertGt(out1, 0, "token1 returned");
        assertEq(pair.totalLPSupply(), supplyBefore - liq, "supply decremented");
        assertEq(pair.liquidityOf(tokenId), 0, "liquidityOf cleared");
        assertEq(token0.balanceOf(alice), out0, "alice received token0");
        assertEq(token1.balanceOf(alice), out1, "alice received token1");

        // Verify NFT is burned
        vm.expectRevert();
        lpNFT.ownerOf(tokenId);

        // Verify proportion
        assertEq(out0, (liq * b0Before) / supplyBefore);
        assertEq(out1, (liq * b1Before) / supplyBefore);
    }

    function test_burn_unauthorizedReverts() public {
        (, uint256 tokenId) = _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        vm.prank(bob);
        vm.expectRevert(Pair.Forbidden.selector);
        pair.burn(tokenId, bob);
    }

    function test_burn_approvedOperatorSucceeds() public {
        (, uint256 tokenId) = _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        vm.prank(alice);
        lpNFT.approve(bob, tokenId);

        vm.prank(bob);
        (uint256 out0,) = pair.burn(tokenId, bob);
        assertGt(out0, 0);
    }

    function test_burn_approvedForAllSucceeds() public {
        (, uint256 tokenId) = _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        vm.prank(alice);
        lpNFT.setApprovalForAll(bob, true);

        vm.prank(bob);
        (uint256 out0,) = pair.burn(tokenId, bob);
        assertGt(out0, 0);
    }

    function test_burn_zeroAddressToReverts() public {
        (, uint256 tokenId) = _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        vm.prank(alice);
        vm.expectRevert(Pair.ZeroAddress.selector);
        pair.burn(tokenId, address(0));
    }

    // -------------------------------------------------------------------------
    // 5. swap
    // -------------------------------------------------------------------------

    function test_swap_correctOutput() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 amtIn = 1000e18;
        // Expected output via constant-product with fee
        uint256 amtInFee = amtIn * 997;
        uint256 expectedOut = (amtInFee * r1) / (r0 * 1000 + amtInFee);

        token0.mint(address(pair), amtIn);
        pair.swap(0, expectedOut, alice, 0, "");

        assertEq(token1.balanceOf(alice), expectedOut);
    }

    function test_swap_kInvariantMaintained() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        (uint112 r0Before, uint112 r1Before,) = pair.getReserves();
        uint256 kBefore = uint256(r0Before) * r1Before;

        uint256 amtIn = 1000e18;
        uint256 amtInFee = amtIn * 997;
        uint256 expectedOut = (amtInFee * uint256(r1Before)) / (uint256(r0Before) * 1000 + amtInFee);

        token0.mint(address(pair), amtIn);
        pair.swap(0, expectedOut, alice, 0, "");

        (uint112 r0After, uint112 r1After,) = pair.getReserves();
        // K should be >= before (fees accrue)
        assertGe(uint256(r0After) * r1After, kBefore);
    }

    function test_swap_slippageReverts() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 amtIn = 1000e18;
        uint256 amtInFee = amtIn * 997;
        uint256 expectedOut = (amtInFee * r1) / (r0 * 1000 + amtInFee);

        token0.mint(address(pair), amtIn);
        vm.expectRevert(Pair.Slippage.selector);
        pair.swap(0, expectedOut, alice, expectedOut + 1, "");
    }

    function test_swap_insufficientLiquidityReverts() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        (uint112 r0,,) = pair.getReserves();

        vm.expectRevert(Pair.InsufficientLiquidity.selector);
        pair.swap(r0, 0, alice, 0, ""); // amount0Out == reserve0
    }

    function test_swap_zeroOutReverts() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        vm.expectRevert(Pair.InsufficientOutput.selector);
        pair.swap(0, 0, alice, 0, "");
    }

    function test_swap_toTokenAddressReverts() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        (uint112 r0, uint112 r1,) = pair.getReserves();
        uint256 amtIn = 1000e18;
        uint256 amtInFee = amtIn * 997;
        uint256 out = (amtInFee * r1) / (r0 * 1000 + amtInFee);

        token0.mint(address(pair), amtIn);
        vm.expectRevert(Pair.InvalidToken.selector);
        pair.swap(0, out, address(token1), 0, "");
    }

    function test_swap_kViolationReverts() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        // Send 1 wei of token0 but demand all of token1's reserve minus 1 — K will fail
        token0.mint(address(pair), 1);
        uint256 r1 = INIT_AMOUNT;
        vm.expectRevert(Pair.K.selector);
        pair.swap(0, r1 - 1, alice, 0, "");
    }

    // -------------------------------------------------------------------------
    // 6. Pause / unpause
    // -------------------------------------------------------------------------

    function test_pause_mintRevertsWhenPaused() public {
        vm.prank(admin);
        pair.pause();

        token0.mint(address(pair), INIT_AMOUNT);
        token1.mint(address(pair), INIT_AMOUNT);
        vm.expectRevert();
        pair.mint(alice);
    }

    function test_pause_swapRevertsWhenPaused() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        vm.prank(admin);
        pair.pause();

        token0.mint(address(pair), 1000e18);
        vm.expectRevert();
        pair.swap(0, 1, alice, 0, "");
    }

    function test_pause_onlyPauserRole() public {
        vm.prank(alice);
        vm.expectRevert();
        pair.pause();
    }

    function test_unpause_restoresFunctionality() public {
        vm.startPrank(admin);
        pair.pause();
        pair.unpause();
        vm.stopPrank();

        (uint256 liq,) = _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);
        assertGt(liq, 0);
    }

    // -------------------------------------------------------------------------
    // 7. skim / sync
    // -------------------------------------------------------------------------

    function test_skim_transfersExcess() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        uint256 excess = 500e18;
        token0.mint(address(pair), excess);

        pair.skim(bob);

        assertEq(token0.balanceOf(bob), excess, "bob receives excess token0");
    }

    function test_sync_updatesReserves() public {
        _addLiquidity(alice, INIT_AMOUNT, INIT_AMOUNT);

        uint256 extra = 333e18;
        token0.mint(address(pair), extra);

        // Before sync reserves haven't updated
        (uint112 r0Before,,) = pair.getReserves();
        assertEq(r0Before, INIT_AMOUNT);

        pair.sync();

        (uint112 r0After,,) = pair.getReserves();
        assertEq(r0After, INIT_AMOUNT + extra);
    }

    // -------------------------------------------------------------------------
    // 8. getReserves
    // -------------------------------------------------------------------------

    function test_getReserves_initiallyZero() public view {
        (uint112 r0, uint112 r1, uint32 ts) = pair.getReserves();
        assertEq(r0, 0);
        assertEq(r1, 0);
        assertEq(ts, 0);
    }

    function test_getReserves_updatesAfterMint() public {
        _addLiquidity(alice, INIT_AMOUNT, 50_000e18);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, INIT_AMOUNT);
        assertEq(r1, 50_000e18);
    }
}
