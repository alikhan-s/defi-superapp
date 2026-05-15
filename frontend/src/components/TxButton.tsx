import React, { useEffect, useRef } from 'react';
import { Loader2, ExternalLink, AlertTriangle } from 'lucide-react';
import toast from 'react-hot-toast';
import { useSimulateContract, useWriteContract, useWaitForTransactionReceipt } from 'wagmi';
import { arbitrumSepolia } from 'wagmi/chains';
import type { Abi } from 'viem';

import { parseTxError } from '../lib/errors';

/** A single contract write the button will simulate and submit. */
export interface TxRequest {
  address: `0x${string}`;
  abi: Abi;
  functionName: string;
  args?: readonly unknown[];
  value?: bigint;
}

interface TxButtonProps {
  /**
   * The write to perform. When omitted (or `enabled` is false) the button is
   * inert and no simulation runs — let the page render a disabled placeholder
   * for empty/invalid input states.
   */
  request?: TxRequest;
  /** Gate pre-flight simulation (e.g. only once the form input is valid). */
  enabled?: boolean;
  text: string;
  loadingText?: string;
  confirmingText?: string;
  successMessage?: string;
  variant?: 'primary' | 'secondary' | 'danger';
  className?: string;
  disabled?: boolean;
  /** Called once the transaction is confirmed on-chain. */
  onSuccess?: (hash: `0x${string}`) => void;
}

const TOAST_STYLE = {
  background: '#13141a',
  color: '#fff',
  border: '1px solid rgba(255,255,255,0.1)',
};

const EXPLORER = arbitrumSepolia.blockExplorers?.default.url ?? 'https://sepolia.arbiscan.io';

const variantStyles = {
  primary: 'bg-gradient-to-r from-indigo-500 to-cyan-500 shadow-indigo-500/25 text-white',
  secondary: 'bg-[#13141a] border border-white/10 hover:bg-white/5 text-white',
  danger: 'bg-rose-500/10 border border-rose-500/20 text-rose-500 hover:bg-rose-500/20',
};

function ArbiscanLink({ hash, message }: { hash: `0x${string}`; message: string }) {
  return (
    <span className="flex flex-col gap-1">
      <span>{message}</span>
      <a
        href={`${EXPLORER}/tx/${hash}`}
        target="_blank"
        rel="noopener noreferrer"
        className="inline-flex items-center gap-1 text-cyan-400 hover:text-cyan-300 underline text-xs"
      >
        View on Arbiscan <ExternalLink size={12} />
      </a>
    </span>
  );
}

export const TxButton: React.FC<TxButtonProps> = ({
  request,
  enabled = true,
  text,
  loadingText = 'Confirm in wallet…',
  confirmingText = 'Confirming…',
  successMessage = 'Transaction confirmed',
  variant = 'primary',
  className = '',
  disabled,
  onSuccess,
}) => {
  const simEnabled = enabled && !disabled && !!request;

  // ── Pre-flight simulation ────────────────────────────────────────────────
  // wagmi can't infer payability (and thus the shape of `value`) when
  // `functionName` is a plain string, so the config is built loosely here. The
  // simulation itself validates the call against the real contract.
  const { data: simulation, error: simError, isLoading: isSimulating } = useSimulateContract(
    (request
      ? { ...request, query: { enabled: simEnabled } }
      : { query: { enabled: false } }) as Parameters<typeof useSimulateContract>[0],
  );

  // ── Submission + confirmation ─────────────────────────────────────────────
  const { writeContract, data: hash, isPending, error: writeError, reset } = useWriteContract();
  const { isLoading: isConfirming, isSuccess, isError: isReceiptError, error: receiptError } =
    useWaitForTransactionReceipt({ hash });

  const toastId = useRef<string | undefined>(undefined);

  // Submitted → confirming: swap the wallet-prompt toast for a "submitted" one.
  useEffect(() => {
    if (hash && isConfirming) {
      toastId.current = toast.loading(
        <span className="flex flex-col gap-1">
          <span>Transaction submitted</span>
          <a
            href={`${EXPLORER}/tx/${hash}`}
            target="_blank"
            rel="noopener noreferrer"
            className="inline-flex items-center gap-1 text-cyan-400 hover:text-cyan-300 underline text-xs"
          >
            Track on Arbiscan <ExternalLink size={12} />
          </a>
        </span>,
        { id: toastId.current, style: TOAST_STYLE },
      );
    }
  }, [hash, isConfirming]);

  // Confirmed.
  useEffect(() => {
    if (isSuccess && hash) {
      toast.success(<ArbiscanLink hash={hash} message={successMessage} />, { id: toastId.current, style: TOAST_STYLE, duration: 8000 });
      toastId.current = undefined;
      onSuccess?.(hash);
      reset();
    }
    // onSuccess intentionally excluded to avoid re-firing on identity changes.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [isSuccess, hash]);

  // Submission error or on-chain revert → friendly toast.
  useEffect(() => {
    const err = writeError ?? (isReceiptError ? receiptError : undefined);
    if (!err) return;
    const parsed = parseTxError(err);
    if (parsed.isUserRejection) {
      if (toastId.current) toast.dismiss(toastId.current);
    } else {
      toast.error(
        <span className="flex flex-col">
          <span className="font-semibold">{parsed.title}</span>
          <span className="text-sm text-gray-300">{parsed.message}</span>
        </span>,
        { id: toastId.current, style: TOAST_STYLE, duration: 6000 },
      );
    }
    toastId.current = undefined;
    reset();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [writeError, isReceiptError, receiptError]);

  const handleClick = () => {
    if (!request) return;
    // Prefer the validated simulation request; fall back to the raw request if
    // simulation hasn't resolved yet but the user insists.
    if (simError) {
      const parsed = parseTxError(simError);
      toast.error(
        <span className="flex flex-col">
          <span className="font-semibold">{parsed.title}</span>
          <span className="text-sm text-gray-300">{parsed.message}</span>
        </span>,
        { style: TOAST_STYLE, duration: 6000 },
      );
      return;
    }
    toastId.current = toast.loading('Confirm in your wallet…', { style: TOAST_STYLE });
    const simRequest = (simulation as { request?: Parameters<typeof writeContract>[0] } | undefined)?.request;
    if (simRequest) {
      writeContract(simRequest);
    } else {
      writeContract({
        address: request.address,
        abi: request.abi,
        functionName: request.functionName,
        args: request.args,
        value: request.value,
      } as Parameters<typeof writeContract>[0]);
    }
  };

  const isBusy = isPending || isConfirming;
  // Block submission when we know the tx will revert.
  const blockedBySim = simEnabled && !!simError;
  const isDisabled = disabled || isBusy || !request || !enabled || blockedBySim;

  let label = text;
  if (isConfirming) label = confirmingText;
  else if (isPending) label = loadingText;
  else if (isSimulating && simEnabled) label = 'Checking…';

  const simReason = blockedBySim ? parseTxError(simError) : undefined;

  return (
    <div className="w-full">
      <button
        onClick={handleClick}
        disabled={isDisabled}
        title={simReason ? `${simReason.title}: ${simReason.message}` : undefined}
        className={`relative group overflow-hidden rounded-xl p-[1px] w-full transition-all hover:scale-[1.02] active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 ${className}`}
      >
        {variant === 'primary' && !isDisabled && (
          <div className="absolute inset-0 bg-white/20 opacity-0 group-hover:opacity-100 transition-opacity" />
        )}
        <div
          className={`flex items-center justify-center h-12 w-full rounded-[11px] font-semibold shadow-lg transition-colors px-6 ${variantStyles[variant]}`}
        >
          {isBusy ? (
            <span className="flex items-center gap-2">
              <Loader2 className="w-5 h-5 animate-spin" />
              <span>{label}</span>
            </span>
          ) : (
            label
          )}
        </div>
      </button>

      {simReason && (
        <p className="mt-2 flex items-start gap-1.5 text-xs text-rose-400">
          <AlertTriangle size={14} className="shrink-0 mt-0.5" />
          <span>{simReason.message}</span>
        </p>
      )}
    </div>
  );
};
