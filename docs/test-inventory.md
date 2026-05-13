# Test Inventory

| Category | Description | Count | Minimum Required | Status |
| :--- | :--- | :--- | :--- | :--- |
| **Unit Tests** | State isolated logic tests across all core contracts. | 68 | 50 | PASS |
| **Fuzz Tests** | Property-based testing with random inputs (e.g., amounts). | 14 | 10 | PASS |
| **Invariant Tests** | Stateful fuzzing ensuring K-invariant and Vault state. | 6 | 5 | PASS |
| **Fork Tests** | Mainnet state forking (Chainlink integration, Arbitrum). | 4 | 3 | PASS |
| **Security Tests** | Reproduction of attack vectors and mitigations. | 6 | 2 | PASS |
| **Total** | | **98** | **80** | PASS |