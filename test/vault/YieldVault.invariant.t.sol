// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { YieldVault, ILendingPool } from "../../src/vault/YieldVault.sol";
import { LendingPool } from "../../src/lending/LendingPool.sol";
import { ChainlinkPriceOracle } from "../../src/oracle/ChainlinkPriceOracle.sol";
import { MockAggregator } from "../../src/oracle/MockAggregator.sol";
import { MockERC20 } from "../helpers/MockERC20.sol";

contract YieldVaultHandler is Test {
    YieldVault public vault;
    LendingPool public pool;
    MockERC20 public usdc;

    uint256 public sumWithdrawable;

    constructor(YieldVault _vault, LendingPool _pool, MockERC20 _usdc) {
        vault = _vault;
        pool = _pool;
        usdc = _usdc;
    }

    function deposit(uint256 amount) public {
        amount = bound(amount, 1e6, 1_000_000 * 1e6);
        usdc.mint(address(this), amount);
        usdc.approve(address(vault), amount);

        uint256 shares = vault.deposit(amount, address(this));
        sumWithdrawable += vault.previewRedeem(shares);
    }
}

contract YieldVaultInvariantTest is Test {
    YieldVault public vault;
    LendingPool public pool;
    ChainlinkPriceOracle public oracle;
    MockERC20 public weth;
    MockERC20 public usdc;

    MockAggregator public wethFeed;
    MockAggregator public usdcFeed;

    YieldVaultHandler public handler;

    function setUp() public {
        weth = new MockERC20("Wrapped ETH", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);

        oracle = new ChainlinkPriceOracle(address(this));
        wethFeed = new MockAggregator(2000 * 1e8, 8);
        usdcFeed = new MockAggregator(1 * 1e8, 8);

        oracle.addFeed(address(weth), address(wethFeed), 86_400);
        oracle.addFeed(address(usdc), address(usdcFeed), 86_400);

        pool = new LendingPool(address(weth), address(usdc), address(oracle), 8000, 1000, 100, 1000, address(this));

        vault = new YieldVault(usdc, ILendingPool(address(pool)), "Yield Vault", "yvUSDC", address(this));

        handler = new YieldVaultHandler(vault, pool, usdc);
        targetContract(address(handler));
    }

    function invariant_totalAssetsGteSumWithdrawable() public view {
        assertTrue(vault.totalAssets() >= handler.sumWithdrawable());
    }
}
