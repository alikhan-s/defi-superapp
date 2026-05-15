import React from 'react';
import { useAccount, useSwitchChain } from 'wagmi';
import { arbitrumSepolia } from 'wagmi/chains';
import { AlertTriangle } from 'lucide-react';
import { motion, AnimatePresence } from 'framer-motion';

interface NetworkGuardProps {
  children: React.ReactNode;
}

/**
 * Wraps the whole app and, whenever a connected wallet is on the wrong chain,
 * overlays a blocking modal that forces a switch to Arbitrum Sepolia via
 * `useSwitchChain`. The app stays mounted behind the modal so state survives
 * the switch.
 */
export const NetworkGuard: React.FC<NetworkGuardProps> = ({ children }) => {
  const { chain, isConnected } = useAccount();
  const { switchChain, isPending, error } = useSwitchChain();

  const isWrongChain = isConnected && chain?.id !== arbitrumSepolia.id;

  return (
    <>
      {children}

      <AnimatePresence>
        {isWrongChain && (
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-black/70 backdrop-blur-md"
          >
            <motion.div
              initial={{ opacity: 0, scale: 0.95, y: 20 }}
              animate={{ opacity: 1, scale: 1, y: 0 }}
              exit={{ opacity: 0, scale: 0.95, y: 20 }}
              className="relative max-w-md w-full rounded-2xl bg-[#13141a] p-8 border border-white/5 shadow-2xl overflow-hidden"
            >
              <div className="absolute top-0 left-1/2 -translate-x-1/2 w-full h-1/2 bg-rose-500/10 blur-[100px] pointer-events-none rounded-full" />

              <div className="relative z-10 flex flex-col items-center text-center">
                <div className="w-16 h-16 rounded-2xl bg-rose-500/10 flex items-center justify-center mb-6 border border-rose-500/20 shadow-[0_0_30px_rgba(244,63,94,0.15)]">
                  <AlertTriangle className="w-8 h-8 text-rose-500" />
                </div>

                <h2 className="text-2xl font-bold text-white mb-3 tracking-tight">Wrong Network</h2>

                <p className="text-white/60 mb-8 leading-relaxed">
                  This application runs on <span className="text-white font-medium">Arbitrum Sepolia</span>. Switch
                  networks to continue — you're currently on{' '}
                  <span className="text-white font-medium">{chain?.name ?? 'an unsupported chain'}</span>.
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
                        <span>Switching…</span>
                      </div>
                    ) : (
                      'Switch to Arbitrum Sepolia'
                    )}
                  </div>
                </button>

                {error && (
                  <p className="mt-4 text-sm text-rose-400">
                    Could not switch automatically. Please change networks in your wallet.
                  </p>
                )}
              </div>
            </motion.div>
          </motion.div>
        )}
      </AnimatePresence>
    </>
  );
};
