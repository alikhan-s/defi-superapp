import { useState, useMemo, useEffect } from 'react';
import { useAccount, useReadContract, useReadContracts } from 'wagmi';
import { motion, AnimatePresence } from 'framer-motion';
import { Settings, ArrowDownUp, AlertCircle, Info } from 'lucide-react';
import { parseUnits, formatUnits, erc20Abi as viemErc20Abi } from 'viem';

import { addresses } from '../contracts/addresses';
import { pairAbi } from '../contracts/abis/pairAbi';
import { TxButton, type TxRequest } from '../components/TxButton';
import { getAmountOut, applySlippage, priceImpactPercent } from '../lib/amm';

const PAIR = addresses.SamplePair as `0x${string}`;
const SLIPPAGE_PRESETS = ['0.1', '0.5', '1.0'];

function short(addr?: string) {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : '—';
}

export function Swap() {
  const { isConnected, address } = useAccount();

  const [amountIn, setAmountIn] = useState('');
  const [slippage, setSlippage] = useState('0.5');
  const [showSettings, setShowSettings] = useState(false);
  const [isReversed, setIsReversed] = useState(false); // false: token0→token1

  // --- Pool token addresses ------------------------------------------------
  const { data: token0 } = useReadContract({ address: PAIR, abi: pairAbi, functionName: 'token0' });
  const { data: token1 } = useReadContract({ address: PAIR, abi: pairAbi, functionName: 'token1' });

  // --- Token metadata (symbol + decimals) via multicall --------------------
  const { data: meta } = useReadContracts({
    contracts:
      token0 && token1
        ? [
            { address: token0, abi: viemErc20Abi, functionName: 'symbol' },
            { address: token0, abi: viemErc20Abi, functionName: 'decimals' },
            { address: token1, abi: viemErc20Abi, functionName: 'symbol' },
            { address: token1, abi: viemErc20Abi, functionName: 'decimals' },
          ]
        : [],
    query: { enabled: !!token0 && !!token1 },
  });

  const sym0 = (meta?.[0]?.result as string) ?? short(token0);
  const dec0 = (meta?.[1]?.result as number) ?? 18;
  const sym1 = (meta?.[2]?.result as string) ?? short(token1);
  const dec1 = (meta?.[3]?.result as number) ?? 18;

  const inToken = isReversed ? token1 : token0;
  const inSym = isReversed ? sym1 : sym0;
  const inDec = isReversed ? dec1 : dec0;
  const outSym = isReversed ? sym0 : sym1;
  const outDec = isReversed ? dec0 : dec1;

  // --- Reserves ------------------------------------------------------------
  const { data: reserves, isLoading: isReservesLoading, refetch: refetchReserves } = useReadContract({
    address: PAIR,
    abi: pairAbi,
    functionName: 'getReserves',
  });

  // --- User balance of the input token + pair balance (to detect funding) --
  const { data: userBalIn, refetch: refetchUserBal } = useReadContract({
    address: inToken,
    abi: viemErc20Abi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!inToken && !!address },
  });

  const { data: pairBalIn, refetch: refetchPairBal } = useReadContract({
    address: inToken,
    abi: viemErc20Abi,
    functionName: 'balanceOf',
    args: [PAIR],
    query: { enabled: !!inToken },
  });

  // --- Quote (exact integer mirror of PairMathYul.getAmountOut) ------------
  const amountInWei = useMemo(() => {
    try {
      return amountIn && Number(amountIn) > 0 ? parseUnits(amountIn, inDec) : 0n;
    } catch {
      return 0n;
    }
  }, [amountIn, inDec]);

  const { quote, minReceived, impact } = useMemo(() => {
    if (!reserves || amountInWei === 0n) return { quote: 0n, minReceived: 0n, impact: 0 };
    const r0 = reserves[0] as bigint;
    const r1 = reserves[1] as bigint;
    const reserveIn = isReversed ? r1 : r0;
    const reserveOut = isReversed ? r0 : r1;
    const q = getAmountOut(amountInWei, reserveIn, reserveOut);
    return {
      quote: q,
      minReceived: applySlippage(q, Number(slippage) || 0),
      impact: priceImpactPercent(amountInWei, q, reserveIn, reserveOut),
    };
  }, [reserves, amountInWei, isReversed, slippage]);

  // A swap is only possible against a pool that actually holds both reserves.
  const hasLiquidity = reserves ? (reserves[0] as bigint) > 0n && (reserves[1] as bigint) > 0n : false;

  // --- Funding detection: pair balance must exceed its reserve by amountIn --
  const reserveInRaw = reserves ? ((isReversed ? reserves[1] : reserves[0]) as bigint) : 0n;
  const pairExcess = pairBalIn !== undefined && reserveInRaw !== undefined ? (pairBalIn as bigint) - reserveInRaw : 0n;
  const isFunded = amountInWei > 0n && pairExcess >= amountInWei;
  const hasBalance = userBalIn !== undefined ? (userBalIn as bigint) >= amountInWei : true;

  // Reset detection when the swap completes.
  const refetchAll = () => {
    refetchReserves();
    refetchUserBal();
    refetchPairBal();
  };

  useEffect(() => {
    // When inputs change, nothing to do; reads refetch on chain block updates.
  }, [amountIn, isReversed]);

  // --- Build the two on-chain requests -------------------------------------
  const transferRequest: TxRequest | undefined =
    inToken && amountInWei > 0n
      ? { address: inToken, abi: viemErc20Abi as unknown as TxRequest['abi'], functionName: 'transfer', args: [PAIR, amountInWei] }
      : undefined;

  const swapRequest: TxRequest | undefined =
    address && quote > 0n
      ? {
          address: PAIR,
          abi: pairAbi as unknown as TxRequest['abi'],
          functionName: 'swap',
          // amount0Out, amount1Out, to, minOut, data
          args: [isReversed ? quote : 0n, isReversed ? 0n : quote, address, minReceived, '0x'],
        }
      : undefined;

  const fmtOut = quote > 0n ? Number(formatUnits(quote, outDec)).toFixed(6) : '';
  const fmtMin = minReceived > 0n ? Number(formatUnits(minReceived, outDec)).toFixed(6) : '0';

  return (
    <div className="flex justify-center items-start py-12">
      <motion.div
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.5, type: 'spring' }}
        className="w-full max-w-md"
      >
        <div className="glass-card p-2 relative overflow-hidden">
          <div className="absolute top-0 right-0 w-64 h-64 bg-indigo-500/10 rounded-full blur-3xl -z-10" />
          <div className="absolute bottom-0 left-0 w-64 h-64 bg-cyan-500/10 rounded-full blur-3xl -z-10" />

          <div className="flex justify-between items-center p-4">
            <h2 className="text-xl font-bold text-white">Swap</h2>
            <button
              onClick={() => setShowSettings(!showSettings)}
              className="p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/10 transition-colors"
            >
              <Settings size={20} />
            </button>
          </div>

          {/* Slippage settings */}
          <AnimatePresence>
            {showSettings && (
              <motion.div
                initial={{ height: 0, opacity: 0 }}
                animate={{ height: 'auto', opacity: 1 }}
                exit={{ height: 0, opacity: 0 }}
                className="overflow-hidden px-4 pb-4"
              >
                <div className="p-4 rounded-2xl bg-black/40 border border-white/5">
                  <p className="text-sm text-gray-400 mb-3 font-medium">Slippage tolerance</p>
                  <div className="flex gap-2">
                    {SLIPPAGE_PRESETS.map((val) => (
                      <button
                        key={val}
                        onClick={() => setSlippage(val)}
                        className={`flex-1 py-1.5 rounded-xl text-sm font-semibold transition-all ${
                          slippage === val
                            ? 'bg-indigo-500 text-white shadow-[0_0_15px_rgba(99,102,241,0.4)]'
                            : 'bg-white/5 text-gray-400 hover:bg-white/10'
                        }`}
                      >
                        {val}%
                      </button>
                    ))}
                    <div className="relative flex-[1.5]">
                      <input
                        type="text"
                        value={slippage}
                        onChange={(e) => setSlippage(e.target.value)}
                        placeholder="Custom"
                        className="w-full py-1.5 px-3 bg-white/5 border border-white/10 rounded-xl text-white text-right focus:outline-none focus:border-indigo-500 transition-colors"
                      />
                      <span className="absolute right-3 top-[6px] text-gray-400 text-sm">%</span>
                    </div>
                  </div>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Sell */}
          <div className="space-y-1 p-2">
            <div className="p-4 rounded-3xl bg-black/40 border border-transparent focus-within:border-white/10 transition-colors">
              <div className="flex justify-between mb-2">
                <span className="text-sm font-medium text-gray-400">Sell</span>
                <span className="text-sm font-medium text-gray-400">
                  Balance:{' '}
                  {userBalIn !== undefined ? Number(formatUnits(userBalIn as bigint, inDec)).toFixed(4) : '0.00'}
                  {address && userBalIn !== undefined && (userBalIn as bigint) > 0n && (
                    <button
                      onClick={() => setAmountIn(formatUnits(userBalIn as bigint, inDec))}
                      className="ml-2 text-indigo-400 hover:text-indigo-300 font-semibold"
                    >
                      MAX
                    </button>
                  )}
                </span>
              </div>
              <div className="flex items-center gap-4">
                <input
                  type="number"
                  placeholder="0"
                  value={amountIn}
                  onChange={(e) => setAmountIn(e.target.value)}
                  className="w-full bg-transparent text-4xl text-white font-medium focus:outline-none placeholder:text-gray-600"
                />
                <div className="flex items-center gap-2 bg-[#13141a] border border-white/5 px-4 py-2 rounded-2xl shadow-lg shrink-0">
                  <div className="w-6 h-6 rounded-full bg-indigo-500 flex items-center justify-center text-xs font-bold text-white">
                    {inSym?.[0] ?? '?'}
                  </div>
                  <span className="font-bold text-white text-lg">{inSym}</span>
                </div>
              </div>
            </div>

            <div className="relative h-2 flex justify-center items-center z-10">
              <button
                onClick={() => {
                  setIsReversed(!isReversed);
                  setAmountIn('');
                }}
                className="absolute p-2 rounded-xl bg-[#13141a] border-4 border-[#0a0b0f] text-gray-400 hover:text-white transition-transform hover:scale-110 active:scale-95"
              >
                <ArrowDownUp size={16} />
              </button>
            </div>

            {/* Buy */}
            <div className="p-4 rounded-3xl bg-black/40 border border-transparent">
              <div className="flex justify-between mb-2">
                <span className="text-sm font-medium text-gray-400">Buy</span>
              </div>
              <div className="flex items-center gap-4">
                {isReservesLoading ? (
                  <div className="h-10 w-full bg-white/5 animate-pulse rounded-lg" />
                ) : (
                  <input
                    type="text"
                    value={fmtOut}
                    readOnly
                    placeholder="0"
                    className="w-full bg-transparent text-4xl text-white font-medium focus:outline-none placeholder:text-gray-600"
                  />
                )}
                <div className="flex items-center gap-2 bg-[#13141a] border border-white/5 px-4 py-2 rounded-2xl shadow-lg shrink-0">
                  <div className="w-6 h-6 rounded-full bg-cyan-500 flex items-center justify-center text-xs font-bold text-white">
                    {outSym?.[0] ?? '?'}
                  </div>
                  <span className="font-bold text-white text-lg">{outSym}</span>
                </div>
              </div>
            </div>
          </div>

          {/* Details */}
          {quote > 0n && (
            <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} className="px-6 py-4 space-y-3">
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Price impact</span>
                <span className={`${impact > 5 ? 'text-red-400' : impact > 1 ? 'text-yellow-400' : 'text-green-400'} font-medium`}>
                  {impact.toFixed(2)}%
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-400 flex items-center gap-1">
                  Minimum received <AlertCircle size={14} className="text-gray-500" />
                </span>
                <span className="text-white font-medium">
                  {fmtMin} {outSym}
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Rate</span>
                <span className="text-white font-medium">
                  1 {inSym} = {(Number(fmtOut) / Number(amountIn || 1)).toFixed(4)} {outSym}
                </span>
              </div>
            </motion.div>
          )}

          {/* Two-step action: fund the pair, then swap (no router deployed) */}
          <div className="p-2 pt-0 mt-2 space-y-3">
            {!isConnected ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold text-lg cursor-not-allowed">
                Connect wallet to swap
              </button>
            ) : amountInWei === 0n ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold text-lg cursor-not-allowed">
                Enter an amount
              </button>
            ) : !hasBalance ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold text-lg cursor-not-allowed">
                Insufficient {inSym} balance
              </button>
            ) : !hasLiquidity ? (
              <>
                <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold text-lg cursor-not-allowed">
                  No liquidity in this pool
                </button>
                <div className="flex items-start gap-2 px-2 text-xs text-gray-500">
                  <Info size={14} className="shrink-0 mt-0.5" />
                  <span>This pool has no reserves yet. Add liquidity on the Pool page before swapping.</span>
                </div>
              </>
            ) : !isFunded ? (
              <>
                <div className="flex items-start gap-2 px-2 text-xs text-gray-500">
                  <Info size={14} className="shrink-0 mt-0.5" />
                  <span>
                    Step 1 of 2 — transfer {inSym} into the pool, then confirm the swap. (This AMM has no router, so the
                    input is sent directly to the pair.)
                  </span>
                </div>
                <TxButton
                  request={transferRequest}
                  enabled={!!transferRequest}
                  text={`Transfer ${inSym}`}
                  className="text-lg font-bold"
                  onSuccess={refetchAll}
                />
              </>
            ) : (
              <TxButton
                request={swapRequest}
                enabled={!!swapRequest}
                text="Swap"
                confirmingText="Swapping…"
                successMessage="Swap confirmed"
                className="text-lg font-bold"
                onSuccess={() => {
                  setAmountIn('');
                  refetchAll();
                }}
              />
            )}
          </div>
        </div>
      </motion.div>
    </div>
  );
}
