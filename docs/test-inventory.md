# Test Inventory

Counts derived from real `forge test --list` output. Commit: `b0be035`.

| Category | Description | Count | Minimum | Status |
| --- | --- | --- | --- | --- |
| **Unit** | `.t.sol` tests outside fuzz / invariant / fork / security suites | 195 | 50 | PASS |
| **Fuzz** | `*.fuzz.t.sol` files plus `testFuzz_*` functions | 12 | 10 | PASS |
| **Invariant** | `*.invariant.t.sol` files plus `invariant_*` functions | 6 | 5 | PASS |
| **Fork** | `*.fork.t.sol` files | 5 | 3 | PASS |
| **Security** | `test/security/*` | 5 | 2 | PASS |
| **Total** | | **223** | 80 | PASS |
