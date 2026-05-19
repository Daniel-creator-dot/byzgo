import { useState } from 'react';
import { motion } from 'motion/react';
import { Copy, CreditCard, KeyRound, Wallet, Banknote, Check } from 'lucide-react';
import axios from 'axios';
import { Order } from '../../types';
import { openPaystackCheckout, paystackPaymentEmail } from '../../lib/paystackCheckout';
import { LoadingIndicator } from '../UI';

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
}: {
  order: Order;
  user: { id: string; email: string; name: string; balance: number };
  paystackKey: string;
  setPaystackKey: (k: string) => void;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData: () => void | Promise<void>;
  embedded?: boolean;
}) {
  const [paying, setPaying] = useState(false);
  const [copied, setCopied] = useState(false);

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

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className={
        embedded
          ? 'rounded-2xl border border-amber-500/30 bg-amber-500/5 overflow-hidden'
          : 'mb-6 rounded-3xl border-2 border-brand-green/40 bg-gradient-to-br from-brand-green/10 to-slate-900 overflow-hidden'
      }
    >
      <div
        className={
          embedded
            ? 'p-4 border-b border-amber-500/20'
            : 'p-5 border-b border-brand-green/20 bg-brand-green/5'
        }
      >
        <p className="text-[10px] font-black uppercase tracking-[0.25em] text-brand-green animate-pulse">
          Driver has arrived
        </p>
        <h3 className="text-lg font-black text-white mt-1">
          {showPay ? 'Complete payment to get your PIN' : 'Share your delivery PIN'}
        </h3>
        <p className="text-xs text-slate-400 mt-1">
          {showPay
            ? 'Pay now, then give the 6-digit code to your driver so they can complete the trip.'
            : 'Tell your driver this code — they must enter it to finish the delivery.'}
        </p>
      </div>

      {showPay && (
        <div className="p-5 space-y-3 border-b border-slate-800">
          <p className="text-center font-mono text-2xl font-black text-white">₵{total.toFixed(2)}</p>
          <button
            type="button"
            disabled={paying || user.balance < total}
            onClick={payWallet}
            className="w-full py-3.5 rounded-2xl bg-slate-800 border border-slate-700 font-black text-[10px] uppercase tracking-widest flex items-center justify-center gap-2 disabled:opacity-40"
          >
            <Wallet size={16} className="text-brand-green" />
            Wallet · ₵{Number(user.balance).toFixed(2)}
          </button>
          <button
            type="button"
            disabled={paying}
            onClick={payPaystack}
            className="w-full py-3.5 rounded-2xl bg-white text-slate-950 font-black text-[10px] uppercase tracking-widest flex items-center justify-center gap-2"
          >
            {paying ? <LoadingIndicator size="sm" /> : <CreditCard size={16} />}
            Card / MoMo
          </button>
          <button
            type="button"
            disabled={paying}
            onClick={ackCash}
            className="w-full py-3.5 rounded-2xl bg-amber-500/20 border border-amber-500/40 text-amber-200 font-black text-[10px] uppercase tracking-widest flex items-center justify-center gap-2"
          >
            <Banknote size={16} />
            I&apos;ll pay cash to driver
          </button>
        </div>
      )}

      {showPin && order.delivery_code && (
        <div className="p-6 text-center">
          <div className="inline-flex items-center gap-2 text-[10px] font-black uppercase tracking-widest text-slate-500 mb-3">
            <KeyRound size={14} className="text-brand-green" />
            Delivery PIN
          </div>
          <div className="flex justify-center gap-2 mb-4">
            {order.delivery_code.split('').map((digit, i) => (
              <span
                key={i}
                className="w-11 h-14 flex items-center justify-center rounded-xl bg-slate-950 border-2 border-brand-green/50 text-2xl font-black text-brand-green font-mono shadow-lg shadow-brand-green/20"
              >
                {digit}
              </span>
            ))}
          </div>
          <button
            type="button"
            onClick={copyPin}
            className="inline-flex items-center gap-2 px-5 py-2.5 rounded-full bg-slate-800 border border-slate-700 text-[10px] font-black uppercase tracking-widest text-slate-300 hover:text-white transition-colors"
          >
            {copied ? <Check size={14} className="text-brand-green" /> : <Copy size={14} />}
            {copied ? 'Copied' : 'Copy PIN'}
          </button>
        </div>
      )}
    </motion.div>
  );
}
