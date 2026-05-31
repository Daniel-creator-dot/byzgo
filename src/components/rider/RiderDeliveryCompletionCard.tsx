import { useState, type ClipboardEvent, type KeyboardEvent } from 'react';
import { motion } from 'motion/react';
import { KeyRound, Hourglass, Check } from 'lucide-react';
import axios from 'axios';
import type { Order } from '../../types';
import { LoadingIndicator } from '../UI';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { isRiderPaymentReady } from './riderTripUi';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

function formatCompleteError(message: string | undefined): string {
  const m = (message || '').trim();
  if (!m) return 'Could not complete delivery. Try again.';
  if (/waiting for customer/i.test(m)) {
    return 'Customer must confirm payment in the app first, then share their PIN.';
  }
  if (/invalid code/i.test(m)) {
    return 'Wrong PIN. Ask the customer for the 6-digit code from their app.';
  }
  if (/mark arrived/i.test(m)) {
    return 'Tap "I\'ve arrived" before completing delivery.';
  }
  return m;
}

/** Pinned footer — payment status + PIN entry (mirrors customer TripCompletionCard). */
export function RiderDeliveryCompletionCard({
  order,
  onSuccess,
  onError,
  pinned = false,
}: {
  order: Order;
  onSuccess: () => void | Promise<void>;
  onError: (msg: string) => void;
  pinned?: boolean;
}) {
  const [code, setCode] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const paymentReady = isRiderPaymentReady(order);
  const paid = order.payment_status === 'paid';
  const collectCash =
    !paid &&
    (order.customer_payment_ack === 'cash' ||
      order.payment_method === 'pay_on_delivery' ||
      order.payment_status === 'cash_on_delivery');
  const total = Number(order.total);

  const applyCode = (raw: string) => setCode(raw.replace(/\D/g, '').slice(0, 6));

  const handlePaste = (e: ClipboardEvent<HTMLInputElement>) => {
    const pasted = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 6);
    if (pasted) {
      e.preventDefault();
      applyCode(pasted);
    }
  };

  const handleKeyDown = (e: KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter' && code.length === 6 && !submitting) {
      e.preventDefault();
      void submit();
    }
  };

  const submit = async () => {
    if (code.length !== 6) return;
    if (!paymentReady) {
      onError(
        'Customer must confirm payment in the app first (pay or tap "I\'ll pay cash"), then share their PIN.'
      );
      return;
    }
    setSubmitting(true);
    try {
      await axios.post(`/api/orders/${order.id}/complete-delivery`, { code });
      if (navigator.vibrate) navigator.vibrate(200);
      setCode('');
      await onSuccess();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      onError(formatCompleteError(msg));
      setCode('');
    } finally {
      setSubmitting(false);
    }
  };

  const shellClass = pinned
    ? 'rounded-2xl border border-brand-green/40 bg-gradient-to-br from-slate-950 via-slate-900 to-slate-950 shadow-[0_-8px_32px_rgba(0,0,0,0.45)] overflow-hidden'
    : 'rounded-2xl border border-amber-500/30 bg-slate-800/60 overflow-hidden';

  return (
    <motion.div
      initial={{ opacity: 0, y: pinned ? 16 : 8 }}
      animate={{ opacity: 1, y: 0 }}
      className={shellClass}
    >
      <div className={cn('p-4', pinned && 'pb-3')}>
        <div className="flex items-start gap-3">
          <div
            className={cn(
              'w-10 h-10 rounded-xl flex items-center justify-center shrink-0',
              paymentReady ? 'bg-brand-green/20' : 'bg-amber-500/20'
            )}
          >
            {paymentReady ? (
              <KeyRound size={20} className="text-brand-green" />
            ) : (
              <Hourglass size={20} className="text-amber-400" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className={cn('font-black leading-tight', pinned ? 'text-sm text-white' : 'text-base text-white')}>
              {paymentReady ? 'Enter customer PIN' : 'Waiting for customer payment'}
            </p>
            <p className="text-2xl font-black text-brand-green font-mono mt-1 tracking-tight">
              ₵{total.toFixed(2)}
            </p>
            {collectCash && paymentReady && (
              <p className="text-[11px] text-white/55 font-semibold mt-0.5">Collect cash from customer</p>
            )}
          </div>
        </div>

        {!paymentReady ? (
          <p className="mt-3 text-xs text-slate-400 leading-snug">
            Ask the customer to open Activity, pay or tap &quot;I&apos;ll pay cash&quot;, then share their PIN.
          </p>
        ) : (
          <>
            <div className="relative mt-4 mb-2">
              <input
                type="tel"
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={6}
                value={code}
                onChange={(e) => applyCode(e.target.value)}
                onPaste={handlePaste}
                onKeyDown={handleKeyDown}
                placeholder="6-digit PIN"
                aria-label="6-digit delivery PIN"
                className="w-full py-3 px-4 rounded-xl bg-white/10 border border-white/15 text-white text-center text-xl font-black tracking-[0.35em] placeholder:text-white/30 placeholder:tracking-normal placeholder:text-sm placeholder:font-bold"
              />
            </div>
            <button
              type="button"
              disabled={submitting || code.length !== 6}
              onClick={() => void submit()}
              className="w-full py-3.5 rounded-xl bg-brand-green text-slate-950 font-black uppercase tracking-widest text-xs flex items-center justify-center gap-2 disabled:opacity-40"
            >
              {submitting ? (
                <LoadingIndicator size="sm" />
              ) : (
                <>
                  <Check size={16} />
                  Complete delivery
                </>
              )}
            </button>
          </>
        )}
      </div>
    </motion.div>
  );
}
