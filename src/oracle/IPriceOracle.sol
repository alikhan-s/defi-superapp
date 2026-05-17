// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title IPriceOracle
/// @notice Oracle adapter interface for the DeFi Super-App price oracle layer.
/// @dev    All implementations must expose both a raw price getter and a safe,
///         normalised getter that reverts on invalid data.
interface IPriceOracle {
    /// @notice Return the raw price data for `asset` as reported by the underlying feed.
    /// @param asset      The ERC-20 token address whose price is queried.
    /// @return answer    Raw price value (signed; decimals are feed-specific).
    /// @return decimals_ Number of decimals in `answer`.
    /// @return updatedAt Unix timestamp of the last feed update.
    function getPrice(address asset) external view returns (int256 answer, uint8 decimals_, uint256 updatedAt);

    /// @notice Return the asset price normalised to 18 decimals, reverting on any invalid state.
    /// @dev    Reverts if:
    ///         - No feed is configured for `asset`
    ///         - `block.timestamp - updatedAt > maxStaleness`
    ///         - `answer <= 0`
    ///         - `updatedAt == 0` (round not yet finalised)
    /// @param asset        The ERC-20 token address whose price is queried.
    /// @param maxStaleness Maximum acceptable age of the price data in seconds.
    /// @return normalizedTo18 Price scaled to 18 decimal places.
    function getPriceSafe(address asset, uint256 maxStaleness) external view returns (uint256 normalizedTo18);
}
