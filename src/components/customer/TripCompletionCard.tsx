import { useState } from 'react';
import { motion } from 'motion/react';
import { Copy, CreditCard, KeyRound, Wallet, Banknote, Check, ChevronDown, ChevronUp, LockOpen } from 'lucide-react';
import axios from 'axios';
import { Order } from '../../types';
import { openPaystackCheckout, paystackPaymentEmail } from '../../lib/paystackCheckout';
import { LoadingIndicator } from '../UI';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

function canShowDeliveryPin(order: Order): boolean {
  if (order.status !== 'arrived') return false;
  if (order.payment_status === 'paid') return true;
  return !!order.customer_payment_ack;
}

function needsPayment(order: Order): boolean {
  return order.status === 'arrived' && order.payment_status !== 'paid' && !order.customer_payment_ack;
}

export function TripCompletionCard({
  order,
  user,
  paystackKey,
  setPaystackKey,
  addNotification,
  refreshData,
  embedded = false,
  pinned = false,
}: {
  order: Order;
  user: { id: string; email: string; name: string; balance: number };
  paystackKey: string;
  setPaystackKey: (k: string) => void;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData: () => void | Promise<void>;
  embedded?: boolean;
  /** Fixed footer layout — compact, always visible without scrolling. */
  pinned?: boolean;
}) {
  const [paying, setPaying] = useState(false);
  const [copied, setCopied] = useState(false);
  const [showMomo, setShowMomo] = useState(false);

  if (order.status !== 'arrived') return null;

  const showPin = canShowDeliveryPin(order);
  const showPay = needsPayment(order);
  const total = Number(order.total);

  const copyPin = async () => {
    if (!order.delivery_code) return;
    try {
      await navigator.clipboard.writeText(order.delivery_code);
      setCopied(true);
      addNotification('PIN copied', 'success');
      setTimeout(() => setCopied(false), 2000);
    } catch {
      addNotification('Could not copy PIN', 'warning');
    }
  };

  const payWallet = async () => {
    setPaying(true);
    try {
      await axios.post(`/api/orders/${order.id}/pay-at-delivery`, { payment_method: 'wallet' });
      addNotification('Payment successful', 'success');
      await refreshData();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      addNotification(msg || 'Wallet payment failed', 'warning');
    } finally {
      setPaying(false);
    }
  };

  const payPaystack = async () => {
    let key = paystackKey;
    if (!key) {
      try {
        const res = await axios.get('/api/config/paystack');
        key = res.data.publicKey;
        setPaystackKey(key);
      } catch {
        addNotification('Payment system offline', 'warning');
        return;
      }
    }
    setPaying(true);
    try {
      await openPaystackCheckout({
        publicKey: key,
        email: paystackPaymentEmail(user),
        amountGhs: total,
        metadata: { type: 'order_delivery', order_id: order.id },
        onSuccess: async (reference) => {
          await axios.post(`/api/orders/${order.id}/pay-at-delivery`, {
            payment_reference: reference,
          });
          addNotification('Payment successful', 'success');
          await refreshData();
        },
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Payment failed';
      addNotification(msg, 'warning');
    } finally {
      setPaying(false);
    }
  };

  const ackCash = async () => {
    setPaying(true);
    try {
      await axios.post(`/api/orders/${order.id}/ack-cash`);
      addNotification('Cash payment noted — share your PIN with the driver', 'success');
      await refreshData();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      addNotification(msg || 'Could not confirm cash payment', 'warning');
    } finally {
      setPaying(false);
    }
  };

  const shellClass = pinned
    ? 'rounded-2xl border border-brand-green/40 bg-gradient-to-br from-slate-950 via-slate-900 to-slate-950 shadow-[0_-8px_32px_rgba(0,0,0,0.45)] overflow-hidden'
    : embedded
      ? 'rounded-2xl border border-amber-500/30 bg-amber-500/5 overflow-hidden'
      : 'mb-6 rounded-3xl border-2 border-brand-green/40 bg-gradient-to-br from-brand-green/10 to-slate-900 overflow-hidden';

  return (
    <motion.div
      initial={{ opacity: 0, y: pinned ? 16 : 12 }}
      animate={{ opacity: 1, y: 0 }}
      className={shellClass}
    >
      <div className={cn('p-4', pinned && showPay && 'pb-3')}>
        <div className="flex items-start gap-3">
          <div
            className={cn(
              'w-10 h-10 rounded-xl flex items-center justify-center shrink-0',
              showPay ? 'bg-brand-green/20' : 'bg-brand-green/15'
            )}
          >
            {showPay ? (
              <LockOpen size={20} className="text-brand-green" />
            ) : (
              <KeyRound size={20} className="text-brand-green" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p
              className={cn(
                'font-black leading-tight',
                pinned ? 'text-sm text-white' : 'text-lg text-white'
              )}
            >
              {showPay ? 'Driver arrived — pay to unlock PIN' : 'Share your delivery PIN'}
            </p>
            {showPay && (
              <p className="text-2xl font-black text-brand-green font-mono mt-1 tracking-tight">
                ₵{total.toFixed(2)}
              </p>
            )}
          </div>
        </div>

        {showPay && (
          <div className="mt-4 grid grid-cols-2 gap-2.5">
            <button
              type="button"
              disabled={paying || user.balance < total}
              onClick={payWallet}
              className="flex flex-col items-center justify-center gap-1 py-3 rounded-xl bg-brand-green text-slate-950 font-black disabled:opacity-40 transition-opacity"
            >
              <Wallet size={20} />
              <span className="text-xs">Wallet</span>
              <span className="text-[10px] font-bold opacity-70">₵{Number(user.balance).toFixed(2)}</span>
            </button>
            <button
              type="button"
              disabled={paying}
              onClick={ackCash}
              className="flex flex-col items-center justify-center gap-1 py-3 rounded-xl bg-white/10 border border-white/15 text-white font-black disabled:opacity-40"
            >
              <Banknote size={20} />
              <span className="text-xs">Cash</span>
              <span className="text-[10px] font-bold text-white/60">To driver</span>
            </button>
          </div>
        )}

        {showPay && user.balance < total && (
          <p className="text-[11px] text-center text-white/55 font-semibold mt-2">
            Wallet low — use cash or MoMo below
          </p>
        )}

        {showPay && (
          <button
            type="button"
            disabled={paying}
            onClick={() => setShowMomo((v) => !v)}
            className="w-full mt-2 flex items-center justify-center gap-1.5 text-xs font-bold text-white/75 py-1"
          >
            Pay with MoMo / card
            {showMomo ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
          </button>
        )}

        {showPay && showMomo && (
          <div className="mt-2 space-y-2">
            <button
              type="button"
              disabled={paying}
              onClick={payPaystack}
              className="w-full py-3 rounded-xl bg-white/10 border border-white/20 text-white font-black text-xs uppercase tracking-wider flex items-center justify-center gap-2"
            >
              {paying ? <LoadingIndicator size="sm" /> : <CreditCard size={16} />}
              Open Paystack checkout
            </button>
          </div>
        )}

        {showPin && order.delivery_code && (
          <>
            {showPay && <div className="border-t border-white/10 my-3" />}
            <p className="text-[10px] font-black uppercase tracking-[0.2em] text-center text-white/60 mb-2">
              Delivery PIN
            </p>
            <div className="flex justify-center gap-1.5 mb-2">
              {order.delivery_code.split('').map((digit, i) => (
                <span
                  key={i}
                  className={cn(
                    'flex items-center justify-center rounded-xl bg-white border-2 border-brand-green/50 font-black text-brand-green font-mono shadow-lg shadow-brand-green/10',
                    pinned ? 'w-9 h-11 text-xl' : 'w-11 h-14 text-2xl'
                  )}
                >
                  {digit}
                </span>
              ))}
            </div>
            <button
              type="button"
              onClick={copyPin}
              className="mx-auto flex items-center gap-2 px-4 py-1.5 rounded-full text-[11px] font-bold text-white/70 hover:text-white transition-colors"
            >
              {copied ? <Check size={14} className="text-brand-green" /> : <Copy size={14} />}
              {copied ? 'Copied' : 'Copy PIN'}
            </button>
          </>
        )}

        {paying && (
          <div className="flex justify-center pt-3">
            <LoadingIndicator size="sm" />
          </div>
        )}
      </div>
    </motion.div>
  );
}
