import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { motion } from 'motion/react';
import type { Order } from '../../types';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function riderTripStepIndex(status: string): number {
  if (status === 'arrived') return 3;
  if (status === 'picked_up') return 2;
  if (status === 'ready') return 1;
  return 0;
}

const RIDER_STEP_LABELS = ['Accepted', 'Picked up', 'Arrived', 'Complete'] as const;

export function RiderTripProgressBar({ order }: { order: Order }) {
  const current = riderTripStepIndex(order.status);
  const label = RIDER_STEP_LABELS[Math.max(0, current - 1)] ?? RIDER_STEP_LABELS[0];

  return (
    <div className="space-y-1.5">
      <motion.div className="flex gap-0.5">
        {RIDER_STEP_LABELS.map((_, i) => (
          <div
            key={i}
            className={cn(
              'h-1 flex-1 rounded-full transition-colors duration-500',
              i < current ? 'bg-brand-green' : 'bg-slate-800'
            )}
          />
        ))}
      </motion.div>
      <div className="flex items-center justify-between">
        <span className="text-xs font-black text-brand-green">{label}</span>
        <span className="text-[9px] font-black uppercase tracking-widest text-brand-green/80 bg-brand-green/10 px-2 py-0.5 rounded-md">
          {order.status.replace(/_/g, ' ')}
        </span>
      </div>
    </div>
  );
}

export function getRiderTripHeadline(order: Order): string {
  if (order.status === 'ready') return 'Head to pickup';
  if (order.status === 'picked_up') return 'Head to drop-off';
  if (order.status === 'arrived') return 'Enter customer PIN';
  return 'Active delivery';
}

/** Max height class for the drive bottom sheet during active trips. */
export function riderTrackingSheetMaxClass(order: Order | null, navigating: boolean): string {
  if (!order) return navigating ? 'max-h-[32vh]' : 'max-h-[48vh]';
  if (order.status === 'arrived') return 'max-h-[46vh]';
  if (order.status === 'picked_up' || order.status === 'ready') return 'max-h-[28vh]';
  return navigating ? 'max-h-[32vh]' : 'max-h-[48vh]';
}

export function isRiderPaymentReady(order: Order): boolean {
  if (order.payment_status === 'paid') return true;
  const ack = order.customer_payment_ack;
  return ack === 'cash' || ack === 'wallet' || ack === 'paystack';
}
