// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { ChainlinkPriceOracle } from "../../src/oracle/ChainlinkPriceOracle.sol";
import { MockAggregator } from "../../src/oracle/MockAggregator.sol";

contract ChainlinkPriceOracleTest is Test {
    // -------------------------------------------------------------------------
    // State
    // -------------------------------------------------------------------------

    ChainlinkPriceOracle internal oracle;
    MockAggregator internal feed8; // 8-decimal (e.g. ETH/USD Chainlink standard)
    MockAggregator internal feed6; // 6-decimal
    MockAggregator internal feed18; // 18-decimal

    bytes32 internal constant FEED_MANAGER_ROLE = keccak256("FEED_MANAGER_ROLE");

    address internal admin = makeAddr("admin");
    address internal manager = makeAddr("manager");
    address internal alice = makeAddr("alice");

    address internal ETH = makeAddr("ETH");
    address internal USDC = makeAddr("USDC");
    address internal DAI = makeAddr("DAI");

    // ETH/USD ≈ 2 500 USD with 8 decimals
    int256 internal constant ETH_PRICE_8 = 2500e8;
    // USDC/USD ≈ 1.000000 with 6 decimals
    int256 internal constant USDC_PRICE_6 = 1_000_000;
    // DAI/USD ≈ 1.0 with 18 decimals
    int256 internal constant DAI_PRICE_18 = 1e18;

    uint256 internal constant MAX_STALENESS = 1 hours;

    // -------------------------------------------------------------------------
    // Setup
    // -------------------------------------------------------------------------

    function setUp() public {
        oracle = new ChainlinkPriceOracle(admin);
        feed8 = new MockAggregator(ETH_PRICE_8, 8);
        feed6 = new MockAggregator(USDC_PRICE_6, 6);
        feed18 = new MockAggregator(DAI_PRICE_18, 18);

        vm.prank(admin);
        oracle.grantRole(FEED_MANAGER_ROLE, manager);

        // Register ETH with the 8-decimal feed
        vm.prank(manager);
        oracle.addFeed(ETH, address(feed8), MAX_STALENESS);
    }

    // -------------------------------------------------------------------------
    // 1. addFeed — role gating
    // -------------------------------------------------------------------------

    function test_addFeed_onlyFeedManager() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.addFeed(USDC, address(feed6), MAX_STALENESS);
    }

    function test_addFeed_storesConfig() public {
        vm.prank(manager);
        oracle.addFeed(USDC, address(feed6), MAX_STALENESS);

        (address storedFeed, uint256 storedStaleness, bool exists) = _getFeedConfig(USDC);

        assertEq(storedFeed, address(feed6));
        assertEq(storedStaleness, MAX_STALENESS);
        assertTrue(exists);
    }

    function test_addFeed_emitsFeedAdded() public {
        vm.prank(manager);
        vm.expectEmit(true, true, false, true);
        emit ChainlinkPriceOracle.FeedAdded(USDC, address(feed6), MAX_STALENESS);
        oracle.addFeed(USDC, address(feed6), MAX_STALENESS);
    }

    // -------------------------------------------------------------------------
    // 2. removeFeed — role gating and state
    // -------------------------------------------------------------------------

    function test_removeFeed_onlyFeedManager() public {
        vm.prank(alice);
        vm.expectRevert();
        oracle.removeFeed(ETH);
    }

    function test_removeFeed_clearsConfig() public {
        vm.prank(manager);
        oracle.removeFeed(ETH);

        (,, bool exists) = _getFeedConfig(ETH);
        assertFalse(exists);
    }

    function test_removeFeed_nonExistentReverts() public {
        vm.prank(manager);
        vm.expectRevert(ChainlinkPriceOracle.FeedNotConfigured.selector);
        oracle.removeFeed(USDC); // never added
    }

    // -------------------------------------------------------------------------
    // 3. updateStaleness
    // -------------------------------------------------------------------------

    function test_updateStaleness_changesStaleness() public {
        uint256 newStaleness = 2 hours;
        vm.prank(manager);
        oracle.updateStaleness(ETH, newStaleness);

        (, uint256 stored,) = _getFeedConfig(ETH);
        assertEq(stored, newStaleness);
    }

    function test_updateStaleness_differentLimitsPerFeed() public {
        vm.prank(manager);
        oracle.addFeed(USDC, address(feed6), 30 minutes);

        (, uint256 ethStaleness,) = _getFeedConfig(ETH);
        (, uint256 usdcStaleness,) = _getFeedConfig(USDC);

        assertEq(ethStaleness, MAX_STALENESS);
        assertEq(usdcStaleness, 30 minutes);
    }

    // -------------------------------------------------------------------------
    // 4. getPrice — happy path
    // -------------------------------------------------------------------------

    function test_getPrice_returnsRawValues() public view {
        (int256 answer, uint8 decimals_, uint256 updatedAt) = oracle.getPrice(ETH);

        assertEq(answer, ETH_PRICE_8);
        assertEq(decimals_, 8);
        assertGt(updatedAt, 0);
    }

    function test_getPrice_feedNotConfiguredReverts() public {
        vm.expectRevert(ChainlinkPriceOracle.FeedNotConfigured.selector);
        oracle.getPrice(USDC);
    }

    // -------------------------------------------------------------------------
    // 5. getPriceSafe — happy paths and normalization
    // -------------------------------------------------------------------------

    function test_getPriceSafe_normalizes8DecimalFeed() public view {
        uint256 price = oracle.getPriceSafe(ETH, MAX_STALENESS);
        // 2_500e8 → 2_500e18
        assertEq(price, 2500e18);
    }

    function test_getPriceSafe_normalizes6DecimalFeed() public {
        vm.prank(manager);
        oracle.addFeed(USDC, address(feed6), MAX_STALENESS);

        uint256 price = oracle.getPriceSafe(USDC, MAX_STALENESS);
        // 1_000_000 (6 dec) → 1e18
        assertEq(price, 1e18);
    }

    function test_getPriceSafe_normalizes18DecimalFeed() public {
        vm.prank(manager);
        oracle.addFeed(DAI, address(feed18), MAX_STALENESS);

        uint256 price = oracle.getPriceSafe(DAI, MAX_STALENESS);
        assertEq(price, 1e18);
    }

    // -------------------------------------------------------------------------
    // 6. getPriceSafe — revert paths
    // -------------------------------------------------------------------------

    function test_getPriceSafe_stalePriceReverts() public {
        // Advance time beyond maxStaleness
        vm.warp(block.timestamp + MAX_STALENESS + 1);

        vm.expectRevert();
        oracle.getPriceSafe(ETH, MAX_STALENESS);
    }

    function test_getPriceSafe_negativePriceReverts() public {
        feed8.setPrice(-1);

        vm.expectRevert(ChainlinkPriceOracle.InvalidPrice.selector);
        oracle.getPriceSafe(ETH, MAX_STALENESS);
    }

    function test_getPriceSafe_zeroPriceReverts() public {
        feed8.setPrice(0);

        vm.expectRevert(ChainlinkPriceOracle.InvalidPrice.selector);
        oracle.getPriceSafe(ETH, MAX_STALENESS);
    }

    function test_getPriceSafe_roundIncompleteReverts() public {
        feed8.setUpdatedAt(0);

        vm.expectRevert(ChainlinkPriceOracle.RoundIncomplete.selector);
        oracle.getPriceSafe(ETH, MAX_STALENESS);
    }

    function test_getPriceSafe_feedNotConfiguredReverts() public {
        vm.expectRevert(ChainlinkPriceOracle.FeedNotConfigured.selector);
        oracle.getPriceSafe(USDC, MAX_STALENESS);
    }

    // -------------------------------------------------------------------------
    // 7. StalePrice error carries correct age and max values
    // -------------------------------------------------------------------------

    function test_getPriceSafe_stalePriceErrorValues() public {
        // Warp to a realistic timestamp so subtraction doesn't underflow.
        vm.warp(1_700_000_000);
        uint256 ts = block.timestamp;
        // Set updatedAt 2 h in the past (beyond MAX_STALENESS = 1 h)
        uint256 updatedAt = ts - 2 hours;
        feed8.setUpdatedAt(updatedAt);

        uint256 expectedAge = ts - updatedAt;
        vm.expectRevert(abi.encodeWithSelector(ChainlinkPriceOracle.StalePrice.selector, expectedAge, MAX_STALENESS));
        oracle.getPriceSafe(ETH, MAX_STALENESS);
    }

    // -------------------------------------------------------------------------
    // 8. Constructor guards
    // -------------------------------------------------------------------------

    function test_constructor_rejectsZeroAdmin() public {
        vm.expectRevert(ChainlinkPriceOracle.ZeroAddress.selector);
        new ChainlinkPriceOracle(address(0));
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Read the public `feeds` mapping. The auto-generated getter returns
    ///      (AggregatorV3Interface, uint256, bool) which ABI-encodes as (address, uint256, bool).
    function _getFeedConfig(address asset) internal view returns (address feedAddr, uint256 maxStaleness, bool exists) {
        (bool ok, bytes memory ret) = address(oracle).staticcall(abi.encodeWithSignature("feeds(address)", asset));
        require(ok, "feeds() call failed");
        (feedAddr, maxStaleness, exists) = abi.decode(ret, (address, uint256, bool));
    }
}
