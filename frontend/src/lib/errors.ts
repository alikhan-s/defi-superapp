/**
 * Human-friendly translation of on-chain reverts.
 *
 * Smart-contract reverts reach the UI as deeply-nested viem errors whose
 * innermost cause carries either a decoded custom-error name or a raw 4-byte
 * selector. This module maps both forms to copy a user can act on, and
 * GUARANTEES that a raw RPC error string is never surfaced — anything we don't
 * recognise collapses to the generic "Transaction failed" fallback.
 */
import { BaseError, ContractFunctionRevertedError, toFunctionSelector } from 'viem';

export interface ParsedTxError {
  title: string;
  /** Safe, user-facing description. Never a raw RPC payload. */
  message: string;
  /** True when the wallet owner declined the request (no toast warranted). */
  isUserRejection: boolean;
}

const GENERIC_FALLBACK = 'Transaction failed. Please try again.';

/**
 * Friendly copy keyed by the contract's custom-error name. Covers every custom
 * error declared across the Pair, LendingPool, Oracle, YieldVault, Governor and
 * shared OpenZeppelin libraries used by the protocol.
 */
const ERROR_MESSAGES: Record<string, { title: string; message: string }> = {
  // ── AMM / Pair ──────────────────────────────────────────────────────────
  InsufficientOutput: {
    title: 'Price moved',
    message:
      'The swap would return less than your minimum. Increase slippage tolerance or reduce the amount.',
  },
  Slippage: {
    title: 'Slippage exceeded',
    message: 'Price moved beyond your slippage tolerance. Adjust the tolerance and try again.',
  },
  InsufficientLiquidity: {
    title: 'Not enough liquidity',
    message: 'The pool does not have enough liquidity for this trade.',
  },
  InvalidToken: { title: 'Invalid token', message: 'That token is not part of this pool.' },
  K: {
    title: 'Invariant check failed',
    message: 'The pool reserves invariant was violated. Try a smaller amount.',
  },
  Locked: { title: 'Pool busy', message: 'The pool is processing another action. Try again shortly.' },
  Forbidden: { title: 'Not allowed', message: 'You are not permitted to perform this action.' },

  // ── Lending ────────────────────────────────────────────────────────────
  HealthFactorTooLow: {
    title: 'Health factor too low',
    message:
      'This would drop your health factor below the safe threshold. Repay debt or add collateral first.',
  },
  InsufficientCollateral: {
    title: 'Insufficient collateral',
    message: 'You do not have enough collateral deposited for this action.',
  },
  NotLiquidatable: {
    title: 'Position is healthy',
    message: 'This position cannot be liquidated — its health factor is above 1.0.',
  },
  TransferFailed: { title: 'Transfer failed', message: 'A token transfer failed. Check balances and allowances.' },

  // ── Oracle ───────────────────────────────────────────────────────────────
  StalePrice: {
    title: 'Stale price',
    message: 'The price feed is stale. Please wait for the oracle to refresh and try again.',
  },
  InvalidPrice: {
    title: 'Invalid price',
    message: 'The oracle returned an invalid or stale price. Please try again later.',
  },
  FeedNotConfigured: {
    title: 'Price feed unavailable',
    message: 'No price feed is configured for this asset.',
  },

  // ── ERC20 / ERC4626 (OpenZeppelin) ────────────────────────────────────────
  ERC20InsufficientBalance: { title: 'Insufficient balance', message: 'You do not have enough tokens for this action.' },
  ERC20InsufficientAllowance: {
    title: 'Approval required',
    message: 'Token spending allowance is too low. Approve the token first.',
  },
  ERC4626ExceededMaxDeposit: { title: 'Deposit too large', message: 'The amount exceeds the vault deposit limit.' },
  ERC4626ExceededMaxWithdraw: { title: 'Withdraw too large', message: 'You cannot withdraw more than your vault balance.' },
  ERC4626ExceededMaxRedeem: { title: 'Redeem too large', message: 'You cannot redeem more shares than you own.' },

  // ── Governor ───────────────────────────────────────────────────────────
  GovernorInsufficientProposerVotes: {
    title: 'Below proposal threshold',
    message: 'You need more voting power (delegated GOV) to create a proposal.',
  },
  GovernorAlreadyCastVote: { title: 'Already voted', message: 'You have already cast a vote on this proposal.' },
  GovernorUnexpectedProposalState: {
    title: 'Wrong proposal state',
    message: 'This action is not available for the proposal in its current state.',
  },
  GovernorNonexistentProposal: { title: 'Unknown proposal', message: 'That proposal does not exist.' },

  // ── Common (shared) ──────────────────────────────────────────────────────
  ZeroAmount: { title: 'Amount required', message: 'Enter an amount greater than zero.' },
  ZeroAddress: { title: 'Invalid address', message: 'A zero address was provided.' },
  EnforcedPause: { title: 'Paused', message: 'This contract is currently paused. Try again later.' },
  ReentrancyGuardReentrantCall: { title: 'Reentrancy blocked', message: 'A reentrant call was blocked.' },
  AccessControlUnauthorizedAccount: {
    title: 'Not authorized',
    message: 'Your account lacks the role required for this action.',
  },
};

/**
 * Full custom-error signatures whose 4-byte selectors we want to recognise even
 * when viem cannot decode them against a local ABI (e.g. an error thrown by a
 * contract we didn't pass the ABI for). Built once into a selector → name table.
 */
const ERROR_SIGNATURES = [
  'InsufficientOutput()',
  'Slippage()',
  'InsufficientLiquidity()',
  'InvalidToken()',
  'K()',
  'Locked()',
  'Forbidden()',
  'HealthFactorTooLow()',
  'InsufficientCollateral()',
  'NotLiquidatable()',
  'TransferFailed()',
  'StalePrice()',
  'InvalidPrice()',
  'FeedNotConfigured()',
  'ZeroAmount()',
  'ZeroAddress()',
  'EnforcedPause()',
  'ReentrancyGuardReentrantCall()',
  'ERC20InsufficientBalance(address,uint256,uint256)',
  'ERC20InsufficientAllowance(address,uint256,uint256)',
  'ERC4626ExceededMaxDeposit(address,uint256,uint256)',
  'ERC4626ExceededMaxWithdraw(address,uint256,uint256)',
  'ERC4626ExceededMaxRedeem(address,uint256,uint256)',
  'GovernorInsufficientProposerVotes(address,uint256,uint256)',
  'GovernorAlreadyCastVote(address)',
  'AccessControlUnauthorizedAccount(address,bytes32)',
] as const;

/** selector (0x + 8 hex, lowercased) → custom-error name. */
const SELECTOR_TO_NAME: Record<string, string> = (() => {
  const table: Record<string, string> = {};
  for (const sig of ERROR_SIGNATURES) {
    try {
      const name = sig.slice(0, sig.indexOf('('));
      table[toFunctionSelector(sig).toLowerCase()] = name;
    } catch {
      /* ignore malformed signature */
    }
  }
  return table;
})();

function lookup(name: string | undefined): { title: string; message: string } | undefined {
  return name ? ERROR_MESSAGES[name] : undefined;
}

/**
 * Many tokens (e.g. the canonical Arbitrum Sepolia WETH) revert with classic
 * `Error(string)` messages rather than 4-byte custom errors. Map the common
 * ones to friendly copy by substring — we only ever return our OWN text, never
 * the raw revert string, so nothing unsafe leaks through.
 */
const STRING_PATTERNS: { match: string; title: string; message: string }[] = [
  { match: 'exceeds allowance', title: 'Approval required', message: 'Token allowance is too low. Approve the token for this amount, then try again.' },
  { match: 'insufficient allowance', title: 'Approval required', message: 'Token allowance is too low. Approve the token first.' },
  { match: 'exceeds balance', title: 'Insufficient balance', message: 'You do not have enough tokens for this action.' },
  { match: 'insufficient balance', title: 'Insufficient balance', message: 'You do not have enough tokens for this action.' },
  { match: 'transfer amount exceeds', title: 'Transfer failed', message: 'Token transfer failed — check your balance and allowance.' },
  { match: 'enforcedpause', title: 'Paused', message: 'This contract is currently paused. Try again later.' },
  { match: 'pausable: paused', title: 'Paused', message: 'This contract is currently paused. Try again later.' },
];

function matchStringRevert(error: unknown): { title: string; message: string } | undefined {
  const text = stringifyError(error).toLowerCase();
  for (const p of STRING_PATTERNS) {
    if (text.includes(p.match)) return { title: p.title, message: p.message };
  }
  return undefined;
}

/** Detect a wallet-side rejection across the common error shapes. */
function detectUserRejection(error: unknown): boolean {
  const code = (error as { code?: number; cause?: { code?: number } })?.code;
  if (code === 4001) return true;
  if ((error as { cause?: { code?: number } })?.cause?.code === 4001) return true;
  const text = stringifyError(error).toLowerCase();
  return (
    text.includes('user rejected') ||
    text.includes('user denied') ||
    text.includes('request rejected') ||
    text.includes('rejected the request')
  );
}

function stringifyError(error: unknown): string {
  if (error instanceof Error) return `${error.message} ${(error as { details?: string }).details ?? ''}`;
  if (typeof error === 'string') return error;
  try {
    return JSON.stringify(error);
  } catch {
    return String(error);
  }
}

/** Scan an error's text for a bare 4-byte selector we recognise. */
function matchRawSelector(error: unknown): string | undefined {
  const text = stringifyError(error);
  const matches = text.toLowerCase().match(/0x[0-9a-f]{8}\b/g);
  if (!matches) return undefined;
  for (const sel of matches) {
    if (SELECTOR_TO_NAME[sel]) return SELECTOR_TO_NAME[sel];
  }
  return undefined;
}

/**
 * Convert any thrown value from a wagmi/viem write or simulation into safe,
 * user-facing copy. Raw RPC errors are never returned verbatim.
 */
export function parseTxError(error: unknown): ParsedTxError {
  if (detectUserRejection(error)) {
    return { title: 'Request cancelled', message: 'You rejected the request in your wallet.', isUserRejection: true };
  }

  // Preferred path: viem decoded the revert against the contract ABI.
  if (error instanceof BaseError) {
    const revert = error.walk((e) => e instanceof ContractFunctionRevertedError) as
      | ContractFunctionRevertedError
      | null;
    if (revert) {
      const name = revert.data?.errorName ?? revert.reason ?? undefined;
      const hit = lookup(name);
      if (hit) return { ...hit, isUserRejection: false };
    }
  }

  // Fallback 1: decode a raw selector we precomputed.
  const byName = lookup(matchRawSelector(error));
  if (byName) return { ...byName, isUserRejection: false };

  // Fallback 2: classic Error(string) reverts (e.g. WETH "exceeds allowance").
  const byString = matchStringRevert(error);
  if (byString) return { ...byString, isUserRejection: false };

  // Nothing recognised — never leak the raw payload.
  return { title: 'Transaction failed', message: GENERIC_FALLBACK, isUserRejection: false };
}
