# Gas Comparison — L1 vs Arbitrum L2

Per-operation gas cost on Ethereum mainnet (simulated via local Anvil) vs Arbitrum Sepolia.

> **TODO** — populate the gas columns below by running [`script/GasComparison.s.sol`](../script/GasComparison.s.sol) on both networks:
>
> ```bash
> anvil &
> forge script script/GasComparison.s.sol --rpc-url http://localhost:8545 | grep GASCOMP
> forge script script/GasComparison.s.sol --fork-url $ARBITRUM_SEPOLIA_RPC_URL | grep GASCOMP
> ```

Pricing assumptions for USD columns:
- L1: 30 gwei base fee, ETH = $3,500
- L2 (Arbitrum): the script's reported gas dominates; treat the L2 fee as ~`gas * 0.1 gwei * $3,500` (Arbitrum's effective rate at quiet times). Adjust if the network you target prices differently.

| Operation | L1 gas | L2 gas | L1 USD (30 gwei, $3.5k ETH) | L2 USD (~0.1 gwei, $3.5k ETH) |
| --- | ---: | ---: | ---: | ---: |
| Swap (WETH→USDC) | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| Add liquidity (first mint) | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| Remove liquidity (burn) | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| Vault deposit (4626) | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| Borrow against collateral | _TODO_ | _TODO_ | _TODO_ | _TODO_ |
| Vote on proposal | _TODO_ | _TODO_ | _TODO_ | _TODO_ |

## Methodology

The gas-comparison script deploys a fresh, minimal instance of the protocol *inside the script* (mock ERC-20s for WETH/USDC, a mock Chainlink aggregator, real Pair/Vault/LendingPool/Governor) so the two runs measure identical work. Gas is captured with `gasleft()` deltas around each call, not via `tx.receipt`, so the numbers reflect the inner execution cost and exclude L1 calldata / Arbitrum data-availability overhead. For L2 deployments you should also factor in Arbitrum's L1 calldata posting cost (typically a few cents per tx at quiet times) — that is *not* included in the table above.

## Caveats

- Anvil does not model Ethereum mainnet's calldata gas precisely; the "L1 gas" column is an in-EVM lower bound, not a wire cost.
- Arbitrum's effective gas price varies with L1 base fee. The 0.1 gwei figure is illustrative.
- The vote measurement uses `vm.roll` to skip the voting delay; the real L2 cost will include block-time waits that don't show up in this measurement.
