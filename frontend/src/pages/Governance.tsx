import { useState } from 'react';
import { useAccount, useReadContract, useWriteContract } from 'wagmi';
import { motion, AnimatePresence } from 'framer-motion';
import { Vote, FileText, Search } from 'lucide-react';
import { parseUnits, formatUnits } from 'viem';

import { addresses } from '../contracts/addresses';
import { protocolGovernorAbi } from '../contracts/abis/protocolGovernorAbi';
import { governanceTokenAbi } from '../contracts/abis/governanceTokenAbi';
import { TxButton } from '../components/TxButton';

export function Governance() {
  const { isConnected, address } = useAccount();
  const [activeTab, setActiveTab] = useState<'proposals' | 'create'>('proposals');
  
  // Create Proposal Form State
  const [description, setDescription] = useState('');
  const [targetAddress, setTargetAddress] = useState('');
  const [value, setValue] = useState('0');
  const [calldata, setCalldata] = useState('0x');

  // Proposal Lookup State
  const [searchId, setSearchId] = useState('');

  // Read Contracts
  const { data: proposalThreshold } = useReadContract({
    address: addresses.Governor as `0x${string}`,
    abi: protocolGovernorAbi,
    functionName: 'proposalThreshold',
  });

  const { data: userVotes } = useReadContract({
    address: addresses.GovernanceToken as `0x${string}`,
    abi: governanceTokenAbi,
    functionName: 'getVotes',
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  const { data: totalSupply } = useReadContract({
    address: addresses.GovernanceToken as `0x${string}`,
    abi: governanceTokenAbi,
    functionName: 'totalSupply',
  });

  // State Lookup
  const { data: searchedProposalState } = useReadContract({
    address: addresses.Governor as `0x${string}`,
    abi: protocolGovernorAbi,
    functionName: 'state',
    args: searchId && !isNaN(Number(searchId)) ? [BigInt(searchId)] : undefined,
    query: { enabled: !!searchId && !isNaN(Number(searchId)) }
  });

  const { writeContractAsync } = useWriteContract();

  const handleCreateProposal = async () => {
    if (!description || !targetAddress) return;
    return writeContractAsync({
      address: addresses.Governor as `0x${string}`,
      abi: protocolGovernorAbi,
      functionName: 'propose',
      args: [
        [targetAddress as `0x${string}`], 
        [parseUnits(value || '0', 18)], 
        [calldata as `0x${string}`], 
        description
      ],
    });
  };

  const handleDelegate = async () => {
    if (!address) return;
    return writeContractAsync({
      address: addresses.GovernanceToken as `0x${string}`,
      abi: governanceTokenAbi,
      functionName: 'delegate',
      args: [address],
    });
  };

  const getStateColorAndLabel = (stateNum?: number) => {
    switch(stateNum) {
      case 0: return { label: 'Pending', color: 'bg-gray-500/20 text-gray-400 border-gray-500/30' };
      case 1: return { label: 'Active', color: 'bg-blue-500/20 text-blue-400 border-blue-500/30' };
      case 2: return { label: 'Canceled', color: 'bg-red-500/20 text-red-400 border-red-500/30' };
      case 3: return { label: 'Defeated', color: 'bg-red-500/20 text-red-400 border-red-500/30' };
      case 4: return { label: 'Succeeded', color: 'bg-green-500/20 text-green-400 border-green-500/30' };
      case 5: return { label: 'Queued', color: 'bg-yellow-500/20 text-yellow-400 border-yellow-500/30' };
      case 6: return { label: 'Expired', color: 'bg-gray-500/20 text-gray-400 border-gray-500/30' };
      case 7: return { label: 'Executed', color: 'bg-green-500/20 text-green-400 border-green-500/30' };
      default: return { label: 'Unknown', color: 'bg-white/5 text-gray-500 border-white/10' };
    }
  };

  return (
    <div className="max-w-5xl mx-auto space-y-10">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div className="space-y-2">
          <h1 className="text-4xl font-bold text-white flex items-center gap-3">
            <Vote className="text-violet-500 w-10 h-10" />
            Governance
          </h1>
          <p className="text-gray-400 text-lg">Participate in protocol decisions and shape the future.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* User Voting Power Panel */}
        <div className="lg:col-span-4 space-y-6">
          <div className="glass-card p-6 border-violet-500/20 relative overflow-hidden">
            <div className="absolute -top-10 -right-10 w-32 h-32 bg-violet-500/20 rounded-full blur-2xl pointer-events-none" />
            
            <h2 className="text-lg font-semibold text-white mb-6">Your Voting Power</h2>
            
            <div className="text-5xl font-bold text-white mb-2">
              {userVotes ? Number(formatUnits(userVotes as bigint, 18)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'}
            </div>
            <p className="text-gray-400 text-sm mb-8">GOV Tokens Delegated</p>
            
            <div className="space-y-4 pt-6 border-t border-white/10">
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Total Supply</span>
                <span className="text-white font-medium">
                  {totalSupply ? Number(formatUnits(totalSupply as bigint, 18)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'}
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Proposal Threshold</span>
                <span className="text-white font-medium">
                  {proposalThreshold ? Number(formatUnits(proposalThreshold as bigint, 18)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'}
                </span>
              </div>
            </div>

            <div className="mt-8 pt-6 border-t border-white/10">
              <p className="text-xs text-gray-400 mb-3 leading-relaxed">
                To participate in governance, you must delegate your votes to yourself or another address.
              </p>
              <TxButton
                onClick={handleDelegate}
                disabled={!isConnected}
                text="Delegate to Self"
                loadingText="Delegating..."
                className="w-full !bg-white/10 !shadow-none hover:!bg-white/20"
              />
            </div>
          </div>
        </div>

        {/* Main Panel */}
        <div className="lg:col-span-8">
          <div className="glass-card p-2 md:p-6 min-h-[600px]">
            <div className="flex gap-2 p-1.5 mb-8 bg-black/40 rounded-2xl w-fit">
              <button
                onClick={() => setActiveTab('proposals')}
                className={`py-2 px-6 rounded-xl text-sm font-bold transition-all ${
                  activeTab === 'proposals' 
                    ? 'bg-white text-black shadow-md' 
                    : 'text-gray-400 hover:text-white hover:bg-white/5'
                }`}
              >
                Proposals
              </button>
              <button
                onClick={() => setActiveTab('create')}
                className={`py-2 px-6 rounded-xl text-sm font-bold transition-all ${
                  activeTab === 'create' 
                    ? 'bg-white text-black shadow-md' 
                    : 'text-gray-400 hover:text-white hover:bg-white/5'
                }`}
              >
                Create Proposal
              </button>
            </div>

            <AnimatePresence mode="wait">
              {activeTab === 'proposals' ? (
                <motion.div
                  key="proposals"
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  className="space-y-6"
                >
                  <div className="p-6 rounded-3xl bg-violet-500/5 border border-violet-500/10 mb-8">
                    <h3 className="text-lg font-semibold text-white mb-2 flex items-center gap-2">
                      <Search size={20} className="text-violet-400" />
                      Lookup Proposal On-Chain
                    </h3>
                    <p className="text-sm text-gray-400 mb-4">
                      Since this app connects directly to the blockchain without an indexing subgraph, proposals cannot be listed automatically. Enter a Proposal ID to view its current state.
                    </p>
                    
                    <div className="flex gap-4">
                      <input
                        type="text"
                        value={searchId}
                        onChange={(e) => setSearchId(e.target.value)}
                        placeholder="Enter numeric Proposal ID..."
                        className="flex-grow px-4 py-3 bg-black/40 border border-white/10 rounded-xl text-white focus:outline-none focus:border-violet-500 transition-colors"
                      />
                    </div>

                    {searchId && !isNaN(Number(searchId)) && (
                      <div className="mt-6 p-4 rounded-xl bg-black/40 border border-white/5 flex items-center justify-between">
                        <div>
                          <p className="text-sm text-gray-400 mb-1">Proposal ID: {searchId}</p>
                          <h4 className="text-white font-medium">On-Chain State</h4>
                        </div>
                        {searchedProposalState !== undefined ? (
                          <div className={`px-4 py-1.5 rounded-full border text-sm font-bold ${getStateColorAndLabel(searchedProposalState as number).color}`}>
                            {getStateColorAndLabel(searchedProposalState as number).label}
                          </div>
                        ) : (
                          <div className="px-4 py-1.5 rounded-full border border-white/10 bg-white/5 text-gray-500 text-sm font-bold animate-pulse">
                            Loading...
                          </div>
                        )}
                      </div>
                    )}
                  </div>

                  <div className="flex flex-col items-center justify-center py-12 text-center">
                    <FileText size={48} className="text-white/10 mb-4" />
                    <h3 className="text-xl font-bold text-gray-300 mb-2">No Active Proposals Found</h3>
                    <p className="text-gray-500 max-w-sm">Use the 'Create Proposal' tab to propose new protocol changes.</p>
                  </div>
                </motion.div>
              ) : (
                <motion.div
                  key="create"
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  className="space-y-6"
                >
                  <div className="space-y-4">
                    <div>
                      <label className="block text-sm font-medium text-gray-400 mb-2">Proposal Title & Description</label>
                      <textarea
                        value={description}
                        onChange={(e) => setDescription(e.target.value)}
                        placeholder="# Add new feature&#10;&#10;This proposal aims to..."
                        className="w-full h-40 px-4 py-3 bg-black/40 border border-white/10 rounded-2xl text-white focus:outline-none focus:border-violet-500 transition-colors resize-none"
                      />
                    </div>

                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                      <div>
                        <label className="block text-sm font-medium text-gray-400 mb-2">Target Contract Address</label>
                        <input
                          type="text"
                          value={targetAddress}
                          onChange={(e) => setTargetAddress(e.target.value)}
                          placeholder="0x..."
                          className="w-full px-4 py-3 bg-black/40 border border-white/10 rounded-xl text-white focus:outline-none focus:border-violet-500 transition-colors"
                        />
                      </div>
                      <div>
                        <label className="block text-sm font-medium text-gray-400 mb-2">Value (ETH)</label>
                        <input
                          type="text"
                          value={value}
                          onChange={(e) => setValue(e.target.value)}
                          placeholder="0.0"
                          className="w-full px-4 py-3 bg-black/40 border border-white/10 rounded-xl text-white focus:outline-none focus:border-violet-500 transition-colors"
                        />
                      </div>
                    </div>

                    <div>
                      <label className="block text-sm font-medium text-gray-400 mb-2">Calldata (Hex)</label>
                      <input
                        type="text"
                        value={calldata}
                        onChange={(e) => setCalldata(e.target.value)}
                        placeholder="0x..."
                        className="w-full px-4 py-3 bg-black/40 border border-white/10 rounded-xl text-white focus:outline-none focus:border-violet-500 transition-colors font-mono text-sm"
                      />
                    </div>

                    <div className="pt-4">
                      <TxButton
                        onClick={handleCreateProposal}
                        disabled={!isConnected || !description || !targetAddress}
                        text="Submit Proposal"
                        loadingText="Submitting..."
                        className="w-full py-4 rounded-2xl text-lg font-bold !bg-gradient-to-r !from-violet-500 !to-fuchsia-500 !shadow-violet-500/25"
                      />
                    </div>
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
