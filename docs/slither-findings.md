# Slither Findings & Justification

**High Severity:** 0
**Medium Severity:** 0

### Low / Informational Findings

**1. Block Timestamp**
- **Location:** `LendingPool.sol` (Interest calculation)
- **Severity:** Low
- **Justification:** The protocol relies on `block.timestamp` to calculate continuous interest across long periods. Minor miner manipulation (within 15 seconds) has a mathematically negligible effect on the accrued interest. Accepted risk.

**2. Low-Level Call**
- **Location:** `TreasuryV1.sol` (withdrawETH function)
- **Severity:** Informational
- **Justification:** Native ETH withdrawals require the use of `.call{value: amount}("")`. Reentrancy risk is mitigated by applying the `whenNotPaused` modifier, CEI pattern, and strict `FUND_MANAGER_ROLE` access control.

**3. Unsafe ERC20 Operations**
- **Location:** `Pair.sol`
- **Severity:** Low
- **Justification:** Slither flags standard `transfer` and `transferFrom`. The protocol intentionally uses raw ERC20 calls inside the Pair to save gas, ensuring only standard, compliant ERC20 tokens (WETH/USDC) are permitted by the PairFactory.