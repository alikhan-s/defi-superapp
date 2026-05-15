import { useState, useEffect, useCallback, useMemo } from 'react';
import { useAccount, useReadContract, useReadContracts, usePublicClient } from 'wagmi';
import { motion } from 'framer-motion';
import { Droplets, Plus, Layers, Info, Hash } from 'lucide-react';
import { parseUnits, formatUnits, erc20Abi as viemErc20Abi } from 'viem';

import { addresses } from '../contracts/addresses';
import { pairAbi } from '../contracts/abis/pairAbi';
import { lpPositionNftAbi } from '../contracts/abis/lpPositionNftAbi';
import { TxButton, type TxRequest } from '../components/TxButton';

const PAIR = addresses.SamplePair as `0x${string}`;
const LP_NFT = addresses.LPPositionNFT as `0x${string}`;
// The LP NFT is not Enumerable and free-tier RPCs cap eth_getLogs at a tiny
// block range, so we can't scan Transfer logs. Instead we enumerate token ids
// (they auto-increment from 1) up to this cap in a single batched multicall.
const MAX_TOKEN_ID = 250;

interface LpPosition {
  tokenId: bigint;
  pool: `0x${string}`;
  liquidity: bigint;
  createdAt: bigint;
}

function short(addr?: string) {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : '—';
}

/** Enumerate a user's LP NFTs via Transfer logs (the NFT is not Enumerable). */
function useLpPositions(address?: `0x${string}`) {
  const publicClient = usePublicClient();
  const [positions, setPositions] = useState<LpPosition[]>([]);
  const [loading, setLoading] = useState(false);
  const [nonce, setNonce] = useState(0);

  const refresh = useCallback(() => setNonce((n) => n + 1), []);

  useEffect(() => {
    // No synchronous setState here — the page renders a connect prompt when
    // there's no address, so stale positions are never shown; an account
    // switch re-runs this effect and replaces them via the async fetch below.
    if (!publicClient || !address) return;
    let cancelled = false;
    (async () => {
      // setState lives inside the async callback (not the synchronous effect
      // body) — the accepted data-fetching pattern for this lint rule.
      setLoading(true);
      try {
        // Enumerate candidate token ids 1..MAX via one batched multicall;
        // ownerOf reverts for non-existent/burned ids (allowFailure → skipped).
        const ids = Array.from({ length: MAX_TOKEN_ID }, (_, i) => BigInt(i + 1));
        const owners = await publicClient.multicall({
          contracts: ids.map((id) => ({ address: LP_NFT, abi: lpPositionNftAbi, functionName: 'ownerOf', args: [id] })),
          allowFailure: true,
        });
        const mine = ids.filter(
          (_id, i) =>
            owners[i].status === 'success' &&
            (owners[i].result as string)?.toLowerCase() === address.toLowerCase(),
        );
        if (mine.length === 0) {
          if (!cancelled) setPositions([]);
          return;
        }
        const metas = await publicClient.multicall({
          contracts: mine.map((id) => ({ address: LP_NFT, abi: lpPositionNftAbi, functionName: 'getPosition', args: [id] })),
          allowFailure: true,
        });
        const result: LpPosition[] = mine.map((id, i) => {
          const r = metas[i].status === 'success' ? (metas[i].result as unknown as [`0x${string}`, bigint, bigint]) : undefined;
          return { tokenId: id, pool: r?.[0] ?? ('0x' as `0x${string}`), liquidity: r?.[1] ?? 0n, createdAt: r?.[2] ?? 0n };
        });
        if (!cancelled) setPositions(result);
      } catch (e) {
        console.error('[pool] failed to load LP positions', e);
        if (!cancelled) setPositions([]);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [publicClient, address, nonce]);

  return { positions, loading, refresh };
}

export function Pool() {
  const { isConnected, address } = useAccount();
  const [amount0, setAmount0] = useState('');
  const [amount1, setAmount1] = useState('');

  // Pool tokens + reserves + supply
  const { data: token0 } = useReadContract({ address: PAIR, abi: pairAbi, functionName: 'token0' });
  const { data: token1 } = useReadContract({ address: PAIR, abi: pairAbi, functionName: 'token1' });
  const { data: reserves, refetch: refetchReserves } = useReadContract({ address: PAIR, abi: pairAbi, functionName: 'getReserves' });
  const { data: totalLPSupply, refetch: refetchSupply } = useReadContract({ address: PAIR, abi: pairAbi, functionName: 'totalLPSupply' });

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

  // User + pair balances (pair balance vs reserve detects funded amounts)
  const { data: userBal0, refetch: refetchUB0 } = useReadContract({
    address: token0, abi: viemErc20Abi, functionName: 'balanceOf', args: address ? [address] : undefined, query: { enabled: !!token0 && !!address },
  });
  const { data: userBal1, refetch: refetchUB1 } = useReadContract({
    address: token1, abi: viemErc20Abi, functionName: 'balanceOf', args: address ? [address] : undefined, query: { enabled: !!token1 && !!address },
  });
  const { data: pairBal0, refetch: refetchPB0 } = useReadContract({
    address: token0, abi: viemErc20Abi, functionName: 'balanceOf', args: [PAIR], query: { enabled: !!token0 },
  });
  const { data: pairBal1, refetch: refetchPB1 } = useReadContract({
    address: token1, abi: viemErc20Abi, functionName: 'balanceOf', args: [PAIR], query: { enabled: !!token1 },
  });

  const { positions, loading: posLoading, refresh: refreshPositions } = useLpPositions(address);

  const amt0Wei = useMemo(() => { try { return amount0 && Number(amount0) > 0 ? parseUnits(amount0, dec0) : 0n; } catch { return 0n; } }, [amount0, dec0]);
  const amt1Wei = useMemo(() => { try { return amount1 && Number(amount1) > 0 ? parseUnits(amount1, dec1) : 0n; } catch { return 0n; } }, [amount1, dec1]);

  // Suggest the paired amount from the reserve ratio when the user edits token0.
  const onChangeAmount0 = (v: string) => {
    setAmount0(v);
    if (reserves && (reserves[0] as bigint) > 0n && v && Number(v) > 0) {
      try {
        const a0 = parseUnits(v, dec0);
        const suggested = (a0 * (reserves[1] as bigint)) / (reserves[0] as bigint);
        setAmount1(formatUnits(suggested, dec1));
      } catch { /* ignore */ }
    }
  };

  const reserve0 = reserves ? (reserves[0] as bigint) : 0n;
  const reserve1 = reserves ? (reserves[1] as bigint) : 0n;
  const excess0 = pairBal0 !== undefined ? (pairBal0 as bigint) - reserve0 : 0n;
  const excess1 = pairBal1 !== undefined ? (pairBal1 as bigint) - reserve1 : 0n;
  const funded0 = amt0Wei > 0n && excess0 >= amt0Wei;

  const refetchAll = () => {
    refetchReserves(); refetchSupply(); refetchUB0(); refetchUB1(); refetchPB0(); refetchPB1();
  };

  const transfer0Req: TxRequest | undefined = token0 && amt0Wei > 0n
    ? { address: token0, abi: viemErc20Abi as unknown as TxRequest['abi'], functionName: 'transfer', args: [PAIR, amt0Wei] } : undefined;
  const transfer1Req: TxRequest | undefined = token1 && amt1Wei > 0n
    ? { address: token1, abi: viemErc20Abi as unknown as TxRequest['abi'], functionName: 'transfer', args: [PAIR, amt1Wei] } : undefined;
  const mintReq: TxRequest | undefined = address
    ? { address: PAIR, abi: pairAbi as unknown as TxRequest['abi'], functionName: 'mint', args: [address] } : undefined;

  // `mint()` consumes whatever is sitting in the pair above its reserves, so
  // minting is possible the moment the pair holds BOTH tokens — independent of
  // the exact amounts typed in the inputs. (Gating on `excess >= typedAmount`
  // would strand users who transferred a slightly different amount.)
  const canMint = excess0 > 0n && excess1 > 0n;

  return (
    <div className="max-w-6xl mx-auto space-y-10">
      <div className="space-y-2">
        <h1 className="text-4xl font-bold text-white flex items-center gap-3">
          <Droplets className="text-indigo-500 w-10 h-10" />
          Liquidity Pool
        </h1>
        <p className="text-gray-400 text-lg">
          Provide liquidity to the {sym0}/{sym1} pool and manage your LP position NFTs.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* Add liquidity */}
        <motion.div initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} className="lg:col-span-5">
          <div className="glass-card p-6 space-y-5">
            <h2 className="text-xl font-bold text-white flex items-center gap-2">
              <Plus size={20} className="text-indigo-400" /> Add Liquidity
            </h2>

            {/* token0 */}
            <div className="p-4 rounded-2xl bg-black/40 border border-white/5">
              <div className="flex justify-between mb-2 text-sm text-gray-400">
                <span>{sym0}</span>
                <span>Balance: {userBal0 !== undefined ? Number(formatUnits(userBal0 as bigint, dec0)).toFixed(4) : '0.00'}</span>
              </div>
              <input
                type="number" placeholder="0.0" value={amount0} onChange={(e) => onChangeAmount0(e.target.value)}
                className="w-full bg-transparent text-3xl text-white font-medium focus:outline-none placeholder:text-gray-600"
              />
            </div>

            {/* token1 */}
            <div className="p-4 rounded-2xl bg-black/40 border border-white/5">
              <div className="flex justify-between mb-2 text-sm text-gray-400">
                <span>{sym1}</span>
                <span>Balance: {userBal1 !== undefined ? Number(formatUnits(userBal1 as bigint, dec1)).toFixed(4) : '0.00'}</span>
              </div>
              <input
                type="number" placeholder="0.0" value={amount1} onChange={(e) => setAmount1(e.target.value)}
                className="w-full bg-transparent text-3xl text-white font-medium focus:outline-none placeholder:text-gray-600"
              />
            </div>

            <div className="flex items-start gap-2 text-xs text-gray-500">
              <Info size={14} className="shrink-0 mt-0.5" />
              <span>Funds are sent directly to the pair, then minted (no router). Confirm each token transfer, then mint your LP NFT.</span>
            </div>

            {!isConnected ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold cursor-not-allowed">Connect wallet</button>
            ) : canMint ? (
              <>
                <TxButton
                  request={mintReq} enabled={!!mintReq} text="Mint LP Position" confirmingText="Minting…"
                  className="font-bold"
                  onSuccess={() => { setAmount0(''); setAmount1(''); refetchAll(); refreshPositions(); }}
                />
                <p className="mt-2 text-xs text-gray-500">
                  Pool holds {Number(formatUnits(excess0, dec0)).toFixed(4)} {sym0} +{' '}
                  {Number(formatUnits(excess1, dec1)).toFixed(4)} {sym1} ready to mint.
                </p>
              </>
            ) : amt0Wei === 0n || amt1Wei === 0n ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold cursor-not-allowed">Enter amounts</button>
            ) : !funded0 ? (
              <TxButton request={transfer0Req} enabled={!!transfer0Req} text={`Transfer ${sym0}`} onSuccess={refetchAll} className="font-bold" />
            ) : (
              <TxButton request={transfer1Req} enabled={!!transfer1Req} text={`Transfer ${sym1}`} onSuccess={refetchAll} className="font-bold" />
            )}
          </div>
        </motion.div>

        {/* Positions */}
        <motion.div initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} className="lg:col-span-7">
          <div className="glass-card p-6">
            <h2 className="text-xl font-bold text-white flex items-center gap-2 mb-6">
              <Layers size={20} className="text-cyan-400" /> Your LP Positions
            </h2>

            {!isConnected ? (
              <p className="text-gray-500 text-center py-12">Connect your wallet to view positions.</p>
            ) : posLoading ? (
              <div className="space-y-3">
                {[0, 1].map((i) => <div key={i} className="h-24 rounded-2xl bg-white/5 animate-pulse" />)}
              </div>
            ) : positions.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-12 text-center">
                <Droplets size={40} className="text-white/10 mb-3" />
                <p className="text-gray-400 font-medium">No liquidity positions yet</p>
                <p className="text-gray-500 text-sm">Add liquidity to mint your first LP NFT.</p>
              </div>
            ) : (
              <div className="space-y-4">
                {positions.map((p) => {
                  const sharePct = totalLPSupply && (totalLPSupply as bigint) > 0n
                    ? (Number(p.liquidity) / Number(totalLPSupply as bigint)) * 100 : 0;
                  // Underlying token amounts for this position's share.
                  const amt0 = totalLPSupply && (totalLPSupply as bigint) > 0n ? (p.liquidity * reserve0) / (totalLPSupply as bigint) : 0n;
                  const amt1 = totalLPSupply && (totalLPSupply as bigint) > 0n ? (p.liquidity * reserve1) / (totalLPSupply as bigint) : 0n;
                  return (
                    <div key={p.tokenId.toString()} className="p-5 rounded-2xl bg-black/40 border border-white/5 hover:border-cyan-500/30 transition-colors">
                      <div className="flex items-center justify-between mb-4">
                        <div className="flex items-center gap-2">
                          <span className="px-2.5 py-1 rounded-lg bg-cyan-500/10 text-cyan-400 text-xs font-bold flex items-center gap-1">
                            <Hash size={12} />{p.tokenId.toString()}
                          </span>
                          <span className="text-white font-semibold">{sym0}/{sym1}</span>
                        </div>
                        <span className="text-sm text-gray-400">{sharePct.toFixed(4)}% of pool</span>
                      </div>
                      <div className="grid grid-cols-3 gap-3 mb-4 text-sm">
                        <div>
                          <p className="text-gray-500">Liquidity</p>
                          <p className="text-white font-medium">{p.liquidity.toLocaleString()}</p>
                        </div>
                        <div>
                          <p className="text-gray-500">{sym0}</p>
                          <p className="text-white font-medium">{Number(formatUnits(amt0, dec0)).toFixed(4)}</p>
                        </div>
                        <div>
                          <p className="text-gray-500">{sym1}</p>
                          <p className="text-white font-medium">{Number(formatUnits(amt1, dec1)).toFixed(4)}</p>
                        </div>
                      </div>
                      <TxButton
                        request={address ? { address: PAIR, abi: pairAbi as unknown as TxRequest['abi'], functionName: 'burn', args: [p.tokenId, address] } : undefined}
                        enabled={!!address}
                        variant="danger"
                        text="Remove Liquidity"
                        confirmingText="Removing…"
                        onSuccess={() => { refetchAll(); refreshPositions(); }}
                      />
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </motion.div>
      </div>
    </div>
  );
}
