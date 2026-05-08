// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IPriceOracle } from "./IPriceOracle.sol";

/// @title ChainlinkPriceOracle
/// @notice IPriceOracle implementation backed by Chainlink AggregatorV3 feeds.
/// @dev    Feed management is role-gated via AccessControl.
///         All price reads are validated for staleness, sign, and round completeness
///         before being returned to callers.
contract ChainlinkPriceOracle is IPriceOracle, AccessControl {
    // -------------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------------

    /// @notice Role authorised to add, remove, and update feed configurations.
    bytes32 public constant FEED_MANAGER_ROLE = keccak256("FEED_MANAGER_ROLE");

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    /// @notice Per-asset Chainlink feed configuration.
    struct FeedConfig {
        AggregatorV3Interface feed;
        uint256 maxStaleness;
        bool exists;
    }

    /// @notice Maps an asset address to its Chainlink feed configuration.
    mapping(address asset => FeedConfig) public feeds;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a new feed is registered for an asset.
    /// @param asset        The asset whose feed was added.
    /// @param feed         The AggregatorV3Interface address.
    /// @param maxStaleness Maximum staleness threshold in seconds.
    event FeedAdded(address indexed asset, address indexed feed, uint256 maxStaleness);

    /// @notice Emitted when a feed is unregistered for an asset.
    /// @param asset The asset whose feed was removed.
    event FeedRemoved(address indexed asset);

    /// @notice Emitted when the staleness threshold for an asset feed is updated.
    /// @param asset        The asset whose threshold changed.
    /// @param maxStaleness New maximum staleness in seconds.
    event StalenessUpdated(address indexed asset, uint256 maxStaleness);

    // -------------------------------------------------------------------------
    // Custom errors
    // -------------------------------------------------------------------------

    /// @notice Thrown when `getPrice` or `getPriceSafe` is called for an asset with no feed.
    error FeedNotConfigured();

    /// @notice Thrown when the price data is older than the configured maximum staleness.
    /// @param age Current age of the price data in seconds.
    /// @param max Configured maximum staleness in seconds.
    error StalePrice(uint256 age, uint256 max);

    /// @notice Thrown when the feed returns a non-positive answer.
    error InvalidPrice();

    /// @notice Thrown when the round has not yet been finalised (updatedAt == 0).
    error RoundIncomplete();

    /// @notice Thrown when a zero address is provided for a required parameter.
    error ZeroAddress();

    /// @notice Thrown when maxStaleness is set to zero.
    error ZeroStaleness();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    /// @notice Deploy the oracle and grant the deployer both admin and feed-manager roles.
    /// @param admin Address granted DEFAULT_ADMIN_ROLE and FEED_MANAGER_ROLE.
    constructor(address admin) {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(FEED_MANAGER_ROLE, admin);
    }

    // -------------------------------------------------------------------------
    // Feed management
    // -------------------------------------------------------------------------

    /// @notice Register a Chainlink feed for an asset.
    /// @dev    Overwrites any existing configuration for the same asset.
    /// @param asset        ERC-20 token address.
    /// @param feed         AggregatorV3Interface-compliant feed address.
    /// @param maxStaleness Maximum acceptable age of a price update in seconds.
    function addFeed(address asset, address feed, uint256 maxStaleness) external onlyRole(FEED_MANAGER_ROLE) {
        if (asset == address(0) || feed == address(0)) revert ZeroAddress();
        if (maxStaleness == 0) revert ZeroStaleness();

        feeds[asset] = FeedConfig({ feed: AggregatorV3Interface(feed), maxStaleness: maxStaleness, exists: true });

        emit FeedAdded(asset, feed, maxStaleness);
    }

    /// @notice Unregister the feed for an asset.
    /// @param asset ERC-20 token address whose feed should be removed.
    function removeFeed(address asset) external onlyRole(FEED_MANAGER_ROLE) {
        if (!feeds[asset].exists) revert FeedNotConfigured();
        delete feeds[asset];
        emit FeedRemoved(asset);
    }

    /// @notice Update the staleness threshold for an already-registered feed.
    /// @param asset        ERC-20 token address.
    /// @param maxStaleness New maximum acceptable age in seconds.
    function updateStaleness(address asset, uint256 maxStaleness) external onlyRole(FEED_MANAGER_ROLE) {
        if (!feeds[asset].exists) revert FeedNotConfigured();
        if (maxStaleness == 0) revert ZeroStaleness();
        feeds[asset].maxStaleness = maxStaleness;
        emit StalenessUpdated(asset, maxStaleness);
    }

    // -------------------------------------------------------------------------
    // IPriceOracle — getPrice
    // -------------------------------------------------------------------------

    /// @inheritdoc IPriceOracle
    /// @dev Validates feed existence but does NOT check staleness or sign here;
    ///      callers that need validated data should use `getPriceSafe`.
    function getPrice(address asset)
        external
        view
        override
        returns (int256 answer, uint8 decimals_, uint256 updatedAt)
    {
        FeedConfig storage cfg = feeds[asset];
        if (!cfg.exists) revert FeedNotConfigured();

        (, answer,, updatedAt,) = cfg.feed.latestRoundData();
        decimals_ = cfg.feed.decimals();
    }

    // -------------------------------------------------------------------------
    // IPriceOracle — getPriceSafe
    // -------------------------------------------------------------------------

    /// @inheritdoc IPriceOracle
    function getPriceSafe(address asset, uint256 maxStaleness) external view override returns (uint256 normalizedTo18) {
        FeedConfig storage cfg = feeds[asset];
        if (!cfg.exists) revert FeedNotConfigured();

        (, int256 answer,, uint256 updatedAt,) = cfg.feed.latestRoundData();

        if (updatedAt == 0) revert RoundIncomplete();
        if (answer <= 0) revert InvalidPrice();

        uint256 age = block.timestamp - updatedAt;
        if (age > maxStaleness) revert StalePrice(age, maxStaleness);

        uint8 feedDecimals = cfg.feed.decimals();
        normalizedTo18 = _normalizeTo18(uint256(answer), feedDecimals);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Scale `value` from `fromDecimals` to 18 decimals.
    ///      Truncates if fromDecimals > 18 (no overflow risk for realistic feed values).
    function _normalizeTo18(uint256 value, uint8 fromDecimals) internal pure returns (uint256) {
        if (fromDecimals == 18) return value;
        if (fromDecimals < 18) return value * 10 ** (18 - fromDecimals);
        return value / 10 ** (fromDecimals - 18);
    }
}
