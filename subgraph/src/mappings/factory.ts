import { log } from "@graphprotocol/graph-ts";

import { PairCreated } from "../../generated/PairFactory/PairFactory";
import { Pair as PairTemplate } from "../../generated/templates";
import { Pool } from "../../generated/schema";
import { ZERO_BI } from "./shared";

/**
 * PairFactory.PairCreated(
 *   address indexed token0,
 *   address indexed token1,
 *   address pair,
 *   uint256 count,
 *   bool deterministic
 * )
 */
export function handlePairCreated(event: PairCreated): void {
  let poolId = event.params.pair.toHexString();

  let pool = new Pool(poolId);
  pool.token0 = event.params.token0;
  pool.token1 = event.params.token1;
  pool.reserve0 = ZERO_BI;
  pool.reserve1 = ZERO_BI;
  pool.totalSupply = ZERO_BI;
  pool.swapsCount = ZERO_BI;
  pool.createdAtBlock = event.block.number;
  pool.save();

  PairTemplate.create(event.params.pair);

  log.info("PairCreated: {} (token0={} token1={})", [
    poolId,
    event.params.token0.toHexString(),
    event.params.token1.toHexString(),
  ]);
}
