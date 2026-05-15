# DeFi Super-App Protocol

> A modular, upgradeable DeFi protocol covering tokens, oracles, AMM, lending, vaults, treasury, and governance — built with Foundry and OpenZeppelin.

## Overview

<!-- TODO: 2–3 paragraph description of the protocol's purpose, design philosophy, and target users. -->

## Architecture

```
src/
├── tokens/      # ERC-20 / ERC-721 / ERC-4626 token contracts
├── oracle/      # Chainlink price feed adapters and TWAP helpers
├── amm/         # Automated market maker (constant-product + concentrated)
├── lending/     # Collateralised lending pools and interest rate models
├── vault/       # ERC-4626 yield vaults and strategy layer
├── treasury/    # Protocol fee collection and allocation
└── governance/  # On-chain governor and timelock
```

<!-- TODO: Add architecture diagram link -->

## Deployed Contracts — Arbitrum Sepolia (chain ID `421614`)

Populated by [script/Deploy.s.sol](script/Deploy.s.sol). Explorer base: `https://sepolia.arbiscan.io/address/`.

| Contract | Address | Explorer |
| --- | --- | --- |
| GovernanceToken | `0x75126A3c6A49a595246b82a08DA73d7608337C36` | [arbiscan](https://sepolia.arbiscan.io/address/0x75126A3c6A49a595246b82a08DA73d7608337C36) |
| ChainlinkPriceOracle | `0x65DBbd9B7d2a04474dafAE487557ECCE805f33a9` | [arbiscan](https://sepolia.arbiscan.io/address/0x65DBbd9B7d2a04474dafAE487557ECCE805f33a9) |
| LPPositionNFT | `0x038F1A0E06E36EF33fdB963CF2DE4570F319eA0c` | [arbiscan](https://sepolia.arbiscan.io/address/0x038F1A0E06E36EF33fdB963CF2DE4570F319eA0c) |
| PairFactory | `0xf56921ef32f00C65836E99324e350F97C5c39229` | [arbiscan](https://sepolia.arbiscan.io/address/0xf56921ef32f00C65836E99324e350F97C5c39229) |
| SamplePair (WETH/USDC) | `0xC139a14BCA5e03Da3C3ea6be458A5E592e37BFF4` | [arbiscan](https://sepolia.arbiscan.io/address/0xC139a14BCA5e03Da3C3ea6be458A5E592e37BFF4) |
| LendingPool | `0x0013766F7fb601E43aF9b4b1F40C9bE667E53205` | [arbiscan](https://sepolia.arbiscan.io/address/0x0013766F7fb601E43aF9b4b1F40C9bE667E53205) |
| YieldVault (yvUSDC) | `0xfb72FBbA8cbeb5D3C8E5871912A4884B7492C852` | [arbiscan](https://sepolia.arbiscan.io/address/0xfb72FBbA8cbeb5D3C8E5871912A4884B7492C852) |
| TreasuryProxy (UUPS) | `0x9C0005C1E5d91BadDE2941f021bD8d66748495fe` | [arbiscan](https://sepolia.arbiscan.io/address/0x9C0005C1E5d91BadDE2941f021bD8d66748495fe) |
| ProtocolTimelock | `0x85dBA7e4Ef173DD5daFcD6977f070bAD6fe2e61C` | [arbiscan](https://sepolia.arbiscan.io/address/0x85dBA7e4Ef173DD5daFcD6977f070bAD6fe2e61C) |
| ProtocolGovernor | `0xdED11a6Fa7062B7b6422061B54998C4002c2d80b` | [arbiscan](https://sepolia.arbiscan.io/address/0xdED11a6Fa7062B7b6422061B54998C4002c2d80b) |

See [docs/deployment-runbook.md](docs/deployment-runbook.md) for the end-to-end deployment + verification procedure. Source of truth for the addresses is [deployments/421614.json](deployments/421614.json) after a successful broadcast.

**Subgraph (The Graph — Arbitrum Sepolia):**

- Studio dashboard: `https://thegraph.com/studio/subgraph/defi-superapp/`
- Query endpoint (Studio): `https://api.studio.thegraph.com/query/<STUDIO_ID>/defi-superapp/v0.0.1`
- Source: [subgraph/](subgraph/) — `subgraph.yaml`, `schema.graphql`, mappings under `src/mappings/`
- Sample queries: [subgraph/queries.md](subgraph/queries.md) (top pools, user swaps, proposal states, at-risk lending positions, full portfolio)

Build and deploy:

```bash
cd subgraph
npm install
npx graph codegen
npx graph build
# Authenticate once with the deploy key from https://thegraph.com/studio
npx graph auth --studio <DEPLOY_KEY>
npx graph deploy --studio defi-superapp --version-label v0.0.1
```

The `<STUDIO_ID>` placeholder above is filled in by The Graph Studio after the first successful deploy.

**Frontend:** TBD — populated in Phase 11.

## Run Locally

**Prerequisites:** [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.

```bash
# Clone with submodules
git clone --recurse-submodules https://github.com/your-org/defi-superapp
cd defi-superapp

# Build
forge build

# Run tests (with verbosity)
forge test -vvv

# Run fuzz + invariant tests
forge test --match-path "test/**/*.t.sol"

# Format check
forge fmt --check

# Coverage (canonical command — excludes script/, test/, lib/)
make coverage

# Start local node
anvil
```

## Deploy

```bash
# Copy and fill in the env template
cp .env.example .env

# Simulate deployment (no broadcast)
forge script script/Deploy.s.sol --rpc-url $RPC_URL -vvvv

# Broadcast to a live network
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify
```

## License

[MIT](LICENSE)
