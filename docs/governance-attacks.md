# Governance Security Analysis

This document outlines the primary attack vectors against the protocol's governance infrastructure and the embedded mitigations.

## 1. Flash-Loan Governance Attack
**Vector:** An attacker borrows a massive amount of governance tokens via a flash loan, executes a proposal vote, and returns the tokens in the same block or transaction.
**Mitigation:** The OpenZeppelin Governor reads voting power from past snapshots. Even if an attacker acquires tokens during the active voting phase or at the exact block of the proposal creation, their historical voting power at the snapshot block remains `0`. The attack is completely neutralized.

## 2. Whale Attack
**Vector:** A single entity with a massive token concentration forces through a malicious proposal (e.g., draining the treasury) and executes it before the community can respond.
**Mitigation:** The architecture enforces a strict Timelock delay (2 days) between a proposal succeeding and its execution. This grants the community and developers a 48-hour window to react, withdraw liquidity, or potentially execute an emergency pause if the protocol permits.

## 3. Proposal Spam
**Vector:** An attacker spams the network with thousands of meaningless proposals to bloat the contract state or confuse voters.
**Mitigation:** The `ProtocolGovernor` implements a strict `proposalThreshold`. Only accounts holding at least 1% of the total token supply can submit proposals.

## 4. Timelock Bypass
**Vector:** An attacker discovers an alternative administrative path to access sensitive functions, completely ignoring the governance voting process.
**Mitigation:** Ownership and critical roles (`DEFAULT_ADMIN_ROLE`) for the Treasury, LendingPool, PairFactory, and YieldVault are exclusively held by the `ProtocolTimelock` contract. Any direct calls from EOAs (including the original deployer) immediately revert with an `AccessControl` error.