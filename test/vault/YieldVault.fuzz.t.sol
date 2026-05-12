// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { YieldVault, ILendingPool } from "../../src/vault/YieldVault.sol";
import { LendingPool } from "../../src/lending/LendingPool.sol";
import { ChainlinkPriceOracle } from "../../src/oracle/ChainlinkPriceOracle.sol";
import { MockAggregator } from "../../src/oracle/MockAggregator.sol";
import { MockERC20 } from "../helpers/MockERC20.sol";

contract YieldVaultFuzzTest is Test {
    YieldVault public vault;
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

        wethFeed = new MockAggregator(2000 * 1e8, 8); // $2000
        usdcFeed = new MockAggregator(1 * 1e8, 8); // $1

        oracle.addFeed(address(weth), address(wethFeed), 86_400);
        oracle.addFeed(address(usdc), address(usdcFeed), 86_400);

        pool = new LendingPool(
            address(weth),
            address(usdc),
            address(oracle),
            8000, 1000, 100, 1000, admin
        );

        vault = new YieldVault(
            usdc,
            ILendingPool(address(pool)),
            "Yield Vault",
            "yvUSDC",
            admin
        );

        usdc.mint(user, type(uint128).max);
        
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    function testFuzz_depositWithdraw(uint256 depositAmt) public {
        depositAmt = bound(depositAmt, 1e6, 1_000_000_000 * 1e6); // bounded to realistic USDC amounts

        vm.startPrank(user);
        uint256 shares = vault.deposit(depositAmt, user);
        
        uint256 withdrawn = vault.withdraw(depositAmt, user, user);
        vm.stopPrank();

        // Should withdraw exactly what was deposited if no yield accrued and no rounding loss.
        // Or if rounding occurs, user cannot withdraw more than deposited.
        assertTrue(withdrawn >= depositAmt - 1, "Rounding should be tiny");
    }

    function testFuzz_previewFavorsVault(uint256 assets) public {
        assets = bound(assets, 1e6, 1_000_000 * 1e6);

        uint256 pShares = vault.previewDeposit(assets);
        
        vm.prank(user);
        uint256 mShares = vault.deposit(assets, user);

        // Preview should not under-estimate shares given to vault?
        // Actually, ERC4626 standard requires previewDeposit to be INCLUSIVE of fees, meaning it is an EXACT prediction.
        // It should match exactly or favor the vault. 
        // We favor the vault by minting FEWER shares. So mShares <= pShares is not strictly required if exact.
        assertEq(pShares, mShares);
    }
}
