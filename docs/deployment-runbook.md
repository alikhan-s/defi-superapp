# Deployment Runbook — Arbitrum Sepolia

End-to-end playbook for deploying the protocol to a live testnet and verifying it.

## 1. Prerequisites

| Tool | Version |
| --- | --- |
| [foundry](https://book.getfoundry.sh/getting-started/installation) | stable (`forge --version`) |
| [jq](https://stedolan.github.io/jq/) | any (used in post-deploy checks) |

Funded deployer EOA on **Arbitrum Sepolia** (chain ID `421614`). Faucet: <https://faucet.quicknode.com/arbitrum/sepolia>.

## 2. Required environment variables

```bash
# RPC endpoint (Alchemy / Infura / public node)
ARBITRUM_SEPOLIA_RPC_URL=https://arb-sepolia.g.alchemy.com/v2/<key>

# Deployer key (must be funded with Arbitrum Sepolia ETH)
PRIVATE_KEY=0x<64 hex chars>

# Arbiscan key for contract verification (free tier OK)
ARBISCAN_API_KEY=<key>
```

Add them to `.env` (already gitignored) and `source .env` before running any forge command.

## 3. Fill the chain config

Edit [script/config/421614.json](../script/config/421614.json) and replace the two zero-address placeholders with the real Arbitrum Sepolia WETH and USDC token addresses you intend to use.
`Deploy.s.sol` will revert *before broadcasting* if either is still `address(0)`.

The Chainlink feed addresses are pre-filled with the published Arbitrum Sepolia ETH/USD and USDC/USD feeds and don't normally need changing.

## 4. Dry-run

```bash
forge script script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

A clean run prints the addresses each contract *would* land at and reports gas. No broadcast is sent. Verify all logs look sane (no zero addresses, no reverts) before continuing.

## 5. Broadcast + verify

```bash
forge script script/Deploy.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ARBISCAN_API_KEY
```

The script is idempotent: if `deployments/421614.json` already contains an address with bytecode, that contract is reused and only the missing pieces are deployed. Safe to re-run after a partial failure.

On success:
- All addresses are written to `deployments/421614.json`.
- Contracts are submitted to Arbiscan for source verification.
- Final ownership: every contract listed in the spec has `DEFAULT_ADMIN_ROLE` on the Timelock; the deployer EOA has renounced its admin role on each.

## 6. Post-deployment verification

```bash
forge script script/PostDeployCheck.s.sol \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL
```

The script reverts (with the failing assertion name) if anything is misconfigured. On success it writes [docs/post-deployment-report.md](post-deployment-report.md) with a `- [x] ...` line per check.

Checks performed:
- Treasury / LendingPool / PairFactory / YieldVault admin == Timelock
- Deployer no longer holds `DEFAULT_ADMIN_ROLE` on any of the above
- `Timelock.getMinDelay() == 2 days`
- `Governor.votingDelay()`, `votingPeriod()`, `quorumNumerator()`, `proposalThreshold()` match the constants
- `Governor.token() == GovernanceToken`
- Oracle returns non-stale ETH and USDC prices

## 7. Gas comparison (optional)

```bash
# L1-baseline run against a local Anvil
anvil &
forge script script/GasComparison.s.sol --rpc-url http://localhost:8545 | grep GASCOMP

# L2 run against Arbitrum Sepolia
forge script script/GasComparison.s.sol \
  --fork-url $ARBITRUM_SEPOLIA_RPC_URL | grep GASCOMP
```

Copy the two sets of numbers into the table in [docs/gas-comparison-l1-l2.md](gas-comparison-l1-l2.md).

## 8. Rollback / re-deploy

To redeploy a single contract from scratch, delete its entry from `deployments/421614.json` and re-run `Deploy.s.sol`. The orchestrator's bytecode check will treat the missing entry as a hole and deploy a fresh instance.

To redeploy everything, delete `deployments/421614.json` entirely.
