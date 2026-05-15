/// <reference types="vite/client" />

interface ImportMetaEnv {
  /** The Graph query endpoint for the Phase 10 subgraph. */
  readonly VITE_SUBGRAPH_URL: string;
  /** WalletConnect Cloud project id used by RainbowKit connectors. */
  readonly VITE_WALLETCONNECT_PROJECT_ID: string;
  /** Dedicated Arbitrum Sepolia RPC URL (falls back to public if unset). */
  readonly VITE_ARBITRUM_SEPOLIA_RPC_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
