# DeFi Super-App — Sample GraphQL Queries

Five reference queries against the deployed subgraph. Run them in The Graph
Studio playground or via any GraphQL client.

---

## Q1 — Top 10 pools by 24h swap count

Returns pools sorted by total swaps. To restrict to "last 24h", filter the
inner `swaps` selection by `timestamp_gte` (current unix - 86400).

```graphql
query TopPools24h($since: BigInt!) {
  pools(
    first: 10
    orderBy: swapsCount
    orderDirection: desc
  ) {
    id
    token0
    token1
    reserve0
    reserve1
    totalSupply
    swapsCount
    swaps(where: { timestamp_gte: $since }) {
      id
      timestamp
    }
  }
}
```

Variables:

```json
{ "since": "1715731200" }
```

> Note: `swapsCount` is lifetime. For an exact 24h leaderboard, count
> `swaps_aggregate` server-side by post-processing, or maintain a daily
> rollup entity (next milestone).

---

## Q2 — All swaps for a given user

```graphql
query SwapsForUser($user: Bytes!, $first: Int = 100, $skip: Int = 0) {
  swaps(
    first: $first
    skip: $skip
    where: { sender: $user }
    orderBy: timestamp
    orderDirection: desc
  ) {
    id
    pool { id token0 token1 }
    amount0In
    amount1In
    amount0Out
    amount1Out
    timestamp
    blockNumber
  }
}
```

Variables:

```json
{ "user": "0x1234abcd…", "first": 50, "skip": 0 }
```

---

## Q3 — All proposals with their current state

```graphql
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
```

> `state` reflects the last on-chain transition we indexed
> (`Pending → Active → Queued → Executed`, or `Canceled`). The
> Succeeded / Defeated transitions are not emitted as events by OZ
> Governor; clients can derive them from `forVotes`, `againstVotes`,
> quorum, and `voteEnd` if needed.

---

## Q4 — Lending positions at risk (health factor < 1.5e18)

```graphql
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
```

> `healthFactor` is stored as a 1e18-scaled BigInt. `1500000000000000000`
> = 1.5e18. Positions with `debt == 0` carry `MAX_UINT256` as a
> sentinel and are excluded by the `debt_gt: 0` filter.

---

## Q5 — A user's full portfolio

Pulls LP NFTs (Pool participation derived from mints/swaps), the user's
`LendingPosition`, and the per-pool reserve / supply snapshot that lets the
client compute their share-of-pool client-side. Vault share balances live in
the `YieldVault` ERC-20 and are exposed by The Graph hosted
`erc20-balances` subgraph — query that endpoint with the user address.

```graphql
query Portfolio($user: ID!, $userBytes: Bytes!) {
  # Lending side
  lendingPosition(id: $user) {
    collateral
    debt
    healthFactor
    lastUpdated
  }

  # Recent AMM swaps (proxy for LP / trading activity)
  swaps(
    where: { sender: $userBytes }
    orderBy: timestamp
    orderDirection: desc
    first: 25
  ) {
    pool { id token0 token1 reserve0 reserve1 totalSupply }
    amount0In
    amount1In
    amount0Out
    amount1Out
    timestamp
  }

  # Governance participation
  proposals(where: { proposer: $userBytes }) {
    id
    state
    forVotes
    againstVotes
    abstainVotes
  }
}
```

Variables:

```json
{
  "user":      "0x1234abcd…",
  "userBytes": "0x1234abcd…"
}
```

For ERC-20 (GovernanceToken, YieldVault shares, debt token) balances,
combine this with The Graph's hosted balances API:

```
https://api.thegraph.com/subgraphs/name/messari/erc20-balances-arbitrum-sepolia
```

Query `accountBalances(where: { account: $user })` to recover share /
token holdings, then join client-side against this subgraph's `Pool` and
`LendingPosition` entities.
