# Post-deployment Report
Chain ID: 421614
Block:    10893164

- [x] Treasury admin == Timelock
- [x] LendingPool admin == Timelock
- [x] PairFactory admin == Timelock
- [x] YieldVault admin == Timelock
- [x] Deployer renounced Treasury admin
- [x] Deployer renounced LendingPool admin
- [x] Deployer renounced PairFactory admin
- [x] Deployer renounced YieldVault admin
- [x] Deployer renounced Timelock admin
- [x] Timelock minDelay == 2 days  (got 172800)
- [x] Governor votingDelay == 345600
- [x] Governor votingPeriod == 2419200
- [x] Governor quorumNumerator == 4
- [x] Governor.token() == GovernanceToken
- [x] Governor proposalThreshold == totalSupply/100  (got 100000000000000000000000)
- [x] Oracle ETH price > 0  (got 2139129782630000000000)
- [x] Oracle USDC price > 0 (got 999775090000000000)
