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

export function getCustomerTripHeadline(order: Order): string {
  const shop = Boolean(order.vendor_id?.trim());
  if (order.status === 'arrived') return 'Driver has arrived';
  if (order.status === 'picked_up') return shop ? 'On the way from pharmacy' : 'On the way to you';
  if (order.rider_id) {
    if (order.status === 'ready') return shop ? 'Rider heading to pharmacy' : 'Driver heading to pickup';
    if (order.status === 'preparing') return shop ? 'Rider heading to pharmacy' : 'Order being prepared';
    return 'Driver on the way';
  }
  if (order.status === 'ready') {
    return shop ? 'Finding a rider for your pharmacy order…' : 'Finding a biker nearby…';
  }
  if (order.status === 'preparing') {
    return shop ? 'Pharmacy preparing your order' : 'Preparing your order';
  }
  if (order.status === 'pending') {
    return shop ? 'Waiting for pharmacy confirmation' : 'Order placed';
  }
  return 'Order placed';
}

const TRIP_STEPS = [
  { key: 'placed', label: 'Placed' },
  { key: 'pickup', label: 'Pickup' },
  { key: 'transit', label: 'En route' },
  { key: 'arrived', label: 'Arrived' },
] as const;

function tripStepIndex(order: Order, isShop: boolean): number {
  if (order.status === 'arrived' || order.status === 'delivered') return 3;
  if (order.status === 'picked_up') return 2;
  if (isShop) {
    if (order.status === 'ready' || order.status === 'preparing') {
      return order.rider_id ? 2 : 1;
    }
    return 0;
  }
  if (['ready', 'preparing'].includes(order.status)) return 1;
  return 0;
}

export function TripProgressBar({ order, isCourier }: { order: Order; isCourier: boolean }) {
  const isShop = Boolean(order.vendor_id?.trim()) && !isCourier;
  const current = tripStepIndex(order, isShop);
  const labels = isCourier
    ? ['Placed', 'At pickup', 'Delivering', 'Arrived']
    : isShop
      ? ['Placed', 'Pharmacy confirmed', 'Rider & delivery', 'Arrived']
      : ['Placed', 'Ready', 'On the way', 'Arrived'];

  return (
    <div className="space-y-2">
      <motion.div className="flex gap-1">
        {TRIP_STEPS.map((_, i) => (
          <div
            key={i}
            className={cn(
              'h-1 flex-1 rounded-full transition-colors duration-500',
              i <= current ? 'bg-brand-green' : 'bg-slate-800'
            )}
          />
        ))}
      </motion.div>
      <div className="flex justify-between">
        {labels.map((label, i) => (
          <span
            key={label}
            className={cn(
              'text-[8px] font-black uppercase tracking-wider',
              i <= current ? 'text-brand-green' : 'text-slate-600'
            )}
          >
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}
