import { useState, useMemo } from 'react';
import { useAccount, useReadContract, useReadContracts } from 'wagmi';
import { motion } from 'framer-motion';
import { TrendingUp, Lock, CheckCircle2, AlertCircle } from 'lucide-react';
import { parseUnits, formatUnits, erc20Abi as viemErc20Abi } from 'viem';

import { addresses } from '../contracts/addresses';
import { yieldVaultAbi } from '../contracts/abis/yieldVaultAbi';
import { lendingPoolAbi } from '../contracts/abis/lendingPoolAbi';
import { TxButton, type TxRequest } from '../components/TxButton';

const VAULT = addresses.YieldVault as `0x${string}`;
const POOL = addresses.LendingPool as `0x${string}`;
const BPS_DENOMINATOR = 10_000;
const WAD = 10n ** 18n;

export function Vaults() {
  const { isConnected, address } = useAccount();
  const [action, setAction] = useState<'deposit' | 'withdraw'>('deposit');
  const [amount, setAmount] = useState('');

  // --- Vault state ---------------------------------------------------------
  const { data: assetAddr } = useReadContract({ address: VAULT, abi: yieldVaultAbi, functionName: 'asset' });
  const { data: shareDecimals } = useReadContract({ address: VAULT, abi: yieldVaultAbi, functionName: 'decimals' });
  const { data: totalAssets, refetch: refetchTA } = useReadContract({ address: VAULT, abi: yieldVaultAbi, functionName: 'totalAssets' });
  const { data: userShares, refetch: refetchShares } = useReadContract({
    address: VAULT, abi: yieldVaultAbi, functionName: 'balanceOf', args: address ? [address] : undefined, query: { enabled: !!address },
  });
  const { data: userAssets, refetch: refetchUA } = useReadContract({
    address: VAULT, abi: yieldVaultAbi, functionName: 'maxWithdraw', args: address ? [address] : undefined, query: { enabled: !!address },
  });

  // --- Asset metadata + user allowance/balance -----------------------------
  const { data: assetMeta } = useReadContracts({
    contracts: assetAddr
      ? [
          { address: assetAddr, abi: viemErc20Abi, functionName: 'symbol' },
          { address: assetAddr, abi: viemErc20Abi, functionName: 'decimals' },
        ]
      : [],
    query: { enabled: !!assetAddr },
  });
  const assetSym = (assetMeta?.[0]?.result as string) ?? 'USDC';
  const assetDec = (assetMeta?.[1]?.result as number) ?? 6;

  const { data: userAssetBal, refetch: refetchBal } = useReadContract({
    address: assetAddr, abi: viemErc20Abi, functionName: 'balanceOf', args: address ? [address] : undefined, query: { enabled: !!assetAddr && !!address },
  });
  const { data: allowance, refetch: refetchAllowance } = useReadContract({
    address: assetAddr, abi: viemErc20Abi, functionName: 'allowance', args: address ? [address, VAULT] : undefined, query: { enabled: !!assetAddr && !!address },
  });

  // --- Interest-rate model inputs (for APY) --------------------------------
  const { data: rateData } = useReadContracts({
    contracts: [
      { address: POOL, abi: lendingPoolAbi, functionName: 'baseRate' },
      { address: POOL, abi: lendingPoolAbi, functionName: 'slope1' },
      { address: POOL, abi: lendingPoolAbi, functionName: 'totalDebt' },
    ],
  });
  const { data: poolLiquidity } = useReadContract({
    address: assetAddr, abi: viemErc20Abi, functionName: 'balanceOf', args: [POOL], query: { enabled: !!assetAddr },
  });

  // APY derived from the on-chain borrow rate:
  //   borrowRateBPS = baseRate + utilization * slope1   (utilization in [0,1])
  //   supplyAPR     = borrowAPR * utilization           (suppliers earn borrower interest)
  //   APY           = (1 + supplyAPR/365)^365 - 1        (daily compounding)
  const { apy, borrowApr, utilization } = useMemo(() => {
    const baseRate = (rateData?.[0]?.result as bigint) ?? 0n;
    const slope1 = (rateData?.[1]?.result as bigint) ?? 0n;
    const totalDebt = (rateData?.[2]?.result as bigint) ?? 0n;
    const available = (poolLiquidity as bigint) ?? 0n;
    const denom = available + totalDebt;
    const util = denom > 0n ? Number((totalDebt * WAD) / denom) / 1e18 : 0;
    const borrowRateBps = Number(baseRate) + util * Number(slope1);
    const borrowAprFrac = borrowRateBps / BPS_DENOMINATOR;
    const supplyApr = borrowAprFrac * util;
    const apyPct = (Math.pow(1 + supplyApr / 365, 365) - 1) * 100;
    return { apy: apyPct, borrowApr: borrowAprFrac * 100, utilization: util * 100 };
  }, [rateData, poolLiquidity]);

  // --- Build requests ------------------------------------------------------
  const parsedAmount = useMemo(() => {
    try { return amount && Number(amount) > 0 ? parseUnits(amount, assetDec) : 0n; } catch { return 0n; }
  }, [amount, assetDec]);

  const needsApproval = action === 'deposit' && parsedAmount > 0n && (allowance === undefined || (allowance as bigint) < parsedAmount);

  const approveReq: TxRequest | undefined = assetAddr && parsedAmount > 0n
    ? { address: assetAddr, abi: viemErc20Abi as unknown as TxRequest['abi'], functionName: 'approve', args: [VAULT, parsedAmount] } : undefined;
  const depositReq: TxRequest | undefined = address && parsedAmount > 0n
    ? { address: VAULT, abi: yieldVaultAbi as unknown as TxRequest['abi'], functionName: 'deposit', args: [parsedAmount, address] } : undefined;
  const withdrawReq: TxRequest | undefined = address && parsedAmount > 0n
    ? { address: VAULT, abi: yieldVaultAbi as unknown as TxRequest['abi'], functionName: 'withdraw', args: [parsedAmount, address, address] } : undefined;

  const refetchAll = () => { refetchTA(); refetchShares(); refetchUA(); refetchBal(); refetchAllowance(); };

  const displayBalance = action === 'deposit'
    ? (userAssetBal !== undefined ? Number(formatUnits(userAssetBal as bigint, assetDec)) : 0)
    : (userAssets !== undefined ? Number(formatUnits(userAssets as bigint, assetDec)) : 0);

  return (
    <div className="max-w-6xl mx-auto space-y-10">
      <div className="space-y-2">
        <h1 className="text-4xl font-bold text-white flex items-center gap-3">
          <TrendingUp className="text-cyan-500 w-10 h-10" />
          Yield Vault
        </h1>
        <p className="text-gray-400 text-lg">ERC-4626 vault that supplies {assetSym} to the lending market to earn the supply rate.</p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        <div className="lg:col-span-8 space-y-6">
          <motion.div initial={{ opacity: 0, y: 20 }} animate={{ opacity: 1, y: 0 }} className="glass-card p-8 border-cyan-500/20 relative overflow-hidden group">
            <div className="absolute top-0 right-0 w-[500px] h-[500px] bg-cyan-500/10 rounded-full blur-[100px] pointer-events-none" />

            <div className="relative z-10 flex flex-col sm:flex-row justify-between items-start sm:items-center gap-6 mb-10 border-b border-white/5 pb-8">
              <div className="flex items-center gap-4">
                <div className="w-16 h-16 rounded-2xl bg-gradient-to-br from-[#2775CA] to-cyan-500 p-[1px] shadow-lg shadow-cyan-500/20">
                  <div className="w-full h-full rounded-2xl bg-[#0a0b0f] flex items-center justify-center">
                    <span className="font-bold text-cyan-400 text-2xl">{assetSym[0]}</span>
                  </div>
                </div>
                <div>
                  <h2 className="text-3xl font-bold text-white tracking-tight">yv{assetSym}</h2>
                  <p className="text-gray-400 text-lg">Lending Supply Strategy</p>
                </div>
              </div>

              <div className="text-left sm:text-right p-4 rounded-2xl bg-cyan-500/10 border border-cyan-500/20 shadow-[0_0_20px_rgba(6,182,212,0.15)]">
                <p className="text-sm font-semibold text-cyan-400 tracking-wider uppercase mb-1">Estimated APY</p>
                <div className="text-4xl font-black text-white flex items-baseline gap-1">
                  {apy.toFixed(2)}<span className="text-2xl text-cyan-500">%</span>
                </div>
              </div>
            </div>

            <div className="relative z-10 grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="p-6 rounded-3xl bg-black/40 border border-white/5">
                <div className="flex items-center gap-2 mb-2">
                  <Lock size={16} className="text-gray-400" />
                  <p className="text-sm font-medium text-gray-400 uppercase tracking-wider">Total Value Locked</p>
                </div>
                <p className="text-3xl font-bold text-white">
                  {totalAssets ? Number(formatUnits(totalAssets as bigint, assetDec)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : '0'} {assetSym}
                </p>
              </div>
              <div className="p-6 rounded-3xl bg-black/40 border border-white/5">
                <div className="flex items-center gap-2 mb-2">
                  <CheckCircle2 size={16} className="text-gray-400" />
                  <p className="text-sm font-medium text-gray-400 uppercase tracking-wider">Your Position</p>
                </div>
                <p className="text-3xl font-bold text-white">
                  {userAssets ? Number(formatUnits(userAssets as bigint, assetDec)).toFixed(2) : '0.00'} {assetSym}
                </p>
                <p className="text-sm text-gray-500 mt-1">
                  {userShares ? Number(formatUnits(userShares as bigint, (shareDecimals as number) ?? 18)).toFixed(4) : '0.00'} shares
                </p>
              </div>
            </div>

            {/* Rate breakdown — shows the APY is grounded in on-chain data */}
            <div className="relative z-10 mt-4 grid grid-cols-2 gap-4 text-sm">
              <div className="flex justify-between p-4 rounded-2xl bg-black/40 border border-white/5">
                <span className="text-gray-400">Borrow APR</span>
                <span className="text-white font-medium">{borrowApr.toFixed(2)}%</span>
              </div>
              <div className="flex justify-between p-4 rounded-2xl bg-black/40 border border-white/5">
                <span className="text-gray-400">Utilization</span>
                <span className="text-white font-medium">{utilization.toFixed(1)}%</span>
              </div>
            </div>
          </motion.div>
        </div>

        {/* Action panel */}
        <motion.div initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} className="lg:col-span-4">
          <div className="glass-card p-4">
            <div className="flex p-1.5 gap-1.5 mb-6 bg-black/40 rounded-2xl">
              {(['deposit', 'withdraw'] as const).map((a) => (
                <button
                  key={a}
                  onClick={() => { setAction(a); setAmount(''); }}
                  className={`flex-1 py-2.5 rounded-xl text-sm font-bold capitalize transition-all ${
                    action === a ? 'bg-white text-black shadow-md' : 'text-gray-400 hover:text-white hover:bg-white/5'
                  }`}
                >
                  {a}
                </button>
              ))}
            </div>

            <div className="p-4 rounded-2xl bg-black/40 border border-white/5 focus-within:border-cyan-500/50 transition-colors mb-6">
              <div className="flex justify-between mb-3 text-sm text-gray-400">
                <span>Amount</span>
                <span>
                  Balance: {displayBalance.toFixed(2)}
                  {displayBalance > 0 && (
                    <button onClick={() => setAmount(String(displayBalance))} className="ml-2 text-cyan-400 hover:text-cyan-300 font-semibold">MAX</button>
                  )}
                </span>
              </div>
              <input
                type="number" placeholder="0.00" value={amount} onChange={(e) => setAmount(e.target.value)}
                className="w-full bg-transparent text-4xl text-white font-bold focus:outline-none placeholder:text-gray-700"
              />
            </div>

            {!isConnected ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold cursor-not-allowed">Connect wallet</button>
            ) : parsedAmount === 0n ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold cursor-not-allowed">Enter an amount</button>
            ) : needsApproval ? (
              <TxButton request={approveReq} enabled={!!approveReq} text={`Approve ${assetSym}`} confirmingText="Approving…"
                className="!bg-cyan-500/20 !text-cyan-400 !shadow-none" onSuccess={() => { refetchAllowance(); }} />
            ) : action === 'deposit' ? (
              <TxButton request={depositReq} enabled={!!depositReq} text={`Deposit ${assetSym}`} confirmingText="Depositing…"
                className="!bg-gradient-to-r !from-cyan-500 !to-blue-500 !shadow-cyan-500/25"
                onSuccess={() => { setAmount(''); refetchAll(); }} />
            ) : (
              <TxButton request={withdrawReq} enabled={!!withdrawReq} text={`Withdraw ${assetSym}`} confirmingText="Withdrawing…"
                className="!bg-gradient-to-r !from-cyan-500 !to-blue-500 !shadow-cyan-500/25"
                onSuccess={() => { setAmount(''); refetchAll(); }} />
            )}

            {action === 'deposit' && (
              <div className="mt-4 flex items-start gap-2 text-xs text-gray-500">
                <AlertCircle size={14} className="shrink-0 mt-0.5" />
                <p>Deposits are supplied to the lending pool. Yield accrues as borrowers pay interest; APY varies with utilization.</p>
              </div>
            )}
          </div>
        </motion.div>
      </div>
    </div>
  );
}
