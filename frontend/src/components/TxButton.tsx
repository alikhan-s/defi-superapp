import React from 'react';
import { Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';

interface TxButtonProps extends Omit<React.ButtonHTMLAttributes<HTMLButtonElement>, 'onClick'> {
  onClick?: () => Promise<any> | void;
  isPending?: boolean;
  isConfirming?: boolean;
  text: string;
  loadingText?: string;
  confirmingText?: string;
  variant?: 'primary' | 'secondary' | 'danger';
}

export const TxButton: React.FC<TxButtonProps> = ({
  onClick,
  isPending = false,
  isConfirming = false,
  text,
  loadingText = 'Confirm in Wallet...',
  confirmingText = 'Confirming Tx...',
  variant = 'primary',
  disabled,
  className = '',
  ...props
}) => {
  const [internalLoading, setInternalLoading] = React.useState(false);

  const handleClick = async (_e: React.MouseEvent<HTMLButtonElement>) => {
    if (!onClick) return;

    try {
      setInternalLoading(true);
      await onClick();
    } catch (error: any) {
      console.error('Tx error:', error);
      const errorMessage = error?.shortMessage || error?.message || 'Transaction failed';
      // Filter out user rejection errors so we don't show a toast for them
      if (!errorMessage.toLowerCase().includes('user rejected')) {
        toast.error(errorMessage, {
          style: {
            background: '#13141a',
            color: '#fff',
            border: '1px solid rgba(255,255,255,0.1)',
          },
        });
      }
    } finally {
      setInternalLoading(false);
    }
  };

  const isLoading = isPending || internalLoading;
  const isTxActive = isLoading || isConfirming;
  const isDisabled = disabled || isTxActive;

  const variantStyles = {
    primary: 'bg-gradient-to-r from-indigo-500 to-cyan-500 shadow-indigo-500/25 text-white',
    secondary: 'bg-[#13141a] border border-white/10 hover:bg-white/5 text-white',
    danger: 'bg-rose-500/10 border border-rose-500/20 text-rose-500 hover:bg-rose-500/20',
  };

  let displayText = text;
  if (isConfirming) displayText = confirmingText;
  else if (isLoading) displayText = loadingText;

  return (
    <button
      onClick={handleClick}
      disabled={isDisabled}
      className={`relative group overflow-hidden rounded-xl p-[1px] transition-all hover:scale-[1.02] active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 ${className}`}
      {...props}
    >
      {variant === 'primary' && !isDisabled && (
        <div className="absolute inset-0 bg-white/20 opacity-0 group-hover:opacity-100 transition-opacity" />
      )}
      
      <div className={`flex items-center justify-center h-12 w-full rounded-[11px] font-semibold shadow-lg transition-colors px-6 ${variantStyles[variant]}`}>
        {isTxActive ? (
          <div className="flex items-center gap-2">
            <Loader2 className="w-5 h-5 animate-spin" />
            <span>{displayText}</span>
          </div>
        ) : (
          displayText
        )}
      </div>
    </button>
  );
};
