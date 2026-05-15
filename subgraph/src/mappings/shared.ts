import { BigInt } from "@graphprotocol/graph-ts";

export const ZERO_BI: BigInt = BigInt.fromI32(0);
export const ONE_BI: BigInt = BigInt.fromI32(1);

// 1e18 scaling factor used for healthFactor math.
export const WAD: BigInt = BigInt.fromString("1000000000000000000");

// type(uint256).max — sentinel for "no debt -> infinite health factor".
export const MAX_UINT256: BigInt = BigInt.fromString(
  "115792089237316195423570985008687907853269984665640564039457584007913129639935"
);
