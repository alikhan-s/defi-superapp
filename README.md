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
| GovernanceToken | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| ChainlinkPriceOracle | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| LPPositionNFT | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| PairFactory | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| SamplePair (WETH/USDC) | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| LendingPool | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| YieldVault (yvUSDC) | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| TreasuryProxy (UUPS) | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| ProtocolTimelock | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |
| ProtocolGovernor | `TBD` | [arbiscan](https://sepolia.arbiscan.io/address/TBD) |

See [docs/deployment-runbook.md](docs/deployment-runbook.md) for the end-to-end deployment + verification procedure. Source of truth for the addresses is [deployments/421614.json](deployments/421614.json) after a successful broadcast.

**Subgraph:** TBD — populated in Phase 10.
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
