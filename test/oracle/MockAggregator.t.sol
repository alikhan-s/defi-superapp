// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { MockAggregator } from "../../src/oracle/MockAggregator.sol";

contract MockAggregatorTest is Test {
    MockAggregator internal mock;

    int256 internal constant INIT_PRICE = 2500e8;
    uint8 internal constant INIT_DECIMALS = 8;

    function setUp() public {
        mock = new MockAggregator(INIT_PRICE, INIT_DECIMALS);
    }

    function test_mock_description() public view {
        string memory desc = mock.description();
        assertGt(bytes(desc).length, 0, "description must be non-empty");
    }

    function test_mock_version() public view {
        uint256 v = mock.version();
        assertEq(v, 1);
    }

    function test_mock_getRoundData() public view {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            mock.getRoundData(1);

        assertEq(roundId, 1);
        assertEq(answer, INIT_PRICE);
        assertGt(startedAt, 0);
        assertGt(updatedAt, 0);
        assertEq(answeredInRound, 1);
    }

    function test_mock_setPrice() public {
        int256 newPrice = 3000e8;
        mock.setPrice(newPrice);

        (, int256 answer,,,) = mock.latestRoundData();
        assertEq(answer, newPrice);
    }

    function test_mock_setUpdatedAt() public {
        uint256 newTs = 1_700_000_000;
        mock.setUpdatedAt(newTs);

        (,,, uint256 updatedAt,) = mock.latestRoundData();
        assertEq(updatedAt, newTs);
    }

    function test_mock_setDecimals() public {
        mock.setDecimals(6);
        assertEq(mock.decimals(), 6);
    }

    function test_mock_latestRoundData_reflectsAllSetters() public {
        mock.setPrice(1e6);
        mock.setDecimals(6);
        mock.setUpdatedAt(999);

        (uint80 roundId, int256 answer,, uint256 updatedAt,) = mock.latestRoundData();

        assertEq(roundId, 1);
        assertEq(answer, 1e6);
        assertEq(updatedAt, 999);
        assertEq(mock.decimals(), 6);
    }
}
