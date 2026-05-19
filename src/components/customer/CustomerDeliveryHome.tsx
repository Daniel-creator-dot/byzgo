import { Dispatch, SetStateAction, useEffect, useRef, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronRight, Clock, CreditCard, MapPin, Navigation, Store, Wallet } from 'lucide-react';
import { openPaystackCheckout, paystackPaymentEmail } from '../../lib/paystackCheckout';
import axios from 'axios';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Order } from '../../types';
import {
  hasValidCoords,
  looksLikeCoordinates,
  resolveAddressLabel,
  resolvePickupLocation,
} from '../../lib/ghanaLocation';
import { LocationAutocompleteInput } from '../LocationAutocompleteInput';
import { DeliveryMapPicker } from './DeliveryMapPicker';
import { MapsHealthBanner } from '../MapsProvider';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

type Loc = { lat: number; lng: number; address: string } | null;

export type CourierFormState = {
  pickup: Loc;
  destination: Loc;
  itemDesc: string;
  scheduledTime: string;
  scheduleDate: string;
  scheduleClock: string;
  senderContact: string;
  receiverContact: string;
};

export function CustomerDeliveryHome({
  liveOrders,
  user,
  courierForm,
  setCourierForm,
  courierFee,
  mapMode,
  setMapMode,
  isMapOpen,
  setIsMapOpen,
  showDeliveryDetails,
  setShowDeliveryDetails,
  onPlaceOrder,
  addNotification,
  setActiveTab,
  paystackKey,
  setPaystackKey,
}: {
  liveOrders: Order[];
  user: { id: string; email: string; name: string; balance: number; lat?: number; lng?: number; address?: string; phone?: string };
  courierForm: CourierFormState;
  setCourierForm: Dispatch<SetStateAction<CourierFormState>>;
  courierFee: number;
  mapMode: 'pickup' | 'destination';
  setMapMode: (m: 'pickup' | 'destination') => void;
  isMapOpen: boolean;
  setIsMapOpen: (v: boolean) => void;
  showDeliveryDetails: boolean;
  setShowDeliveryDetails: Dispatch<SetStateAction<boolean>>;
  onPlaceOrder: (items: unknown[], total: number, vendorId?: string, extra?: Record<string, unknown>) => void | Promise<void>;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  setActiveTab: (tab: string) => void;
  paystackKey: string;
  setPaystackKey: (k: string) => void;
}) {
  const [pickupLocating, setPickupLocating] = useState(false);
  const [paymentTiming, setPaymentTiming] = useState<'on_arrival' | 'now'>('on_arrival');
  const [payMethod, setPayMethod] = useState<'wallet' | 'paystack'>('paystack');
  const [booking, setBooking] = useState(false);
  const pickupAutoRan = useRef(false);
  const arrivedLive = liveOrders.filter((o) => o.status === 'arrived');
  const hasDriverArrived = arrivedLive.length > 0;

  const buildOrderExtra = () => ({
    order_type: 'courier',
    address: courierForm.destination!.address,
    pickup: courierForm.pickup!.address,
    lat: courierForm.destination!.lat,
    lng: courierForm.destination!.lng,
    pickup_lat: courierForm.pickup!.lat,
    pickup_lng: courierForm.pickup!.lng,
    delivery_fee: courierFee,
    scheduled_time:
      courierForm.scheduledTime === 'later'
        ? `${courierForm.scheduleDate} ${courierForm.scheduleClock}`
        : null,
  });

  const submitCourier = async (extra: Record<string, unknown>) => {
    await onPlaceOrder(
      [{ id: 'courier-1', name: `Delivery: ${courierForm.itemDesc}`, quantity: 1, price: courierFee }],
      courierFee,
      undefined,
      extra
    );
    setActiveTab('tracking');
  };

  useEffect(() => {
    if (pickupAutoRan.current) return;
    if (hasValidCoords(courierForm.pickup) && courierForm.pickup?.address?.trim()) return;

    pickupAutoRan.current = true;
    setPickupLocating(true);

    resolvePickupLocation({
      userLat: user.lat,
      userLng: user.lng,
      userAddress: user.address,
    })
      .then((loc) => {
        if (!loc) {
          pickupAutoRan.current = false;
          addNotification('Allow location access to set pickup automatically', 'warning');
          return;
        }
        setCourierForm((prev) => ({
          ...prev,
          pickup: loc,
          senderContact: prev.senderContact || user.phone || '',
        }));
      })
      .finally(() => setPickupLocating(false));
  }, [user.lat, user.lng, user.address, user.phone, courierForm.pickup, setCourierForm, addNotification]);

  useEffect(() => {
    const fields: Array<'pickup' | 'destination'> = ['pickup', 'destination'];
    fields.forEach((field) => {
      const loc = courierForm[field];
      if (!loc?.lat || !loc?.lng || !looksLikeCoordinates(loc.address)) return;
      resolveAddressLabel(loc.lat, loc.lng, loc.address).then((address) => {
        if (!address || looksLikeCoordinates(address)) return;
        setCourierForm((prev) => {
          const current = prev[field];
          if (!current || !looksLikeCoordinates(current.address)) return prev;
          return { ...prev, [field]: { ...current, address } };
        });
      });
    });
  }, [courierForm.pickup?.lat, courierForm.pickup?.lng, courierForm.pickup?.address, courierForm.destination?.lat, courierForm.destination?.lng, courierForm.destination?.address, setCourierForm]);

  return (
    <div className="space-y-4 max-w-lg mx-auto">
      <MapsHealthBanner compact />
      {liveOrders.length > 0 && (
        <button
          type="button"
          onClick={() => setActiveTab('tracking')}
          className={cn(
            'w-full flex items-center justify-between gap-3 p-4 rounded-2xl text-left transition-colors',
            hasDriverArrived
              ? 'bg-amber-500/20 border-2 border-amber-500/50 hover:bg-amber-500/25'
              : 'bg-brand-green/15 border border-brand-green/30 hover:bg-brand-green/20'
          )}
        >
          <div className="flex items-center gap-3 min-w-0">
            <motion.div
              className={cn(
                'w-10 h-10 rounded-xl flex items-center justify-center shrink-0',
                hasDriverArrived ? 'bg-amber-500' : 'bg-brand-green'
              )}
            >
              <Navigation size={20} className={hasDriverArrived ? 'text-slate-950' : 'text-white'} />
            </motion.div>
            <div className="min-w-0">
              <p
                className={cn(
                  'text-[10px] font-black uppercase tracking-widest',
                  hasDriverArrived ? 'text-amber-300' : 'text-brand-green'
                )}
              >
                {hasDriverArrived ? 'Driver has arrived' : 'Live trip'}
              </p>
              <p className="font-black text-sm truncate text-white">
                {hasDriverArrived
                  ? 'Pay now & get your delivery PIN'
                  : `${liveOrders.length} active ${liveOrders.length === 1 ? 'order' : 'orders'}`}
              </p>
            </div>
          </div>
          <ChevronRight
            size={18}
            className={hasDriverArrived ? 'text-amber-400 shrink-0' : 'text-brand-green shrink-0'}
          />
        </button>
      )}

      <form
        onSubmit={async (e) => {
          e.preventDefault();
          if (!courierForm.pickup || !courierForm.destination) {
            return addNotification('Please select pickup and destination', 'warning');
          }
          if (!courierForm.itemDesc?.trim()) {
            return addNotification('Describe what you are sending', 'warning');
          }
          setBooking(true);
          try {
            const base = buildOrderExtra();
            if (paymentTiming === 'on_arrival') {
              await submitCourier({ ...base, payment_method: 'pay_on_delivery' });
              return;
            }
            if (payMethod === 'wallet') {
              if (user.balance < courierFee) {
                addNotification('Insufficient wallet balance', 'warning');
                return;
              }
              await submitCourier({ ...base, payment_method: 'wallet' });
              return;
            }
            let key = paystackKey;
            if (!key) {
              const res = await axios.get('/api/config/paystack');
              key = res.data.publicKey;
              setPaystackKey(key);
            }
            await openPaystackCheckout({
              publicKey: key,
              email: paystackPaymentEmail(user),
              amountGhs: courierFee,
              metadata: { type: 'courier_order' },
              onSuccess: async (reference) => {
                await submitCourier({ ...base, payment_reference: reference, payment_method: 'paystack' });
              },
            });
          } catch (err: unknown) {
            const msg = err instanceof Error ? err.message : 'Booking failed';
            addNotification(msg, 'warning');
          } finally {
            setBooking(false);
          }
        }}
        className="space-y-4"
      >
        <div className="bg-slate-900 rounded-3xl border border-slate-800 overflow-hidden shadow-xl">
          <div className="flex gap-3 p-4">
            <div className="flex flex-col items-center pt-3 shrink-0">
              <div className="w-3 h-3 rounded-full bg-brand-green ring-4 ring-brand-green/25" />
              <div className="w-0.5 flex-1 min-h-[52px] bg-slate-700 my-1" />
              <div className="w-3 h-3 rounded-sm bg-white shadow-md" />
            </div>
            <div className="flex-1 divide-y divide-slate-800">
              <div className="py-1">
                <p className="text-[10px] font-black uppercase tracking-widest text-slate-500 mb-1">Pickup</p>
                <LocationAutocompleteInput
                  placeholder={pickupLocating ? 'Getting your location…' : 'Current location or address'}
                  icon={MapPin}
                  value={courierForm.pickup?.address || ''}
                  onChange={(val) =>
                    setCourierForm({ ...courierForm, pickup: { ...(courierForm.pickup || {}), ...val } })
                  }
                  onMapClick={() => {
                    setMapMode('pickup');
                    setIsMapOpen(true);
                  }}
                  onLocationError={(m) => addNotification(m, 'warning')}
                  variant="dark"
                  hideIcon
                />
              </div>
              <div className="py-1">
                <p className="text-[10px] font-black uppercase tracking-widest text-slate-500 mb-1">Drop-off</p>
                <LocationAutocompleteInput
                  placeholder="Where to?"
                  icon={Navigation}
                  value={courierForm.destination?.address || ''}
                  onChange={(val) =>
                    setCourierForm({ ...courierForm, destination: { ...(courierForm.destination || {}), ...val } })
                  }
                  onMapClick={() => {
                    setMapMode('destination');
                    setIsMapOpen(true);
                  }}
                  onLocationError={(m) => addNotification(m, 'warning')}
                  variant="dark"
                  hideIcon
                  showUseMyLocation={false}
                />
              </div>
            </div>
          </div>
        </div>

        <AnimatePresence>
          {isMapOpen && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, height: 0 }}
              className="overflow-hidden"
            >
              <div className="bg-slate-800 border border-slate-700 rounded-2xl p-2 shadow-inner">
                <div className="flex justify-between items-center px-4 py-3 border-b border-slate-700 mb-2">
                  <span className="text-[10px] font-black uppercase tracking-widest text-slate-400">
                    Pin {mapMode} on map
                  </span>
                  <button
                    type="button"
                    onClick={() => setIsMapOpen(false)}
                    className="text-[10px] font-black uppercase tracking-widest bg-brand-blue text-white px-4 py-2 rounded-full"
                  >
                    Done
                  </button>
                </div>
                <DeliveryMapPicker
                  mapMode={mapMode}
                  courierForm={courierForm}
                  setCourierForm={setCourierForm}
                />
              </div>
            </motion.div>
          )}
        </AnimatePresence>

        {courierFee > 0 && courierForm.pickup?.lat && courierForm.destination?.lat && (
          <div className="flex items-center justify-between px-4 py-3 rounded-2xl bg-slate-900 border border-slate-800">
            <span className="text-[10px] font-black uppercase tracking-widest text-slate-400">Estimated fare</span>
            <span className="text-xl font-black text-brand-green">₵{courierFee.toFixed(2)}</span>
          </div>
        )}

        <button
          type="button"
          onClick={() => setShowDeliveryDetails((v) => !v)}
          className="w-full flex items-center justify-between px-4 py-3 rounded-2xl bg-slate-900 border border-slate-800 text-left"
        >
          <span className="text-sm font-black text-slate-300">Package & contact details</span>
          <ChevronRight
            size={18}
            className={cn('text-slate-500 transition-transform', showDeliveryDetails && 'rotate-90')}
          />
        </button>

        <AnimatePresence>
          {showDeliveryDetails && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: 'auto' }}
              exit={{ opacity: 0, height: 0 }}
              className="overflow-hidden space-y-4"
            >
              <div className="grid grid-cols-2 gap-3">
                <div className="space-y-1">
                  <label className="text-[10px] font-black uppercase tracking-widest text-slate-500 ml-1">
                    Sender
                  </label>
                  <input
                    required
                    type="tel"
                    placeholder="054..."
                    className="w-full bg-slate-900 border border-slate-800 rounded-xl py-3 px-3 text-white font-bold text-sm"
                    value={courierForm.senderContact}
                    onChange={(e) => setCourierForm({ ...courierForm, senderContact: e.target.value })}
                  />
                </div>
                <div className="space-y-1">
                  <label className="text-[10px] font-black uppercase tracking-widest text-slate-500 ml-1">
                    Receiver
                  </label>
                  <input
                    required
                    type="tel"
                    placeholder="024..."
                    className="w-full bg-slate-900 border border-slate-800 rounded-xl py-3 px-3 text-white font-bold text-sm"
                    value={courierForm.receiverContact}
                    onChange={(e) => setCourierForm({ ...courierForm, receiverContact: e.target.value })}
                  />
                </div>
              </div>
              <div className="space-y-1">
                <label className="text-[10px] font-black uppercase tracking-widest text-slate-500 ml-1">
                  What are you sending?
                </label>
                <textarea
                  required
                  placeholder="e.g. documents, food, parcel..."
                  className="w-full bg-slate-900 border border-slate-800 rounded-xl py-3 px-3 text-white font-bold text-sm h-24 resize-none"
                  value={courierForm.itemDesc}
                  onChange={(e) => setCourierForm({ ...courierForm, itemDesc: e.target.value })}
                />
              </div>
              <div className="grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={() => setCourierForm({ ...courierForm, scheduledTime: 'now' })}
                  className={cn(
                    'py-3 rounded-xl font-black text-[10px] uppercase tracking-widest border',
                    courierForm.scheduledTime !== 'later'
                      ? 'bg-brand-blue text-white border-brand-blue'
                      : 'bg-slate-900 text-slate-500 border-slate-800'
                  )}
                >
                  Now
                </button>
                <button
                  type="button"
                  onClick={() => setCourierForm({ ...courierForm, scheduledTime: 'later' })}
                  className={cn(
                    'py-3 rounded-xl font-black text-[10px] uppercase tracking-widest border flex items-center justify-center gap-1',
                    courierForm.scheduledTime === 'later'
                      ? 'bg-brand-blue text-white border-brand-blue'
                      : 'bg-slate-900 text-slate-500 border-slate-800'
                  )}
                >
                  <Clock size={14} /> Later
                </button>
              </div>
              {courierForm.scheduledTime === 'later' && (
                <div className="grid grid-cols-2 gap-3">
                  <input
                    type="date"
                    required
                    className="bg-slate-900 border border-slate-800 rounded-xl py-3 px-3 text-white text-sm font-bold"
                    value={courierForm.scheduleDate}
                    onChange={(e) => setCourierForm({ ...courierForm, scheduleDate: e.target.value })}
                  />
                  <input
                    type="time"
                    required
                    className="bg-slate-900 border border-slate-800 rounded-xl py-3 px-3 text-white text-sm font-bold"
                    value={courierForm.scheduleClock}
                    onChange={(e) => setCourierForm({ ...courierForm, scheduleClock: e.target.value })}
                  />
                </div>
              )}
            </motion.div>
          )}
        </AnimatePresence>

        <motion.div className="bg-slate-900 rounded-2xl border border-slate-800 p-4 space-y-3">
          <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">Payment</p>
          <div className="grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() => setPaymentTiming('on_arrival')}
              className={cn(
                'py-3 rounded-xl font-black text-[10px] uppercase tracking-widest border',
                paymentTiming === 'on_arrival'
                  ? 'bg-brand-green/20 border-brand-green text-brand-green'
                  : 'bg-slate-950 border-slate-800 text-slate-500'
              )}
            >
              Pay on arrival
            </button>
            <button
              type="button"
              onClick={() => setPaymentTiming('now')}
              className={cn(
                'py-3 rounded-xl font-black text-[10px] uppercase tracking-widest border',
                paymentTiming === 'now'
                  ? 'bg-brand-blue/20 border-brand-blue text-brand-blue'
                  : 'bg-slate-950 border-slate-800 text-slate-500'
              )}
            >
              Pay now
            </button>
          </div>
          {paymentTiming === 'now' && (
            <div className="grid grid-cols-2 gap-2">
              <button
                type="button"
                onClick={() => setPayMethod('paystack')}
                className={cn(
                  'py-2.5 rounded-xl font-black text-[9px] uppercase tracking-widest border flex items-center justify-center gap-1',
                  payMethod === 'paystack' ? 'bg-white text-slate-950 border-white' : 'border-slate-700 text-slate-500'
                )}
              >
                <CreditCard size={14} /> Card / MoMo
              </button>
              <button
                type="button"
                onClick={() => setPayMethod('wallet')}
                className={cn(
                  'py-2.5 rounded-xl font-black text-[9px] uppercase tracking-widest border flex items-center justify-center gap-1',
                  payMethod === 'wallet' ? 'bg-white text-slate-950 border-white' : 'border-slate-700 text-slate-500'
                )}
              >
                <Wallet size={14} /> Wallet
              </button>
            </div>
          )}
        </motion.div>

        <button
          type="submit"
          disabled={booking}
          className="w-full py-4 rounded-2xl bg-white text-slate-950 font-black text-sm uppercase tracking-widest shadow-xl hover:bg-slate-100 active:scale-[0.98] transition-all disabled:opacity-50"
        >
          {booking ? 'Booking…' : `Request delivery${courierFee > 0 ? ` · ₵${courierFee.toFixed(2)}` : ''}`}
        </button>
      </form>

      <button
        type="button"
        onClick={() => setActiveTab('menu')}
        className="w-full flex items-center gap-4 p-4 rounded-2xl bg-slate-900/60 border border-slate-800 text-left hover:border-slate-600 transition-colors"
      >
        <div className="w-12 h-12 rounded-2xl bg-slate-800 flex items-center justify-center shrink-0">
          <Store size={22} className="text-brand-blue" />
        </div>
        <div className="flex-1 min-w-0">
          <p className="font-black text-sm">Order from shops</p>
          <p className="text-[11px] text-slate-500 font-medium">Food & vendors — optional</p>
        </div>
        <ChevronRight size={18} className="text-slate-500 shrink-0" />
      </button>
    </div>
  );
}
