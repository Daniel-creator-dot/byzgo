import {
  type ButtonHTMLAttributes,
  type InputHTMLAttributes,
  type ReactNode,
} from 'react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { AlertCircle, Inbox } from 'lucide-react';

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function DarkCard({
  children,
  className,
  padding = true,
}: {
  children: ReactNode;
  className?: string;
  padding?: boolean;
}) {
  return (
    <div
      className={cn(
        'rounded-2xl border border-slate-800 bg-slate-900/80 backdrop-blur-sm shadow-xl',
        padding && 'p-5 sm:p-6',
        className,
      )}
    >
      {children}
    </div>
  );
}

export function DarkButton({
  children,
  className,
  variant = 'primary',
  size = 'md',
  type = 'button',
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'secondary' | 'danger' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
}) {
  const variants = {
    primary: 'bg-brand-blue text-white hover:bg-sky-400 shadow-lg shadow-brand-blue/20',
    secondary: 'bg-slate-800 text-slate-200 border border-slate-700 hover:bg-slate-700',
    danger: 'bg-red-600 text-white hover:bg-red-500',
    ghost: 'bg-transparent text-slate-400 hover:text-white hover:bg-slate-800',
  };
  const sizes = {
    sm: 'px-3 py-2 text-xs rounded-xl',
    md: 'px-5 py-3 text-sm rounded-xl',
    lg: 'px-6 py-4 text-base rounded-2xl',
  };
  return (
    <button
      type={type}
      className={cn(
        'font-bold transition-all active:scale-[0.98] disabled:opacity-50 disabled:pointer-events-none',
        variants[variant],
        sizes[size],
        className,
      )}
      {...props}
    >
      {children}
    </button>
  );
}

export function DarkInput({
  className,
  label,
  ...props
}: InputHTMLAttributes<HTMLInputElement> & { label?: string }) {
  return (
    <div className="space-y-1.5">
      {label && (
        <label className="text-[10px] font-bold uppercase tracking-wider text-slate-500 ml-1">
          {label}
        </label>
      )}
      <input
        className={cn(
          'w-full bg-slate-950 border border-slate-800 rounded-xl py-3.5 px-4 text-white font-medium text-sm',
          'placeholder:text-slate-600 focus:outline-none focus:border-brand-blue focus:ring-1 focus:ring-brand-blue/30',
          className,
        )}
        {...props}
      />
    </div>
  );
}

export function StatusBadge({
  children,
  tone = 'neutral',
}: {
  children: ReactNode;
  tone?: 'success' | 'warning' | 'danger' | 'info' | 'neutral';
}) {
  const tones = {
    success: 'bg-emerald-500/15 text-emerald-400 border-emerald-500/30',
    warning: 'bg-amber-500/15 text-amber-400 border-amber-500/30',
    danger: 'bg-red-500/15 text-red-400 border-red-500/30',
    info: 'bg-brand-blue/15 text-sky-400 border-brand-blue/30',
    neutral: 'bg-slate-800 text-slate-400 border-slate-700',
  };
  return (
    <span
      className={cn(
        'inline-flex items-center px-2.5 py-1 rounded-lg text-[10px] font-bold uppercase tracking-wide border',
        tones[tone],
      )}
    >
      {children}
    </span>
  );
}

export function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-16 px-6 text-center">
      <div className="w-16 h-16 rounded-2xl bg-slate-800 flex items-center justify-center mb-4">
        <Inbox className="text-slate-500" size={28} />
      </div>
      <h3 className="text-lg font-bold text-white mb-1">{title}</h3>
      {description && <p className="text-sm text-slate-500 max-w-xs">{description}</p>}
      {action && <div className="mt-6">{action}</div>}
    </div>
  );
}

export function ErrorBanner({
  message,
  onRetry,
}: {
  message: string;
  onRetry?: () => void;
}) {
  return (
    <div className="flex items-start gap-3 p-4 rounded-xl bg-red-500/10 border border-red-500/30 text-red-300 text-sm">
      <AlertCircle size={18} className="shrink-0 mt-0.5" />
      <div className="flex-1 min-w-0">
        <p className="font-medium">{message}</p>
        {onRetry && (
          <button
            type="button"
            onClick={onRetry}
            className="mt-2 text-xs font-bold text-red-200 underline"
          >
            Try again
          </button>
        )}
      </div>
    </div>
  );
}
