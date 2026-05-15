/**
 * Client-side mirror of the on-chain constant-product math.
 *
 * The deployed `Pair` computes swap output via `PairMathYul.getAmountOut`
 * (a linked library, not a callable method on the Pair). To preview a swap and
 * derive an honest `minAmountOut` we replicate that exact integer formula here
 * — bigint throughout, no floating point — so the preview matches what the
 * contract will actually execute:
 *
 *   amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
 */
export function getAmountOut(amountIn: bigint, reserveIn: bigint, reserveOut: bigint): bigint {
  if (amountIn <= 0n || reserveIn <= 0n || reserveOut <= 0n) return 0n;
  const amountInWithFee = amountIn * 997n;
  const numerator = amountInWithFee * reserveOut;
  const denominator = reserveIn * 1000n + amountInWithFee;
  return numerator / denominator;
}

/**
 * Apply a slippage tolerance (in percent, e.g. "0.5") to an output amount,
 * returning the minimum acceptable amount as an integer in token base units.
 * Uses basis points internally to avoid floating-point drift.
 */
export function applySlippage(amountOut: bigint, slippagePercent: number): bigint {
  if (amountOut <= 0n || !Number.isFinite(slippagePercent) || slippagePercent < 0) return 0n;
  const slippageBps = BigInt(Math.round(slippagePercent * 100)); // percent → bps
  const denominator = 10_000n;
  const numerator = denominator - slippageBps > 0n ? denominator - slippageBps : 0n;
  return (amountOut * numerator) / denominator;
}

/**
 * Spot-price-based execution price impact in percent, computed with the same
 * reserves used for the quote. Returns a non-negative number.
 */
export function priceImpactPercent(
  amountIn: bigint,
  amountOut: bigint,
  reserveIn: bigint,
  reserveOut: bigint,
): number {
  if (amountIn <= 0n || amountOut <= 0n || reserveIn <= 0n || reserveOut <= 0n) return 0;
  // spot = reserveOut/reserveIn ; exec = amountOut/amountIn ; impact = 1 - exec/spot
  const spotNum = reserveOut * amountIn;
  const execNum = amountOut * reserveIn;
  if (spotNum === 0n) return 0;
  const impact = 1 - Number(execNum) / Number(spotNum);
  return impact > 0 ? impact * 100 : 0;
}
