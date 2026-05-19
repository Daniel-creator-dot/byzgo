import { useEffect, useRef, useState, type ClipboardEvent, type KeyboardEvent } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, KeyRound, AlertCircle } from 'lucide-react';
import axios from 'axios';
import { Order } from '../../types';
import { LoadingIndicator } from '../UI';

function isPaymentReady(order: Order): boolean {
  if (order.payment_status === 'paid') return true;
  const ack = order.customer_payment_ack;
  return ack === 'cash' || ack === 'wallet' || ack === 'paystack';
}

function formatCompleteError(message: string | undefined): string {
  const m = (message || '').trim();
  if (!m) return 'Could not complete delivery. Try again.';
  if (/waiting for customer/i.test(m)) {
    return 'Customer must tap “I’ll pay cash” or pay in the app first — then they’ll see the 6-digit PIN.';
  }
  if (/invalid code/i.test(m)) {
    return 'Wrong PIN. Ask the customer to read the 6-digit code from their BytzGo app (Activity tab).';
  }
  if (/too many attempts/i.test(m)) {
    return m;
  }
  if (/mark arrived/i.test(m)) {
    return 'Tap “I’ve arrived” before completing delivery.';
  }
  return m;
}

export function DeliveryPinModal({
  order,
  onClose,
  onSuccess,
  onError,
}: {
  order: Order | null;
  onClose: () => void;
  onSuccess: () => void;
  onError: (msg: string) => void;
}) {
  const [code, setCode] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const paid = order?.payment_status === 'paid';
  const collectCash =
    !paid &&
    (order?.customer_payment_ack === 'cash' ||
      order?.payment_method === 'pay_on_delivery' ||
      order?.payment_status === 'cash_on_delivery');
  const paymentReady = order ? isPaymentReady(order) : false;
  const digits = code.padEnd(6, ' ').split('').slice(0, 6);

  useEffect(() => {
    if (!order) {
      setCode('');
      return;
    }
    const t = window.setTimeout(() => inputRef.current?.focus(), 200);
    return () => window.clearTimeout(t);
  }, [order?.id]);

  const applyCode = (raw: string) => {
    setCode(raw.replace(/\D/g, '').slice(0, 6));
  };

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
    if (!order || code.length !== 6) return;
    if (!paymentReady) {
      onError(
        'Customer must confirm payment in the BytzGo app first (pay or tap “I’ll pay cash”), then share their PIN.'
      );
      return;
    }
    setSubmitting(true);
    try {
      await axios.post(`/api/orders/${order.id}/complete-delivery`, { code });
      if (navigator.vibrate) navigator.vibrate(200);
      onSuccess();
      onClose();
      setCode('');
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      onError(formatCompleteError(msg));
      setCode('');
      inputRef.current?.focus();
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AnimatePresence>
      {order && (
        <>
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            className="fixed inset-0 bg-black/70 backdrop-blur-sm z-[300]"
            onClick={onClose}
          />
          <motion.div
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 28, stiffness: 280 }}
            className="fixed bottom-0 left-0 right-0 z-[310] bg-slate-900 border-t border-slate-700 rounded-t-[2rem] p-6 pb-10 max-w-lg mx-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <motion.div className="w-10 h-1 bg-slate-600 rounded-full mx-auto mb-5" />
            <div className="flex justify-between items-start mb-6">
              <div>
                <p className="text-[10px] font-black uppercase tracking-widest text-brand-green">Complete trip</p>
                <h3 className="text-xl font-black text-white mt-1">Enter delivery PIN</h3>
                <p className="text-xs text-slate-400 mt-1">Ask customer for their 6-digit code from the app</p>
              </div>
              <button type="button" onClick={onClose} className="p-2 rounded-xl bg-slate-800 text-slate-400">
                <X size={20} />
              </button>
            </div>

            <div className="p-4 rounded-2xl bg-slate-800/80 border border-slate-700 mb-4 flex justify-between items-center">
              <div>
                <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">Order</p>
                <p className="font-black text-lg">#{order.id.slice(-4)}</p>
              </div>
              <div className="text-right">
                <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">Total</p>
                <p className="font-mono font-black text-brand-green text-xl">₵{Number(order.total).toFixed(2)}</p>
                <p className="text-[9px] font-black uppercase tracking-widest mt-1 text-amber-400">
                  {collectCash ? 'Collect cash' : 'Paid online'}
                </p>
              </div>
            </div>

            {!paymentReady && (
              <div className="mb-4 p-3 rounded-xl bg-amber-500/15 border border-amber-500/40 flex gap-2 items-start">
                <AlertCircle size={16} className="text-amber-400 shrink-0 mt-0.5" />
                <p className="text-xs text-amber-100 leading-snug">
                  Customer hasn&apos;t confirmed payment in the app yet. Ask them to open{' '}
                  <strong>Activity</strong>, tap pay or &quot;I&apos;ll pay cash&quot;, then read you the PIN.
                </p>
              </div>
            )}

            <div className="relative mb-2">
              <div className="flex justify-center gap-2 pointer-events-none">
                {digits.map((d, i) => (
                  <div
                    key={i}
                    className={`w-11 h-14 flex items-center justify-center text-2xl font-black rounded-xl border-2 ${
                      i === code.length
                        ? 'border-brand-green bg-slate-800 text-white'
                        : d.trim()
                          ? 'border-slate-600 bg-slate-800 text-white'
                          : 'border-slate-600 bg-slate-800/50 text-slate-600'
                    }`}
                  >
                    {d.trim() || (i === code.length ? '|' : '')}
                  </div>
                ))}
              </div>
              <input
                ref={inputRef}
                type="tel"
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={6}
                value={code}
                onChange={(e) => applyCode(e.target.value)}
                onPaste={handlePaste}
                onKeyDown={handleKeyDown}
                aria-label="6-digit delivery PIN"
                className="absolute inset-0 w-full h-full opacity-0 cursor-text"
              />
            </div>
            <p className="text-center text-[10px] text-slate-500 mb-6">
              Tap the boxes to type, or paste all 6 digits
            </p>

            <button
              type="button"
              disabled={submitting || code.length !== 6}
              onClick={() => void submit()}
              className="w-full py-4 rounded-2xl bg-brand-green text-slate-950 font-black uppercase tracking-widest text-sm flex items-center justify-center gap-2 disabled:opacity-40 active:scale-[0.98]"
            >
              {submitting ? (
                <LoadingIndicator size="sm" />
              ) : (
                <>
                  <KeyRound size={18} />
                  Confirm delivery
                </>
              )}
            </button>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
