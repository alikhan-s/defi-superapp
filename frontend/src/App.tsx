import { RainbowKitProvider, darkTheme } from '@rainbow-me/rainbowkit';
import { WagmiProvider } from 'wagmi';
import { QueryClientProvider, QueryClient } from '@tanstack/react-query';
import { ApolloProvider } from '@apollo/client/react';
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom';
import { Toaster } from 'react-hot-toast';

import '@rainbow-me/rainbowkit/styles.css';

import { config } from './config/wagmi';
import { apolloClient } from './lib/graph';
import { Layout } from './components/Layout';
import { NetworkGuard } from './components/NetworkGuard';
import { Dashboard } from './pages/Dashboard';
import { Swap } from './pages/Swap';
import { Pool } from './pages/Pool';
import { Lend } from './pages/Lend';
import { Vaults } from './pages/Vaults';
import { Governance } from './pages/Governance';
import { Portfolio } from './pages/Portfolio';

const queryClient = new QueryClient();

export default function App() {
  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <ApolloProvider client={apolloClient}>
          <RainbowKitProvider
            theme={darkTheme({
              accentColor: '#6366f1',
              accentColorForeground: 'white',
              borderRadius: 'large',
              fontStack: 'system',
              overlayBlur: 'small',
            })}
          >
            <BrowserRouter>
              <NetworkGuard>
                <Layout>
                  <Routes>
                    <Route path="/" element={<Dashboard />} />
                    <Route path="/swap" element={<Swap />} />
                    <Route path="/pool" element={<Pool />} />
                    <Route path="/vault" element={<Vaults />} />
                    <Route path="/lending" element={<Lend />} />
                    <Route path="/governance" element={<Governance />} />
                    <Route path="/portfolio" element={<Portfolio />} />
                    {/* Back-compat redirects for the old route names. */}
                    <Route path="/vaults" element={<Navigate to="/vault" replace />} />
                    <Route path="/lend" element={<Navigate to="/lending" replace />} />
                    <Route path="*" element={<Navigate to="/" replace />} />
                  </Routes>
                </Layout>
              </NetworkGuard>
            </BrowserRouter>
            <Toaster
              position="bottom-right"
              toastOptions={{
                style: {
                  background: '#13141a',
                  color: '#fff',
                  border: '1px solid rgba(255,255,255,0.1)',
                },
              }}
            />
          </RainbowKitProvider>
        </ApolloProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
