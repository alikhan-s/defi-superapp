// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Test } from "forge-std/Test.sol";
import { PairMathYul } from "../../src/amm/PairMathYul.sol";

/// @notice Gas benchmark: inline Yul vs pure-Solidity getAmountOut.
///
///         Run with:
///           forge test --match-contract PairGasTest -vv
///
///         The test writes results to docs/gas-yul-vs-solidity.md.
contract PairGasTest is Test {
    uint256 internal constant AMOUNT_IN = 1000e18;
    uint256 internal constant RESERVE_IN = 1_000_000e18;
    uint256 internal constant RESERVE_OUT = 1_000_000e18;

    uint256 internal constant ITERATIONS = 100;

    function test_gas_yulVsSolidity() public {
        // --- Yul ---
        uint256 gasStartYul = gasleft();
        for (uint256 i; i < ITERATIONS; ++i) {
            PairMathYul.getAmountOut(AMOUNT_IN + i, RESERVE_IN, RESERVE_OUT);
        }
        uint256 gasYul = gasStartYul - gasleft();

        // --- Solidity ---
        uint256 gasStartSol = gasleft();
        for (uint256 i; i < ITERATIONS; ++i) {
            PairMathYul.getAmountOutSol(AMOUNT_IN + i, RESERVE_IN, RESERVE_OUT);
        }
        uint256 gasSol = gasStartSol - gasleft();

        uint256 perCallYul = gasYul / ITERATIONS;
        uint256 perCallSol = gasSol / ITERATIONS;

        emit log_named_uint("Gas per call - Yul    ", perCallYul);
        emit log_named_uint("Gas per call - Solidity", perCallSol);

        // Sanity: results must agree
        uint256 outYul = PairMathYul.getAmountOut(AMOUNT_IN, RESERVE_IN, RESERVE_OUT);
        uint256 outSol = PairMathYul.getAmountOutSol(AMOUNT_IN, RESERVE_IN, RESERVE_OUT);
        assertEq(outYul, outSol, "Yul and Solidity must agree");

        // Write markdown report to docs/
        string memory report = string.concat(
            "# getAmountOut: Yul vs Solidity Gas Benchmark\n\n",
            "| Implementation | Gas per call |\n",
            "|---|---|\n",
            "| Yul            | ",
            vm.toString(perCallYul),
            " |\n",
            "| Solidity       | ",
            vm.toString(perCallSol),
            " |\n\n",
            "_Iterations: ",
            vm.toString(ITERATIONS),
            " | amountIn: 1 000e18 | reserveIn = reserveOut = 1 000 000e18_\n"
        );

        vm.writeFile("docs/gas-yul-vs-solidity.md", report);
    }
}
