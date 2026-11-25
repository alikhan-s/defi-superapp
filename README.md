# DeFi Super-App Protocol

> A modular, upgradeable DeFi protocol covering tokens, oracles, AMM, lending, vaults, treasury, and governance — built with Foundry, OpenZeppelin, React/Wagmi, and The Graph.

## Overview

The DeFi Super-App Protocol is a full-stack Decentralized Finance ecosystem designed for modularity, security, and on-chain decentralization. It integrates a constant-product (`x * y = k`) Automated Market Maker (AMM) with ERC-721 LP position NFTs, inline Yul math optimizations, and flash swaps; an overcollateralized Lending engine backed by Chainlink price feeds; an auto-compounding ERC-4626 Yield Vault; a UUPS-upgradeable Treasury; and an on-chain DAO Governance system with Timelock execution.

Built for Arbitrum's Layer 2 scalability, the architecture separates immutable core AMM pools from upgradeable treasury modules controlled by DAO governance.

## Architecture

```text
src/
├── tokens/      # ERC-20 / ERC-721 / ERC-4626 token contracts
├── oracle/      # Chainlink price feed adapters and TWAP helpers
├── amm/         # Constant-product AMM, LP Position NFTs, flash swaps & Yul math
├── lending/     # Overcollateralized lending pools and interest rate models
├── vault/       # ERC-4626 yield vaults and strategy layer
├── treasury/    # UUPS-upgradeable protocol fee collection and allocation
└── governance/  # On-chain OpenZeppelin Governor and Timelock
```

### Documentation & Security Reports

- **System Architecture & Storage Layouts:** [docs/architecture.md](docs/architecture.md) · [docs/storage-layout-treasury.md](docs/storage-layout-treasury.md)
- **Security & Static Analysis:** [docs/security-audit.md](docs/security-audit.md) · [docs/slither-findings.md](docs/slither-findings.md) · [docs/governance-attacks.md](docs/governance-attacks.md)
- **Testing & Gas Benchmarks:** [docs/test-inventory.md](docs/test-inventory.md) · [docs/coverage-report.md](docs/coverage-report.md) · [docs/gas-report.md](docs/gas-report.md) · [docs/gas-yul-vs-solidity.md](docs/gas-yul-vs-solidity.md)
- **Operations & Deployment:** [docs/deployment-runbook.md](docs/deployment-runbook.md) · [docs/post-deployment-report.md](docs/post-deployment-report.md)

## Deployed Contracts — Arbitrum Sepolia (Chain ID `421614`)

Populated by `script/Deploy.s.sol`. All contracts are verified on the block explorer. Source of truth for the addresses is `deployments/421614.json`.

| Contract | Address | Explorer |
| --- | --- | --- |
| GovernanceToken | `0x75126A3c6A49a595246b82a08DA73d7608337C36` | [Arbiscan](https://sepolia.arbiscan.io/address/0x75126A3c6A49a595246b82a08DA73d7608337C36) |
| ChainlinkPriceOracle | `0x65DBbd9B7d2a04474dafAE487557ECCE805f33a9` | [Arbiscan](https://sepolia.arbiscan.io/address/0x65DBbd9B7d2a04474dafAE487557ECCE805f33a9) |
| LPPositionNFT | `0x038F1A0E06E36EF33fdB963CF2DE4570F319eA0c` | [Arbiscan](https://sepolia.arbiscan.io/address/0x038F1A0E06E36EF33fdB963CF2DE4570F319eA0c) |
| PairFactory | `0xf56921ef32f00C65836E99324e350F97C5c39229` | [Arbiscan](https://sepolia.arbiscan.io/address/0xf56921ef32f00C65836E99324e350F97C5c39229) |
| SamplePair (WETH/USDC) | `0xC139a14BCA5e03Da3C3ea6be458A5E592e37BFF4` | [Arbiscan](https://sepolia.arbiscan.io/address/0xC139a14BCA5e03Da3C3ea6be458A5E592e37BFF4) |
| LendingPool | `0x0013766F7fb601E43aF9b4b1F40C9bE667E53205` | [Arbiscan](https://sepolia.arbiscan.io/address/0x0013766F7fb601E43aF9b4b1F40C9bE667E53205) |
| YieldVault (yvUSDC) | `0xfb72FBbA8cbeb5D3C8E5871912A4884B7492C852` | [Arbiscan](https://sepolia.arbiscan.io/address/0xfb72FBbA8cbeb5D3C8E5871912A4884B7492C852) |
| TreasuryProxy (UUPS) | `0x9C0005C1E5d91BadDE2941f021bD8d66748495fe` | [Arbiscan](https://sepolia.arbiscan.io/address/0x9C0005C1E5d91BadDE2941f021bD8d66748495fe) |
| ProtocolTimelock | `0x85dBA7e4Ef173DD5daFcD6977f070bAD6fe2e61C` | [Arbiscan](https://sepolia.arbiscan.io/address/0x85dBA7e4Ef173DD5daFcD6977f070bAD6fe2e61C) |
| ProtocolGovernor | `0xdED11a6Fa7062B7b6422061B54998C4002c2d80b` | [Arbiscan](https://sepolia.arbiscan.io/address/0xdED11a6Fa7062B7b6422061B54998C4002c2d80b) |

## Subgraph (The Graph — Arbitrum Sepolia)

The protocol utilizes The Graph for reliable, decentralized data querying.

* **Studio Dashboard:** [defi-superapp](https://thegraph.com/studio/subgraph/defi-superapp/)
* **Query Endpoint:** `https://api.studio.thegraph.com/query/1753772/defi-superapp/v0.0.1`
* **Sample Queries:** Available in `subgraph/queries.md` (top pools, user swaps, proposal states, at-risk lending positions).

Build and deploy locally:

```bash
cd subgraph
npm install
npx graph codegen
npx graph build
npx graph auth --studio <DEPLOY_KEY>
npx graph deploy --studio defi-superapp --version-label v0.0.1

```

## Local Development & Testing

**Prerequisites:** [Foundry](https://book.getfoundry.sh/getting-started/installation) installed.

Clone the repository and install dependencies:

```bash
git clone --recurse-submodules https://github.com/alikhan-s/defi-superapp.git
cd defi-superapp
forge install
```

Build and test the smart contracts:

```bash
forge build
forge test -vvv
forge test --match-path "test/**/*.t.sol"
forge fmt --check
make coverage

```

**Frontend Application:**
The frontend dApp is designed to run locally. Navigate to the `frontend/` directory, install dependencies via `npm install`, and start the development server with `npm run dev`.

## Deployment

To deploy the ecosystem to a live network, set up your `.env` file with `RPC_URL`, `PRIVATE_KEY`, and `ARBISCAN_API_KEY`.

Execute the deployment script with broadcasting and contract verification:

```bash
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify --etherscan-api-key $ARBISCAN_API_KEY

```
