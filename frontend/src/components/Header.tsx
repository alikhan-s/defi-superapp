import { useState } from 'react';
import { ConnectButton } from '@rainbow-me/rainbowkit';
import { Link, useLocation } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { useAccount } from 'wagmi';
import { arbitrumSepolia } from 'wagmi/chains';
import { Menu, X } from 'lucide-react';

export function Header() {
  const location = useLocation();
  const { isConnected, chain } = useAccount();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  const links = [
    { name: 'Home', path: '/' },
    { name: 'Swap', path: '/swap' },
    { name: 'Pool', path: '/pool' },
    { name: 'Vault', path: '/vault' },
    { name: 'Lending', path: '/lending' },
    { name: 'Governance', path: '/governance' },
    { name: 'Portfolio', path: '/portfolio' },
  ];

  return (
    <header className="sticky top-0 z-50 w-full border-b border-white/10 bg-[#0a0b0f]/80 backdrop-blur-xl supports-[backdrop-filter]:bg-[#0a0b0f]/60">
      <div className="container mx-auto flex h-20 items-center justify-between px-4 max-w-7xl">
        <div className="flex items-center gap-8">
          <Link to="/" className="flex items-center gap-3 group">
            <div className="relative h-10 w-10">
              <div className="absolute inset-0 rounded-xl bg-gradient-to-br from-indigo-500 via-violet-500 to-cyan-400 opacity-70 group-hover:opacity-100 blur-sm transition-opacity duration-300"></div>
              <div className="relative h-full w-full rounded-xl bg-[#0a0b0f] p-[1px]">
                <div className="h-full w-full rounded-xl bg-gradient-to-br from-[#13141a] to-[#0a0b0f] flex items-center justify-center border border-white/10">
                  <span className="text-xl text-transparent bg-clip-text bg-gradient-to-br from-indigo-400 to-cyan-400 font-bold tracking-tighter group-hover:scale-110 transition-transform">DSA</span>
                </div>
              </div>
            </div>
            <span className="text-xl font-bold tracking-tight text-white hidden sm:block group-hover:text-transparent group-hover:bg-clip-text group-hover:bg-gradient-to-r group-hover:from-white group-hover:to-gray-400 transition-all duration-300">
              DeFi SuperApp
            </span>
          </Link>

          <nav className="hidden lg:flex items-center gap-1 bg-white/5 p-1 rounded-2xl border border-white/5">
            {links.map((link) => {
              const isActive = location.pathname === link.path;
              return (
                <Link
                  key={link.path}
                  to={link.path}
                  className={`relative px-4 py-2 text-sm font-medium transition-colors rounded-xl ${
                    isActive ? 'text-white' : 'text-gray-400 hover:text-white hover:bg-white/5'
                  }`}
                >
                  {isActive && (
                    <motion.div
                      layoutId="active-nav-pill"
                      className="absolute inset-0 rounded-xl bg-white/10 shadow-[0_0_15px_rgba(255,255,255,0.05)]"
                      transition={{ type: 'spring', stiffness: 400, damping: 30 }}
                    />
                  )}
                  <span className="relative z-10">{link.name}</span>
                </Link>
              );
            })}
          </nav>
        </div>

        <div className="flex items-center gap-4">
          <div className="hidden sm:flex items-center gap-3">
            {isConnected && chain?.id === arbitrumSepolia.id && (
              <div className="flex items-center gap-2 px-3 py-1.5 rounded-full bg-green-500/10 border border-green-500/20 text-green-400 text-xs font-semibold tracking-wide">
                <div className="w-2 h-2 rounded-full bg-green-500 animate-pulse"></div>
                Arb Sepolia
              </div>
            )}
            <ConnectButton 
              chainStatus="none"
              showBalance={{ smallScreen: false, largeScreen: true }}
              accountStatus="avatar"
            />
          </div>

          <button 
            className="lg:hidden p-2 text-gray-400 hover:text-white"
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
          >
            {isMobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
          </button>
        </div>
      </div>

      <AnimatePresence>
        {isMobileMenuOpen && (
          <motion.div
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="lg:hidden border-t border-white/10 overflow-hidden bg-[#0a0b0f]"
          >
            <div className="flex flex-col p-4 gap-2">
              {links.map((link) => (
                <Link
                  key={link.path}
                  to={link.path}
                  onClick={() => setIsMobileMenuOpen(false)}
                  className={`px-4 py-3 rounded-xl font-medium ${
                    location.pathname === link.path 
                      ? 'bg-indigo-500/20 text-indigo-400' 
                      : 'text-gray-400 hover:bg-white/5 hover:text-white'
                  }`}
                >
                  {link.name}
                </Link>
              ))}
              <div className="mt-4 pt-4 border-t border-white/10 flex justify-center">
                <ConnectButton />
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </header>
  );
}
