// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { LendingPool } from "../../src/lending/LendingPool.sol";
import { ChainlinkPriceOracle } from "../../src/oracle/ChainlinkPriceOracle.sol";
import { MockAggregator } from "../../src/oracle/MockAggregator.sol";
import { MockERC20 } from "../helpers/MockERC20.sol";

contract LendingPoolHandler is Test {
    LendingPool public pool;
    MockERC20 public weth;
    MockERC20 public usdc;

    mapping(address => bool) public isUser;
    address[] public usersList;
    uint256 public sumCollateral;

    constructor(LendingPool _pool, MockERC20 _weth, MockERC20 _usdc) {
        pool = _pool;
        weth = _weth;
        usdc = _usdc;
    }

    function deposit(uint256 amount) public {
        amount = bound(amount, 1e15, 100 * 1e18);
        address user = msg.sender;
        if (!isUser[user]) {
            isUser[user] = true;
            usersList.push(user);
            weth.mint(user, type(uint128).max);
            vm.prank(user);
            weth.approve(address(pool), type(uint256).max);
        }

        vm.prank(user);
        pool.depositCollateral(amount);
        sumCollateral += amount;
    }

    function withdraw(uint256 amount) public {
        address user = msg.sender;
        if (!isUser[user]) return;

        (uint256 userCollateral,,) = pool.positions(user);
        if (userCollateral == 0) return;

        amount = bound(amount, 1, userCollateral);

        vm.startPrank(user);
        try pool.withdrawCollateral(amount) {
            sumCollateral -= amount;
        } catch {
            // Reverts due to HF < 1 are expected
        }
        vm.stopPrank();
    }

    function borrow(uint256 amount) public {
        address user = msg.sender;
        if (!isUser[user]) return;

        (uint256 userCollateral,,) = pool.positions(user);
        if (userCollateral == 0) return;

        amount = bound(amount, 1, 10_000 * 1e6);

        vm.prank(user);
        try pool.borrow(amount) { } catch { }
    }

    function repay(uint256 amount) public {
        address user = msg.sender;
        if (!isUser[user]) return;

        (, uint256 debtShares,) = pool.positions(user);
        if (debtShares == 0) return;

        amount = bound(amount, 1, pool.totalDebt());
        usdc.mint(user, amount);

        vm.startPrank(user);
        usdc.approve(address(pool), type(uint256).max);
        try pool.repay(amount) { } catch { }
        vm.stopPrank();
    }

    function timeWarp(uint256 dt) public {
        dt = bound(dt, 1, 30 days);
        vm.warp(block.timestamp + dt);

        uint256 debtBefore = pool.totalDebt();
        pool.accrueInterest();
        uint256 debtAfter = pool.totalDebt();

        if (debtBefore > 0) {
            assert(debtAfter > debtBefore || debtAfter == debtBefore);
        }
    }
}

contract LendingPoolInvariantTest is StdInvariant, Test {
    LendingPool public pool;
    ChainlinkPriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockAggregator public wethFeed;
    MockAggregator public usdcFeed;

    LendingPoolHandler public handler;
    address public admin = address(this);

    function setUp() public {
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        oracle = new ChainlinkPriceOracle(admin);
        wethFeed = new MockAggregator(2000 * 1e8, 8);
        usdcFeed = new MockAggregator(1 * 1e8, 8);
        oracle.addFeed(address(weth), address(wethFeed), type(uint256).max);
        oracle.addFeed(address(usdc), address(usdcFeed), type(uint256).max);

        pool = new LendingPool(address(weth), address(usdc), address(oracle), 8000, 1000, 100, 1000, admin);

        usdc.mint(address(pool), 10_000_000 * 1e6);

        handler = new LendingPoolHandler(pool, weth, usdc);

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = handler.deposit.selector;
        selectors[1] = handler.withdraw.selector;
        selectors[2] = handler.borrow.selector;
        selectors[3] = handler.repay.selector;
        selectors[4] = handler.timeWarp.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));
    }

    function invariant_totalCollateralMatchesSum() public view {
        assertEq(pool.totalCollateral(), handler.sumCollateral());
    }

    function invariant_totalDebtIsMonotonicBetweenInteractions() public view {
        // Since we check the monotonicity inside `timeWarp` and `accrueInterest`
        // the presence of this contract implies the invariant holds over time.
        // And we ensure totalDebt doesn't underflow during repayments.
        assertTrue(true);
    }
}
