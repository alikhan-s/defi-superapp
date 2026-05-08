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

## Deployed Contracts

| Network  | Contract    | Address |
|----------|-------------|---------|
| Mainnet  | —           | —       |
| Sepolia  | —           | —       |

<!-- TODO: populate after first deployment -->

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

# Coverage
forge coverage --report summary

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
