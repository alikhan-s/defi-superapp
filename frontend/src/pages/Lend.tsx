import { useState, useMemo } from 'react';
import { useAccount, useBalance, useReadContract } from 'wagmi';
import { motion } from 'framer-motion';
import { Shield, ArrowUpCircle, ArrowDownCircle, Info } from 'lucide-react';
import { parseUnits, formatUnits, zeroAddress, erc20Abi as viemErc20Abi } from 'viem';

import { addresses } from '../contracts/addresses';
import { lendingPoolAbi } from '../contracts/abis/lendingPoolAbi';
import { TxButton, type TxRequest } from '../components/TxButton';

const POOL = addresses.LendingPool as `0x${string}`;
type TabType = 'deposit' | 'withdraw' | 'borrow' | 'repay';
const TABS: { id: TabType; label: string }[] = [
  { id: 'deposit', label: 'Deposit' },
  { id: 'withdraw', label: 'Withdraw' },
  { id: 'borrow', label: 'Borrow' },
  { id: 'repay', label: 'Repay' },
];

export function Lend() {
  const { isConnected, address } = useAccount();
  const [tab, setTab] = useState<TabType>('deposit');
  const [amount, setAmount] = useState('');

  // --- Market config -------------------------------------------------------
  const { data: collateralAsset } = useReadContract({ address: POOL, abi: lendingPoolAbi, functionName: 'collateralAsset' });
  const { data: debtAsset } = useReadContract({ address: POOL, abi: lendingPoolAbi, functionName: 'debtAsset' });
  const { data: collDecimals } = useReadContract({ address: POOL, abi: lendingPoolAbi, functionName: 'collateralDecimals' });
  const { data: debtDecimals } = useReadContract({ address: POOL, abi: lendingPoolAbi, functionName: 'debtDecimals' });

  const isNativeCollateral = !collateralAsset || collateralAsset === zeroAddress;
  const collDec = (collDecimals as number) ?? 18;
  const debtDec = (debtDecimals as number) ?? 6;

  const { data: collSymbol } = useReadContract({
    address: collateralAsset, abi: viemErc20Abi, functionName: 'symbol', query: { enabled: !isNativeCollateral && !!collateralAsset },
  });
  const { data: debtSymbol } = useReadContract({ address: debtAsset, abi: viemErc20Abi, functionName: 'symbol', query: { enabled: !!debtAsset } });
  const collSym = isNativeCollateral ? 'ETH' : ((collSymbol as string) ?? 'COLL');
  const debtSym = (debtSymbol as string) ?? 'USDC';

  // --- Protocol + user state ----------------------------------------------
  const { data: totalCollateral } = useReadContract({ address: POOL, abi: lendingPoolAbi, functionName: 'totalCollateral' });
  const { data: totalDebt, refetch: refetchTotalDebt } = useReadContract({ address: POOL, abi: lendingPoolAbi, functionName: 'totalDebt' });
  const { data: totalDebtShares } = useReadContract({ address: POOL, abi: lendingPoolAbi, functionName: 'totalDebtShares' });

  const { data: position, refetch: refetchPosition } = useReadContract({
    address: POOL, abi: lendingPoolAbi, functionName: 'positions', args: address ? [address] : undefined, query: { enabled: !!address },
  });
  const { data: healthFactorRaw, refetch: refetchHF } = useReadContract({
    address: POOL, abi: lendingPoolAbi, functionName: 'healthFactor', args: address ? [address] : undefined, query: { enabled: !!address },
  });

  // --- Balances + allowances ----------------------------------------------
  const { data: nativeBal } = useBalance({ address, query: { enabled: isNativeCollateral && !!address } });
  const { data: collTokenBal, refetch: refetchCollBal } = useReadContract({
    address: collateralAsset, abi: viemErc20Abi, functionName: 'balanceOf', args: address ? [address] : undefined,
    query: { enabled: !isNativeCollateral && !!collateralAsset && !!address },
  });
  const { data: debtTokenBal, refetch: refetchDebtBal } = useReadContract({
    address: debtAsset, abi: viemErc20Abi, functionName: 'balanceOf', args: address ? [address] : undefined, query: { enabled: !!debtAsset && !!address },
  });
  const { data: collAllowance, refetch: refetchCollAllow } = useReadContract({
    address: collateralAsset, abi: viemErc20Abi, functionName: 'allowance', args: address ? [address, POOL] : undefined,
    query: { enabled: !isNativeCollateral && !!collateralAsset && !!address },
  });
  const { data: debtAllowance, refetch: refetchDebtAllow } = useReadContract({
    address: debtAsset, abi: viemErc20Abi, functionName: 'allowance', args: address ? [address, POOL] : undefined,
    query: { enabled: !!debtAsset && !!address },
  });

  // --- Derived position figures -------------------------------------------
  const userCollateral = position ? Number(formatUnits(position[0] as bigint, collDec)) : 0;
  const userDebtRaw = useMemo(() => {
    if (!position || !totalDebt || !totalDebtShares || (totalDebtShares as bigint) === 0n) return 0n;
    return ((position[1] as bigint) * (totalDebt as bigint)) / (totalDebtShares as bigint);
  }, [position, totalDebt, totalDebtShares]);
  const userDebt = Number(formatUnits(userDebtRaw, debtDec));

  // Health factor: contract returns type(uint256).max when there's no debt.
  const hfNum = healthFactorRaw ? Number(formatUnits(healthFactorRaw as bigint, 18)) : 0;
  const isInfinite = hfNum > 1e6 || userDebtRaw === 0n;
  const healthFactor = isInfinite ? '∞' : hfNum.toFixed(2);

  let hfColor = 'text-gray-400';
  let hfRing = 'border-gray-500/30';
  if (userCollateral > 0 || userDebtRaw > 0n) {
    if (isInfinite || hfNum > 2) { hfColor = 'text-green-400'; hfRing = 'border-green-500 shadow-[0_0_15px_rgba(34,197,94,0.4)]'; }
    else if (hfNum >= 1.5) { hfColor = 'text-yellow-400'; hfRing = 'border-yellow-400 shadow-[0_0_15px_rgba(250,204,21,0.4)]'; }
    else { hfColor = 'text-red-400'; hfRing = 'border-red-500 shadow-[0_0_15px_rgba(239,68,68,0.4)]'; }
  }

  // --- Build requests ------------------------------------------------------
  const tabDec = tab === 'deposit' || tab === 'withdraw' ? collDec : debtDec;
  const parsedAmount = useMemo(() => { try { return amount && Number(amount) > 0 ? parseUnits(amount, tabDec) : 0n; } catch { return 0n; } }, [amount, tabDec]);

  // Deposit (ERC20 collateral) needs approval; repay always needs debt approval.
  const needsCollApproval = tab === 'deposit' && !isNativeCollateral && parsedAmount > 0n && (collAllowance === undefined || (collAllowance as bigint) < parsedAmount);
  const needsDebtApproval = tab === 'repay' && parsedAmount > 0n && (debtAllowance === undefined || (debtAllowance as bigint) < parsedAmount);

  const refetchAll = () => { refetchPosition(); refetchHF(); refetchTotalDebt(); refetchCollBal(); refetchDebtBal(); refetchCollAllow(); refetchDebtAllow(); };

  const request: TxRequest | undefined = useMemo(() => {
    if (!address || parsedAmount === 0n) return undefined;
    const poolAbi = lendingPoolAbi as unknown as TxRequest['abi'];
    if (needsCollApproval) return { address: collateralAsset!, abi: viemErc20Abi as unknown as TxRequest['abi'], functionName: 'approve', args: [POOL, parsedAmount] };
    if (needsDebtApproval) return { address: debtAsset!, abi: viemErc20Abi as unknown as TxRequest['abi'], functionName: 'approve', args: [POOL, parsedAmount] };
    switch (tab) {
      case 'deposit':
        return { address: POOL, abi: poolAbi, functionName: 'depositCollateral', args: [parsedAmount], value: isNativeCollateral ? parsedAmount : undefined };
      case 'withdraw':
        return { address: POOL, abi: poolAbi, functionName: 'withdrawCollateral', args: [parsedAmount] };
      case 'borrow':
        return { address: POOL, abi: poolAbi, functionName: 'borrow', args: [parsedAmount] };
      case 'repay':
        return { address: POOL, abi: poolAbi, functionName: 'repay', args: [parsedAmount] };
    }
  }, [address, parsedAmount, tab, needsCollApproval, needsDebtApproval, isNativeCollateral, collateralAsset, debtAsset]);

  const buttonText = needsCollApproval ? `Approve ${collSym}` : needsDebtApproval ? `Approve ${debtSym}` : TABS.find((t) => t.id === tab)!.label;

  const tabBalance = useMemo(() => {
    if (tab === 'deposit') return isNativeCollateral ? (nativeBal ? Number(formatUnits(nativeBal.value, 18)) : 0) : (collTokenBal !== undefined ? Number(formatUnits(collTokenBal as bigint, collDec)) : 0);
    if (tab === 'withdraw') return userCollateral;
    if (tab === 'repay') return Math.min(userDebt, debtTokenBal !== undefined ? Number(formatUnits(debtTokenBal as bigint, debtDec)) : userDebt);
    return debtTokenBal !== undefined ? Number(formatUnits(debtTokenBal as bigint, debtDec)) : 0; // borrow: show wallet debt-token balance
  }, [tab, isNativeCollateral, nativeBal, collTokenBal, collDec, userCollateral, userDebt, debtTokenBal, debtDec]);

  return (
    <div className="max-w-6xl mx-auto space-y-10">
      <div className="flex flex-col md:flex-row md:items-end justify-between gap-6">
        <div className="space-y-2">
          <h1 className="text-4xl font-bold text-white flex items-center gap-3">
            <Shield className="text-indigo-500 w-10 h-10" />
            Lending Market
          </h1>
          <p className="text-gray-400 text-lg">Supply {collSym} collateral, borrow {debtSym}, and manage your health factor.</p>
        </div>

        <div className="flex gap-4">
          <div className="p-4 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-md">
            <p className="text-sm text-gray-400 mb-1">Total Collateral</p>
            <p className="text-xl font-bold text-white">
              {totalCollateral ? Number(formatUnits(totalCollateral as bigint, collDec)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : '0'} <span className="text-sm text-indigo-400">{collSym}</span>
            </p>
          </div>
          <div className="p-4 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-md">
            <p className="text-sm text-gray-400 mb-1">Total Borrowed</p>
            <p className="text-xl font-bold text-white">
              {totalDebt ? Number(formatUnits(totalDebt as bigint, debtDec)).toLocaleString(undefined, { maximumFractionDigits: 2 }) : '0'} <span className="text-sm text-cyan-400">{debtSym}</span>
            </p>
          </div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-8">
        {/* Position panel */}
        <motion.div initial={{ opacity: 0, x: -20 }} animate={{ opacity: 1, x: 0 }} className="lg:col-span-4 space-y-6">
          <div className="glass-card flex flex-col items-center p-8 relative overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-br from-indigo-500/10 to-cyan-500/10 blur-xl z-0" />
            <h2 className="text-xl font-semibold text-white mb-8 relative z-10 w-full text-left">Your Position</h2>

            <div className="relative z-10 flex flex-col items-center justify-center mb-8">
              <div className={`w-40 h-40 rounded-full border-[6px] ${hfRing} flex flex-col items-center justify-center bg-[#0a0b0f]/80 backdrop-blur-sm transition-all duration-500`}>
                <span className="text-sm text-gray-400 mb-1 font-medium tracking-wide">HEALTH FACTOR</span>
                <span className={`text-4xl font-bold ${hfColor}`}>{isConnected ? healthFactor : '-'}</span>
              </div>
            </div>

            <div className="w-full space-y-4 relative z-10">
              <div className="flex justify-between items-center p-4 rounded-xl bg-black/40 border border-white/5">
                <div className="flex items-center gap-2"><ArrowUpCircle className="text-indigo-400 w-5 h-5" /><span className="text-gray-300">Supplied</span></div>
                <span className="text-white font-bold">{userCollateral.toFixed(4)} {collSym}</span>
              </div>
              <div className="flex justify-between items-center p-4 rounded-xl bg-black/40 border border-white/5">
                <div className="flex items-center gap-2"><ArrowDownCircle className="text-cyan-400 w-5 h-5" /><span className="text-gray-300">Borrowed</span></div>
                <span className="text-white font-bold">{userDebt.toFixed(2)} {debtSym}</span>
              </div>
            </div>
          </div>
        </motion.div>

        {/* Action panel */}
        <motion.div initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} className="lg:col-span-8 glass-card p-2">
          <div className="flex p-2 gap-2 mb-6 bg-black/20 rounded-2xl overflow-x-auto no-scrollbar">
            {TABS.map((t) => (
              <button
                key={t.id}
                onClick={() => { setTab(t.id); setAmount(''); }}
                className={`flex-1 min-w-[100px] py-3 px-4 rounded-xl font-semibold transition-all relative ${tab === t.id ? 'text-white' : 'text-gray-500 hover:text-gray-300 hover:bg-white/5'}`}
              >
                {tab === t.id && (
                  <motion.div layoutId="lend-tab" className="absolute inset-0 bg-white/10 rounded-xl shadow-[0_0_15px_rgba(255,255,255,0.05)] border border-white/10" transition={{ type: 'spring', stiffness: 300, damping: 25 }} />
                )}
                <span className="relative z-10">{t.label}</span>
              </button>
            ))}
          </div>

          <div className="p-6 pt-0">
            <div className="flex items-start gap-3 p-4 mb-6 rounded-xl bg-indigo-500/10 border border-indigo-500/20 text-indigo-200 text-sm leading-relaxed">
              <Info className="w-5 h-5 shrink-0 mt-0.5 text-indigo-400" />
              {tab === 'deposit' && `Supply ${collSym} as collateral to enable borrowing.`}
              {tab === 'withdraw' && `Withdraw collateral. Your health factor must stay above 1.0.`}
              {tab === 'borrow' && `Borrow ${debtSym} against your collateral. Watch your health factor.`}
              {tab === 'repay' && `Repay ${debtSym} debt to improve your health factor.`}
            </div>

            <div className="p-4 rounded-2xl bg-black/40 border border-white/10 focus-within:border-indigo-500/50 transition-colors mb-8">
              <div className="flex justify-between mb-3 text-sm text-gray-400">
                <span className="capitalize">Amount to {tab}</span>
                <span>
                  Balance: {tabBalance.toFixed(tab === 'deposit' || tab === 'withdraw' ? 4 : 2)}
                  {tabBalance > 0 && (
                    <button onClick={() => setAmount(String(tabBalance))} className="ml-2 text-indigo-400 hover:text-indigo-300 font-semibold">MAX</button>
                  )}
                </span>
              </div>
              <div className="flex items-center gap-4">
                <input
                  type="number" placeholder="0.00" value={amount} onChange={(e) => setAmount(e.target.value)}
                  className="w-full bg-transparent text-5xl text-white font-bold focus:outline-none placeholder:text-gray-700"
                />
                <div className="flex items-center gap-2 bg-[#13141a] px-4 py-2.5 rounded-xl border border-white/5 shrink-0">
                  <div className={`w-8 h-8 rounded-full flex items-center justify-center font-bold text-white ${['deposit', 'withdraw'].includes(tab) ? 'bg-[#627EEA]' : 'bg-[#2775CA]'}`}>
                    {(['deposit', 'withdraw'].includes(tab) ? collSym : debtSym)[0]}
                  </div>
                  <span className="font-bold text-white text-xl">{['deposit', 'withdraw'].includes(tab) ? collSym : debtSym}</span>
                </div>
              </div>
            </div>

            {!isConnected ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold cursor-not-allowed border border-white/5">Connect wallet</button>
            ) : parsedAmount === 0n ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold cursor-not-allowed border border-white/5">Enter an amount</button>
            ) : (
              <TxButton request={request} enabled={!!request} text={buttonText} confirmingText="Processing…" onSuccess={() => { setAmount(''); refetchAll(); }} className="text-lg" />
            )}
          </div>
        </motion.div>
      </div>
    </div>
  );
}
