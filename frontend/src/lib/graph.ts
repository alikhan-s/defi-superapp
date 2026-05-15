/**
 * Subgraph integration — Apollo Client (v4) + typed hooks.
 *
 * Wraps the five reference queries shipped with the Phase 10 subgraph
 * (see subgraph/queries.md): top pools, a user's swaps, proposals, at-risk
 * lending positions, and a full portfolio. The endpoint is read from
 * `VITE_SUBGRAPH_URL` so it can be pointed at Studio or a self-hosted node
 * without code changes.
 *
 * Apollo Client v4 split React bindings into `@apollo/client/react`; core
 * symbols stay on `@apollo/client`.
 */
import { ApolloClient, HttpLink, InMemoryCache, gql } from '@apollo/client';
import { useQuery } from '@apollo/client/react';

const SUBGRAPH_URL = import.meta.env.VITE_SUBGRAPH_URL;

if (!SUBGRAPH_URL) {
  // Surface misconfiguration loudly in dev rather than failing silently at query time.
  console.warn('[graph] VITE_SUBGRAPH_URL is not set — subgraph queries will fail. See .env.example.');
}

export const apolloClient = new ApolloClient({
  link: new HttpLink({ uri: SUBGRAPH_URL }),
  cache: new InMemoryCache(),
  defaultOptions: {
    watchQuery: { fetchPolicy: 'cache-and-network' },
  },
});

// ───────────────────────────── Entity types ──────────────────────────────

export interface Pool {
  id: string;
  token0: string;
  token1: string;
  reserve0: string;
  reserve1: string;
  totalSupply: string;
  swapsCount: string;
  createdAtBlock: string;
}

export interface Swap {
  id: string;
  pool: Pick<Pool, 'id' | 'token0' | 'token1'> & Partial<Pool>;
  sender?: string;
  amount0In: string;
  amount1In: string;
  amount0Out: string;
  amount1Out: string;
  timestamp: string;
  blockNumber?: string;
}

export interface Proposal {
  id: string;
  proposalId: string;
  proposer: string;
  description: string;
  state: string;
  forVotes: string;
  againstVotes: string;
  abstainVotes: string;
  createdAt: string;
  executedAt: string | null;
}

export interface LendingPosition {
  id: string;
  collateral: string;
  debt: string;
  healthFactor: string;
  lastUpdated: string;
}

// ─────────────────────────────── Queries ──────────────────────────────────

/** Q1 — Top pools by lifetime swap count. */
const TOP_POOLS = gql`
  query TopPools($first: Int!) {
    pools(first: $first, orderBy: swapsCount, orderDirection: desc) {
      id
      token0
      token1
      reserve0
      reserve1
      totalSupply
      swapsCount
      createdAtBlock
    }
  }
`;

/** Q2 — All swaps for a given user. */
const USER_SWAPS = gql`
  query SwapsForUser($user: Bytes!, $first: Int!) {
    swaps(first: $first, where: { sender: $user }, orderBy: timestamp, orderDirection: desc) {
      id
      pool {
        id
        token0
        token1
      }
      amount0In
      amount1In
      amount0Out
      amount1Out
      timestamp
      blockNumber
    }
  }
`;

/** Q3 — All proposals with their current indexed state. */
const PROPOSALS = gql`
  query Proposals {
    proposals(orderBy: createdAt, orderDirection: desc) {
      id
      proposalId
      proposer
      description
      state
      forVotes
      againstVotes
      abstainVotes
      createdAt
      executedAt
    }
  }
`;

/** Q4 — Lending positions at risk (health factor < 1.5e18, debt > 0). */
const AT_RISK_POSITIONS = gql`
  query AtRiskPositions {
    lendingPositions(
      where: { healthFactor_lt: "1500000000000000000", debt_gt: "0" }
      orderBy: healthFactor
      orderDirection: asc
      first: 100
    ) {
      id
      collateral
      debt
      healthFactor
      lastUpdated
    }
  }
`;

/** Q5 — A user's full portfolio (lending position + AMM activity + governance). */
const PORTFOLIO = gql`
  query Portfolio($user: ID!, $userBytes: Bytes!) {
    lendingPosition(id: $user) {
      id
      collateral
      debt
      healthFactor
      lastUpdated
    }
    swaps(where: { sender: $userBytes }, orderBy: timestamp, orderDirection: desc, first: 25) {
      id
      pool {
        id
        token0
        token1
        reserve0
        reserve1
        totalSupply
      }
      amount0In
      amount1In
      amount0Out
      amount1Out
      timestamp
    }
    proposals(where: { proposer: $userBytes }) {
      id
      proposalId
      description
      state
      forVotes
      againstVotes
      abstainVotes
    }
  }
`;

// ──────────────────────────────── Hooks ───────────────────────────────────

export function useTopPools(first = 10) {
  return useQuery<{ pools: Pool[] }, { first: number }>(TOP_POOLS, {
    variables: { first },
    pollInterval: 30_000,
  });
}

export function useUserSwaps(address?: string, first = 50) {
  return useQuery<{ swaps: Swap[] }, { user: string; first: number }>(USER_SWAPS, {
    variables: { user: (address ?? '').toLowerCase(), first },
    skip: !address,
  });
}

export function useProposals() {
  return useQuery<{ proposals: Proposal[] }>(PROPOSALS, { pollInterval: 30_000 });
}

export function useAtRiskPositions() {
  return useQuery<{ lendingPositions: LendingPosition[] }>(AT_RISK_POSITIONS, { pollInterval: 30_000 });
}

export interface PortfolioData {
  lendingPosition: LendingPosition | null;
  swaps: Swap[];
  proposals: Pick<Proposal, 'id' | 'proposalId' | 'description' | 'state' | 'forVotes' | 'againstVotes' | 'abstainVotes'>[];
}

export function usePortfolio(address?: string) {
  const user = (address ?? '').toLowerCase();
  return useQuery<PortfolioData, { user: string; userBytes: string }>(PORTFOLIO, {
    variables: { user, userBytes: user },
    skip: !address,
  });
}
