import { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { CheckCircle, Star } from 'lucide-react';
import axios from 'axios';
import { Order } from '../../types';

export function TripRatingModal({
  order,
  onClose,
  addNotification,
  refreshData,
}: {
  order: Order | null;
  onClose: () => void;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData: () => void | Promise<void>;
}) {
  const [stars, setStars] = useState(0);
  const [comment, setComment] = useState('');
  const [submitting, setSubmitting] = useState(false);

  if (!order) return null;

  const submit = async () => {
    if (stars < 1) return;
    setSubmitting(true);
    try {
      await axios.post(`/api/orders/${order.id}/rate`, { rating: stars, comment });
      addNotification('Thanks for your rating!', 'success');
      await refreshData();
      onClose();
    } catch {
      addNotification('Failed to save rating', 'warning');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <AnimatePresence>
      {order && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className="fixed inset-0 z-[200] flex items-end sm:items-center justify-center bg-black/60 p-4"
          onClick={onClose}
        >
          <motion.div
            initial={{ y: 40, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            exit={{ y: 40, opacity: 0 }}
            className="w-full max-w-md rounded-3xl bg-white p-6 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex flex-col items-center text-center">
              <div className="mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-brand-green/15">
                <CheckCircle className="text-brand-green" size={40} />
              </div>
              <h2 className="text-2xl font-black text-slate-900">Delivery complete!</h2>
              <p className="mt-2 text-sm text-slate-500">
                How was your trip with {(order as Order & { rider_name?: string }).rider_name || order.riderName || 'your biker'}?
              </p>
              <div className="mt-6 flex gap-2">
                {[1, 2, 3, 4, 5].map((star) => (
                  <button
                    key={star}
                    type="button"
                    disabled={submitting}
                    onClick={() => setStars(star)}
                    className="transition-transform hover:scale-110"
                  >
                    <Star
                      size={36}
                      className={
                        star <= stars
                          ? 'fill-yellow-400 text-yellow-400'
                          : 'text-slate-300'
                      }
                    />
                  </button>
                ))}
              </div>
              <textarea
                value={comment}
                onChange={(e) => setComment(e.target.value)}
                placeholder="Add a comment (optional)"
                rows={2}
                className="mt-4 w-full rounded-xl border border-slate-200 bg-slate-50 p-3 text-sm text-slate-800 outline-none focus:border-brand-green"
              />
              <button
                type="button"
                disabled={submitting || stars < 1}
                onClick={submit}
                className="mt-5 w-full rounded-2xl bg-brand-green py-3.5 text-sm font-black uppercase tracking-widest text-slate-950 disabled:opacity-40"
              >
                {submitting ? 'Saving…' : 'Submit rating'}
              </button>
              <button
                type="button"
                disabled={submitting}
                onClick={onClose}
                className="mt-3 text-xs font-bold uppercase tracking-widest text-slate-400 hover:text-slate-600"
              >
                Skip for now
              </button>
            </div>
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
