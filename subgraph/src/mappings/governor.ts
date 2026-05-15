import { BigInt } from "@graphprotocol/graph-ts";

import {
  ProposalCreated,
  VoteCast,
  ProposalQueued,
  ProposalExecuted,
  ProposalCanceled,
} from "../../generated/ProtocolGovernor/ProtocolGovernor";
import { Proposal } from "../../generated/schema";
import { ZERO_BI } from "./shared";

// GovernorCountingSimple support values:
//   0 = Against, 1 = For, 2 = Abstain
const SUPPORT_AGAINST: i32 = 0;
const SUPPORT_FOR: i32 = 1;
const SUPPORT_ABSTAIN: i32 = 2;

function loadProposal(proposalId: BigInt): Proposal | null {
  return Proposal.load(proposalId.toString());
}

/**
 * Governor.ProposalCreated(
 *   uint256 proposalId,
 *   address proposer,
 *   address[] targets,
 *   uint256[] values,
 *   string[] signatures,
 *   bytes[] calldatas,
 *   uint256 voteStart,
 *   uint256 voteEnd,
 *   string description
 * )
 */
export function handleProposalCreated(event: ProposalCreated): void {
  let id = event.params.proposalId.toString();
  let p = new Proposal(id);
  p.proposalId = event.params.proposalId;
  p.proposer = event.params.proposer;
  p.description = event.params.description;
  p.state = "Pending";
  p.forVotes = ZERO_BI;
  p.againstVotes = ZERO_BI;
  p.abstainVotes = ZERO_BI;
  p.createdAt = event.block.timestamp;
  p.executedAt = null;
  p.save();
}

/**
 * Governor.VoteCast(
 *   address indexed voter,
 *   uint256 proposalId,
 *   uint8 support,
 *   uint256 weight,
 *   string reason
 * )
 */
export function handleVoteCast(event: VoteCast): void {
  let p = loadProposal(event.params.proposalId);
  if (p == null) return;

  let weight = event.params.weight;
  let support = event.params.support;

  if (support == SUPPORT_AGAINST) {
    p.againstVotes = p.againstVotes.plus(weight);
  } else if (support == SUPPORT_FOR) {
    p.forVotes = p.forVotes.plus(weight);
  } else if (support == SUPPORT_ABSTAIN) {
    p.abstainVotes = p.abstainVotes.plus(weight);
  }
  // Once any vote is cast the proposal is at least Active.
  if (p.state == "Pending") {
    p.state = "Active";
  }
  p.save();
}

export function handleProposalQueued(event: ProposalQueued): void {
  let p = loadProposal(event.params.proposalId);
  if (p == null) return;
  p.state = "Queued";
  p.save();
}

export function handleProposalExecuted(event: ProposalExecuted): void {
  let p = loadProposal(event.params.proposalId);
  if (p == null) return;
  p.state = "Executed";
  p.executedAt = event.block.timestamp;
  p.save();
}

export function handleProposalCanceled(event: ProposalCanceled): void {
  let p = loadProposal(event.params.proposalId);
  if (p == null) return;
  p.state = "Canceled";
  p.save();
}
