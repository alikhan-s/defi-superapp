// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @title MockAggregator
/// @notice Minimal AggregatorV3Interface stub for use in unit tests.
/// @dev    NOT intended for production use. All values are freely configurable.
contract MockAggregator is AggregatorV3Interface {
    int256 private _price;
    uint256 private _updatedAt;
    uint8 private _decimals;
    uint80 private _roundId;

    constructor(int256 initialPrice, uint8 initialDecimals) {
        _price = initialPrice;
        _decimals = initialDecimals;
        _updatedAt = block.timestamp;
        _roundId = 1;
    }

    // -------------------------------------------------------------------------
    // Setters — test control surface
    // -------------------------------------------------------------------------

    function setPrice(int256 price) public {
        _price = price;
    }

    function setUpdatedAt(uint256 updatedAt) public {
        _updatedAt = updatedAt;
    }

    function setDecimals(uint8 decimals_) public {
        _decimals = decimals_;
    }

    // -------------------------------------------------------------------------
    // AggregatorV3Interface
    // -------------------------------------------------------------------------

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external pure override returns (string memory) {
        return "MockAggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _updatedAt, _updatedAt, _roundId);
    }
}
