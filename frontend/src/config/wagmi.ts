import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { arbitrumSepolia } from 'wagmi/chains';

/**
 * Single source of truth for the wagmi/RainbowKit config. Arbitrum Sepolia is
 * the only supported chain — `<NetworkGuard>` forces users onto it. The
 * WalletConnect project id comes from the environment (see .env.example);
 * injected wallets (MetaMask, Rabby, …) work even without it.
 */
export const config = getDefaultConfig({
  appName: 'DeFi SuperApp',
  projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || 'YOUR_WALLETCONNECT_PROJECT_ID',
  chains: [arbitrumSepolia],
  ssr: false,
});
