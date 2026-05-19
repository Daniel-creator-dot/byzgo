import { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronUp, MapPin, Navigation, Package, ShoppingBag } from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Order } from '../../types';
import {
  getDropoffCoords,
  getPickupCoordsForOrder,
  hasValidCoords,
} from '../../lib/riderTrip';
import { TripTrackingMap } from './TripTrackingMap';
import { TripCompletionCard } from './TripCompletionCard';
import { getCustomerTripHeadline, TripProgressBar } from './tripUi';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

const DEFAULT_CENTER = { lat: 5.6037, lng: -0.187 };

export function LiveTripTracker({
  order,
  vendors,
  riderLocation,
  user,
  paystackKey,
  setPaystackKey,
  addNotification,
  refreshData,
}: {
  order: Order;
  vendors: { id: string; name: string; lat?: number; lng?: number; address?: string }[];
  riderLocation: { lat: number; lng: number } | null;
  user: { id: string; email: string; name: string; balance: number };
  paystackKey: string;
  setPaystackKey: (k: string) => void;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData: () => void | Promise<void>;
}) {
  const [eta, setEta] = useState<string | null>(null);
  const [sheetExpanded, setSheetExpanded] = useState(order.status === 'arrived');

  const isCourier = (order as Order & { order_type?: string }).order_type === 'courier';
  const pickup = getPickupCoordsForOrder(order, vendors);
  const dropoff = getDropoffCoords(order);
  const vendor = vendors.find((v) => v.id === order.vendor_id);

  const pickupLocation =
    pickup && hasValidCoords(pickup.lat, pickup.lng)
      ? { lat: pickup.lat, lng: pickup.lng }
      : {
          lat: vendor?.lat ?? (order as Order & { pickup_lat?: number }).pickup_lat ?? DEFAULT_CENTER.lat,
          lng: vendor?.lng ?? (order as Order & { pickup_lng?: number }).pickup_lng ?? DEFAULT_CENTER.lng,
        };

  const destination =
    dropoff && hasValidCoords(dropoff.lat, dropoff.lng)
      ? { lat: dropoff.lat, lng: dropoff.lng }
      : { lat: order.lat ?? DEFAULT_CENTER.lat, lng: order.lng ?? DEFAULT_CENTER.lng };

  const headline = getCustomerTripHeadline(order);
  const pickupLabel = pickup?.label || vendor?.name || 'Pickup';
  const dropoffLabel = dropoff?.label || order.address || 'Your address';

  return (
    <div className="relative w-full">
      <motion.div
        layout
        className="relative h-[calc(100dvh-10.5rem)] min-h-[380px] max-h-[720px] bg-slate-950 overflow-hidden"
      >
        {!riderLocation && order.rider_id && (
          <motion.div className="absolute inset-0 z-20 flex items-center justify-center bg-slate-950/50 backdrop-blur-[2px] pointer-events-none">
            <div className="bg-slate-900/95 px-5 py-3 rounded-2xl border border-slate-700 flex items-center gap-3 shadow-xl">
              <div className="w-2.5 h-2.5 bg-brand-blue rounded-full animate-ping" />
              <p className="text-[10px] font-black uppercase tracking-widest text-slate-200">
                Connecting to driver GPS…
              </p>
            </div>
          </motion.div>
        )}

        <TripTrackingMap
          riderLocation={riderLocation}
          pickupLocation={pickupLocation}
          destination={destination}
          orderStatus={order.status}
          followRider={!!riderLocation}
          onEtaChange={setEta}
          showEtaBadge={false}
        />

        <div className="absolute top-0 left-0 right-0 z-10 p-3 pointer-events-none">
          <motion.div
            initial={{ opacity: 0, y: -8 }}
            animate={{ opacity: 1, y: 0 }}
            className="mx-auto max-w-lg pointer-events-auto"
          >
            <div className="rounded-2xl bg-slate-950/90 backdrop-blur-md border border-white/10 shadow-2xl px-4 py-3 flex items-center justify-between gap-3">
              <motion.div className="flex items-center gap-3 min-w-0">
                <div
                  className={cn(
                    'w-10 h-10 rounded-xl flex items-center justify-center shrink-0',
                    order.status === 'arrived' ? 'bg-amber-500/20' : 'bg-brand-green/20'
                  )}
                >
                  {isCourier ? (
                    <Package size={18} className="text-brand-blue" />
                  ) : (
                    <ShoppingBag size={18} className="text-brand-green" />
                  )}
                </div>
                <div className="min-w-0">
                  <p className="text-[9px] font-black uppercase tracking-widest text-slate-500">
                    Trip #{order.id.slice(-4)}
                  </p>
                  <p className="text-sm font-black text-white truncate">{headline}</p>
                </div>
              </motion.div>
              {eta && (
                <div className="text-right shrink-0">
                  <p className="text-[8px] font-black uppercase tracking-widest text-slate-500">ETA</p>
                  <p className="text-lg font-black text-brand-green font-mono leading-tight">{eta}</p>
                </div>
              )}
            </div>
          </motion.div>
        </div>
      </motion.div>

      <motion.div
        layout
        className="relative z-20 -mt-6 max-w-lg mx-auto px-4"
      >
        <button
          type="button"
          onClick={() => setSheetExpanded((v) => !v)}
          className="w-full flex flex-col items-center pt-2 pb-1"
          aria-expanded={sheetExpanded}
        >
          <span className="w-10 h-1 rounded-full bg-slate-600 mb-1" />
          <span className="text-[9px] font-black uppercase tracking-widest text-slate-500 flex items-center gap-1">
            {sheetExpanded ? 'Less' : 'Trip details'}
            <ChevronUp
              size={12}
              className={cn('transition-transform', sheetExpanded ? 'rotate-180' : '')}
            />
          </span>
        </button>

        <motion.div
          className={cn(
            'rounded-t-[1.75rem] bg-slate-900 border border-slate-800 border-b-0 shadow-[0_-12px_40px_rgba(0,0,0,0.45)] overflow-hidden',
            sheetExpanded ? '' : 'max-h-[220px]'
          )}
        >
          <div className="px-4 pt-2 pb-4 space-y-4">
            <TripProgressBar order={order} isCourier={isCourier} />

            <div className="space-y-2.5">
              <div className="flex items-start gap-3">
                <motion.div className="w-8 h-8 rounded-lg bg-brand-blue/20 flex items-center justify-center shrink-0 mt-0.5">
                  <MapPin size={14} className="text-brand-blue" />
                </motion.div>
                <div className="min-w-0">
                  <p className="text-[9px] font-black uppercase tracking-widest text-slate-500">Pickup</p>
                  <p className="text-sm font-bold text-white leading-snug">{pickupLabel}</p>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <motion.div className="w-8 h-8 rounded-lg bg-brand-green/20 flex items-center justify-center shrink-0 mt-0.5">
                  <Navigation size={14} className="text-brand-green" />
                </motion.div>
                <div className="min-w-0">
                  <p className="text-[9px] font-black uppercase tracking-widest text-slate-500">Drop-off</p>
                  <p className="text-sm font-bold text-white leading-snug">{dropoffLabel}</p>
                </div>
              </div>
            </div>

            <AnimatePresence>
              {order.status === 'arrived' && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  exit={{ opacity: 0, height: 0 }}
                >
                  <TripCompletionCard
                    order={order}
                    user={user}
                    paystackKey={paystackKey}
                    setPaystackKey={setPaystackKey}
                    addNotification={addNotification}
                    refreshData={refreshData}
                    embedded
                  />
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </motion.div>
      </motion.div>
    </div>
  );
}
