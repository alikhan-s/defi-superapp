import { useState } from 'react';
import { useAccount, useReadContract, useWriteContract } from 'wagmi';
import { motion } from 'framer-motion';
import { Shield, ArrowUpCircle, ArrowDownCircle, Info } from 'lucide-react';
import { parseUnits, formatUnits } from 'viem';

import { addresses } from '../contracts/addresses';
import { lendingPoolAbi } from '../contracts/abis/lendingPoolAbi';

import { TxButton } from '../components/TxButton';

type TabType = 'deposit' | 'withdraw' | 'borrow' | 'repay';

export function Lend() {
  const { isConnected, address } = useAccount();
  const [activeTab, setActiveTab] = useState<TabType>('deposit');
  const [amount, setAmount] = useState('');

  // Read Protocol Stats
  const { data: totalCollateral } = useReadContract({
    address: addresses.LendingPool as `0x${string}`,
    abi: lendingPoolAbi,
    functionName: 'totalCollateral',
  });
  
  const { data: totalDebt } = useReadContract({
    address: addresses.LendingPool as `0x${string}`,
    abi: lendingPoolAbi,
    functionName: 'totalDebt',
  });



  // Read User Position
  const { data: position } = useReadContract({
    address: addresses.LendingPool as `0x${string}`,
    abi: lendingPoolAbi,
    functionName: 'positions',
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  const { data: healthFactorRaw } = useReadContract({
    address: addresses.LendingPool as `0x${string}`,
    abi: lendingPoolAbi,
    functionName: 'healthFactor',
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  // Parse Position
  const userCollateral = position ? Number(formatUnits(position[0], 18)) : 0;
  const userDebt = position ? Number(formatUnits(position[1], 18)) : 0; // Using debt shares as proxy for now

  // Health Factor UI
  const rawHf = healthFactorRaw ? Number(formatUnits(healthFactorRaw as bigint, 18)) : 0;
  const isInfiniteHf = rawHf > 1000000 || userDebt === 0;
  const healthFactor = isInfiniteHf ? '∞' : rawHf.toFixed(2);
  
  let hfColor = 'text-gray-400';
  let hfRing = 'border-gray-500/30';
  if (userCollateral > 0) {
    if (isInfiniteHf || rawHf > 2) {
      hfColor = 'text-green-400';
      hfRing = 'border-green-500 shadow-[0_0_15px_rgba(34,197,94,0.4)]';
    } else if (rawHf >= 1.5) {
      hfColor = 'text-yellow-400';
      hfRing = 'border-yellow-400 shadow-[0_0_15px_rgba(250,204,21,0.4)]';
    } else {
      hfColor = 'text-red-400';
      hfRing = 'border-red-500 shadow-[0_0_15px_rgba(239,68,68,0.4)]';
    }
  }

  // Contract Writes
  const { writeContractAsync } = useWriteContract();

  const handleAction = async () => {
    if (!amount || isNaN(Number(amount))) return;
    const parsedAmount = parseUnits(amount, 18);

    if (activeTab === 'deposit') {
      return writeContractAsync({
        address: addresses.LendingPool as `0x${string}`,
        abi: lendingPoolAbi,
        functionName: 'depositCollateral',
        args: [parsedAmount],
        value: parsedAmount, // ETH is collateral
      });
    } else if (activeTab === 'withdraw') {
      return writeContractAsync({
        address: addresses.LendingPool as `0x${string}`,
        abi: lendingPoolAbi,
        functionName: 'withdrawCollateral',
        args: [parsedAmount],
      });
    } else if (activeTab === 'borrow') {
      return writeContractAsync({
        address: addresses.LendingPool as `0x${string}`,
        abi: lendingPoolAbi,
        functionName: 'borrow',
        args: [parsedAmount],
      });
    } else if (activeTab === 'repay') {
      // Typically requires approval first, but we will just call repay assuming it's done or it's native
      return writeContractAsync({
        address: addresses.LendingPool as `0x${string}`,
        abi: lendingPoolAbi,
        functionName: 'repay',
        args: [parsedAmount],
      });
    }
  };

  return (
    <div className="max-w-6xl mx-auto space-y-10">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div className="space-y-2">
          <h1 className="text-4xl font-bold text-white flex items-center gap-3">
            <Shield className="text-indigo-500 w-10 h-10" />
            Lending Market
          </h1>
          <p className="text-gray-400 text-lg">Supply collateral to earn yield, or borrow assets instantly.</p>
        </div>
        
        {/* Protocol Stats */}
        <div className="flex gap-4">
          <div className="p-4 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-md">
            <p className="text-sm text-gray-400 mb-1">Total Supplied</p>
            <p className="text-xl font-bold text-white">
              {totalCollateral ? Number(formatUnits(totalCollateral, 18)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'} <span className="text-sm text-indigo-400">ETH</span>
            </p>
          </div>
          <div className="p-4 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-md">
            <p className="text-sm text-gray-400 mb-1">Total Borrowed</p>
            <p className="text-xl font-bold text-white">
              {totalDebt ? Number(formatUnits(totalDebt, 18)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'} <span className="text-sm text-cyan-400">USDC</span>
            </p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* User Position Panel */}
        <motion.div
          initial={{ opacity: 0, x: -20 }}
          animate={{ opacity: 1, x: 0 }}
          className="lg:col-span-4 space-y-6"
        >
          <div className="glass-card flex flex-col items-center p-8 relative overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/10 to-cyan-500/10 blur-xl z-0" />
            <h2 className="text-xl font-semibold text-white mb-8 relative z-10 w-full text-left">Your Position</h2>
            
            {/* Health Factor Gauge */}
            <div className="relative z-10 flex flex-col items-center justify-center mb-8">
              <div className={`w-40 h-40 rounded-full border-[6px] ${hfRing} flex flex-col items-center justify-center bg-[#0a0b0f]/80 backdrop-blur-sm transition-all duration-500`}>
                <span className="text-sm text-gray-400 mb-1 font-medium tracking-wide">HEALTH FACTOR</span>
                <span className={`text-4xl font-bold ${hfColor}`}>{isConnected ? healthFactor : '-'}</span>
              </div>
            </div>

            <div className="w-full space-y-4 relative z-10">
              <div className="flex justify-between items-center p-4 rounded-xl bg-black/40 border border-white/5">
                <div className="flex items-center gap-2">
                  <ArrowUpCircle className="text-indigo-400 w-5 h-5" />
                  <span className="text-gray-300">Supplied</span>
                </div>
                <span className="text-white font-bold">{userCollateral.toFixed(4)} ETH</span>
              </div>
              <div className="flex justify-between items-center p-4 rounded-xl bg-black/40 border border-white/5">
                <div className="flex items-center gap-2">
                  <ArrowDownCircle className="text-cyan-400 w-5 h-5" />
                  <span className="text-gray-300">Borrowed</span>
                </div>
                <span className="text-white font-bold">{userDebt.toFixed(2)} USDC</span>
              </div>
            </div>
          </div>
        </motion.div>

        {/* Action Panel */}
        <motion.div
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          className="lg:col-span-8 glass-card p-2"
        >
          {/* Tabs */}
          <div className="flex p-2 gap-2 mb-6 bg-black/20 rounded-2xl overflow-x-auto no-scrollbar">
            {[
              { id: 'deposit', label: 'Deposit' },
              { id: 'withdraw', label: 'Withdraw' },
              { id: 'borrow', label: 'Borrow' },
              { id: 'repay', label: 'Repay' }
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as TabType)}
                className={`flex-1 min-w-[100px] py-3 px-4 rounded-xl font-semibold transition-all relative ${
                  activeTab === tab.id 
                    ? 'text-white' 
                    : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'
                }`}
              >
                {activeTab === tab.id && (
                  <motion.div 
                    layoutId="lend-tab"
                    className="absolute inset-0 bg-white/10 rounded-xl shadow-[0_0_15px_rgba(255,255,255,0.05)] border border-white/10"
                    transition={{ type: 'spring', stiffness: 300, damping: 25 }}
                  />
                )}
                <span className="relative z-10">{tab.label}</span>
              </button>
            ))}
          </div>

          <div className="p-6 pt-0">
            {/* Context Info */}
            <div className="flex items-start gap-3 p-4 mb-6 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-indigo-200 text-sm leading-relaxed">
              <Info className="w-5 h-5 shrink-0 mt-0.5 text-indigo-400" />
              {activeTab === 'deposit' && "Supply ETH to earn interest and enable borrowing. ETH is used as collateral."}
              {activeTab === 'withdraw' && "Withdraw your supplied ETH. Ensure your Health Factor stays above 1.0 to avoid liquidation."}
              {activeTab === 'borrow' && "Borrow USDC against your ETH collateral. Keep an eye on your Health Factor."}
              {activeTab === 'repay' && "Repay your USDC debt to improve your Health Factor and free up collateral."}
            </div>

            {/* Input Field */}
            <div className="p-4 rounded-2xl bg-black/40 border border-white/10 focus-within:border-indigo-500/50 transition-colors mb-8 group">
              <div className="flex justify-between mb-3">
                <span className="text-sm font-medium text-gray-400 capitalize">Amount to {activeTab}</span>
                <span className="text-sm font-medium text-gray-400">
                  Balance: {
                    activeTab === 'withdraw' ? userCollateral.toFixed(4) : 
                    activeTab === 'repay' ? userDebt.toFixed(2) : 
                    '---'
                  }
                </span>
              </div>
              <div className="flex items-center gap-4">
                <input
                  type="number"
                  placeholder="0.00"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  className="w-full bg-transparent text-5xl text-white font-bold focus:outline-none placeholder:text-gray-700"
                />
                <div className="flex items-center gap-2 bg-[#13141a] px-4 py-2.5 rounded-xl border border-white/5 shrink-0">
                  <div className={`w-8 h-8 rounded-full flex items-center justify-center font-bold text-white shadow-lg ${
                    ['deposit', 'withdraw'].includes(activeTab) ? 'bg-[#627EEA]' : 'bg-[#2775CA]'
                  }`}>
                    {['deposit', 'withdraw'].includes(activeTab) ? 'E' : 'U'}
                  </div>
                  <span className="font-bold text-white text-xl">
                    {['deposit', 'withdraw'].includes(activeTab) ? 'ETH' : 'USDC'}
                  </span>
                </div>
              </div>
            </div>

            {/* Action Button */}
            {!isConnected ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold text-lg cursor-not-allowed border border-white/5">
                Connect Wallet
              </button>
            ) : (
              <TxButton
                onClick={handleAction}
                text={activeTab.charAt(0).toUpperCase() + activeTab.slice(1)}
                loadingText="Processing..."
                className="w-full h-14 text-lg"
              />
            )}
          </div>
        </motion.div>
      </div>
    </div>
  );
}
