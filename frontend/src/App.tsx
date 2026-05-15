import { getDefaultConfig, RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit';
import { WagmiProvider } from 'wagmi';
import { arbitrumSepolia } from 'wagmi/chains';
import { QueryClientProvider, QueryClient } from '@tanstack/react-query';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';

import '@rainbow-me/rainbowkit/styles.css';

import { Layout } from './components/Layout';
import { NetworkGuard } from './components/NetworkGuard';
import { Dashboard } from './pages/Dashboard';
import { Swap } from './pages/Swap';
import { Lend } from './pages/Lend';
import { Vaults } from './pages/Vaults';
import { Governance } from './pages/Governance';

const config = getDefaultConfig({
  appName: 'DeFi SuperApp',
  projectId: 'YOUR_PROJECT_ID', // Replace with real WalletConnect ID
  chains: [arbitrumSepolia],
});

const queryClient = new QueryClient();

export default function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider 
          theme={darkTheme({
            accentColor: '#6366f1',
            accentColorForeground: 'white',
            borderRadius: 'large',
            fontStack: 'system',
            overlayBlur: 'small',
          })}
        >
          <NetworkGuard>
            <BrowserRouter>
              <Layout>
                <Routes>
                  <Route path="/" element={<Dashboard />} />
                  <Route path="/swap" element={<Swap />} />
                  <Route path="/lend" element={<Lend />} />
                  <Route path="/vaults" element={<Vaults />} />
                  <Route path="/governance" element={<Governance />} />
                </Routes>
              </Layout>
            </BrowserRouter>
          </NetworkGuard>
          <Toaster 
            position="bottom-right"
            toastOptions={{
              style: {
                background: '#13141a',
                color: '#fff',
                border: '1px solid rgba(255,255,255,0.1)',
              }
            }}
          />
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
