import { createConfig, http } from 'wagmi';
import { arbitrumSepolia, localhost } from 'wagmi/chains';
import { injected, walletConnect } from 'wagmi/connectors';

export const config = createConfig({
  chains: [arbitrumSepolia, localhost],
  connectors: [
    injected(),
    walletConnect({ projectId: 'YOUR_PROJECT_ID' }),
  ],
  transports: {
    [arbitrumSepolia.id]: http(),
    [localhost.id]: http(),
  },
});
