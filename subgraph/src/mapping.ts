import {
  Address,
  BigDecimal,
  BigInt,
  Bytes,
  dataSource,
  log,
} from "@graphprotocol/graph-ts";

import { PairCreated } from "../generated/PairFactory/PairFactory";
import {
  Mint as MintEvent,
  Burn as BurnEvent,
  Swap as SwapEvent,
  Sync as SyncEvent,
} from "../generated/templates/Pair/Pair";
import { Pair as PairTemplate } from "../generated/templates";

import {
  Factory,
  Pair,
  MintEvent as MintEntity,
  BurnEvent as BurnEntity,
  SwapEvent as SwapEntity,
  SyncEvent as SyncEntity,
  LPPosition,
} from "../generated/schema";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const FACTORY_ID = "factory";
const ZERO_BD = BigDecimal.fromString("0");
const ZERO_BI = BigInt.fromI32(0);
const ONE_BI = BigInt.fromI32(1);
const ONE_I32 = 1;

// AMM reserves are stored as uint112 — no decimals to strip at the contract
// level.  If you want human-readable amounts you should divide by 10^decimals
// using the ERC-20 decimals() call.  For simplicity the mapping keeps raw
// uint values as BigDecimal.  Swap out the helper below to add decimal
// normalisation once you have token metadata.
function toDecimal(value: BigInt): BigDecimal {
  return value.toBigDecimal();
}

// ---------------------------------------------------------------------------
// Factory helpers
// ---------------------------------------------------------------------------

function loadOrCreateFactory(): Factory {
  let factory = Factory.load(FACTORY_ID);
  if (factory == null) {
    factory = new Factory(FACTORY_ID);
    factory.pairCount = 0;
    factory.totalVolumeUSD = ZERO_BD;
    factory.txCount = ZERO_BI;
  }
  return factory as Factory;
}

// ---------------------------------------------------------------------------
// PairCreated handler
// ---------------------------------------------------------------------------

/**
 * Fired by PairFactory._register() for every new Pair.
 *
 * event PairCreated(
 *   address indexed token0,
 *   address indexed token1,
 *   address pair,
 *   uint256 count,
 *   bool deterministic
 * )
 */
export function handlePairCreated(event: PairCreated): void {
  // --- Factory ---
  let factory = loadOrCreateFactory();
  factory.pairCount = factory.pairCount + ONE_I32;
  factory.txCount = factory.txCount.plus(ONE_BI);
  factory.save();

  // --- Pair entity ---
  let pairAddress = event.params.pair.toHexString();
  let pair = new Pair(pairAddress);
  pair.token0 = event.params.token0;
  pair.token1 = event.params.token1;
  pair.pairIndex = event.params.count;
  pair.deterministic = event.params.deterministic;
  pair.createdAtTimestamp = event.block.timestamp;
  pair.createdAtBlockNumber = event.block.number;

  pair.reserve0 = ZERO_BD;
  pair.reserve1 = ZERO_BD;
  pair.reserveLastUpdatedAt = ZERO_BI;
  pair.totalLPSupply = ZERO_BD;
  pair.txCount = ZERO_BI;
  pair.volumeToken0 = ZERO_BD;
  pair.volumeToken1 = ZERO_BD;
  pair.save();

  // --- Spin up the dynamic data source for this pair's events ---
  PairTemplate.create(event.params.pair);

  log.info("PairCreated: {} (token0={} token1={})", [
    pairAddress,
    event.params.token0.toHexString(),
    event.params.token1.toHexString(),
  ]);
}

// ---------------------------------------------------------------------------
// Mint handler
// ---------------------------------------------------------------------------

/**
 * event Mint(
 *   address indexed sender,
 *   uint256 amount0,
 *   uint256 amount1,
 *   uint256 liquidity,
 *   uint256 tokenId
 * )
 */
export function handleMint(event: MintEvent): void {
  let pairAddress = dataSource.address().toHexString();
  let pair = Pair.load(pairAddress);
  if (pair == null) {
    log.warning("Mint: unknown pair {}", [pairAddress]);
    return;
  }

  pair.txCount = pair.txCount.plus(ONE_BI);
  pair.totalLPSupply = pair.totalLPSupply.plus(toDecimal(event.params.liquidity));
  pair.save();

  // Update factory tx count
  let factory = loadOrCreateFactory();
  factory.txCount = factory.txCount.plus(ONE_BI);
  factory.save();

  // MintEvent entity (immutable)
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let entity = new MintEntity(id);
  entity.pair = pairAddress;
  entity.sender = event.params.sender;
  entity.amount0 = toDecimal(event.params.amount0);
  entity.amount1 = toDecimal(event.params.amount1);
  entity.liquidity = toDecimal(event.params.liquidity);
  entity.tokenId = event.params.tokenId;
  entity.transaction = event.transaction.hash;
  entity.logIndex = event.logIndex;
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.save();

  // LPPosition
  let positionId = event.params.tokenId.toString();
  let position = LPPosition.load(positionId);
  if (position == null) {
    position = new LPPosition(positionId);
  }
  position.pair = pairAddress;
  position.owner = event.params.sender;
  position.liquidity = toDecimal(event.params.liquidity);
  position.active = true;
  position.mintedAt = event.block.timestamp;
  position.burnedAt = null;
  position.save();
}

// ---------------------------------------------------------------------------
// Burn handler
// ---------------------------------------------------------------------------

/**
 * event Burn(
 *   address indexed sender,
 *   uint256 amount0,
 *   uint256 amount1,
 *   address indexed to,
 *   uint256 tokenId
 * )
 */
export function handleBurn(event: BurnEvent): void {
  let pairAddress = dataSource.address().toHexString();
  let pair = Pair.load(pairAddress);
  if (pair == null) {
    log.warning("Burn: unknown pair {}", [pairAddress]);
    return;
  }

  // Read the position to get the liquidity amount before nullifying
  let positionId = event.params.tokenId.toString();
  let position = LPPosition.load(positionId);
  let burnedLiquidity = position != null ? position.liquidity : ZERO_BD;

  pair.txCount = pair.txCount.plus(ONE_BI);
  // Subtract burned liquidity; guard against going negative
  let newSupply = pair.totalLPSupply.minus(burnedLiquidity);
  pair.totalLPSupply = newSupply.lt(ZERO_BD) ? ZERO_BD : newSupply;
  pair.save();

  // Update factory tx count
  let factory = loadOrCreateFactory();
  factory.txCount = factory.txCount.plus(ONE_BI);
  factory.save();

  // BurnEvent entity (immutable)
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let entity = new BurnEntity(id);
  entity.pair = pairAddress;
  entity.sender = event.params.sender;
  entity.amount0 = toDecimal(event.params.amount0);
  entity.amount1 = toDecimal(event.params.amount1);
  entity.to = event.params.to;
  entity.tokenId = event.params.tokenId;
  entity.transaction = event.transaction.hash;
  entity.logIndex = event.logIndex;
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.save();

  // Mark LPPosition as inactive
  if (position != null) {
    position.liquidity = ZERO_BD;
    position.active = false;
    position.burnedAt = event.block.timestamp;
    position.save();
  }
}

// ---------------------------------------------------------------------------
// Swap handler
// ---------------------------------------------------------------------------

/**
 * event Swap(
 *   address indexed sender,
 *   uint256 amount0In,
 *   uint256 amount1In,
 *   uint256 amount0Out,
 *   uint256 amount1Out,
 *   address indexed to
 * )
 */
export function handleSwap(event: SwapEvent): void {
  let pairAddress = dataSource.address().toHexString();
  let pair = Pair.load(pairAddress);
  if (pair == null) {
    log.warning("Swap: unknown pair {}", [pairAddress]);
    return;
  }

  let amount0In = toDecimal(event.params.amount0In);
  let amount1In = toDecimal(event.params.amount1In);
  let amount0Out = toDecimal(event.params.amount0Out);
  let amount1Out = toDecimal(event.params.amount1Out);

  // Accumulate volume for each side (use the "in" direction)
  pair.volumeToken0 = pair.volumeToken0.plus(amount0In).plus(amount0Out);
  pair.volumeToken1 = pair.volumeToken1.plus(amount1In).plus(amount1Out);
  pair.txCount = pair.txCount.plus(ONE_BI);
  pair.save();

  // Update factory tx count
  let factory = loadOrCreateFactory();
  factory.txCount = factory.txCount.plus(ONE_BI);
  factory.save();

  // SwapEvent entity (immutable)
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let entity = new SwapEntity(id);
  entity.pair = pairAddress;
  entity.sender = event.params.sender;
  entity.to = event.params.to;
  entity.amount0In = amount0In;
  entity.amount1In = amount1In;
  entity.amount0Out = amount0Out;
  entity.amount1Out = amount1Out;
  entity.transaction = event.transaction.hash;
  entity.logIndex = event.logIndex;
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.save();
}

// ---------------------------------------------------------------------------
// Sync handler
// ---------------------------------------------------------------------------

/**
 * event Sync(uint112 reserve0, uint112 reserve1)
 *
 * Emitted at the end of every mint / burn / swap / sync call.
 * We use it to keep Pair.reserve0 / reserve1 always up to date.
 */
export function handleSync(event: SyncEvent): void {
  let pairAddress = dataSource.address().toHexString();
  let pair = Pair.load(pairAddress);
  if (pair == null) {
    log.warning("Sync: unknown pair {}", [pairAddress]);
    return;
  }

  pair.reserve0 = toDecimal(event.params.reserve0);
  pair.reserve1 = toDecimal(event.params.reserve1);
  pair.reserveLastUpdatedAt = event.block.timestamp;
  pair.save();

  // SyncEvent entity (immutable)
  let id = event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let entity = new SyncEntity(id);
  entity.pair = pairAddress;
  entity.reserve0 = toDecimal(event.params.reserve0);
  entity.reserve1 = toDecimal(event.params.reserve1);
  entity.transaction = event.transaction.hash;
  entity.logIndex = event.logIndex;
  entity.timestamp = event.block.timestamp;
  entity.blockNumber = event.block.number;
  entity.save();
}
