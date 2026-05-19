import { Check, CheckCircle2, AlertCircle } from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { motion } from 'motion/react';
import { Order } from '../../types';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function PaymentStatusBadge({ order }: { order: Order }) {
  if (!order.payment_status) return null;
  const isPaid = order.payment_status === 'paid';
  return (
    <span
      className={cn(
        'px-2.5 py-1 rounded-lg text-[8px] font-black uppercase tracking-widest inline-flex items-center gap-1',
        isPaid ? 'bg-emerald-500/20 text-emerald-400' : 'bg-amber-500/20 text-amber-400'
      )}
    >
      {isPaid ? <Check size={10} strokeWidth={4} /> : <AlertCircle size={10} strokeWidth={4} />}
      {isPaid ? 'Paid' : 'Pay on arrival'}
    </span>
  );
}

export function TrackingStep({ label, active }: { label: string; active: boolean }) {
  return (
    <motion.div className="flex items-center gap-3">
      <div
        className={cn(
          'w-7 h-7 rounded-xl flex items-center justify-center shrink-0',
          active ? 'bg-brand-green text-white' : 'bg-slate-800 text-slate-500 border border-slate-700'
        )}
      >
        <CheckCircle2 size={14} />
      </div>
      <span className={cn('text-sm font-bold', active ? 'text-white' : 'text-slate-500')}>{label}</span>
    </motion.div>
  );
}

export function statusLabel(status: string): string {
  return status.replace(/_/g, ' ');
}

export function statusColor(status: string): string {
  if (status === 'arrived') return 'bg-amber-500/20 text-amber-300 border-amber-500/40';
  if (status === 'delivered') return 'bg-brand-green/20 text-brand-green border-brand-green/40';
  if (status === 'picked_up') return 'bg-brand-blue/20 text-brand-blue border-brand-blue/40';
  return 'bg-slate-800 text-slate-400 border-slate-700';
}
