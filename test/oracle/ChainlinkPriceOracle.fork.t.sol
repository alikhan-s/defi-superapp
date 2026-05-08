// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { ChainlinkPriceOracle } from "../../src/oracle/ChainlinkPriceOracle.sol";

/// @notice Live-fork tests against real Chainlink feeds on Arbitrum Sepolia.
/// @dev    Requires ARBITRUM_SEPOLIA_RPC_URL env var (or foundry.toml [rpc_endpoints]).
///         Run with: forge test --match-path test/oracle/*.fork.t.sol --fork-url $ARBITRUM_SEPOLIA_RPC_URL
contract ChainlinkPriceOracleForkTest is Test {
    // -------------------------------------------------------------------------
    // Arbitrum Sepolia feed addresses (Chainlink docs)
    // -------------------------------------------------------------------------

    // ETH / USD — Arbitrum Sepolia
    address internal constant ETH_USD_FEED = 0xd30e2101a97dcbAeBCBC04F14C3f624E67A35165;

    // BTC / USD — Arbitrum Sepolia
    address internal constant BTC_USD_FEED = 0x56a43EB56Da12C0dc1D972ACb089c06a5dEF8e69;

    // USDC / USD — Arbitrum Sepolia
    address internal constant USDC_USD_FEED = 0x0153002d20B96532c639313C291fBd1E4b659e8c;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 internal constant ONE_DAY = 24 hours;
    uint256 internal constant MAX_STALENESS = ONE_DAY;

    address internal constant ETH_TOKEN = address(0xE1);
    address internal constant BTC_TOKEN = address(0xB1);
    address internal constant USDC_TOKEN = address(0xC1);

    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    ChainlinkPriceOracle internal oracle;
    address internal admin = makeAddr("admin");

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        vm.createSelectFork(vm.envOr("ARBITRUM_SEPOLIA_RPC_URL", string("arbitrum_sepolia")));

        oracle = new ChainlinkPriceOracle(admin);

        vm.startPrank(admin);
        oracle.addFeed(ETH_TOKEN, ETH_USD_FEED, MAX_STALENESS);
        oracle.addFeed(BTC_TOKEN, BTC_USD_FEED, MAX_STALENESS);
        vm.stopPrank();
    }

    // -------------------------------------------------------------------------
    // Fork test 1 — ETH/USD: price > 0 and freshness
    // -------------------------------------------------------------------------

    function test_fork_ethUsd_pricePositiveAndFresh() public view {
        (int256 answer,, uint256 updatedAt) = oracle.getPrice(ETH_TOKEN);

        assertGt(answer, 0, "ETH/USD price must be positive");
        assertGt(updatedAt, 0, "updatedAt must be non-zero");
        assertLe(block.timestamp - updatedAt, ONE_DAY, "ETH/USD feed must be updated within last 24 h");
    }

    // -------------------------------------------------------------------------
    // Fork test 2 — ETH/USD: getPriceSafe normalises to 18 decimals in plausible range
    // -------------------------------------------------------------------------

    function test_fork_ethUsd_getPriceSafe_normalised() public view {
        uint256 price = oracle.getPriceSafe(ETH_TOKEN, MAX_STALENESS);

        // ETH price should be between $100 and $100 000 (sanity bounds, 18 dec)
        assertGt(price, 100e18, "ETH price below $100");
        assertLt(price, 100_000e18, "ETH price above $100 000");
    }

    // -------------------------------------------------------------------------
    // Fork test 3 — BTC/USD: independent feed reads correctly
    // -------------------------------------------------------------------------

    function test_fork_btcUsd_pricePositiveAndFresh() public view {
        (int256 answer,, uint256 updatedAt) = oracle.getPrice(BTC_TOKEN);

        assertGt(answer, 0, "BTC/USD price must be positive");
        assertLe(block.timestamp - updatedAt, ONE_DAY, "BTC/USD feed stale");
    }

    // -------------------------------------------------------------------------
    // Fork test 4 — raw feed decimals match expectation
    // -------------------------------------------------------------------------

    function test_fork_feedDecimals() public view {
        (, uint8 ethDecimals,) = oracle.getPrice(ETH_TOKEN);
        (, uint8 btcDecimals,) = oracle.getPrice(BTC_TOKEN);

        // Standard Chainlink USD feeds use 8 decimals
        assertEq(ethDecimals, 8, "ETH/USD feed should have 8 decimals");
        assertEq(btcDecimals, 8, "BTC/USD feed should have 8 decimals");
    }
}
