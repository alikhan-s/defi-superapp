import { useAccount } from 'wagmi';
import { motion } from 'framer-motion';
import { Wallet, Shield, ArrowLeftRight, Vote, AlertTriangle, Loader2, Info } from 'lucide-react';
import { formatUnits } from 'viem';

import { usePortfolio } from '../lib/graph';

const MAX_HF = 1e6; // healthFactor stored as 1e18; debt==0 carries MAX_UINT256

function short(addr?: string) {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : '—';
}
function fmt(v?: string, decimals = 18, digits = 4) {
  if (v === undefined || v === null) return '0';
  try { return Number(formatUnits(BigInt(v), decimals)).toLocaleString(undefined, { maximumFractionDigits: digits }); }
  catch { return '0'; }
}
function timeAgo(ts: string) {
  const d = new Date(Number(ts) * 1000);
  return d.toLocaleString();
}

const STATE_STYLES: Record<string, string> = {
  Active: 'bg-blue-500/20 text-blue-400 border-blue-500/30',
  Succeeded: 'bg-green-500/20 text-green-400 border-green-500/30',
  Executed: 'bg-green-500/20 text-green-400 border-green-500/30',
  Defeated: 'bg-red-500/20 text-red-400 border-red-500/30',
  Canceled: 'bg-red-500/20 text-red-400 border-red-500/30',
  Queued: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30',
  Pending: 'bg-gray-500/20 text-gray-400 border-gray-500/30',
};

export function Portfolio() {
  const { address, isConnected } = useAccount();
  const { data, loading, error } = usePortfolio(address);

  if (!isConnected) {
    return (
      <div className="max-w-5xl mx-auto py-24 text-center">
        <Wallet size={48} className="mx-auto text-white/10 mb-4" />
        <h1 className="text-2xl font-bold text-white mb-2">Connect your wallet</h1>
        <p className="text-gray-500">Your portfolio is reconstructed entirely from the subgraph.</p>
      </div>
    );
  }

  const lending = data?.lendingPosition;
  const swaps = data?.swaps ?? [];
  const proposals = data?.proposals ?? [];

  // Health factor from the indexed 1e18 value.
  const hfNum = lending ? Number(formatUnits(BigInt(lending.healthFactor || '0'), 18)) : 0;
  const debtZero = !lending || BigInt(lending.debt || '0') === 0n;
  const isInfinite = hfNum > MAX_HF || debtZero;
  let hfColor = 'text-gray-400';
  if (lending && !debtZero) {
    if (isInfinite || hfNum > 2) hfColor = 'text-green-400';
    else if (hfNum >= 1.5) hfColor = 'text-yellow-400';
    else hfColor = 'text-red-400';
  } else if (lending) hfColor = 'text-green-400';

  // Distinct pools the user has traded in — proxy for AMM/LP participation (Q5).
  const pools = Array.from(new Set(swaps.map((s) => s.pool.id)));

  return (
    <div className="max-w-5xl mx-auto space-y-8 pb-16">
      <div className="space-y-2">
        <h1 className="text-4xl font-bold text-white flex items-center gap-3">
          <Wallet className="text-indigo-500 w-10 h-10" />
          Portfolio
        </h1>
        <p className="text-gray-400 text-lg">
          A unified view for <span className="text-white font-mono">{short(address)}</span>, sourced entirely from the subgraph.
        </p>
      </div>

      {loading ? (
        <div className="flex flex-col items-center py-24 text-gray-500"><Loader2 className="w-8 h-8 animate-spin mb-3" />Querying the subgraph…</div>
      ) : error ? (
        <div className="glass-card flex flex-col items-center py-16 text-center">
          <AlertTriangle className="w-10 h-10 text-yellow-500/60 mb-3" />
          <p className="text-gray-300 font-medium mb-1">Couldn't reach the subgraph</p>
          <p className="text-gray-500 text-sm max-w-md">Set <code className="text-gray-400">VITE_SUBGRAPH_URL</code> to your deployed Phase 10 endpoint and reload.</p>
        </div>
      ) : (
        <>
          {/* Lending position */}
          <motion.section initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} className="glass-card">
            <div className="flex items-center gap-3 mb-6">
              <div className="p-2 bg-indigo-500/20 rounded-xl text-indigo-400"><Shield size={22} /></div>
              <h2 className="text-xl font-bold text-white">Lending Position</h2>
            </div>
            {lending ? (
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
                <div className="p-5 rounded-2xl bg-black/40 border border-white/5">
                  <p className="text-sm text-gray-400 mb-1">Collateral</p>
                  <p className="text-2xl font-bold text-white">{fmt(lending.collateral, 18, 4)}</p>
                </div>
                <div className="p-5 rounded-2xl bg-black/40 border border-white/5">
                  <p className="text-sm text-gray-400 mb-1">Debt</p>
                  <p className="text-2xl font-bold text-white">{fmt(lending.debt, 6, 2)}</p>
                </div>
                <div className="p-5 rounded-2xl bg-black/40 border border-white/5">
                  <p className="text-sm text-gray-400 mb-1">Health Factor</p>
                  <p className={`text-2xl font-bold ${hfColor}`}>{isInfinite ? '∞' : hfNum.toFixed(2)}</p>
                </div>
              </div>
            ) : (
              <p className="text-gray-500">No lending position indexed for this account.</p>
            )}
          </motion.section>

          {/* AMM / LP activity */}
          <motion.section initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.05 }} className="glass-card">
            <div className="flex items-center justify-between mb-6">
              <div className="flex items-center gap-3">
                <div className="p-2 bg-cyan-500/20 rounded-xl text-cyan-400"><ArrowLeftRight size={22} /></div>
                <h2 className="text-xl font-bold text-white">Liquidity & Trading</h2>
              </div>
              <span className="text-sm text-gray-400">{pools.length} pool{pools.length === 1 ? '' : 's'} · {swaps.length} swap{swaps.length === 1 ? '' : 's'}</span>
            </div>
            {swaps.length === 0 ? (
              <p className="text-gray-500">No AMM activity indexed yet.</p>
            ) : (
              <div className="space-y-2">
                {swaps.slice(0, 10).map((s) => {
                  const sold0 = BigInt(s.amount0In) > 0n;
                  const inAmt = sold0 ? s.amount0In : s.amount1In;
                  const outAmt = sold0 ? s.amount1Out : s.amount0Out;
                  const inTok = sold0 ? s.pool.token0 : s.pool.token1;
                  const outTok = sold0 ? s.pool.token1 : s.pool.token0;
                  return (
                    <div key={s.id} className="flex items-center justify-between p-4 rounded-xl bg-black/40 border border-white/5 text-sm">
                      <div className="flex items-center gap-2 text-white">
                        <span className="font-medium">{fmt(inAmt)}</span>
                        <span className="text-gray-500">{short(inTok)}</span>
                        <ArrowLeftRight size={14} className="text-gray-600" />
                        <span className="font-medium">{fmt(outAmt)}</span>
                        <span className="text-gray-500">{short(outTok)}</span>
                      </div>
                      <span className="text-gray-500">{timeAgo(s.timestamp)}</span>
                    </div>
                  );
                })}
              </div>
            )}
          </motion.section>

          {/* Governance */}
          <motion.section initial={{ opacity: 0, y: 16 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }} className="glass-card">
            <div className="flex items-center gap-3 mb-6">
              <div className="p-2 bg-violet-500/20 rounded-xl text-violet-400"><Vote size={22} /></div>
              <h2 className="text-xl font-bold text-white">Governance Activity</h2>
            </div>
            {proposals.length === 0 ? (
              <p className="text-gray-500">No proposals authored by this account.</p>
            ) : (
              <div className="space-y-2">
                {proposals.map((p) => (
                  <div key={p.id} className="flex items-center justify-between p-4 rounded-xl bg-black/40 border border-white/5">
                    <div className="min-w-0">
                      <p className="text-white font-medium truncate">{p.description?.split('\n')[0] || `Proposal ${short(p.proposalId)}`}</p>
                      <p className="text-xs text-gray-500">For {fmt(p.forVotes, 18, 0)} · Against {fmt(p.againstVotes, 18, 0)} · Abstain {fmt(p.abstainVotes, 18, 0)}</p>
                    </div>
                    <span className={`shrink-0 px-3 py-1 rounded-full border text-xs font-bold ${STATE_STYLES[p.state] ?? STATE_STYLES.Pending}`}>{p.state}</span>
                  </div>
                ))}
              </div>
            )}
          </motion.section>

          <div className="flex items-start gap-2 text-xs text-gray-500 px-2">
            <Info size={14} className="shrink-0 mt-0.5" />
            <p>
              LP positions are derived from indexed pool participation; lending and governance come from their entities. Per the Phase 10
              queries, raw ERC-20 holdings (vault shares, GOV voting power) are served by the companion <code className="text-gray-400">erc20-balances</code> endpoint.
            </p>
          </div>
        </>
      )}
    </div>
  );
}
