import { getDefaultConfig } from '@rainbow-me/rainbowkit';
import { arbitrumSepolia } from 'wagmi/chains';
import { http } from 'wagmi';

/**
 * Single source of truth for the wagmi/RainbowKit config. Arbitrum Sepolia is
 * the only supported chain — `<NetworkGuard>` forces users onto it. The
 * WalletConnect project id comes from the environment (see .env.example);
 * injected wallets (MetaMask, Rabby, …) work even without it.
 *
 * IMPORTANT: pin the transport to a dedicated RPC (Alchemy) via
 * `VITE_ARBITRUM_SEPOLIA_RPC_URL`. RainbowKit's default public RPC is
 * rate-limited and frequently stale, which makes `useSimulateContract`
 * pre-flight checks fail intermittently (surfacing as "Transaction failed").
 * Falls back to the public RPC only if the env var is unset.
 */
const rpcUrl = import.meta.env.VITE_ARBITRUM_SEPOLIA_RPC_URL;

export const config = getDefaultConfig({
  appName: 'DeFi SuperApp',
  projectId: import.meta.env.VITE_WALLETCONNECT_PROJECT_ID || 'YOUR_WALLETCONNECT_PROJECT_ID',
  chains: [arbitrumSepolia],
  transports: {
    [arbitrumSepolia.id]: http(rpcUrl || undefined),
  },
  ssr: false,
});
