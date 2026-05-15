import { useAccount, useBalance, useReadContract } from 'wagmi';
import { motion } from 'framer-motion';
import { Link } from 'react-router-dom';
import { ArrowLeftRight, Landmark, Vault, Vote, Activity, Wallet, ChevronRight } from 'lucide-react';
import { formatUnits } from 'viem';

import { addresses } from '../contracts/addresses';
import { pairAbi } from '../contracts/abis/pairAbi';
import { lendingPoolAbi } from '../contracts/abis/lendingPoolAbi';
import { yieldVaultAbi } from '../contracts/abis/yieldVaultAbi';
import { erc20Abi } from '../contracts/abis/erc20Abi';

export function Dashboard() {
  const { address, isConnected } = useAccount();

  // Read User Balances
  const { data: ethBalance } = useBalance({ address });
  const { data: govBalance } = useReadContract({
    address: addresses.GovernanceToken as `0x${string}`,
    abi: erc20Abi,
    functionName: 'balanceOf',
    args: address ? [address] : undefined,
    query: { enabled: !!address }
  });

  // Read Protocol Stats (TVL components)
  const { data: reserves } = useReadContract({
    address: addresses.SamplePair as `0x${string}`,
    abi: pairAbi,
    functionName: 'getReserves',
  });

  const { data: poolCollateral } = useReadContract({
    address: addresses.LendingPool as `0x${string}`,
    abi: lendingPoolAbi,
    functionName: 'totalCollateral',
  });

  const { data: vaultAssets } = useReadContract({
    address: addresses.YieldVault as `0x${string}`,
    abi: yieldVaultAbi,
    functionName: 'totalAssets',
  });

  // Calculate approximate TVL (very rough mockup for UI purposes)
  let tvl = 0;
  if (reserves) {
    const r0 = Number(formatUnits(reserves[0], 18));
    const r1 = Number(formatUnits(reserves[1], 18));
    tvl += (r0 + r1) * 2000; // Mock ETH price
  }
  if (poolCollateral) tvl += Number(formatUnits(poolCollateral, 18)) * 2000;
  if (vaultAssets) tvl += Number(formatUnits(vaultAssets, 6)); // USDC

  const containerVariants = {
    hidden: { opacity: 0 },
    show: {
      opacity: 1,
      transition: { staggerChildren: 0.1 }
    }
  };

  const itemVariants = {
    hidden: { opacity: 0, y: 20 },
    show: { opacity: 1, y: 0, transition: { type: "spring" as const, stiffness: 300, damping: 24 } }
  };

  return (
    <div className="flex flex-col gap-12 pb-20">
      {/* Hero Section */}
      <section className="relative pt-12 pb-8">
        <div className="absolute inset-0 bg-gradient-to-b from-indigo-500/10 to-transparent blur-3xl pointer-events-none rounded-full" />
        <motion.div 
          initial={{ opacity: 0, y: 30 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.8, ease: "easeOut" }}
          className="text-center relative z-10 space-y-6"
        >
          <div className="inline-flex items-center gap-2 px-3 py-1 rounded-full bg-indigo-500/10 border border-indigo-500/20 text-indigo-400 text-sm font-medium mb-4">
            <Activity size={16} />
            <span>Protocol Live on Arbitrum Sepolia</span>
          </div>
          <h1 className="text-5xl md:text-7xl font-bold tracking-tight">
            The Ultimate <br/>
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-400 via-violet-400 to-cyan-400">
              DeFi Super-App
            </span>
          </h1>
          <p className="text-xl text-gray-400 max-w-2xl mx-auto leading-relaxed">
            Swap, lend, borrow, and earn yield in one seamless premium experience. Fully decentralized, governed by you.
          </p>
        </motion.div>
      </section>

      {/* Protocol Stats */}
      <motion.section 
        variants={containerVariants}
        initial="hidden"
        animate="show"
        className="grid grid-cols-1 md:grid-cols-3 gap-6"
      >
        <motion.div variants={itemVariants} className="glass-card relative overflow-hidden group">
          <div className="absolute -right-10 -top-10 w-32 h-32 bg-indigo-500/20 rounded-full blur-2xl group-hover:bg-indigo-500/30 transition-colors" />
          <p className="text-gray-400 text-sm font-medium mb-2 uppercase tracking-wider">Total Value Locked</p>
          <div className="text-4xl font-bold text-white tracking-tight">
            ${tvl > 0 ? tvl.toLocaleString(undefined, { maximumFractionDigits: 0 }) : '---'}
          </div>
        </motion.div>
        
        <motion.div variants={itemVariants} className="glass-card relative overflow-hidden group">
          <div className="absolute -right-10 -top-10 w-32 h-32 bg-cyan-500/20 rounded-full blur-2xl group-hover:bg-cyan-500/30 transition-colors" />
          <p className="text-gray-400 text-sm font-medium mb-2 uppercase tracking-wider">24h Volume</p>
          <div className="text-4xl font-bold text-white tracking-tight">
            $24,592,100
          </div>
        </motion.div>

        <motion.div variants={itemVariants} className="glass-card relative overflow-hidden group">
          <div className="absolute -right-10 -top-10 w-32 h-32 bg-violet-500/20 rounded-full blur-2xl group-hover:bg-violet-500/30 transition-colors" />
          <p className="text-gray-400 text-sm font-medium mb-2 uppercase tracking-wider">Active Users</p>
          <div className="text-4xl font-bold text-white tracking-tight">
            12,408
          </div>
        </motion.div>
      </motion.section>

      {/* User Portfolio */}
      {isConnected && (
        <motion.section 
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.4 }}
          className="glass-card border-indigo-500/30 shadow-[0_0_30px_rgba(99,102,241,0.1)]"
        >
          <div className="flex items-center gap-3 mb-8">
            <div className="p-2 bg-indigo-500/20 rounded-xl text-indigo-400">
              <Wallet size={24} />
            </div>
            <h2 className="text-2xl font-bold text-white">Your Portfolio</h2>
          </div>
          
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
            <div className="p-6 rounded-2xl bg-black/40 border border-white/5 flex items-center justify-between hover:border-indigo-500/30 transition-colors">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-full bg-[#627EEA] flex items-center justify-center text-white font-bold shadow-lg">
                  E
                </div>
                <div>
                  <h3 className="text-white font-semibold text-lg">Ethereum</h3>
                  <p className="text-gray-400 text-sm">ETH</p>
                </div>
              </div>
              <div className="text-right">
                <p className="text-2xl font-bold text-white">
                  {ethBalance ? (Number(ethBalance.value) / 1e18).toFixed(4) : '0.0000'}
                </p>
                <p className="text-gray-400 text-sm">On Arbitrum Sepolia</p>
              </div>
            </div>

            <div className="p-6 rounded-2xl bg-black/40 border border-white/5 flex items-center justify-between hover:border-violet-500/30 transition-colors">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-full bg-violet-500 flex items-center justify-center text-white font-bold shadow-lg">
                  G
                </div>
                <div>
                  <h3 className="text-white font-semibold text-lg">Governance</h3>
                  <p className="text-gray-400 text-sm">GOV</p>
                </div>
              </div>
              <div className="text-right">
                <p className="text-2xl font-bold text-white">
                  {govBalance ? Number(formatUnits(govBalance as bigint, 18)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : '0.00'}
                </p>
                <p className="text-gray-400 text-sm">Voting Power</p>
              </div>
            </div>
          </div>
        </motion.section>
      )}

      {/* Quick Actions */}
      <section>
        <div className="flex items-center justify-between mb-6">
          <h2 className="text-2xl font-bold text-white">Explore DeFi</h2>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          <Link to="/swap" className="group p-6 rounded-3xl bg-white/5 border border-white/10 hover:bg-white/10 transition-all duration-300 hover:scale-[1.02] hover:shadow-[0_0_30px_rgba(255,255,255,0.05)]">
            <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-indigo-500/20 to-cyan-500/20 text-indigo-400 flex items-center justify-center mb-6 group-hover:scale-110 transition-transform">
              <ArrowLeftRight size={28} />
            </div>
            <h3 className="text-xl font-bold text-white mb-2 flex items-center justify-between">
              Swap Tokens
              <ChevronRight size={20} className="text-gray-500 group-hover:text-white transition-colors" />
            </h3>
            <p className="text-gray-400 text-sm leading-relaxed">Instant trades with deep liquidity and minimal slippage via our AMM.</p>
          </Link>

          <Link to="/lend" className="group p-6 rounded-3xl bg-white/5 border border-white/10 hover:bg-white/10 transition-all duration-300 hover:scale-[1.02] hover:shadow-[0_0_30px_rgba(255,255,255,0.05)]">
            <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-green-500/20 to-emerald-500/20 text-green-400 flex items-center justify-center mb-6 group-hover:scale-110 transition-transform">
              <Landmark size={28} />
            </div>
            <h3 className="text-xl font-bold text-white mb-2 flex items-center justify-between">
              Lend & Borrow
              <ChevronRight size={20} className="text-gray-500 group-hover:text-white transition-colors" />
            </h3>
            <p className="text-gray-400 text-sm leading-relaxed">Supply assets to earn interest, or borrow against your collateral.</p>
          </Link>

          <Link to="/vaults" className="group p-6 rounded-3xl bg-white/5 border border-white/10 hover:bg-white/10 transition-all duration-300 hover:scale-[1.02] hover:shadow-[0_0_30px_rgba(255,255,255,0.05)]">
            <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-yellow-500/20 to-orange-500/20 text-yellow-400 flex items-center justify-center mb-6 group-hover:scale-110 transition-transform">
              <Vault size={28} />
            </div>
            <h3 className="text-xl font-bold text-white mb-2 flex items-center justify-between">
              Yield Vaults
              <ChevronRight size={20} className="text-gray-500 group-hover:text-white transition-colors" />
            </h3>
            <p className="text-gray-400 text-sm leading-relaxed">Automated ERC4626 strategies to maximize your passive income.</p>
          </Link>

          <Link to="/governance" className="group p-6 rounded-3xl bg-white/5 border border-white/10 hover:bg-white/10 transition-all duration-300 hover:scale-[1.02] hover:shadow-[0_0_30px_rgba(255,255,255,0.05)]">
            <div className="w-14 h-14 rounded-2xl bg-gradient-to-br from-violet-500/20 to-fuchsia-500/20 text-violet-400 flex items-center justify-center mb-6 group-hover:scale-110 transition-transform">
              <Vote size={28} />
            </div>
            <h3 className="text-xl font-bold text-white mb-2 flex items-center justify-between">
              Governance
              <ChevronRight size={20} className="text-gray-500 group-hover:text-white transition-colors" />
            </h3>
            <p className="text-gray-400 text-sm leading-relaxed">Vote on protocol upgrades and shape the future of the SuperApp.</p>
          </Link>
        </div>
      </section>
    </div>
  );
}
