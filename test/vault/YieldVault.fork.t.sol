// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { YieldVault, ILendingPool } from "../../src/vault/YieldVault.sol";
import { LendingPool } from "../../src/lending/LendingPool.sol";
import { ChainlinkPriceOracle } from "../../src/oracle/ChainlinkPriceOracle.sol";
import { MockAggregator } from "../../src/oracle/MockAggregator.sol";
import { MockERC20 } from "../helpers/MockERC20.sol";

contract YieldVaultForkTest is Test {
    YieldVault public vault;
    LendingPool public pool;
    ChainlinkPriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;

    MockAggregator public wethFeed;
    MockAggregator public usdcFeed;

    address public admin = address(this);
    address public user = address(0x111);
    address public borrower = address(0x222);

    function setUp() public {
        string memory rpcUrl = vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", string("https://sepolia-rollup.arbitrum.io/rpc"));
        vm.createSelectFork(rpcUrl);

        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        oracle = new ChainlinkPriceOracle(admin);
        wethFeed = new MockAggregator(2000 * 1e8, 8);
        usdcFeed = new MockAggregator(1 * 1e8, 8);

        oracle.addFeed(address(weth), address(wethFeed), 86_400);
        oracle.addFeed(address(usdc), address(usdcFeed), 86_400);

        pool = new LendingPool(address(weth), address(usdc), address(oracle), 8000, 1000, 100, 1000, admin);

        vault = new YieldVault(usdc, ILendingPool(address(pool)), "Yield Vault", "yvUSDC", admin);

        usdc.mint(user, 10_000 * 1e6);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);

        weth.mint(borrower, 100 * 1e18);
        vm.startPrank(borrower);
        weth.approve(address(pool), type(uint256).max);
        pool.depositCollateral(100 * 1e18);
        vm.stopPrank();
    }

    function test_fork_yieldCycle() public {
        // 1. Deposit into vault
        vm.prank(user);
        uint256 shares = vault.deposit(10_000 * 1e6, user);

        // 2. Borrower takes a loan
        vm.prank(borrower);
        pool.borrow(5000 * 1e6);

        // 3. Time passes (30 days)
        vm.warp(block.timestamp + 30 days);
        pool.accrueInterest();

        // 4. Admin harvests yield
        vm.prank(admin);
        vault.harvest();

        // 4.5 Borrower repays loan + interest so pool has liquidity
        usdc.mint(borrower, 10_000 * 1e6); // Give borrower extra for interest
        vm.startPrank(borrower);
        usdc.approve(address(pool), type(uint256).max);
        pool.repay(type(uint256).max);
        vm.stopPrank();

        // 5. User withdraws, gets back more than deposited
        vm.prank(user);
        uint256 withdrawn = vault.redeem(shares, user, user);

        assertTrue(withdrawn > 10_000 * 1e6, "Should withdraw with profit");
    }
}
