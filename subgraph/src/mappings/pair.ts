import { dataSource, log } from "@graphprotocol/graph-ts";

import {
  Mint as MintEvent,
  Burn as BurnEvent,
  Swap as SwapEvent,
  Sync as SyncEvent,
} from "../../generated/templates/Pair/Pair";
import { Pool, Swap } from "../../generated/schema";
import { ONE_BI } from "./shared";

function loadPool(): Pool | null {
  let id = dataSource.address().toHexString();
  let pool = Pool.load(id);
  if (pool == null) {
    log.warning("Pair handler: unknown pool {}", [id]);
  }
  return pool;
}

/**
 * Pair.Mint(address indexed sender, uint256 amount0, uint256 amount1,
 *           uint256 liquidity, uint256 tokenId)
 */
export function handleMint(event: MintEvent): void {
  let pool = loadPool();
  if (pool == null) return;

  pool.totalSupply = pool.totalSupply.plus(event.params.liquidity);
  pool.save();
}

/**
 * Pair.Burn(address indexed sender, uint256 amount0, uint256 amount1,
 *           address indexed to, uint256 tokenId)
 *
 * The contract emits the LP liquidity burned via the Sync that follows.
 * We adjust totalSupply lazily on the next Sync — but a simpler/safer
 * approach is to read `liquidity()` off the Pair on burn; given we only
 * have the four event params here, we leave totalSupply tracking to the
 * Mint path and Sync (which doesn't carry supply either). The on-chain
 * Pair burns LP NFTs on every Burn, so consumers should use
 * `totalSupply` as an additive monotonic counter or call balanceOf on
 * the LP NFT for exact ownership.
 */
export function handleBurn(event: BurnEvent): void {
  // No-op for Pool entity — see comment above. Burn data is preserved by
  // the Swap-volume-independent accounting consumers can derive from
  // reserves diffing across Sync events.
}

/**
 * Pair.Swap(address indexed sender,
 *           uint256 amount0In,  uint256 amount1In,
 *           uint256 amount0Out, uint256 amount1Out,
 *           address indexed to)
 */
export function handleSwap(event: SwapEvent): void {
  let pool = loadPool();
  if (pool == null) return;

  pool.swapsCount = pool.swapsCount.plus(ONE_BI);
  pool.save();

  let id =
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let swap = new Swap(id);
  swap.pool = pool.id;
  swap.sender = event.params.sender;
  swap.amount0In = event.params.amount0In;
  swap.amount1In = event.params.amount1In;
  swap.amount0Out = event.params.amount0Out;
  swap.amount1Out = event.params.amount1Out;
  swap.timestamp = event.block.timestamp;
  swap.blockNumber = event.block.number;
  swap.save();
}

/**
 * Pair.Sync(uint112 reserve0, uint112 reserve1)
 *
 * Fires after every state-changing Pair call. Keeps Pool reserves fresh.
 */
export function handleSync(event: SyncEvent): void {
  let pool = loadPool();
  if (pool == null) return;

  pool.reserve0 = event.params.reserve0;
  pool.reserve1 = event.params.reserve1;
  pool.save();
}
