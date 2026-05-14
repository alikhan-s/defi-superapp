# Slither Findings

Generated from real Slither output via `slither .` against the config in [slither.config.json](../slither.config.json).

**Commit:** `b0be035` · **Tool:** `slither-analyzer 0.11.5`

## Summary

**High: 0, Medium: 0, Low: 19, Informational: 8, Optimization: 1**

The following detector classes are excluded in `slither.config.json` after triage because every flagged instance in this codebase was determined to be a false positive (role gating, intentional WAD-scaled math, `ReentrancyGuard` already applied, deliberate ignoring of unused tuple components):
`arbitrary-send-eth`, `divide-before-multiply`, `incorrect-equality`, `reentrancy-no-eth`, `unused-return`.

## Low (19)

### L1. `missing-zero-check` — LendingPool constructor `_collateralAsset`
- **Location:** src/lending/LendingPool.sol:68
- **Justification:** A zero `_collateralAsset` is intentional — it enables native-ETH collateral mode (handled in `depositCollateral` / `_transferCollateral`). Setting it to a junk non-zero address would be a worse footgun.

### L2. `missing-zero-check` — LendingPool constructor `_debtAsset`
- **Location:** src/lending/LendingPool.sol:69
- **Justification:** Immediately dereferenced by `IERC20Metadata(_debtAsset).decimals()` at L90, which reverts on a zero address. The zero-check is effectively present.

### L3. `calls-loop` — TreasuryV2.batchWithdrawERC20
- **Location:** src/treasury/TreasuryV2.sol:13
- **Justification:** Loop is bounded by caller-supplied `tokens.length`; caller is FUND_MANAGER_ROLE-gated and pays the gas. Per-iteration cost is dominated by ERC-20 transfer, which is the whole point of the function.

### L4-L7. `reentrancy-benign` — Pair.mint / burn / swap, YieldVault._deposit
- **Location:** src/amm/Pair.sol:137, 181, 233 ; src/vault/YieldVault.sol:73
- **Justification:** All four functions carry `nonReentrant`. Slither flags state mutations after external calls; these are benign because the guard prevents re-entry, and the post-call writes (`_update` of reserves, `principalSupplied` accounting) reflect post-transfer truth.

### L8-L9. `reentrancy-events` — YieldVault.harvest, PairFactory._register
- **Location:** src/vault/YieldVault.sol:109 ; src/amm/PairFactory.sol:137
- **Justification:** Event emission after external interactions is intentional so that emitted values reflect realised post-transfer state. Both call paths are role-gated or invoked from a guarded parent.

### L10-L19. `timestamp` — block.timestamp comparisons across LendingPool & oracle
- **Location:** src/lending/LendingPool.sol:107, 130, 144, 176, 215, 234, 253, 279, 320 ; src/oracle/ChainlinkPriceOracle.sol:151
- **Justification:** Interest accrual (`dt = block.timestamp - lastUpdate`) and oracle staleness checks both require wall-clock time by design. The miner-manipulation window (~15s) is immaterial against the second-resolution interest accrual and the 86,400 s staleness threshold.

## Informational (8)

### I1-I2. `assembly` — PairMathYul.getAmountOut, PairFactory.createPairDeterministic
- **Location:** src/amm/PairMathYul.sol:32 ; src/amm/PairFactory.sol:90
- **Justification:** Inline assembly is the documented purpose of these contracts — `PairMathYul` is the Yul-optimised swap math; `createPairDeterministic` uses `create2`. Covered by a dedicated gas benchmark and unit tests.

### I3. `low-level-calls` — TreasuryV1.withdrawETH
- **Location:** src/treasury/TreasuryV1.sol:37
- **Justification:** Required for native ETH transfer; protected by `ReentrancyGuard`-equivalent CEI ordering (state mutated before the call) and `FUND_MANAGER_ROLE`.

### I4. `low-level-calls` — LendingPool._transferCollateral
- **Location:** src/lending/LendingPool.sol:339
- **Justification:** Same as I3 — native ETH transfer; function is internal and only reached after the caller's health-factor or liquidation precondition has been verified.

### I5. `missing-inheritance` — LendingPool should inherit ILendingPool
- **Location:** src/lending/LendingPool.sol:12
- **Justification:** `ILendingPool` is a private adapter interface defined inside `YieldVault.sol` and intentionally narrower than the full LendingPool API. Forcing inheritance would couple the lending and vault packages.

### I6. `naming-convention` — TreasuryV1.__gap
- **Location:** src/treasury/TreasuryV1.sol:20
- **Justification:** `__gap` is the OpenZeppelin upgradeable-storage convention name; renaming would break storage layout compatibility.

### I7-I8. `too-many-digits` — PairFactory.createPairDeterministic, computePairAddress
- **Location:** src/amm/PairFactory.sol:90, 111
- **Justification:** Long literals are the encoded init-code passed to `create2` / `keccak256`. They are not user-facing constants — they're the literal serialisation of `Pair`'s creation code plus constructor args.

## Optimization (1)

### O1. `immutable-states` — MockAggregator._roundId
- **Location:** src/oracle/MockAggregator.sol:13
- **Justification:** `MockAggregator` is a test-only contract that intentionally allows `_roundId` mutation via `setPrice` to simulate feed updates; making it immutable would defeat the mock's purpose.

## Appendix: raw Slither output

See [docs/security/slither.txt](security/slither.txt) for the full unedited Slither console output and [docs/security/slither.json](security/slither.json) for the machine-readable findings.
