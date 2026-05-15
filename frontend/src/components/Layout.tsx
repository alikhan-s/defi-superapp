import type { ReactNode } from 'react';
import { motion } from 'framer-motion';
import { Header } from './Header';


interface LayoutProps {
  children: ReactNode;
}

export function Layout({ children }: LayoutProps) {
  return (
    <div className="min-h-screen bg-[#0a0b0f] text-gray-100 font-sans selection:bg-indigo-500/30 relative overflow-hidden flex flex-col">
      {/* Animated Background */}
      <div className="fixed inset-0 z-0">
        <div className="absolute inset-0 bg-[#0a0b0f] bg-[linear-gradient(to_right,#80808012_1px,transparent_1px),linear-gradient(to_bottom,#80808012_1px,transparent_1px)] bg-[size:24px_24px]"></div>
        <motion.div 
          animate={{ 
            scale: [1, 1.2, 1],
            x: [0, 50, 0],
            y: [0, 30, 0]
          }}
          transition={{ duration: 15, repeat: Infinity, ease: "linear" }}
          className="absolute top-[-10%] left-[-10%] w-[40%] h-[40%] rounded-full bg-indigo-600/20 blur-[120px]" 
        />
        <motion.div 
          animate={{ 
            scale: [1, 1.1, 1],
            x: [0, -30, 0],
            y: [0, 50, 0]
          }}
          transition={{ duration: 12, repeat: Infinity, ease: "linear" }}
          className="absolute bottom-[-10%] right-[-10%] w-[30%] h-[40%] rounded-full bg-cyan-600/10 blur-[100px]" 
        />
      </div>

      <div className="relative z-10 flex flex-col min-h-screen">
        <Header />
        
        <main className="flex-grow container mx-auto px-4 py-8 max-w-7xl flex flex-col">
          {children}
        </main>

        <footer className="w-full border-t border-white/10 bg-[#0a0b0f]/50 backdrop-blur-lg mt-auto">
          <div className="container mx-auto px-4 py-8 max-w-7xl flex flex-col md:flex-row justify-between items-center gap-4">
            <div className="flex items-center gap-2">
              <div className="h-6 w-6 rounded-full bg-gradient-to-br from-indigo-500 to-cyan-400 p-[1px]">
                <div className="h-full w-full rounded-full bg-[#0a0b0f] flex items-center justify-center">
                  <span className="text-[10px] text-transparent bg-clip-text bg-gradient-to-r from-indigo-500 to-cyan-400 font-bold">D</span>
                </div>
              </div>
              <span className="text-sm font-semibold text-gray-400">DeFi SuperApp © 2026</span>
            </div>
            
            <div className="flex items-center gap-6">
              <a href="#" className="text-gray-500 hover:text-indigo-400 transition-colors">
                Github
              </a>
              <a href="#" className="text-gray-500 hover:text-cyan-400 transition-colors">
                Twitter
              </a>
              <a href="#" className="text-gray-500 hover:text-indigo-400 transition-colors">
                Discord
              </a>
            </div>
            
            <div className="flex items-center gap-4 text-sm text-gray-500">
              <a href="#" className="hover:text-white transition-colors">Terms</a>
              <a href="#" className="hover:text-white transition-colors">Privacy</a>
              <a href="#" className="hover:text-white transition-colors">Docs</a>
            </div>
          </div>
        </footer>
      </div>
    </div>
  );
}
