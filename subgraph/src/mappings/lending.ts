import { Address, BigInt } from "@graphprotocol/graph-ts";

import {
  CollateralDeposited,
  CollateralWithdrawn,
  Borrowed,
  Repaid,
  Liquidated,
} from "../../generated/LendingPool/LendingPool";
import { LendingPosition, LiquidationEvent } from "../../generated/schema";
import { MAX_UINT256, WAD, ZERO_BI } from "./shared";

function loadOrCreate(user: Address): LendingPosition {
  let id = user.toHexString();
  let pos = LendingPosition.load(id);
  if (pos == null) {
    pos = new LendingPosition(id);
    pos.collateral = ZERO_BI;
    pos.debt = ZERO_BI;
    pos.healthFactor = MAX_UINT256;
    pos.lastUpdated = ZERO_BI;
  }
  return pos as LendingPosition;
}

// Mirror of LendingPool's healthFactor with collateralFactor = 1e18 (no
// oracle price applied here — the on-chain version uses an oracle ratio).
// This is a best-effort approximation; consumers wanting the exact value
// should call `LendingPool.healthFactor(user)` directly.
function computeHealthFactor(collateral: BigInt, debt: BigInt): BigInt {
  if (debt.equals(ZERO_BI)) {
    return MAX_UINT256;
  }
  return collateral.times(WAD).div(debt);
}

function touch(pos: LendingPosition, blockTimestamp: BigInt): void {
  pos.healthFactor = computeHealthFactor(pos.collateral, pos.debt);
  pos.lastUpdated = blockTimestamp;
  pos.save();
}

export function handleCollateralDeposited(event: CollateralDeposited): void {
  let pos = loadOrCreate(event.params.user);
  pos.collateral = pos.collateral.plus(event.params.amount);
  touch(pos, event.block.timestamp);
}

export function handleCollateralWithdrawn(event: CollateralWithdrawn): void {
  let pos = loadOrCreate(event.params.user);
  let next = pos.collateral.minus(event.params.amount);
  pos.collateral = next.lt(ZERO_BI) ? ZERO_BI : next;
  touch(pos, event.block.timestamp);
}

export function handleBorrowed(event: Borrowed): void {
  let pos = loadOrCreate(event.params.user);
  pos.debt = pos.debt.plus(event.params.amount);
  touch(pos, event.block.timestamp);
}

export function handleRepaid(event: Repaid): void {
  let pos = loadOrCreate(event.params.user);
  let next = pos.debt.minus(event.params.amount);
  pos.debt = next.lt(ZERO_BI) ? ZERO_BI : next;
  touch(pos, event.block.timestamp);
}

/**
 * LendingPool.Liquidated(
 *   address indexed liquidator,
 *   address indexed user,
 *   uint256 debtCovered,
 *   uint256 collateralLiquidated
 * )
 */
export function handleLiquidated(event: Liquidated): void {
  // Update borrower position
  let pos = loadOrCreate(event.params.user);
  let nextDebt = pos.debt.minus(event.params.debtCovered);
  pos.debt = nextDebt.lt(ZERO_BI) ? ZERO_BI : nextDebt;
  let nextCollat = pos.collateral.minus(event.params.collateralLiquidated);
  pos.collateral = nextCollat.lt(ZERO_BI) ? ZERO_BI : nextCollat;
  touch(pos, event.block.timestamp);

  // Immutable LiquidationEvent record
  let id =
    event.transaction.hash.toHexString() + "-" + event.logIndex.toString();
  let liq = new LiquidationEvent(id);
  liq.user = event.params.user;
  liq.liquidator = event.params.liquidator;
  liq.debtCovered = event.params.debtCovered;
  liq.collateralSeized = event.params.collateralLiquidated;
  liq.timestamp = event.block.timestamp;
  liq.save();
}
