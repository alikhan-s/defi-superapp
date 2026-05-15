import React from 'react';
import { useAccount, useSwitchChain } from 'wagmi';
import { arbitrumSepolia } from 'wagmi/chains';
import { AlertTriangle } from 'lucide-react';
import { motion } from 'framer-motion';

interface NetworkGuardProps {
  children: React.ReactNode;
}

export const NetworkGuard: React.FC<NetworkGuardProps> = ({ children }) => {
  const { chain, isConnected } = useAccount();
  const { switchChain, isPending } = useSwitchChain();

  const isWrongChain = isConnected && chain?.id !== arbitrumSepolia.id;

  if (isWrongChain) {
    return (
      <div className="min-h-screen bg-[#0a0b0f] flex items-center justify-center p-4">
        <motion.div 
          initial={{ opacity: 0, scale: 0.95, y: 20 }}
          animate={{ opacity: 1, scale: 1, y: 0 }}
          className="relative max-w-md w-full rounded-2xl bg-[#13141a] p-8 border border-white/5 shadow-2xl overflow-hidden"
        >
          {/* Background Glow */}
          <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-1/2 bg-rose-500/10 blur-[100px] pointer-events-none rounded-full" />
          
          <div className="relative z-10 flex flex-col items-center text-center">
            <div className="w-16 h-16 rounded-2xl bg-rose-500/10 flex items-center justify-center mb-6 border border-rose-500/20 shadow-[0_0_30px_rgba(244,63,94,0.15)]">
              <AlertTriangle className="w-8 h-8 text-rose-500" />
            </div>
            
            <h2 className="text-2xl font-bold text-white mb-3 tracking-tight">Wrong Network</h2>
            
            <p className="text-white/60 mb-8 leading-relaxed">
              This application requires the <span className="text-white font-medium">Arbitrum Sepolia</span> network. Please switch networks in your wallet to continue.
            </p>
            
            <button
              onClick={() => switchChain({ chainId: arbitrumSepolia.id })}
              disabled={isPending}
              className="w-full relative group overflow-hidden rounded-xl bg-gradient-to-r from-indigo-500 to-cyan-500 p-[1px] transition-all hover:scale-[1.02] active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100"
            >
              <div className="absolute inset-0 bg-white/20 opacity-0 group-hover:opacity-100 transition-opacity" />
              <div className="flex items-center justify-center h-12 w-full rounded-[11px] bg-gradient-to-r from-indigo-600 to-cyan-600 text-white font-semibold shadow-lg shadow-indigo-500/25">
                {isPending ? (
                  <div className="flex items-center gap-2">
                    <div className="w-4 h-4 rounded-full border-2 border-white border-t-transparent animate-spin" />
                    <span>Switching...</span>
                  </div>
                ) : (
                  'Switch to Arbitrum Sepolia'
                )}
              </div>
            </button>
          </div>
        </motion.div>
      </div>
    );
  }

  return <>{children}</>;
};
