```markdown
# DeFi Super-App Protocol

> A modular, upgradeable DeFi protocol covering tokens, oracles, AMM, lending, vaults, treasury, and governance — built with Foundry and OpenZeppelin.

## Overview

The DeFi Super-App Protocol is a comprehensive, full-stack Decentralized Finance ecosystem designed for maximum efficiency, security, and true decentralization. It integrates an Automated Market Maker (AMM) with concentrated liquidity mechanics, an overcollateralized Lending engine, an auto-compounding ERC-4626 Yield Vault, and a fully on-chain DAO Governance system.

Designed as a modern DeFi primitive, the Superapp leverages Arbitrum's Layer 2 scalability and Chainlink's decentralized oracle networks to provide lightning-fast, low-cost financial services. The architecture strictly separates concerns, ensuring upgradeability through UUPS proxies where necessary while keeping core AMM pools immutable and trustless.

## Architecture

```text
src/
├── tokens/      # ERC-20 / ERC-721 / ERC-4626 token contracts
├── oracle/      # Chainlink price feed adapters and TWAP helpers
├── amm/         # Automated market maker (constant-product + concentrated)
├── lending/     # Collateralised lending pools and interest rate models
├── vault/       # ERC-4626 yield vaults and strategy layer
├── treasury/    # Protocol fee collection and allocation
└── governance/  # On-chain governor and timelock

```

*See the detailed system architecture, C4 diagrams, and Storage Layouts in [docs/architecture.md](https://www.google.com/search?q=docs/architecture.md).*

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
git clone --recurse-submodules [https://github.com/alikhan-s/defi-superapp.git](https://github.com/alikhan-s/defi-superapp.git)
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

## Team & Credits

Developed with love by:

* **Yeraly Zhumagul**
* **Alikhan**
* **Alizhan**
