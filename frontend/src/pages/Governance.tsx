import { useState } from 'react';
import { useAccount, useReadContract } from 'wagmi';
import { motion, AnimatePresence } from 'framer-motion';
import { Vote, FileText, AlertTriangle, Loader2 } from 'lucide-react';
import { parseUnits, formatUnits } from 'viem';

import { addresses } from '../contracts/addresses';
import { protocolGovernorAbi } from '../contracts/abis/protocolGovernorAbi';
import { governanceTokenAbi } from '../contracts/abis/governanceTokenAbi';
import { TxButton, type TxRequest } from '../components/TxButton';
import { useProposals, type Proposal } from '../lib/graph';

const GOVERNOR = addresses.Governor as `0x${string}`;
const TOKEN = addresses.GovernanceToken as `0x${string}`;

// OpenZeppelin GovernorCountingSimple support values.
const SUPPORT = { Against: 0, For: 1, Abstain: 2 } as const;

const STATE_STYLES: Record<string, string> = {
  Pending: 'bg-gray-500/20 text-gray-400 border-gray-500/30',
  Active: 'bg-blue-500/20 text-blue-400 border-blue-500/30',
  Canceled: 'bg-red-500/20 text-red-400 border-red-500/30',
  Defeated: 'bg-red-500/20 text-red-400 border-red-500/30',
  Succeeded: 'bg-green-500/20 text-green-400 border-green-500/30',
  Queued: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30',
  Expired: 'bg-gray-500/20 text-gray-400 border-gray-500/30',
  Executed: 'bg-green-500/20 text-green-400 border-green-500/30',
};

function fmtVotes(v: string) {
  return Number(formatUnits(BigInt(v || '0'), 18)).toLocaleString(undefined, { maximumFractionDigits: 0 });
}

function ProposalCard({ p, canVote }: { p: Proposal; canVote: boolean }) {
  const isActive = p.state === 'Active';
  const voteReq = (support: number): TxRequest => ({
    address: GOVERNOR,
    abi: protocolGovernorAbi as unknown as TxRequest['abi'],
    functionName: 'castVote',
    args: [BigInt(p.proposalId), support],
  });

  return (
    <div className="p-6 rounded-2xl bg-black/40 border border-white/5 hover:border-violet-500/30 transition-colors">
      <div className="flex items-start justify-between gap-4 mb-3">
        <div className="min-w-0">
          <p className="text-xs text-gray-500 mb-1">#{p.proposalId.slice(0, 10)}…</p>
          <h3 className="text-white font-semibold truncate">{p.description?.split('\n')[0] || 'Untitled proposal'}</h3>
        </div>
        <span className={`shrink-0 px-3 py-1 rounded-full border text-xs font-bold ${STATE_STYLES[p.state] ?? STATE_STYLES.Pending}`}>{p.state}</span>
      </div>

      <div className="grid grid-cols-3 gap-2 text-center my-4">
        <div className="p-2 rounded-lg bg-green-500/5"><p className="text-green-400 font-bold">{fmtVotes(p.forVotes)}</p><p className="text-xs text-gray-500">For</p></div>
        <div className="p-2 rounded-lg bg-red-500/5"><p className="text-red-400 font-bold">{fmtVotes(p.againstVotes)}</p><p className="text-xs text-gray-500">Against</p></div>
        <div className="p-2 rounded-lg bg-gray-500/5"><p className="text-gray-300 font-bold">{fmtVotes(p.abstainVotes)}</p><p className="text-xs text-gray-500">Abstain</p></div>
      </div>

      {isActive && canVote ? (
        <div className="grid grid-cols-3 gap-2">
          <TxButton request={voteReq(SUPPORT.For)} text="For" confirmingText="Voting…" className="!from-green-500 !to-emerald-500 !shadow-none" />
          <TxButton request={voteReq(SUPPORT.Against)} text="Against" variant="danger" confirmingText="Voting…" />
          <TxButton request={voteReq(SUPPORT.Abstain)} text="Abstain" variant="secondary" confirmingText="Voting…" />
        </div>
      ) : isActive ? (
        <p className="text-center text-xs text-gray-500">Delegate voting power to participate.</p>
      ) : null}
    </div>
  );
}

export function Governance() {
  const { isConnected, address } = useAccount();
  const [activeTab, setActiveTab] = useState<'proposals' | 'create'>('proposals');

  const [description, setDescription] = useState('');
  const [targetAddress, setTargetAddress] = useState('');
  const [value, setValue] = useState('0');
  const [calldata, setCalldata] = useState('0x');

  // Subgraph-driven proposal list (Q3).
  const { data: proposalData, loading: proposalsLoading, error: proposalsError } = useProposals();
  const proposals = proposalData?.proposals ?? [];

  const { data: proposalThreshold } = useReadContract({ address: GOVERNOR, abi: protocolGovernorAbi, functionName: 'proposalThreshold' });
  const { data: userVotes } = useReadContract({
    address: TOKEN, abi: governanceTokenAbi, functionName: 'getVotes', args: address ? [address] : undefined, query: { enabled: !!address },
  });
  const { data: totalSupply } = useReadContract({ address: TOKEN, abi: governanceTokenAbi, functionName: 'totalSupply' });

  const votes = (userVotes as bigint) ?? 0n;
  const threshold = (proposalThreshold as bigint) ?? 0n;
  const meetsThreshold = votes >= threshold;
  const canVote = (votes ?? 0n) > 0n;

  // Create-proposal request (gated below by meetsThreshold).
  const proposeReq: TxRequest | undefined =
    description && targetAddress
      ? {
          address: GOVERNOR,
          abi: protocolGovernorAbi as unknown as TxRequest['abi'],
          functionName: 'propose',
          args: [[targetAddress as `0x${string}`], [parseUnits(value || '0', 18)], [(calldata || '0x') as `0x${string}`], description],
        }
      : undefined;

  const delegateReq: TxRequest | undefined = address
    ? { address: TOKEN, abi: governanceTokenAbi as unknown as TxRequest['abi'], functionName: 'delegate', args: [address] }
    : undefined;

  return (
    <div className="max-w-5xl mx-auto space-y-10">
      <div className="space-y-2">
        <h1 className="text-4xl font-bold text-white flex items-center gap-3">
          <Vote className="text-violet-500 w-10 h-10" />
          Governance
        </h1>
        <p className="text-gray-400 text-lg">Vote on proposals and shape the protocol. Proposals are indexed by the subgraph.</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* Voting power */}
        <div className="lg:col-span-4 space-y-6">
          <div className="glass-card p-6 border-violet-500/20 relative overflow-hidden">
            <div className="absolute -top-10 -right-10 w-32 h-32 bg-violet-500/20 rounded-full blur-2xl pointer-events-none" />
            <h2 className="text-lg font-semibold text-white mb-6">Your Voting Power</h2>
            <div className="text-5xl font-bold text-white mb-2">
              {Number(formatUnits(votes, 18)).toLocaleString(undefined, { maximumFractionDigits: 0 })}
            </div>
            <p className="text-gray-400 text-sm mb-8">GOV delegated</p>

            <div className="space-y-4 pt-6 border-t border-white/10 text-sm">
              <div className="flex justify-between"><span className="text-gray-400">Total Supply</span><span className="text-white font-medium">{totalSupply ? Number(formatUnits(totalSupply as bigint, 18)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'}</span></div>
              <div className="flex justify-between"><span className="text-gray-400">Proposal Threshold</span><span className="text-white font-medium">{Number(formatUnits(threshold, 18)).toLocaleString(undefined, { maximumFractionDigits: 0 })}</span></div>
            </div>

            <div className="mt-8 pt-6 border-t border-white/10">
              <p className="text-xs text-gray-400 mb-3 leading-relaxed">You must delegate votes (to yourself) before they count.</p>
              <TxButton request={delegateReq} enabled={isConnected} text="Delegate to Self" confirmingText="Delegating…" className="!bg-white/10 !shadow-none hover:!bg-white/20" />
            </div>
          </div>
        </div>

        {/* Main */}
        <div className="lg:col-span-8">
          <div className="glass-card p-2 md:p-6 min-h-[600px]">
            <div className="flex gap-2 p-1.5 mb-8 bg-black/40 rounded-2xl w-fit">
              {(['proposals', 'create'] as const).map((t) => (
                <button
                  key={t}
                  onClick={() => setActiveTab(t)}
                  className={`py-2 px-6 rounded-xl text-sm font-bold capitalize transition-all ${activeTab === t ? 'bg-white text-black shadow-md' : 'text-gray-400 hover:text-white hover:bg-white/5'}`}
                >
                  {t === 'create' ? 'Create Proposal' : 'Proposals'}
                </button>
              ))}
            </div>

            <AnimatePresence mode="wait">
              {activeTab === 'proposals' ? (
                <motion.div key="proposals" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -10 }} className="space-y-4">
                  {proposalsLoading ? (
                    <div className="flex flex-col items-center py-16 text-gray-500"><Loader2 className="w-8 h-8 animate-spin mb-3" />Loading proposals from subgraph…</div>
                  ) : proposalsError ? (
                    <div className="flex flex-col items-center py-16 text-center">
                      <AlertTriangle className="w-10 h-10 text-yellow-500/60 mb-3" />
                      <p className="text-gray-300 font-medium mb-1">Couldn't reach the subgraph</p>
                      <p className="text-gray-500 text-sm max-w-sm">Check that <code className="text-gray-400">VITE_SUBGRAPH_URL</code> points at the deployed Phase 10 subgraph.</p>
                    </div>
                  ) : proposals.length === 0 ? (
                    <div className="flex flex-col items-center justify-center py-16 text-center">
                      <FileText size={48} className="text-white/10 mb-4" />
                      <h3 className="text-xl font-bold text-gray-300 mb-2">No proposals yet</h3>
                      <p className="text-gray-500 max-w-sm">Use the Create Proposal tab to propose protocol changes.</p>
                    </div>
                  ) : (
                    proposals.map((p) => <ProposalCard key={p.id} p={p} canVote={isConnected && canVote} />)
                  )}
                </motion.div>
              ) : (
                <motion.div key="create" initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} exit={{ opacity: 0, y: -10 }} className="space-y-4">
                  {isConnected && !meetsThreshold && (
                    <div className="flex items-start gap-3 p-4 rounded-xl bg-yellow-500/10 border border-yellow-500/20 text-yellow-200 text-sm">
                      <AlertTriangle className="w-5 h-5 shrink-0 mt-0.5 text-yellow-400" />
                      <span>
                        You need at least {Number(formatUnits(threshold, 18)).toLocaleString()} delegated GOV to create a proposal. You currently
                        have {Number(formatUnits(votes, 18)).toLocaleString()}.
                      </span>
                    </div>
                  )}

                  <div>
                    <label className="block text-sm font-medium text-gray-400 mb-2">Description</label>
                    <textarea value={description} onChange={(e) => setDescription(e.target.value)} placeholder="# Title&#10;&#10;Details…" className="w-full h-40 px-4 py-3 bg-black/40 border border-white/10 rounded-2xl text-white focus:outline-none focus:border-violet-500 transition-colors resize-none" />
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-400 mb-2">Target Contract</label>
                      <input type="text" value={targetAddress} onChange={(e) => setTargetAddress(e.target.value)} placeholder="0x…" className="w-full px-4 py-3 bg-black/40 border border-white/10 rounded-xl text-white focus:outline-none focus:border-violet-500 transition-colors" />
                    </div>
                    <div>
                      <label className="block text-sm font-medium text-gray-400 mb-2">Value (ETH)</label>
                      <input type="text" value={value} onChange={(e) => setValue(e.target.value)} placeholder="0.0" className="w-full px-4 py-3 bg-black/40 border border-white/10 rounded-xl text-white focus:outline-none focus:border-violet-500 transition-colors" />
                    </div>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-gray-400 mb-2">Calldata (hex)</label>
                    <input type="text" value={calldata} onChange={(e) => setCalldata(e.target.value)} placeholder="0x" className="w-full px-4 py-3 bg-black/40 border border-white/10 rounded-xl text-white focus:outline-none focus:border-violet-500 transition-colors font-mono text-sm" />
                  </div>

                  <div className="pt-4">
                    {!isConnected ? (
                      <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold cursor-not-allowed">Connect wallet</button>
                    ) : (
                      <TxButton
                        request={proposeReq}
                        enabled={!!proposeReq && meetsThreshold}
                        disabled={!meetsThreshold}
                        text="Submit Proposal"
                        confirmingText="Submitting…"
                        className="text-lg font-bold !bg-gradient-to-r !from-violet-500 !to-fuchsia-500 !shadow-violet-500/25"
                      />
                    )}
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </div>
    </div>
  );
}
