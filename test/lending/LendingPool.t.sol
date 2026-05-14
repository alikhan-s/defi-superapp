// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { LendingPool } from "../../src/lending/LendingPool.sol";
import { ChainlinkPriceOracle } from "../../src/oracle/ChainlinkPriceOracle.sol";
import { MockAggregator } from "../../src/oracle/MockAggregator.sol";
import { MockERC20 } from "../helpers/MockERC20.sol";

contract LendingPoolTest is Test {
    LendingPool public pool;
    ChainlinkPriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;

    MockAggregator public wethFeed;
    MockAggregator public usdcFeed;

    address public admin = address(this);
    address public user1 = address(0x111);
    address public user2 = address(0x222);

    function setUp() public {
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        oracle = new ChainlinkPriceOracle(admin);

        wethFeed = new MockAggregator(2000 * 1e8, 8); // $2000
        usdcFeed = new MockAggregator(1 * 1e8, 8); // $1

        oracle.addFeed(address(weth), address(wethFeed), 86_400);
        oracle.addFeed(address(usdc), address(usdcFeed), 86_400);

        pool = new LendingPool(
            address(weth),
            address(usdc),
            address(oracle),
            8000, // 80% liquidation threshold
            1000, // 10% bonus
            100, // 1% base rate
            1000, // 10% slope
            admin
        );

        // Seed some initial liquidity into the pool
        usdc.mint(address(pool), 100_000 * 1e6);

        weth.mint(user1, 100 * 1e18);
        usdc.mint(user1, 100_000 * 1e6);

        weth.mint(user2, 100 * 1e18);
        usdc.mint(user2, 100_000 * 1e6);

        vm.startPrank(user1);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function test_depositCollateral() public {
        vm.prank(user1);
        pool.depositCollateral(10 * 1e18);

        (uint256 collateral,,) = pool.positions(user1);
        assertEq(collateral, 10 * 1e18);
        assertEq(pool.totalCollateral(), 10 * 1e18);
        assertEq(weth.balanceOf(address(pool)), 10 * 1e18);
    }

    function test_withdrawCollateral() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        pool.withdrawCollateral(5 * 1e18);
        vm.stopPrank();

        (uint256 collateral,,) = pool.positions(user1);
        assertEq(collateral, 5 * 1e18);
        assertEq(pool.totalCollateral(), 5 * 1e18);
        assertEq(weth.balanceOf(address(pool)), 5 * 1e18);
    }

    function test_withdrawCollateral_revertsIfHFBelow1() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18); // $20,000 collateral

        // HF = collateral * price * LT / debt
        // debt max allowed: 20,000 * 0.8 = 16,000
        pool.borrow(10_000 * 1e6); // $10,000 borrowed. HF = 1.6

        // withdraw 5 WETH. new collateral = 5 WETH ($10,000).
        // HF = 10,000 * 0.8 / 10,000 = 0.8
        // Should revert because 0.8 < 1
        vm.expectRevert(LendingPool.HealthFactorTooLow.selector);
        pool.withdrawCollateral(5 * 1e18);
        vm.stopPrank();
    }

    function test_borrow() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18); // $20,000 collateral
        pool.borrow(10_000 * 1e6); // $10,000 borrowed
        vm.stopPrank();

        (uint256 collateral, uint256 debtShares,) = pool.positions(user1);
        assertEq(collateral, 10 * 1e18);
        assertEq(debtShares, 10_000 * 1e6);
        assertEq(pool.totalDebt(), 10_000 * 1e6);
        assertEq(usdc.balanceOf(user1), 110_000 * 1e6);
    }

    function test_borrow_revertsOversized() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18); // $20,000 collateral
        // Borrowing $17,000 > $16,000 max allowed
        vm.expectRevert(LendingPool.HealthFactorTooLow.selector);
        pool.borrow(17_000 * 1e6);
        vm.stopPrank();
    }

    function test_borrow_respectsOraclePrice() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18); // $20,000 initially
        vm.stopPrank();

        // Price drops to $1000
        wethFeed.setPrice(1000 * 1e8);

        vm.startPrank(user1);
        // Collateral value is $10,000. Max borrow is $8,000.
        vm.expectRevert(LendingPool.HealthFactorTooLow.selector);
        pool.borrow(9000 * 1e6);

        pool.borrow(8000 * 1e6); // Should succeed exactly
        vm.stopPrank();
    }

    function test_accrueInterest() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        pool.borrow(10_000 * 1e6);
        vm.stopPrank();

        uint256 borrowIndexBefore = pool.borrowIndex();
        uint256 debtBefore = pool.totalDebt();

        vm.warp(block.timestamp + 365 days);
        pool.accrueInterest();

        uint256 borrowIndexAfter = pool.borrowIndex();
        uint256 debtAfter = pool.totalDebt();

        assertTrue(borrowIndexAfter > borrowIndexBefore);
        assertTrue(debtAfter > debtBefore);
    }

    function test_repay() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        pool.borrow(10_000 * 1e6);

        uint256 usdcBefore = usdc.balanceOf(user1);
        pool.repay(5000 * 1e6);
        uint256 usdcAfter = usdc.balanceOf(user1);

        assertEq(usdcBefore - usdcAfter, 5000 * 1e6);
        (, uint256 debtShares,) = pool.positions(user1);
        assertEq(debtShares, 5000 * 1e6);
        vm.stopPrank();
    }

    function test_repay_fullRepayZerosPosition() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        pool.borrow(10_000 * 1e6);

        vm.warp(block.timestamp + 365 days);
        pool.repay(type(uint256).max); // Pass max to repay full

        (, uint256 debtShares,) = pool.positions(user1);
        assertEq(debtShares, 0);
        assertEq(pool.totalDebtShares(), 0);
        assertEq(pool.totalDebt(), 0);
        vm.stopPrank();
    }

    function test_liquidate_happyPath() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18); // $20,000
        pool.borrow(15_000 * 1e6); // $15,000
        vm.stopPrank();

        // Price drops to $1500. Collateral = $15,000.
        // HF = 15000 * 0.8 / 15000 = 0.8
        wethFeed.setPrice(1500 * 1e8);

        vm.startPrank(user2);
        uint256 usdcBefore = usdc.balanceOf(user2);
        uint256 wethBefore = weth.balanceOf(user2);

        // Liquidate $10,000 debt
        pool.liquidate(user1, 10_000 * 1e6);
        vm.stopPrank();

        uint256 usdcAfter = usdc.balanceOf(user2);
        uint256 wethAfter = weth.balanceOf(user2);

        assertEq(usdcBefore - usdcAfter, 10_000 * 1e6);

        // $10,000 debt covered + 10% bonus = $11,000 worth of collateral
        // WETH price = $1500 -> 11000 / 1500 = 7.3333... WETH
        uint256 expectedWeth = (uint256(10_000) * 1e18 * 11_000) / 10_000 / 1500;
        assertEq(wethAfter - wethBefore, expectedWeth);
    }

    function test_liquidate_revertsNotLiquidatable() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        pool.borrow(10_000 * 1e6);
        vm.stopPrank();

        // HF = 20000 * 0.8 / 10000 = 1.6
        vm.startPrank(user2);
        vm.expectRevert(LendingPool.NotLiquidatable.selector);
        pool.liquidate(user1, 5000 * 1e6);
        vm.stopPrank();
    }

    function test_staleOracleReverts() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);

        vm.warp(block.timestamp + 86_401);
        // Stale oracle should revert inside ChainlinkPriceOracle
        vm.expectRevert(abi.encodeWithSignature("StalePrice(uint256,uint256)", 86_401, 86_400));
        pool.borrow(1000 * 1e6);
        vm.stopPrank();
    }

    function test_pauseBlocksActions() public {
        pool.pause();

        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pool.depositCollateral(10 * 1e18);
        vm.stopPrank();
    }

    function test_accessControlPause() public {
        vm.startPrank(user1);
        vm.expectRevert();
        pool.pause();
        vm.stopPrank();
    }

    function test_nativeEthCollateral() public {
        LendingPool ethPool = new LendingPool(address(0), address(usdc), address(oracle), 8000, 1000, 100, 1000, admin);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceSafe.selector, address(0), 86_400),
            abi.encode(2000 * 1e18)
        );
        usdc.mint(address(ethPool), 100_000 * 1e6);

        vm.deal(user1, 10 ether);
        vm.startPrank(user1);
        ethPool.depositCollateral{ value: 10 ether }(0);

        (uint256 col,,) = ethPool.positions(user1);
        assertEq(col, 10 ether);

        ethPool.borrow(5000 * 1e6);
        ethPool.withdrawCollateral(5 ether);
        vm.stopPrank();

        assertEq(user1.balance, 5 ether);

        // test revert TransferFailed on deposit with ERC20
        vm.deal(user1, 1 ether);
        vm.startPrank(user1);
        vm.expectRevert(LendingPool.TransferFailed.selector);
        pool.depositCollateral{ value: 1 ether }(10 * 1e18);
        vm.stopPrank();
    }

    function test_ethTransferFailed() public {
        LendingPool ethPool = new LendingPool(address(0), address(usdc), address(oracle), 8000, 1000, 100, 1000, admin);
        vm.mockCall(
            address(oracle),
            abi.encodeWithSelector(oracle.getPriceSafe.selector, address(0), 86_400),
            abi.encode(2000 * 1e18)
        );
        RejectETH rejecter = new RejectETH();
        vm.deal(address(rejecter), 10 ether);

        vm.prank(address(rejecter));
        ethPool.depositCollateral{ value: 10 ether }(0);

        vm.prank(address(rejecter));
        vm.expectRevert(LendingPool.TransferFailed.selector);
        ethPool.withdrawCollateral(10 ether);
    }

    function test_unpause() public {
        pool.pause();
        assertTrue(pool.paused());
        pool.unpause();
        assertFalse(pool.paused());
    }

    function test_zeroAmountReverts() public {
        vm.startPrank(user1);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.depositCollateral(0);

        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.withdrawCollateral(0);

        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.borrow(0);

        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.repay(0);

        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.liquidate(user2, 0);
        vm.stopPrank();
    }

    function test_repay_zeroDebt() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        pool.repay(100);
        vm.stopPrank();
    }

    function test_repay_moreThanDebt() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        pool.borrow(1000 * 1e6);
        pool.repay(2000 * 1e6);
        (, uint256 debtShares,) = pool.positions(user1);
        assertEq(debtShares, 0);
        vm.stopPrank();
    }

    function test_healthFactor_noDebt() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        vm.stopPrank();

        assertEq(pool.healthFactor(user1), type(uint256).max);
    }

    function test_liquidate_moreThanDebt() public {
        vm.startPrank(user1);
        pool.depositCollateral(10 * 1e18);
        pool.borrow(1000 * 1e6);
        vm.stopPrank();

        wethFeed.setPrice(100 * 1e8);

        vm.startPrank(user2);
        pool.liquidate(user1, 2000 * 1e6);
        vm.stopPrank();

        (, uint256 debtShares,) = pool.positions(user1);
        assertEq(debtShares, 0);
    }

    function test_accrueInterest_noDebt() public {
        vm.warp(block.timestamp + 100);
        pool.accrueInterest();
        assertEq(pool.totalDebt(), 0);
    }

    // ---- Coverage gap closers ----

    // L131 br4 — supply(0)
    function test_supply_zeroAmountReverts() public {
        vm.prank(user1);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.supply(0);
    }

    // L144-L157 (whole function) + L145 br5 zero shares + L154 br6 happy path (balance >= amount)
    function test_withdraw_sharesHappyPath() public {
        // user1 supplies; uses the share-denominated withdraw
        vm.prank(user1);
        pool.supply(10_000 * 1e6);

        uint256 shares = pool.liquidityShares(user1);
        uint256 balanceBefore = usdc.balanceOf(user1);

        vm.prank(user1);
        uint256 amount = pool.withdraw(shares);

        assertGt(amount, 0);
        assertEq(usdc.balanceOf(user1) - balanceBefore, amount);
        assertEq(pool.liquidityShares(user1), 0);
    }

    // L145 br5 — withdraw(0)
    function test_withdraw_zeroSharesReverts() public {
        vm.prank(user1);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.withdraw(0);
    }

    // L154 br6 — withdraw when pool's debtAsset balance < computed amount
    function test_withdraw_insufficientBalanceReverts() public {
        // Supply, then have someone borrow nearly all idle liquidity so withdraw can't be serviced
        vm.prank(user1);
        pool.supply(10_000 * 1e6);

        vm.startPrank(user2);
        pool.depositCollateral(100 * 1e18); // $200k collateral
        // Pool has 100k seed + 10k supplied = 110k; borrow 109k leaves 1k idle
        pool.borrow(109_000 * 1e6);
        vm.stopPrank();

        // Withdrawing all shares maps to ~10k assets — pool only has 1k idle
        uint256 shares = pool.liquidityShares(user1);
        vm.prank(user1);
        vm.expectRevert(LendingPool.TransferFailed.selector);
        pool.withdraw(shares);
    }

    // L161 br7 — withdrawAssets(0)
    function test_withdrawAssets_zeroAmountReverts() public {
        vm.prank(user1);
        vm.expectRevert(LendingPool.ZeroAmount.selector);
        pool.withdrawAssets(0);
    }

    // L170 br8 — withdrawAssets when pool's balance < amount
    function test_withdrawAssets_insufficientBalanceReverts() public {
        vm.prank(user1);
        pool.supply(10_000 * 1e6);

        vm.startPrank(user2);
        pool.depositCollateral(100 * 1e18);
        pool.borrow(109_000 * 1e6);
        vm.stopPrank();

        // Try to pull out more than the pool currently holds in idle liquidity
        vm.prank(user1);
        vm.expectRevert(LendingPool.TransferFailed.selector);
        pool.withdrawAssets(5000 * 1e6);
    }

    // L181-L189 + L180 br10 + L184 br11 — getSupplyValue simulates pending interest
    function test_getSupplyValue_simulatesPendingInterest() public {
        vm.prank(user1);
        pool.supply(20_000 * 1e6);

        vm.startPrank(user2);
        pool.depositCollateral(100 * 1e18);
        pool.borrow(50_000 * 1e6); // creates totalDebt > 0
        vm.stopPrank();

        uint256 snapshotBefore = pool.getSupplyValue(user1);

        // Warp without calling accrueInterest — the view must simulate growth
        vm.warp(block.timestamp + 365 days);

        uint256 snapshotAfter = pool.getSupplyValue(user1);
        assertGt(snapshotAfter, snapshotBefore, "view must include accrued interest");
    }

    // L220 br17 — withdrawCollateral when amount exceeds posted collateral
    function test_withdrawCollateral_insufficientCollateralReverts() public {
        vm.startPrank(user1);
        pool.depositCollateral(5 * 1e18);
        vm.expectRevert(LendingPool.InsufficientCollateral.selector);
        pool.withdrawCollateral(10 * 1e18);
        vm.stopPrank();
    }
}

contract RejectETH {
    receive() external payable {
        revert();
    }
}
