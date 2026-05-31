import { useState } from 'react';
import { motion } from 'motion/react';
import { Award, Leaf, Send, Star } from 'lucide-react';
import axios from 'axios';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Order } from '../../types';
import { LoadingIndicator } from '../UI';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export type DriverTier = 'gold' | 'silver' | 'bronze' | 'new';

/**
 * Uber Eats / Bolt Food-style driver tier. The more stars a driver keeps
 * (across enough rated trips), the higher they climb toward Gold.
 */
export function driverTierFrom(avg: number | null | undefined, count: number): DriverTier {
  if (avg == null || !Number.isFinite(avg) || count < 3) return 'new';
  if (avg >= 4.8 && count >= 20) return 'gold';
  if (avg >= 4.5 && count >= 8) return 'silver';
  if (avg >= 4.0) return 'bronze';
  return 'new';
}

export function driverTierForOrder(order: Order): DriverTier {
  if (order.riderTier) return order.riderTier as DriverTier;
  return driverTierFrom(order.riderAvgRating, order.riderRatingCount ?? 0);
}

const TIER_META: Record<DriverTier, { label: string; classes: string; lightClasses: string; icon: 'award' | 'leaf' }> = {
  gold: { label: 'Gold driver', classes: 'bg-amber-400/15 text-amber-300 border-amber-400/50', lightClasses: 'bg-amber-50 text-amber-600 border-amber-300', icon: 'award' },
  silver: { label: 'Silver driver', classes: 'bg-slate-400/15 text-slate-300 border-slate-400/50', lightClasses: 'bg-slate-100 text-slate-600 border-slate-300', icon: 'award' },
  bronze: { label: 'Bronze driver', classes: 'bg-orange-500/15 text-orange-300 border-orange-500/50', lightClasses: 'bg-orange-50 text-orange-600 border-orange-300', icon: 'award' },
  new: { label: 'New driver', classes: 'bg-brand-blue/15 text-brand-blue border-brand-blue/50', lightClasses: 'bg-blue-50 text-brand-blue border-blue-200', icon: 'leaf' },
};

export function DriverTierBadge({
  tier,
  avgRating,
  ratingCount,
  className,
  light,
}: {
  tier: DriverTier;
  avgRating?: number | null;
  ratingCount?: number;
  className?: string;
  light?: boolean;
}) {
  const meta = TIER_META[tier];
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 px-2.5 py-1 rounded-full border text-[10px] font-black uppercase tracking-wider',
        light ? meta.lightClasses : meta.classes,
        className
      )}
    >
      {meta.icon === 'award' ? <Award size={12} /> : <Leaf size={12} />}
      {meta.label}
      {avgRating != null && (ratingCount ?? 0) > 0 && (
        <span className="inline-flex items-center gap-0.5">
          <Star size={11} className="fill-current" />
          {avgRating.toFixed(1)}
        </span>
      )}
    </span>
  );
}

/**
 * Post-delivery driver rating. High ratings push the driver up the Gold ladder.
 */
export function RateDriverCard({
  order,
  addNotification,
  refreshData,
}: {
  order: Order;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData: () => void | Promise<void>;
}) {
  const alreadyRated = (order.rating ?? 0) > 0;
  const [stars, setStars] = useState(0);
  const [hover, setHover] = useState(0);
  const [comment, setComment] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const given = alreadyRated ? (order.rating ?? 0) : hover || stars;
  const driverName = order.riderName || order.rider_name || 'your driver';

  const submit = async () => {
    if (stars < 1) {
      addNotification('Tap a star to rate your driver', 'warning');
      return;
    }
    setSubmitting(true);
    try {
      await axios.post(`/api/orders/${order.id}/rate`, {
        rating: stars,
        ...(comment.trim() ? { comment: comment.trim() } : {}),
      });
      addNotification('Thanks for rating your driver!', 'success');
      await refreshData();
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      addNotification(msg || 'Could not save rating', 'warning');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className="rounded-2xl border border-brand-green/40 bg-gradient-to-br from-brand-green/10 to-slate-900 p-5"
    >
      <div className="flex items-center justify-between gap-3 mb-1">
        <h3 className="text-base font-black text-white">
          {alreadyRated ? 'Delivery complete — thank you!' : `Rate ${driverName}`}
        </h3>
        {order.rider_id && <DriverTierBadge tier={driverTierForOrder(order)} />}
      </div>
      <p className="text-xs text-slate-400 mb-4">
        {alreadyRated
          ? `You rated this trip ${order.rating} of 5 stars.`
          : 'More stars help great drivers reach Gold status.'}
      </p>

      <div className="flex justify-center gap-2 mb-4">
        {[1, 2, 3, 4, 5].map((s) => (
          <button
            key={s}
            type="button"
            disabled={alreadyRated || submitting}
            onMouseEnter={() => !alreadyRated && setHover(s)}
            onMouseLeave={() => !alreadyRated && setHover(0)}
            onClick={() => !alreadyRated && setStars(s)}
            className="disabled:cursor-default"
            aria-label={`${s} star${s > 1 ? 's' : ''}`}
          >
            <Star
              size={36}
              className={cn(
                'transition-colors',
                s <= given ? 'text-amber-400 fill-amber-400' : 'text-slate-600'
              )}
            />
          </button>
        ))}
      </div>

      {!alreadyRated && (
        <textarea
          value={comment}
          onChange={(e) => setComment(e.target.value)}
          disabled={submitting}
          rows={2}
          maxLength={500}
          placeholder="Add a note for your driver (optional)"
          className="w-full mb-3 rounded-2xl bg-slate-900/60 border border-slate-700 text-white text-xs px-4 py-3 placeholder:text-slate-500 focus:outline-none focus:border-brand-green/60 resize-none"
        />
      )}

      {!alreadyRated && (
        <button
          type="button"
          disabled={submitting || stars < 1}
          onClick={submit}
          className="w-full py-3.5 rounded-2xl bg-brand-green text-slate-950 font-black text-[11px] uppercase tracking-widest flex items-center justify-center gap-2 disabled:opacity-40"
        >
          {submitting ? <LoadingIndicator size="sm" /> : <Send size={16} />}
          Submit rating
        </button>
      )}
    </motion.div>
  );
}
