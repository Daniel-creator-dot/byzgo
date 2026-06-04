import { useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronUp, MapPin, Navigation, Package, ShoppingBag, Phone, MessageCircle } from 'lucide-react';
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
import {
  customerEtaLabel,
  fetchDirectionsEta,
  fetchNearbyRiders,
  fetchRiderLocation,
  isCustomerSearchingBiker,
} from '../../lib/customerTrip';
import { EtaCountdown } from './EtaCountdown';
import { DriverTierBadge, RateDriverCard, driverTierForOrder } from '../shared/DriverTier';

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
  const [etaExpiresAt, setEtaExpiresAt] = useState<number | null>(null);
  const [searchEta, setSearchEta] = useState<string | null>(null);
  const [searchExpiresAt, setSearchExpiresAt] = useState<number | null>(null);
  const [localRiderLoc, setLocalRiderLoc] = useState<{ lat: number; lng: number } | null>(null);
  const [sheetExpanded, setSheetExpanded] = useState(false);

  const isArrived = order.status === 'arrived';
  const isDelivered = order.status === 'delivered';
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

  const searching = isCustomerSearchingBiker(order);
  const effectiveRiderLocation = riderLocation ?? localRiderLoc;

  useEffect(() => {
    if (!searching) {
      setSearchEta(null);
      setSearchExpiresAt(null);
      return;
    }
    let cancelled = false;
    const tick = async () => {
      try {
        const riders = await fetchNearbyRiders(pickupLocation.lat, pickupLocation.lng);
        if (cancelled || !riders.length) {
          if (!cancelled) {
            setSearchEta(null);
            setSearchExpiresAt(null);
          }
          return;
        }
        const nearest = riders[0];
        const dir = await fetchDirectionsEta(
          { lat: nearest.lat, lng: nearest.lng },
          pickupLocation
        );
        if (!cancelled && dir) {
          setSearchEta(dir.eta);
          setSearchExpiresAt(dir.expires_at);
        }
      } catch {
        /* ignore */
      }
    };
    void tick();
    const id = setInterval(tick, 10000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [searching, pickupLocation.lat, pickupLocation.lng]);

  useEffect(() => {
    if (!order.rider_id || searching) {
      setLocalRiderLoc(null);
      return;
    }
    if (riderLocation) return;
    let cancelled = false;
    const tick = async () => {
      const loc = await fetchRiderLocation(order.rider_id!);
      if (!cancelled && loc) setLocalRiderLoc(loc);
    };
    void tick();
    const id = setInterval(tick, 8000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [order.rider_id, searching, riderLocation]);

  const routeDest =
    order.status === 'picked_up' || order.status === 'arrived' ? destination : pickupLocation;

  useEffect(() => {
    if (searching || !effectiveRiderLocation) {
      if (!searching) {
        setEtaExpiresAt(null);
      }
      return;
    }
    let cancelled = false;
    const refresh = async () => {
      const dir = await fetchDirectionsEta(effectiveRiderLocation, routeDest);
      if (!cancelled && dir) {
        setEta(dir.eta);
        setEtaExpiresAt(dir.expires_at);
      }
    };
    void refresh();
    const id = setInterval(refresh, 12000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [
    searching,
    effectiveRiderLocation?.lat,
    effectiveRiderLocation?.lng,
    routeDest.lat,
    routeDest.lng,
    order.status,
  ]);

  const headline = getCustomerTripHeadline(order);
  const displayEta = searching ? searchEta : eta;
  const displayExpiresAt = searching ? searchExpiresAt : etaExpiresAt;
  const pickupLabel = pickup?.label || vendor?.name || 'Pickup';
  const dropoffLabel = dropoff?.label || order.address || 'Your address';
  const riderPhone = order.riderPhone ?? order.rider_phone;

  const mapHeightClass = isArrived
    ? 'h-[calc(100dvh-19rem)] min-h-[340px]'
    : isDelivered
      ? 'h-[calc(100dvh-14rem)] min-h-[320px]'
      : 'h-[calc(100dvh-12rem)] min-h-[380px] max-h-[720px]';

  return (
    <div className="relative w-full flex flex-col">
      <motion.div layout className={cn('relative bg-slate-950 overflow-hidden', mapHeightClass)}>
        {!effectiveRiderLocation && order.rider_id && !isArrived && (
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
          riderLocation={effectiveRiderLocation}
          pickupLocation={pickupLocation}
          destination={destination}
          orderStatus={order.status}
          followRider={!!effectiveRiderLocation}
          onEtaChange={setEta}
          showEtaBadge={false}
          showPreviewRoute={searching}
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
                    isArrived ? 'bg-amber-500/20' : 'bg-brand-green/20'
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
                  {order.rider_id && (
                    <div className="mt-1">
                      <DriverTierBadge
                        tier={driverTierForOrder(order)}
                        avgRating={order.riderAvgRating}
                        ratingCount={order.riderRatingCount}
                      />
                    </div>
                  )}
                </div>
              </motion.div>
              {(displayExpiresAt != null || displayEta) && !isArrived && (
                <div className="text-right shrink-0">
                  <p className="text-[8px] font-black uppercase tracking-widest text-slate-500">
                    {customerEtaLabel(order, searching)}
                  </p>
                  {displayExpiresAt != null ? (
                    <EtaCountdown expiresAtMs={displayExpiresAt} />
                  ) : (
                    <p className="text-lg font-black text-brand-green font-mono leading-tight">
                      {displayEta}
                    </p>
                  )}
                  {displayEta && displayExpiresAt != null && (
                    <p className="text-[9px] font-bold text-slate-500 truncate max-w-[120px]">
                      {displayEta}
                    </p>
                  )}
                </div>
              )}
            </div>
          </motion.div>
        </div>
      </motion.div>

      {/* Compact trip sheet — progress + contact only; payment pinned below when arrived */}
      <motion.div layout className="relative z-20 -mt-5 max-w-lg mx-auto w-full px-4">
        <div
          className={cn(
            'rounded-t-[1.75rem] bg-slate-900 border border-slate-800 shadow-[0_-12px_40px_rgba(0,0,0,0.45)] overflow-hidden',
            !isArrived && !isDelivered && !sheetExpanded && 'max-h-[168px]'
          )}
        >
          {!isArrived && !isDelivered && (
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
          )}

          <div className="px-4 pt-2 pb-3 space-y-3">
            <TripProgressBar order={order} isCourier={isCourier} />

            {order.rider_id && (
              <div className="flex items-center gap-2 rounded-xl bg-slate-800/60 border border-slate-700/80 px-3 py-2">
                <span className="flex-1 text-sm font-bold text-white truncate">
                  {order.rider_name || 'Your biker'}
                </span>
                {riderPhone && (
                  <>
                    <a
                      href={`tel:${riderPhone}`}
                      className="w-9 h-9 rounded-lg bg-slate-900 border border-slate-700 flex items-center justify-center text-slate-300 hover:text-white"
                      aria-label="Call biker"
                    >
                      <Phone size={16} />
                    </a>
                    <a
                      href={`sms:${riderPhone}`}
                      className="w-9 h-9 rounded-lg bg-brand-blue flex items-center justify-center text-white"
                      aria-label="Text biker"
                    >
                      <MessageCircle size={16} />
                    </a>
                  </>
                )}
              </div>
            )}

            <AnimatePresence>
              {(sheetExpanded || isDelivered) && !isArrived && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  exit={{ opacity: 0, height: 0 }}
                  className="space-y-2.5 overflow-hidden"
                >
                  <div className="flex items-start gap-3">
                    <div className="w-8 h-8 rounded-lg bg-brand-blue/20 flex items-center justify-center shrink-0 mt-0.5">
                      <MapPin size={14} className="text-brand-blue" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-[9px] font-black uppercase tracking-widest text-slate-500">Pickup</p>
                      <p className="text-sm font-bold text-white leading-snug">{pickupLabel}</p>
                    </div>
                  </div>
                  <div className="flex items-start gap-3">
                    <div className="w-8 h-8 rounded-lg bg-brand-green/20 flex items-center justify-center shrink-0 mt-0.5">
                      <Navigation size={14} className="text-brand-green" />
                    </div>
                    <div className="min-w-0">
                      <p className="text-[9px] font-black uppercase tracking-widest text-slate-500">Drop-off</p>
                      <p className="text-sm font-bold text-white leading-snug">{dropoffLabel}</p>
                    </div>
                  </div>
                </motion.div>
              )}

              {isDelivered && (
                <motion.div
                  initial={{ opacity: 0, height: 0 }}
                  animate={{ opacity: 1, height: 'auto' }}
                  exit={{ opacity: 0, height: 0 }}
                >
                  <RateDriverCard
                    order={order}
                    addNotification={addNotification}
                    refreshData={refreshData}
                  />
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </motion.div>

      {/* Pinned payment dock — always visible when driver arrives, no scroll needed */}
      {isArrived && (
        <div className="sticky bottom-0 z-30 max-w-lg mx-auto w-full px-4 pb-2 pt-1 bg-gradient-to-t from-slate-950 via-slate-950/95 to-transparent">
          <TripCompletionCard
            order={order}
            user={user}
            paystackKey={paystackKey}
            setPaystackKey={setPaystackKey}
            addNotification={addNotification}
            refreshData={refreshData}
            pinned
          />
        </div>
      )}
    </div>
  );
}
