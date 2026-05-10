// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { LendingPool } from "../../src/lending/LendingPool.sol";
import { ChainlinkPriceOracle } from "../../src/oracle/ChainlinkPriceOracle.sol";
import { MockAggregator } from "../../src/oracle/MockAggregator.sol";
import { MockERC20 } from "../helpers/MockERC20.sol";

contract LendingPoolFuzzTest is Test {
    LendingPool public pool;
    ChainlinkPriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockAggregator public wethFeed;
    MockAggregator public usdcFeed;

    address public admin = address(this);
    address public user = address(0x111);

    function setUp() public {
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new ChainlinkPriceOracle(admin);
        wethFeed = new MockAggregator(2000 * 1e8, 8);
        usdcFeed = new MockAggregator(1 * 1e8, 8);
        oracle.addFeed(address(weth), address(wethFeed), type(uint256).max);
        oracle.addFeed(address(usdc), address(usdcFeed), type(uint256).max);

        pool = new LendingPool(address(weth), address(usdc), address(oracle), 8000, 1000, 100, 1000, admin);

        usdc.mint(address(pool), 1_000_000 * 1e6);
        weth.mint(user, type(uint128).max);
        usdc.mint(user, type(uint128).max);

        vm.startPrank(user);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_depositBorrowHF(uint256 depositAmt, uint256 borrowAmt) public {
        depositAmt = bound(depositAmt, 1e15, 1000 * 1e18);
        borrowAmt = bound(borrowAmt, 0, 1_000_000 * 1e6); // bound to avoid panic overflow

        vm.startPrank(user);
        pool.depositCollateral(depositAmt);

        uint256 maxBorrow = (depositAmt * 2000 * 80) / (1e12 * 100);

        if (borrowAmt > 0 && borrowAmt <= maxBorrow) {
            pool.borrow(borrowAmt);
            uint256 hf = pool.healthFactor(user);
            assertTrue(hf >= 1e18);
        } else if (borrowAmt > maxBorrow) {
            vm.expectRevert(LendingPool.HealthFactorTooLow.selector);
            pool.borrow(borrowAmt);
        }
        vm.stopPrank();
    }

    function testFuzz_timeWarpInterest(uint256 timeDelta) public {
        timeDelta = bound(timeDelta, 1, 3650 days);

        vm.startPrank(user);
        pool.depositCollateral(10 * 1e18);
        pool.borrow(1000 * 1e6);
        vm.stopPrank();

        uint256 debtBefore = pool.totalDebt();
        vm.warp(block.timestamp + timeDelta);
        pool.accrueInterest();
        uint256 debtAfter = pool.totalDebt();

        assertTrue(debtAfter >= debtBefore);
    }

    function testFuzz_liquidationAmounts(uint256 priceDropPercent, uint256 debtToCover) public {
        priceDropPercent = bound(priceDropPercent, 21, 90);

        vm.startPrank(user);
        pool.depositCollateral(10 * 1e18);
        pool.borrow(15_000 * 1e6);
        vm.stopPrank();

        uint256 newPrice = (2000 * (100 - priceDropPercent)) / 100;
        wethFeed.setPrice(int256(newPrice) * 1e8);

        assertTrue(pool.healthFactor(user) < 1e18);

        address liquidator = address(0x222);
        usdc.mint(liquidator, 15_000 * 1e6);
        vm.startPrank(liquidator);
        usdc.approve(address(pool), type(uint256).max);

        uint256 wethBefore = weth.balanceOf(liquidator);
        uint256 usdcBefore = usdc.balanceOf(liquidator);

        debtToCover = bound(debtToCover, 1, 15_000 * 1e6);
        pool.liquidate(user, debtToCover);

        uint256 wethAfter = weth.balanceOf(liquidator);
        uint256 wethReceived = wethAfter - wethBefore;

        uint256 actualValueReceivedUSD = wethReceived * newPrice;

        uint256 actualDebtCovered = usdcBefore - usdc.balanceOf(liquidator);
        uint256 expectedValueReceivedUSD = (actualDebtCovered * 1e18 * 110) / (1e6 * 100);

        // Liquidator should never get MORE than the expected value (plus minor precision rounding margin)
        assertTrue(actualValueReceivedUSD <= expectedValueReceivedUSD + 1e18);
        vm.stopPrank();
    }
}
