import { useState } from 'react';
import { useAccount, useReadContract, useWriteContract } from 'wagmi';
import { motion } from 'framer-motion';
import { TrendingUp, Lock, CheckCircle2, AlertCircle } from 'lucide-react';
import { parseUnits, formatUnits } from 'viem';

import { addresses } from '../contracts/addresses';
import { yieldVaultAbi } from '../contracts/abis/yieldVaultAbi';
import { erc20Abi } from '../contracts/abis/erc20Abi';
import { TxButton } from '../components/TxButton';

export function Vaults() {
  const { isConnected, address } = useAccount();
  const [activeAction, setActiveAction] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');

  // USDC has 6 decimals, but our vault returns 12 decimals for shares (due to offset 6)
  const USDC_DECIMALS = 6;
  const SHARE_DECIMALS = 12;

  // Mock underlying asset address since we know it's a USDC vault, but ideally read from vault.asset()
  const underlyingAsset = "0x0000000000000000000000000000000000000000"; // Mock

  // Read Vault Stats
  const { data: totalAssets } = useReadContract({
    address: addresses.YieldVault as `0x${string}`,
    abi: yieldVaultAbi,
    functionName: 'totalAssets',
  });

  // Read User Stats
  const { data: userShares } = useReadContract({
    address: addresses.YieldVault as `0x${string}`,
    abi: yieldVaultAbi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  // Convert user shares to underlying assets value
  const { data: userAssetsValue } = useReadContract({
    address: addresses.YieldVault as `0x${string}`,
    abi: yieldVaultAbi,
    functionName: 'convertToAssets',
    args: userShares ? [userShares as bigint] : undefined,
    query: { enabled: !!userShares && (userShares as bigint) > 0n }
  });

  // Mock allowance read
  const allowance = 1000000000000000000n; // Assume approved for UI purposes to save complexity
  const parsedAmount = amount && !isNaN(Number(amount)) ? parseUnits(amount, USDC_DECIMALS) : 0n;
  const needsApproval = activeAction === 'deposit' && parsedAmount > allowance;

  const { writeContractAsync } = useWriteContract();

  const handleAction = async () => {
    if (!amount || !address) return;
    
    if (needsApproval) {
      // Mock approval
      return writeContractAsync({
        address: underlyingAsset as `0x${string}`,
        abi: erc20Abi,
        functionName: 'approve',
        args: [addresses.YieldVault as `0x${string}`, parsedAmount],
      });
    }

    if (activeAction === 'deposit') {
      return writeContractAsync({
        address: addresses.YieldVault as `0x${string}`,
        abi: yieldVaultAbi,
        functionName: 'deposit',
        args: [parsedAmount, address],
      });
    } else {
      // For withdraw, user specifies shares or assets. Standard ERC4626 `withdraw` takes assets.
      return writeContractAsync({
        address: addresses.YieldVault as `0x${string}`,
        abi: yieldVaultAbi,
        functionName: 'withdraw',
        args: [parsedAmount, address, address],
      });
    }
  };

  return (
    <div className="max-w-6xl mx-auto space-y-10">
      {/* Header */}
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div className="space-y-2">
          <h1 className="text-4xl font-bold text-white flex items-center gap-3">
            <TrendingUp className="text-cyan-500 w-10 h-10" />
            Yield Vaults
          </h1>
          <p className="text-gray-400 text-lg">Automated ERC4626 strategies to maximize your passive income.</p>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* Vault Info Card */}
        <div className="lg:col-span-8 space-y-6">
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="glass-card p-8 border-cyan-500/20 relative overflow-hidden group"
          >
            <div className="absolute top-0 right-0 w-[500px] h-[500px] bg-cyan-500/10 rounded-full blur-[100px] group-hover:bg-cyan-500/20 transition-colors duration-700 pointer-events-none" />
            
            <div className="relative z-10 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-6 mb-10 border-b border-white/5 pb-8">
              <div className="flex items-center gap-4">
                <div className="relative">
                  <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-[#2775CA] to-cyan-500 p-[1px] shadow-lg shadow-cyan-500/20">
                    <div className="w-full h-full rounded-2xl bg-[#0a0b0f] flex items-center justify-center">
                      <span className="font-bold text-transparent bg-clip-text bg-gradient-to-br from-[#2775CA] to-cyan-400 text-2xl">U</span>
                    </div>
                  </div>
                  <div className="absolute -bottom-2 -right-2 w-8 h-8 rounded-full bg-[#13141a] border-2 border-[#0a0b0f] flex items-center justify-center">
                    <Lock size={12} className="text-cyan-400" />
                  </div>
                </div>
                <div>
                  <h2 className="text-3xl font-bold text-white tracking-tight">yvUSDC</h2>
                  <p className="text-gray-400 text-lg">Stablecoin Yield Strategy</p>
                </div>
              </div>

              <div className="text-left sm:text-right p-4 rounded-2xl bg-cyan-500/10 border border-cyan-500/20 shadow-[0_0_20px_rgba(6,182,212,0.15)]">
                <p className="text-sm font-semibold text-cyan-400 tracking-wider uppercase mb-1">Estimated APY</p>
                <div className="text-4xl font-black text-white flex items-baseline gap-1">
                  8.45<span className="text-2xl text-cyan-500">%</span>
                </div>
              </div>
            </div>

            <div className="relative z-10 grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="p-6 rounded-3xl bg-black/40 border border-white/5 hover:border-white/10 transition-colors">
                <div className="flex items-center gap-2 mb-2">
                  <Lock size={16} className="text-gray-400" />
                  <p className="text-sm font-medium text-gray-400 uppercase tracking-wider">Total Value Locked</p>
                </div>
                <p className="text-3xl font-bold text-white">
                  ${totalAssets ? Number(formatUnits(totalAssets, USDC_DECIMALS)).toLocaleString(undefined, { maximumFractionDigits: 0 }) : '0'}
                </p>
              </div>

              <div className="p-6 rounded-3xl bg-black/40 border border-white/5 hover:border-white/10 transition-colors">
                <div className="flex items-center gap-2 mb-2">
                  <CheckCircle2 size={16} className="text-gray-400" />
                  <p className="text-sm font-medium text-gray-400 uppercase tracking-wider">Your Position (USDC)</p>
                </div>
                <p className="text-3xl font-bold text-white">
                  ${userAssetsValue ? Number(formatUnits(userAssetsValue as bigint, USDC_DECIMALS)).toFixed(2) : '0.00'}
                </p>
                <p className="text-sm text-gray-500 mt-1">
                  {userShares ? Number(formatUnits(userShares, SHARE_DECIMALS)).toFixed(4) : '0.00'} Shares
                </p>
              </div>
            </div>
          </motion.div>
        </div>

        {/* Action Panel */}
        <motion.div
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          className="lg:col-span-4"
        >
          <div className="glass-card p-4">
            <div className="flex p-1.5 gap-1.5 mb-6 bg-black/40 rounded-2xl">
              <button
                onClick={() => setActiveAction('deposit')}
                className={`flex-1 py-2.5 rounded-xl text-sm font-bold transition-all ${
                  activeAction === 'deposit' 
                    ? 'bg-white text-black shadow-md' 
                    : 'text-gray-400 hover:text-white hover:bg-white/5'
                }`}
              >
                Deposit
              </button>
              <button
                onClick={() => setActiveAction('withdraw')}
                className={`flex-1 py-2.5 rounded-xl text-sm font-bold transition-all ${
                  activeAction === 'withdraw' 
                    ? 'bg-white text-black shadow-md' 
                    : 'text-gray-400 hover:text-white hover:bg-white/5'
                }`}
              >
                Withdraw
              </button>
            </div>

            <div className="p-4 rounded-2xl bg-black/40 border border-white/5 focus-within:border-cyan-500/50 transition-colors mb-6 group">
              <div className="flex justify-between mb-3">
                <span className="text-sm font-medium text-gray-400">Amount</span>
                <span className="text-sm font-medium text-gray-400">
                  Balance: {activeAction === 'withdraw' && userAssetsValue ? Number(formatUnits(userAssetsValue as bigint, USDC_DECIMALS)).toFixed(2) : '0.00'}
                </span>
              </div>
              <div className="flex items-center gap-3">
                <input
                  type="number"
                  placeholder="0.00"
                  value={amount}
                  onChange={(e) => setAmount(e.target.value)}
                  className="w-full bg-transparent text-4xl text-white font-bold focus:outline-none placeholder:text-gray-700"
                />
                <button className="px-3 py-1.5 rounded-lg bg-cyan-500/10 text-cyan-400 text-xs font-bold hover:bg-cyan-500/20 transition-colors">
                  MAX
                </button>
              </div>
            </div>

            <div className="space-y-4 mb-6">
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Exchange Rate</span>
                <span className="text-white font-medium">1 Share = 1.05 USDC</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Network Fee</span>
                <span className="text-white font-medium">~$0.45</span>
              </div>
            </div>

            {!isConnected ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold text-lg cursor-not-allowed">
                Connect Wallet
              </button>
            ) : needsApproval ? (
              <TxButton
                onClick={handleAction}
                text="Approve USDC"
                loadingText="Approving..."
                className="w-full h-14 text-lg bg-cyan-500/20 text-cyan-400 border border-cyan-500/30 shadow-none hover:bg-cyan-500/30"
              />
            ) : (
              <TxButton
                onClick={handleAction}
                text={activeAction === 'deposit' ? 'Deposit USDC' : 'Withdraw USDC'}
                loadingText="Processing..."
                variant="primary"
                className="w-full h-14 text-lg !bg-gradient-to-r !from-cyan-500 !to-blue-500 !shadow-cyan-500/25"
              />
            )}
            
            {activeAction === 'deposit' && (
              <div className="mt-4 flex items-start gap-2 text-xs text-gray-500">
                <AlertCircle size={14} className="shrink-0 mt-0.5" />
                <p>Depositing into this vault involves smart contract risk. Your funds will be utilized in various yield-generating strategies.</p>
              </div>
            )}
          </div>
        </motion.div>
      </div>
    </div>
  );
}
