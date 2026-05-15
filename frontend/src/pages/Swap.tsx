import { useState, useMemo } from 'react';
import { useAccount, useReadContract, useBalance } from 'wagmi';
import { motion, AnimatePresence } from 'framer-motion';
import { Settings, ArrowDownUp, AlertCircle } from 'lucide-react';
import { parseUnits, formatUnits } from 'viem';

import { addresses } from '../contracts/addresses';
import { pairAbi } from '../contracts/abis/pairAbi';
import { TxButton } from '../components/TxButton';
import { useWriteContract } from 'wagmi';

export function Swap() {
  const { isConnected, address } = useAccount();
  
  // State
  const [amountIn, setAmountIn] = useState('');
  const [slippage, setSlippage] = useState('0.5');
  const [showSettings, setShowSettings] = useState(false);
  const [isReversed, setIsReversed] = useState(false); // false: Token0 -> Token1, true: Token1 -> Token0

  // Mock Tokens (Since we are interacting with a SamplePair)
  const tokenA = { symbol: 'ETH', name: 'Ethereum', icon: 'E', color: 'bg-[#627EEA]' };
  const tokenB = { symbol: 'USDC', name: 'USD Coin', icon: 'U', color: 'bg-[#2775CA]' };
  
  const fromToken = isReversed ? tokenB : tokenA;
  const toToken = isReversed ? tokenA : tokenB;

  // Read Balances (Mocked for UI via useBalance for ETH, hardcoded 0 for USDC since we don't have its address easily available here, or we can just read Pair reserves)
  const { data: ethBalance } = useBalance({ address });

  // Read Pair Reserves
  const { data: reserves, isLoading: isReservesLoading } = useReadContract({
    address: addresses.SamplePair as `0x${string}`,
    abi: pairAbi,
    functionName: 'getReserves',
  });

  // Calculate Output using Constant Product Formula with 0.3% fee
  // outAmount = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
  const { amountOut, priceImpact, minReceived } = useMemo(() => {
    if (!reserves || !amountIn || isNaN(Number(amountIn)) || Number(amountIn) <= 0) {
      return { amountOut: '', priceImpact: '0.00', minReceived: '0' };
    }

    // Assuming token0 is ETH and token1 is USDC for visual sake, both 18 decimals in our SamplePair? 
    // Wait, SamplePair uses generic ERC20s, let's assume 18 decimals for both for calculation
    const r0 = Number(formatUnits(reserves[0] as bigint, 18));
    const r1 = Number(formatUnits(reserves[1] as bigint, 18));
    
    if (r0 === 0 || r1 === 0) return { amountOut: '', priceImpact: '0.00', minReceived: '0' };

    const reserveIn = isReversed ? r1 : r0;
    const reserveOut = isReversed ? r0 : r1;
    const amountInNum = Number(amountIn);

    const amountInWithFee = amountInNum * 0.997;
    const out = (amountInWithFee * reserveOut) / (reserveIn + amountInWithFee);
    
    // Price Impact Calculation
    const spotPrice = reserveOut / reserveIn;
    const executionPrice = out / amountInNum;
    const impact = ((spotPrice - executionPrice) / spotPrice) * 100;

    // Minimum received based on slippage
    const slipMultiplier = 1 - (Number(slippage) / 100);
    const minRec = out * slipMultiplier;

    return { 
      amountOut: out.toFixed(6), 
      priceImpact: impact.toFixed(2),
      minReceived: minRec.toFixed(6)
    };
  }, [amountIn, reserves, isReversed, slippage]);

  // Swap Execution
  const { writeContractAsync } = useWriteContract();

  const handleSwap = async () => {
    if (!amountOut || !address) return;
    
    // The Pair contract swap function: swap(uint amount0Out, uint amount1Out, address to, bytes data)
    // Actually the prompt says: "swap on the Pair with correct args: [amount0Out, amount1Out, toAddress, minOut, '0x']" 
    // Let's check the abi. The ABI in the previous version had 4 args. The real UniswapV2 Pair has 4 args.
    // I will use 4 args: amount0Out, amount1Out, to, data.
    const outParsed = parseUnits(amountOut, 18);
    const minOutParsed = parseUnits(minReceived, 18);
    const arg0 = isReversed ? outParsed : 0n;
    const arg1 = isReversed ? 0n : outParsed;

    return writeContractAsync({
      address: addresses.SamplePair as `0x${string}`,
      abi: pairAbi,
      functionName: 'swap',
      args: [arg0, arg1, address, minOutParsed, '0x'],
    });
  };

  return (
    <div className="flex justify-center items-center py-12">
      <motion.div 
        initial={{ opacity: 0, scale: 0.95 }}
        animate={{ opacity: 1, scale: 1 }}
        transition={{ duration: 0.5, type: "spring" }}
        className="w-full max-w-md"
      >
        <div className="glass-card p-2 relative overflow-hidden">
          {/* Decorative Blobs */}
          <div className="absolute top-0 right-0 w-64 h-64 bg-indigo-500/10 rounded-full blur-3xl -z-10" />
          <div className="absolute bottom-0 left-0 w-64 h-64 bg-cyan-500/10 rounded-full blur-3xl -z-10" />

          {/* Header */}
          <div className="flex justify-between items-center p-4">
            <h2 className="text-xl font-bold text-white">Swap</h2>
            <button 
              onClick={() => setShowSettings(!showSettings)}
              className="p-2 rounded-xl text-gray-400 hover:text-white hover:bg-white/10 transition-colors"
            >
              <Settings size={20} />
            </button>
          </div>

          {/* Settings Dropdown */}
          <AnimatePresence>
            {showSettings && (
              <motion.div
                initial={{ height: 0, opacity: 0 }}
                animate={{ height: 'auto', opacity: 1 }}
                exit={{ height: 0, opacity: 0 }}
                className="overflow-hidden px-4 pb-4"
              >
                <div className="p-4 rounded-2xl bg-black/40 border border-white/5">
                  <p className="text-sm text-gray-400 mb-3 font-medium">Max Slippage</p>
                  <div className="flex gap-2">
                    {['0.1', '0.5', '1.0'].map(val => (
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
                        className="w-full py-1.5 px-3 bg-white/5 border border-white/10 rounded-xl text-white text-right focus:outline-none focus:border-indigo-500 transition-colors"
                      />
                      <span className="absolute right-3 top-[6px] text-gray-400 text-sm">%</span>
                    </div>
                  </div>
                </div>
              </motion.div>
            )}
          </AnimatePresence>

          {/* Input Section */}
          <div className="space-y-1 p-2">
            <div className="p-4 rounded-3xl bg-black/40 border border-transparent focus-within:border-white/10 transition-colors group">
              <div className="flex justify-between mb-2">
                <span className="text-sm font-medium text-gray-400">Sell</span>
                <span className="text-sm font-medium text-gray-400">
                  Balance: {fromToken.symbol === 'ETH' && ethBalance ? (Number(ethBalance.value) / 1e18).toFixed(4) : '0.00'}
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
                <button className="flex items-center gap-2 bg-[#13141a] hover:bg-white/10 border border-white/5 px-4 py-2 rounded-2xl transition-colors shadow-lg shrink-0">
                  <div className={`w-6 h-6 rounded-full ${fromToken.color} flex items-center justify-center text-xs font-bold text-white`}>
                    {fromToken.icon}
                  </div>
                  <span className="font-bold text-white text-lg">{fromToken.symbol}</span>
                </button>
              </div>
            </div>

            {/* Reverse Button */}
            <div className="relative h-2 flex justify-center items-center z-10">
              <button 
                onClick={() => setIsReversed(!isReversed)}
                className="absolute p-2 rounded-xl bg-[#13141a] border-4 border-[#0a0b0f] text-gray-400 hover:text-white transition-transform hover:scale-110 active:scale-95"
              >
                <ArrowDownUp size={16} />
              </button>
            </div>

            {/* Output Section */}
            <div className="p-4 rounded-3xl bg-black/40 border border-transparent transition-colors">
              <div className="flex justify-between mb-2">
                <span className="text-sm font-medium text-gray-400">Buy</span>
                <span className="text-sm font-medium text-gray-400">Balance: 0.00</span>
              </div>
              <div className="flex items-center gap-4">
                {isReservesLoading ? (
                  <div className="h-10 w-full bg-white/5 animate-pulse rounded-lg" />
                ) : (
                  <input
                    type="text"
                    value={amountOut}
                    readOnly
                    placeholder="0"
                    className="w-full bg-transparent text-4xl text-white font-medium focus:outline-none placeholder:text-gray-600"
                  />
                )}
                <button className="flex items-center gap-2 bg-[#13141a] hover:bg-white/10 border border-white/5 px-4 py-2 rounded-2xl transition-colors shadow-lg shrink-0">
                  <div className={`w-6 h-6 rounded-full ${toToken.color} flex items-center justify-center text-xs font-bold text-white`}>
                    {toToken.icon}
                  </div>
                  <span className="font-bold text-white text-lg">{toToken.symbol}</span>
                </button>
              </div>
            </div>
          </div>

          {/* Swap Details */}
          {amountOut && Number(amountOut) > 0 && (
            <motion.div 
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              className="px-6 py-4 space-y-3"
            >
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Price Impact</span>
                <span className={`${Number(priceImpact) > 5 ? 'text-red-400' : Number(priceImpact) > 1 ? 'text-yellow-400' : 'text-green-400'} font-medium`}>
                  {priceImpact}%
                </span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-400 flex items-center gap-1">
                  Minimum Received 
                  <AlertCircle size={14} className="text-gray-500" />
                </span>
                <span className="text-white font-medium">{minReceived} {toToken.symbol}</span>
              </div>
              <div className="flex justify-between text-sm">
                <span className="text-gray-400">Exchange Rate</span>
                <span className="text-white font-medium">
                  1 {fromToken.symbol} = {(Number(amountOut) / Number(amountIn)).toFixed(4)} {toToken.symbol}
                </span>
              </div>
            </motion.div>
          )}

          {/* Action Button */}
          <div className="p-2 pt-0 mt-4">
            {!isConnected ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold text-lg cursor-not-allowed">
                Connect Wallet to Swap
              </button>
            ) : !amountIn || Number(amountIn) <= 0 ? (
              <button disabled className="w-full py-4 rounded-2xl bg-white/5 text-gray-500 font-bold text-lg cursor-not-allowed">
                Enter an amount
              </button>
            ) : (
              <TxButton 
                onClick={handleSwap}
                text="Swap"
                loadingText="Swapping..."
                className="w-full py-4 rounded-2xl text-lg font-bold"
              />
            )}
          </div>
        </div>
      </motion.div>
    </div>
  );
}
