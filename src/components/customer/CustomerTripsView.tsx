import { Fragment } from 'react';
import axios from 'axios';
import { Clock, Package, ShoppingBag, Star, AlertTriangle } from 'lucide-react';
import { motion } from 'motion/react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Order } from '../../types';
import { LiveTripTracker } from './LiveTripTracker';
import { TripCompletionCard } from './TripCompletionCard';
import { PaymentStatusBadge, TrackingStep, statusColor, statusLabel } from './tripUi';
import { isActiveCustomerTrip } from '../../lib/customerTrip';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const ACTIVE_STATUSES = ['pending', 'preparing', 'ready', 'picked_up', 'arrived'] as const;

function tripSortKey(order: Order): number {
  if (order.status === 'arrived') return 0;
  if (ACTIVE_STATUSES.includes(order.status as (typeof ACTIVE_STATUSES)[number]) && order.rider_id) return 1;
  if (order.status === 'delivered') return 3;
  return 2;
}

function isLiveTrackedTrip(order: Order): boolean {
  return isActiveCustomerTrip(order);
}

export function CustomerTripsView({
  tripHistory,
  vendors,
  riderLocations,
  user,
  paystackKey,
  setPaystackKey,
  addNotification,
  refreshData,
  onCancelOrder,
}: {
  tripHistory: Order[];
  vendors: { id: string; name: string; lat?: number; lng?: number; address?: string }[];
  riderLocations: Record<string, { lat: number; lng: number }>;
  user: { id: string; email: string; name: string; balance: number };
  paystackKey: string;
  setPaystackKey: (k: string) => void;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData: () => void | Promise<void>;
  onCancelOrder: (order: Order) => void;
}) {
  const sorted = [...tripHistory].sort((a, b) => tripSortKey(a) - tripSortKey(b));
  const liveTrip = sorted.find(isLiveTrackedTrip);
  const otherTrips = liveTrip ? sorted.filter((o) => o.id !== liveTrip.id) : sorted;

  if (tripHistory.length === 0) {
    return (
      <div className="text-center py-20 bg-slate-900/90 rounded-3xl border border-slate-800 border-dashed max-w-lg mx-auto">
        <Clock className="mx-auto text-slate-600 mb-4" size={48} />
        <p className="text-slate-400 font-black text-lg uppercase tracking-tight">No trips yet</p>
        <p className="text-slate-500 text-sm mt-2">Book a delivery from the Ride tab</p>
      </div>
    );
  }

  return (
    <motion.div className="pb-4">
      {liveTrip && (
        <LiveTripTracker
          order={liveTrip}
          vendors={vendors}
          riderLocation={liveTrip.rider_id ? riderLocations[liveTrip.rider_id] ?? null : null}
          user={user}
          paystackKey={paystackKey}
          setPaystackKey={setPaystackKey}
          addNotification={addNotification}
          refreshData={refreshData}
        />
      )}

      {otherTrips.length > 0 && (
        <div className={cn('space-y-4 max-w-lg mx-auto', liveTrip ? 'mt-6 px-0' : '')}>
          {liveTrip && (
            <p className="text-[10px] font-black uppercase tracking-widest text-slate-500 px-1">
              Other trips
            </p>
          )}
          {otherTrips.map((order) => (
            <Fragment key={order.id}>
              <TripHistoryCard
                order={order}
                vendors={vendors}
                user={user}
                paystackKey={paystackKey}
                setPaystackKey={setPaystackKey}
                addNotification={addNotification}
                refreshData={refreshData}
                onCancelOrder={onCancelOrder}
              />
            </Fragment>
          ))}
        </div>
      )}
    </motion.div>
  );
}

function TripHistoryCard({
  order,
  vendors,
  user,
  paystackKey,
  setPaystackKey,
  addNotification,
  refreshData,
  onCancelOrder,
}: {
  order: Order;
  vendors: { id: string; name: string; lat?: number; lng?: number }[];
  user: { id: string; email: string; name: string; balance: number };
  paystackKey: string;
  setPaystackKey: (k: string) => void;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData: () => void | Promise<void>;
  onCancelOrder: (order: Order) => void;
}) {
  const vendor = vendors.find((v) => v.id === order.vendor_id);
  const isCourier = (order as Order & { order_type?: string }).order_type === 'courier';
  const isShop = Boolean(order.vendor_id?.trim()) && !isCourier;
  const createdAt = (order as Order & { created_at?: string }).created_at || order.createdAt;

  return (
    <motion.article
      layout
      initial={{ opacity: 0, y: 12 }}
      animate={{ opacity: 1, y: 0 }}
      className={cn(
        'rounded-3xl border overflow-hidden',
        order.status === 'arrived'
          ? 'border-amber-500/50 bg-slate-900 shadow-lg shadow-amber-500/10'
          : 'border-slate-800 bg-slate-900/90'
      )}
    >
      <div className="p-5">
        <motion.div className="flex justify-between items-start gap-3 mb-4">
          <div className="flex items-center gap-3 min-w-0">
            <motion.div className="w-11 h-11 bg-slate-800 rounded-2xl flex items-center justify-center text-white shrink-0">
              {isCourier ? <Package size={20} /> : <ShoppingBag size={20} />}
            </motion.div>
            <motion.div className="min-w-0">
              <h4 className="font-black text-lg tracking-tight">#{order.id.slice(-4)}</h4>
              {order.vendor_id && (
                <p className="text-[10px] font-black text-brand-blue uppercase tracking-widest truncate">
                  {vendor?.name || 'Order'}
                </p>
              )}
              <p className="text-[10px] font-mono text-slate-500 uppercase">
                {createdAt ? new Date(createdAt).toLocaleDateString() : ''}
              </p>
            </motion.div>
          </div>
          <div className="flex flex-col items-end gap-1.5 shrink-0">
            <span
              className={cn(
                'px-3 py-1 rounded-lg text-[9px] font-black uppercase tracking-widest border',
                statusColor(order.status)
              )}
            >
              {statusLabel(order.status)}
            </span>
            <PaymentStatusBadge order={order} />
          </div>
        </motion.div>

        {order.status === 'arrived' && order.rider_id && (
          <TripCompletionCard
            order={order}
            user={user}
            paystackKey={paystackKey}
            setPaystackKey={setPaystackKey}
            addNotification={addNotification}
            refreshData={refreshData}
          />
        )}

        {order.status === 'pending' && !order.rider_id && (
          <button
            type="button"
            onClick={() => onCancelOrder(order)}
            className="mb-4 w-full py-3 bg-red-500/10 text-red-400 rounded-2xl font-black uppercase tracking-widest text-[10px] border border-red-500/30 hover:bg-red-500/20 transition-colors active:scale-[0.98]"
          >
            Cancel order
          </button>
        )}

        <div className="space-y-3 border-l-2 border-slate-800 ml-2 pl-5">
          <TrackingStep
            label="Order placed"
            active={['pending', 'preparing', 'ready', 'picked_up', 'arrived', 'delivered'].includes(
              order.status
            )}
          />
          <TrackingStep
            label={isCourier ? 'Rider at pickup' : isShop ? 'Pharmacy confirmed' : 'Preparing'}
            active={
              isShop
                ? ['preparing', 'ready', 'picked_up', 'arrived', 'delivered'].includes(order.status)
                : ['preparing', 'ready', 'picked_up', 'arrived', 'delivered'].includes(order.status)
            }
          />
          <TrackingStep
            label={isShop ? 'Rider delivering' : 'On the way'}
            active={['picked_up', 'arrived', 'delivered'].includes(order.status)}
          />
          <TrackingStep
            label="Driver arrived"
            active={['arrived', 'delivered'].includes(order.status)}
          />
          <TrackingStep
            label={isCourier ? 'Delivered' : isShop ? 'Delivered' : 'Enjoy your meal'}
            active={order.status === 'delivered'}
          />
        </div>

        {order.status === 'delivered' && (
          <div className="mt-5 pt-5 border-t border-slate-800">
            <p className="text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2">
              Rate your trip
            </p>
            {(order as Order & { rating?: number }).rating ? (
              <div className="flex items-center gap-1">
                {[1, 2, 3, 4, 5].map((star) => (
                  <Star
                    key={star}
                    size={16}
                    className={cn(
                      star <= ((order as Order & { rating?: number }).rating || 0)
                        ? 'text-yellow-400 fill-yellow-400'
                        : 'text-slate-600'
                    )}
                  />
                ))}
              </div>
            ) : (
              <div className="flex items-center gap-1">
                {[1, 2, 3, 4, 5].map((star) => (
                  <button
                    key={star}
                    type="button"
                    onClick={async () => {
                      try {
                        await axios.post(`/api/orders/${order.id}/rate`, { rating: star, comment: '' });
                        addNotification('Thanks for your rating!', 'success');
                        await refreshData();
                      } catch {
                        addNotification('Failed to save rating', 'warning');
                      }
                    }}
                    className="hover:scale-110 transition-transform"
                  >
                    <Star size={22} className="text-slate-600 hover:text-yellow-400 transition-colors" />
                  </button>
                ))}
              </div>
            )}
            <button
              type="button"
              className="mt-4 text-[9px] font-black uppercase tracking-widest text-slate-500 hover:text-red-400 flex items-center gap-1.5"
            >
              <AlertTriangle size={12} /> Report a problem
            </button>
          </div>
        )}
      </div>
    </motion.article>
  );
}
