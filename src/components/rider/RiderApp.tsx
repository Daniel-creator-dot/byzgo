import { useState, useEffect, type Dispatch, type SetStateAction, type FormEvent } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import axios from 'axios';
import {
  Bike,
  Clock,
  CreditCard,
  LogOut,
  MapPin,
  Navigation,
  Phone,
  Star,
  Store,
  User,
  Wallet,
  X,
  Zap,
  Upload,
  IdCard,
  Camera,
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Order, OrderStatus } from '../../types';
import { GHANA_REGIONS } from '../../lib/constants';
import { ProfileAvatarUpload } from '../ProfileAvatarUpload';
import { socket } from '../../lib/socket';
import { subscribeRiderPush, unsubscribeRiderPush } from '../../lib/pushNotifications';
import { unlockIncomingRideAudio } from '../../lib/incomingRideAudio';
import { useMapsAvailable } from '../MapsProvider';
import { RiderDriveMap } from './RiderDriveMap';
import { RiderMapPlaceholder } from './RiderMapPlaceholder';
import { ActiveTripHud } from './ActiveTripHud';
import { DeliveryPinModal } from './DeliveryPinModal';
import type { RouteSummary } from './MapDirections';
import { LoadingIndicator } from '../UI';
import {
  getDropoffCoords,
  getNavigationTarget,
  getPickupCoordsForOrder,
  getTripPhase,
  hasValidCoords,
  openTurnByTurnNavigation,
  type TripStop,
} from '../../lib/riderTrip';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

interface AuthUser {
  id: string;
  name: string;
  email: string;
  role: string;
  balance: number;
  status?: string;
  is_online?: boolean;
  region?: string;
  lat?: number;
  lng?: number;
  phone?: string;
  address?: string;
  avatar_url?: string;
}

function PaymentChip({ order }: { order: Order }) {
  if (!order.payment_status) return null;
  const paid = order.payment_status === 'paid';
  return (
    <span
      className={cn(
        'text-[9px] font-black uppercase tracking-widest px-2 py-0.5 rounded-md',
        paid ? 'bg-emerald-500/20 text-emerald-400' : 'bg-amber-500/20 text-amber-400'
      )}
    >
      {paid ? 'Paid' : 'COD'}
    </span>
  );
}

type RiderTab = 'drive' | 'trips' | 'wallet' | 'profile';

export function RiderApp({
  user,
  setUser,
  orders,
  vendors,
  onUpdateStatus,
  onLogout,
  pendingApproval,
  addNotification,
  refreshData,
}: {
  user: AuthUser;
  setUser: Dispatch<SetStateAction<AuthUser | null>>;
  orders: Order[];
  vendors: any[];
  onUpdateStatus: (id: string, status: OrderStatus, extra?: Record<string, unknown>) => void | Promise<boolean>;
  onLogout: () => void;
  pendingApproval?: boolean;
  addNotification?: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData?: () => void | Promise<void>;
}) {
  const mapsAvailable = useMapsAvailable();
  const [tab, setTab] = useState<RiderTab>('drive');
  const [sheetTab, setSheetTab] = useState<'requests' | 'active'>('requests');
  const [isOnline, setIsOnline] = useState(user.is_online === true);
  const [riderPos, setRiderPos] = useState({ lat: user.lat || 5.6037, lng: user.lng || -0.1870 });
  const [riderHeading, setRiderHeading] = useState<number | null>(null);
  const [navigatingTo, setNavigatingTo] = useState<{ lat: number; lng: number } | null>(null);
  const [routeSummary, setRouteSummary] = useState<RouteSummary | null>(null);
  const [focusedOrderId, setFocusedOrderId] = useState<string | null>(null);
  const [pinModalOrder, setPinModalOrder] = useState<Order | null>(null);

  const [offerTick, setOfferTick] = useState(0);
  const isActiveDispatchOffer = (o: Order) =>
    !o.expiresAt || new Date(o.expiresAt).getTime() > Date.now();
  const availableOrders = orders.filter((o) => {
    void offerTick;
    return o.status === 'ready' && !o.rider_id && isActiveDispatchOffer(o);
  });

  useEffect(() => {
    const hasExpiringOffers = orders.some(
      (o) => o.status === 'ready' && !o.rider_id && o.expiresAt && isActiveDispatchOffer(o)
    );
    if (!hasExpiringOffers) return;
    const t = setInterval(() => setOfferTick((n) => n + 1), 1000);
    return () => clearInterval(t);
  }, [orders]);
  const activeOrders = orders.filter((o) => o.rider_id === user.id && o.status !== 'delivered');
  const completedTrips = orders.filter((o) => o.rider_id === user.id && o.status === 'delivered');
  const todayEarnings = completedTrips.length;

  const getVendor = (order: Order) => vendors.find((v) => v.id === order.vendor_id);

  const getPickupCoords = (order: Order) => {
    const stop = getPickupCoordsForOrder(order, vendors);
    if (!stop || !hasValidCoords(stop.lat, stop.lng)) return null;
    return { lat: stop.lat, lng: stop.lng };
  };

  const primaryActiveOrder =
    activeOrders.find((o) => o.id === focusedOrderId) ?? activeOrders[0] ?? null;

  const beginTripNavigation = (order: Order) => {
    const target = getNavigationTarget(order, vendors);
    if (!target) {
      window.alert('No pickup or drop-off location for this trip. Contact support.');
      return;
    }
    openTurnByTurnNavigation(target, riderPos);
    setFocusedOrderId(order.id);
    if (hasValidCoords(target.lat, target.lng)) {
      setNavigatingTo({ lat: target.lat, lng: target.lng });
      setRouteSummary(null);
    } else {
      setNavigatingTo(null);
      setRouteSummary(null);
    }
    setTab('drive');
    setSheetTab('active');
  };

  useEffect(() => {
    const id = navigator.geolocation.watchPosition(
      (pos) => {
        const next = { lat: pos.coords.latitude, lng: pos.coords.longitude };
        setRiderPos(next);
        if (pos.coords.heading != null && !Number.isNaN(pos.coords.heading)) {
          setRiderHeading(pos.coords.heading);
        }
        socket.emit('location:update', { userId: user.id, ...next });
      },
      () => {},
      { enableHighAccuracy: true, maximumAge: 2000 }
    );
    return () => navigator.geolocation.clearWatch(id);
  }, [user.id]);

  useEffect(() => {
    if (activeOrders.length > 0) {
      setSheetTab('active');
      if (!focusedOrderId || !activeOrders.some((o) => o.id === focusedOrderId)) {
        setFocusedOrderId(activeOrders[0].id);
      }
    } else {
      setFocusedOrderId(null);
      setNavigatingTo(null);
      setRouteSummary(null);
    }
  }, [activeOrders.length, activeOrders, focusedOrderId]);

  useEffect(() => {
    if (!primaryActiveOrder) return;
    const target = getNavigationTarget(primaryActiveOrder, vendors);
    if (!target || !hasValidCoords(target.lat, target.lng)) return;
    setNavigatingTo({ lat: target.lat, lng: target.lng });
  }, [primaryActiveOrder?.id, primaryActiveOrder?.status, vendors]);

  useEffect(() => {
    if (primaryActiveOrder && navigatingTo) {
      setTab('drive');
    }
  }, [primaryActiveOrder?.id, navigatingTo]);

  useEffect(() => {
    setIsOnline(user.is_online === true);
  }, [user.is_online]);

  useEffect(() => {
    if (user.status === 'active' && user.is_online) {
      unlockIncomingRideAudio();
    }
  }, [user.status, user.is_online]);

  const toggleOnline = async () => {
    const next = isOnline ? 'offline' : 'active';
    try {
      const res = await axios.patch('/api/auth/status', { status: next });
      const updated = res.data?.user;
      setIsOnline(updated?.is_online === true);
      setUser((u) => (u && updated ? { ...u, ...updated } : u));
      if (res.data?.token) localStorage.setItem('token', res.data.token);
      if (updated) localStorage.setItem('user', JSON.stringify(updated));
      if (next === 'active') {
        unlockIncomingRideAudio();
        socket.emit('join', user.id);
        socket.emit('location:update', { userId: user.id, lat: riderPos.lat, lng: riderPos.lng });
        await subscribeRiderPush();
        await refreshData?.();
      } else {
        await unsubscribeRiderPush();
      }
    } catch (e) {
      const msg = (e as { response?: { data?: { message?: string } } })?.response?.data?.message;
      addNotification?.(msg || 'Could not update online status', 'warning');
    }
  };

  const tripPickup: TripStop | null = primaryActiveOrder
    ? getPickupCoordsForOrder(primaryActiveOrder, vendors)
    : null;
  const tripDropoff = primaryActiveOrder ? getDropoffCoords(primaryActiveOrder) : null;
  const tripPhase = primaryActiveOrder ? getTripPhase(primaryActiveOrder) : null;
  const tripTarget = primaryActiveOrder ? getNavigationTarget(primaryActiveOrder, vendors) : null;
  const isNavigating = Boolean(navigatingTo && primaryActiveOrder);

  // ——— Wallet state ———
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [withdrawMethod, setWithdrawMethod] = useState<'momo' | 'bank'>('momo');
  const [withdrawPhone, setWithdrawPhone] = useState('');
  const [withdrawNetwork, setWithdrawNetwork] = useState('mtn');
  const [withdrawBank, setWithdrawBank] = useState('');
  const [withdrawAccName, setWithdrawAccName] = useState('');
  const [withdrawAccNum, setWithdrawAccNum] = useState('');
  const [withdrawStatus, setWithdrawStatus] = useState<{ message: string; type: 'error' | 'success' } | null>(null);
  const [isWithdrawing, setIsWithdrawing] = useState(false);

  const handleWithdraw = async (e: FormEvent) => {
    e.preventDefault();
    if (!withdrawAmount || isNaN(Number(withdrawAmount))) return;
    setIsWithdrawing(true);
    setWithdrawStatus(null);
    try {
      const res = await axios.post('/api/wallet/withdraw', { amount: Number(withdrawAmount) });
      setUser((u) => (u ? { ...u, balance: res.data.balance } : u));
      setWithdrawStatus({ message: 'Withdrawal successful', type: 'success' });
      setWithdrawAmount('');
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      setWithdrawStatus({ message: msg || 'Withdrawal failed', type: 'error' });
    } finally {
      setIsWithdrawing(false);
    }
  };

  // ——— Profile ———
  const [profileForm, setProfileForm] = useState({
    phone: user.phone || '',
    region: user.region || '',
  });
  const [profileSaving, setProfileSaving] = useState(false);
  const [profileMsg, setProfileMsg] = useState('');
  const [riderDocs, setRiderDocs] = useState<
    Array<{ doc_type: string; image_url: string; review_status?: string; rejection_reason?: string }>
  >([]);
  const [docsLoading, setDocsLoading] = useState(false);
  const [docUploading, setDocUploading] = useState<string | null>(null);
  const [submittingDocs, setSubmittingDocs] = useState(false);

  const docSlots: { type: 'license' | 'ghana_card' | 'photo'; label: string; icon: typeof IdCard }[] = [
    { type: 'license', label: 'Driver licence (JPEG)', icon: IdCard },
    { type: 'ghana_card', label: 'Ghana card (JPEG)', icon: IdCard },
    { type: 'photo', label: 'Profile photo (JPEG)', icon: Camera },
  ];

  useEffect(() => {
    if (tab !== 'profile') return;
    setDocsLoading(true);
    axios
      .get('/api/rider/documents')
      .then((res) => setRiderDocs(res.data?.documents || []))
      .catch(() => addNotification?.('Could not load documents', 'warning'))
      .finally(() => setDocsLoading(false));
  }, [tab, user.status]);

  const uploadRiderDoc = async (docType: 'license' | 'ghana_card' | 'photo', file: File) => {
    if (!/^image\/(jpeg|jpg|pjpeg)$/i.test(file.type)) {
      addNotification?.('Use a JPEG image (.jpg)', 'warning');
      return;
    }
    setDocUploading(docType);
    try {
      const formData = new FormData();
      formData.append('image', file);
      const res = await axios.post(`/api/rider/documents/${docType}/upload`, formData, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      setRiderDocs(res.data?.documents || []);
      if (res.data?.user) {
        setUser((u) => (u ? { ...u, ...res.data.user } : u));
        localStorage.setItem('user', JSON.stringify(res.data.user));
      }
      if (res.data?.token) localStorage.setItem('token', res.data.token);
      addNotification?.('Document uploaded', 'success');
    } catch (err) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      addNotification?.(msg || 'Upload failed', 'warning');
    } finally {
      setDocUploading(null);
    }
  };

  const submitDocsForReview = async () => {
    setSubmittingDocs(true);
    try {
      const res = await axios.post('/api/rider/documents/submit');
      setRiderDocs(res.data?.documents || []);
      if (res.data?.user) {
        setUser((u) => (u ? { ...u, ...res.data.user } : u));
        localStorage.setItem('user', JSON.stringify(res.data.user));
      }
      if (res.data?.token) localStorage.setItem('token', res.data.token);
      addNotification?.('Submitted for admin review', 'success');
    } catch (err) {
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      addNotification?.(msg || 'Submit failed', 'warning');
    } finally {
      setSubmittingDocs(false);
    }
  };

  const docsComplete = docSlots.every((s) => riderDocs.some((d) => d.doc_type === s.type));

  const navItems: { id: RiderTab; label: string; icon: typeof Bike }[] = [
    { id: 'drive', label: 'Drive', icon: Navigation },
    { id: 'trips', label: 'Trips', icon: Clock },
    { id: 'wallet', label: 'Wallet', icon: Wallet },
    { id: 'profile', label: 'Account', icon: User },
  ];

  return (
    <motion.div className="min-h-[100dvh] bg-slate-950 text-white flex flex-col" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
      {/* Top bar */}
      <header className="shrink-0 z-30 px-4 pt-3 pb-2 safe-area-inset-top">
        <motion.div className="flex items-center justify-between gap-3">
          <motion.div className="flex items-center gap-3 min-w-0">
            <motion.div className="w-11 h-11 rounded-2xl bg-gradient-to-br from-brand-green to-emerald-600 flex items-center justify-center font-black text-lg shadow-lg shadow-brand-green/30">
              {user.name[0]}
            </motion.div>
            <motion.div className="min-w-0">
              <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">Rider</p>
              <p className="font-black text-sm truncate">{user.name}</p>
            </motion.div>
          </motion.div>

          <motion.button
            type="button"
            onClick={toggleOnline}
            disabled={pendingApproval}
            className={cn(
              'relative flex items-center gap-2 pl-3 pr-4 py-2.5 rounded-full font-black text-[10px] uppercase tracking-widest transition-all',
              pendingApproval && 'opacity-50 cursor-not-allowed',
              isOnline
                ? 'bg-brand-green text-white shadow-lg shadow-brand-green/40'
                : 'bg-slate-800 text-slate-400 border border-slate-700'
            )}
          >
            <span
              className={cn(
                'w-2.5 h-2.5 rounded-full',
                isOnline ? 'bg-white animate-pulse' : 'bg-red-500'
              )}
            />
            {isOnline ? 'Online' : 'Go online'}
          </motion.button>

          <motion.button
            type="button"
            onClick={onLogout}
            className="p-2.5 rounded-xl bg-slate-800/80 text-slate-400 hover:text-white border border-slate-700"
            aria-label="Sign out"
          >
            <LogOut size={18} />
          </motion.button>
        </motion.div>

        {(pendingApproval || user.status === 'rejected') && (
          <motion.div className="mt-3 p-3 rounded-2xl bg-amber-500/10 border border-amber-500/30 text-amber-200 text-xs font-bold">
            {user.status === 'rejected'
              ? 'Application rejected — update your documents in Account and resubmit.'
              : 'Account pending approval — upload documents in Account, then wait for admin.'}
          </motion.div>
        )}

        <motion.div className="mt-3 grid grid-cols-3 gap-2">
          <motion.div className="p-3 rounded-2xl bg-slate-900/80 border border-slate-800">
            <p className="text-[9px] font-black uppercase tracking-widest text-slate-500">Balance</p>
            <p className="text-lg font-black text-brand-green font-mono">₵{Number(user.balance || 0).toFixed(2)}</p>
          </motion.div>
          <motion.div className="p-3 rounded-2xl bg-slate-900/80 border border-slate-800">
            <p className="text-[9px] font-black uppercase tracking-widest text-slate-500">Active</p>
            <p className="text-lg font-black">{activeOrders.length}</p>
          </motion.div>
          <motion.div className="p-3 rounded-2xl bg-slate-900/80 border border-slate-800">
            <p className="text-[9px] font-black uppercase tracking-widest text-slate-500">Trips today</p>
            <p className="text-lg font-black">{todayEarnings}</p>
          </motion.div>
        </motion.div>
      </header>

      {/* Main content */}
      <main className="flex-1 min-h-0 relative overflow-hidden">
        <AnimatePresence mode="wait">
          {tab === 'drive' && (
            <motion.div
              key="drive"
              className="absolute inset-0 flex flex-col"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
            >
              <motion.div className="flex-1 relative min-h-[52vh] byzgo-map-shell">
                {mapsAvailable ? (
                  <RiderDriveMap
                    riderPos={riderPos}
                    riderHeading={riderHeading}
                    navTarget={navigatingTo}
                    tripPhase={tripPhase}
                    pickup={tripPickup}
                    dropoff={tripDropoff && hasValidCoords(tripDropoff.lat, tripDropoff.lng) ? tripDropoff : null}
                    isNavigating={isNavigating}
                    isOnline={isOnline}
                    availableOrders={availableOrders}
                    getPickupCoords={getPickupCoords}
                    onRouteUpdate={setRouteSummary}
                  />
                ) : (
                  <RiderMapPlaceholder
                    riderPos={riderPos}
                    navigatingTo={navigatingTo}
                    eta={routeSummary?.eta}
                  />
                )}

                {isNavigating && primaryActiveOrder && tripTarget && hasValidCoords(tripTarget.lat, tripTarget.lng) && (
                  <ActiveTripHud
                    order={primaryActiveOrder}
                    phase={tripPhase!}
                    targetLabel={tripTarget.label}
                    navTarget={tripTarget}
                    riderOrigin={riderPos}
                    route={routeSummary}
                    onStopNav={() => setNavigatingTo(null)}
                  />
                )}

                {!isOnline && (
                  <div className="absolute inset-0 bg-slate-950/70 backdrop-blur-sm flex items-center justify-center p-6">
                    <div className="text-center max-w-xs">
                      <Bike className="mx-auto text-slate-600 mb-4" size={48} />
                      <p className="font-black text-lg mb-2">You&apos;re offline</p>
                      <p className="text-sm text-slate-400 mb-6">Go online to see the map and receive ride requests.</p>
                      <button
                        type="button"
                        onClick={toggleOnline}
                        disabled={pendingApproval}
                        className="w-full py-4 bg-brand-green rounded-2xl font-black uppercase tracking-widest text-xs"
                      >
                        Go online
                      </button>
                    </div>
                  </div>
                )}
              </motion.div>

              {/* Bottom sheet */}
              <div
                className={cn(
                  'shrink-0 bg-slate-900 rounded-t-[1.75rem] border-t border-slate-800 shadow-[0_-20px_60px_rgba(0,0,0,0.5)] flex flex-col transition-all',
                  isNavigating ? 'max-h-[32vh]' : 'max-h-[48vh]'
                )}
              >
                <div className="w-10 h-1 bg-slate-700 rounded-full mx-auto mt-2 mb-1" />
                <div className="flex gap-1 p-2 mx-2 bg-slate-800/50 rounded-xl">
                  <button
                    type="button"
                    onClick={() => setSheetTab('requests')}
                    className={cn(
                      'flex-1 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest transition-all',
                      sheetTab === 'requests' ? 'bg-slate-700 text-white' : 'text-slate-500'
                    )}
                  >
                    Requests {availableOrders.length > 0 && `(${availableOrders.length})`}
                  </button>
                  <button
                    type="button"
                    onClick={() => setSheetTab('active')}
                    className={cn(
                      'flex-1 py-2 rounded-lg text-[10px] font-black uppercase tracking-widest transition-all',
                      sheetTab === 'active' ? 'bg-slate-700 text-white' : 'text-slate-500'
                    )}
                  >
                    Active {activeOrders.length > 0 && `(${activeOrders.length})`}
                  </button>
                </div>

                <div className="overflow-y-auto flex-1 px-4 pb-4 space-y-3">
                  {sheetTab === 'requests' && (
                    <>
                      {!isOnline ? (
                        <p className="text-center text-slate-500 text-sm py-8">Go online to receive requests</p>
                      ) : availableOrders.length === 0 ? (
                        <div className="text-center py-10">
                          <Zap className="mx-auto text-brand-green/40 mb-3" size={32} />
                          <p className="font-black text-slate-300">Waiting for rides</p>
                          <p className="text-xs text-slate-500 mt-1">New requests appear here and as incoming calls</p>
                        </div>
                      ) : (
                        availableOrders.map((order) => {
                          const vendor = getVendor(order);
                          const isCourier = (order as Order & { order_type?: string }).order_type === 'courier';
                          const pickup = getPickupCoords(order);
                          return (
                            <div
                              key={order.id}
                              className="p-4 rounded-2xl bg-slate-800/80 border border-slate-700/80"
                            >
                              <motion.div className="flex justify-between items-start mb-3">
                                <div>
                                  <div className="flex items-center gap-2">
                                    <span className="font-black">#{order.id.slice(-4)}</span>
                                    {isCourier && (
                                      <span className="text-[8px] font-black uppercase bg-brand-blue/30 text-brand-blue px-2 py-0.5 rounded">
                                        Courier
                                      </span>
                                    )}
                                  </div>
                                  <PaymentChip order={order} />
                                </div>
                                <span className="text-xl font-black text-brand-green font-mono">₵{order.total}</span>
                              </motion.div>
                              {isCourier ? (
                                <p className="text-xs text-slate-400 mb-1 flex items-center gap-1">
                                  <MapPin size={12} /> Pickup: {(order as Order & { pickup_address?: string }).pickup_address || 'Pickup'}
                                </p>
                              ) : vendor ? (
                                <p className="text-xs text-slate-400 mb-1 flex items-center gap-1">
                                  <Store size={12} /> {vendor.name}
                                </p>
                              ) : null}
                              <p className="text-sm font-medium text-slate-300 mb-3 flex items-start gap-1">
                                <Navigation size={14} className="text-brand-green shrink-0 mt-0.5" />
                                Drop-off: {order.address}
                              </p>
                              {order.expiresAt && (
                                <p className="text-[10px] font-black uppercase tracking-widest text-amber-400/90 mb-2">
                                  Offer expires in{' '}
                                  {Math.max(
                                    0,
                                    Math.ceil(
                                      (new Date(order.expiresAt).getTime() - Date.now()) / 1000
                                    )
                                  )}
                                  s
                                  {order.dispatchWave != null ? ` · wave ${order.dispatchWave}` : ''}
                                </p>
                              )}
                              <div className="flex gap-2">
                                <button
                                  type="button"
                                  onClick={async () => {
                                    const ok = await onUpdateStatus(order.id, order.status, {
                                      riderId: user.id,
                                    });
                                    if (ok) beginTripNavigation(order);
                                  }}
                                  className="w-full py-3.5 rounded-xl bg-brand-green font-black text-[10px] uppercase tracking-widest text-slate-950 shadow-lg shadow-brand-green/30"
                                >
                                  Accept & navigate
                                </button>
                              </div>
                            </div>
                          );
                        })
                      )}
                    </>
                  )}

                  {sheetTab === 'active' &&
                    (activeOrders.length === 0 ? (
                      <p className="text-center text-slate-500 text-sm py-8">No active trips</p>
                    ) : (
                      activeOrders.map((order) => {
                        const vendor = getVendor(order);
                        const isCourier = (order as Order & { order_type?: string }).order_type === 'courier';
                        const step =
                          order.status === 'ready'
                            ? 1
                            : order.status === 'picked_up'
                              ? 2
                              : order.status === 'arrived'
                                ? 3
                                : 4;
                        const navTarget = getNavigationTarget(order, vendors);
                        const tripLeg = getTripPhase(order);
                        return (
                          <div
                            key={order.id}
                            className="p-4 rounded-2xl bg-gradient-to-br from-slate-800 to-slate-900 border border-brand-green/20"
                          >
                            <div className="flex justify-between mb-3">
                              <span className="font-black text-lg">#{order.id.slice(-4)}</span>
                              <span className="text-[10px] font-black uppercase tracking-widest text-brand-green">
                                {order.status.replace('_', ' ')}
                              </span>
                            </div>
                            <div className="flex gap-1 mb-4">
                              {[1, 2, 3, 4].map((s) => (
                                <motion.div
                                  key={s}
                                  className={cn(
                                    'h-1 flex-1 rounded-full',
                                    s <= step ? 'bg-brand-green' : 'bg-slate-700'
                                  )}
                                />
                              ))}
                            </div>
                            {vendor && !isCourier && (
                              <p className="text-xs text-slate-400 mb-2">
                                <Store size={12} className="inline mr-1" />
                                Pickup: {vendor.name}
                              </p>
                            )}
                            {navTarget ? (
                              <p className="text-sm text-slate-300 mb-4 leading-snug">
                                <Navigation size={12} className="inline mr-1 text-brand-green align-text-top" />
                                <span className="text-[10px] font-black uppercase tracking-widest text-brand-green">
                                  {tripLeg === 'to_pickup' ? 'Pickup' : 'Drop-off'}:{' '}
                                </span>
                                {navTarget.label}
                              </p>
                            ) : (
                              <p className="text-xs text-amber-400 mb-4 font-bold">Location not available for navigation</p>
                            )}
                            <div className="grid grid-cols-2 gap-2">
                              <button
                                type="button"
                                onClick={() => beginTripNavigation(order)}
                                disabled={!navTarget}
                                className="py-3 rounded-xl bg-brand-green text-slate-950 font-black text-[10px] uppercase flex items-center justify-center gap-1.5 disabled:opacity-40"
                              >
                                <MapPin size={14} />
                                Open maps
                              </button>
                              {order.status === 'ready' ? (
                                <button
                                  type="button"
                                  onClick={async () => {
                                    const ok = await onUpdateStatus(order.id, 'picked_up');
                                    if (ok) beginTripNavigation(order);
                                  }}
                                  className="py-3 rounded-xl bg-brand-blue font-black text-[10px] uppercase"
                                >
                                  Picked up
                                </button>
                              ) : order.status === 'picked_up' ? (
                                <button
                                  type="button"
                                  onClick={async () => {
                                    try {
                                      await axios.patch(`/api/orders/${order.id}/arrive`);
                                      addNotification?.('Marked arrived — customer can pay & share PIN', 'success');
                                      await refreshData?.();
                                    } catch (err: unknown) {
                                      const msg = (err as { response?: { data?: { message?: string } } })?.response
                                        ?.data?.message;
                                      addNotification?.(msg || 'Could not mark arrived', 'warning');
                                    }
                                  }}
                                  className="py-3 rounded-xl bg-amber-500 font-black text-[10px] uppercase text-slate-950"
                                >
                                  I&apos;ve arrived
                                </button>
                              ) : order.status === 'arrived' ? (
                                <button
                                  type="button"
                                  onClick={() => setPinModalOrder(order)}
                                  className="py-3 rounded-xl bg-brand-green font-black text-[10px] uppercase text-slate-950"
                                >
                                  Complete
                                </button>
                              ) : null}
                            </div>
                          </div>
                        );
                      })
                    ))}
                </div>
              </div>
            </motion.div>
          )}

          {tab === 'trips' && (
            <motion.div
              key="trips"
              className="absolute inset-0 overflow-y-auto p-4 pb-24"
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0 }}
            >
              <h2 className="text-xl font-black mb-1">Trip history</h2>
              <p className="text-slate-500 text-sm mb-6">{completedTrips.length} completed deliveries</p>
              {completedTrips.length === 0 ? (
                <motion.div className="text-center py-16 rounded-2xl border border-dashed border-slate-800">
                  <Clock className="mx-auto text-slate-700 mb-3" size={40} />
                  <p className="text-slate-500 font-bold">No trips yet</p>
                </motion.div>
              ) : (
                <div className="space-y-3">
                  {completedTrips.map((order) => {
                    const vendor = getVendor(order);
                    return (
                      <div
                        key={order.id}
                        className="p-4 rounded-2xl bg-slate-900 border border-slate-800 flex justify-between gap-4"
                      >
                        <div className="min-w-0">
                          <p className="font-black">#{order.id.slice(-4)}</p>
                          <p className="text-xs text-slate-500 truncate mt-1">
                            {vendor?.name || 'Delivery'} → {order.address}
                          </p>
                          {(order as Order & { rating?: number }).rating && (
                            <div className="flex gap-0.5 mt-2">
                              {[1, 2, 3, 4, 5].map((s) => (
                                <Star
                                  key={s}
                                  size={10}
                                  className={
                                    s <= ((order as Order & { rating?: number }).rating || 0)
                                      ? 'text-amber-400 fill-amber-400'
                                      : 'text-slate-700'
                                  }
                                />
                              ))}
                            </div>
                          )}
                        </div>
                        <div className="text-right shrink-0">
                          <p className="text-[9px] font-black uppercase text-brand-green">Done</p>
                          <p className="font-mono font-black text-brand-green">₵{order.total}</p>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </motion.div>
          )}

          {tab === 'wallet' && (
            <motion.div
              key="wallet"
              className="absolute inset-0 overflow-y-auto p-4 pb-24"
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
            >
              <div className="text-center py-8 mb-6 rounded-3xl bg-gradient-to-b from-brand-green/20 to-transparent border border-brand-green/20">
                <CreditCard className="mx-auto text-brand-green mb-3" size={32} />
                <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">Available</p>
                <p className="text-4xl font-black font-mono text-brand-green mt-1">
                  ₵{Number(user.balance || 0).toFixed(2)}
                </p>
              </div>
              <form onSubmit={handleWithdraw} className="space-y-4">
                <motion.div className="flex gap-2">
                  {(['momo', 'bank'] as const).map((m) => (
                    <button
                      key={m}
                      type="button"
                      onClick={() => setWithdrawMethod(m)}
                      className={cn(
                        'flex-1 py-3 rounded-xl text-[10px] font-black uppercase border',
                        withdrawMethod === m
                          ? 'bg-brand-green border-brand-green text-slate-950'
                          : 'border-slate-700 text-slate-500'
                      )}
                    >
                      {m === 'momo' ? 'MoMo' : 'Bank'}
                    </button>
                  ))}
                </motion.div>
                {withdrawMethod === 'momo' ? (
                  <>
                    <select
                      value={withdrawNetwork}
                      onChange={(e) => setWithdrawNetwork(e.target.value)}
                      className="w-full bg-slate-900 border border-slate-700 rounded-xl py-3 px-4 text-sm font-bold"
                    >
                      <option value="mtn">MTN</option>
                      <option value="vodafone">Vodafone</option>
                      <option value="airteltigo">AirtelTigo</option>
                    </select>
                    <input
                      type="tel"
                      required
                      value={withdrawPhone}
                      onChange={(e) => setWithdrawPhone(e.target.value)}
                      placeholder="Phone number"
                      className="w-full bg-slate-900 border border-slate-700 rounded-xl py-3 px-4 text-sm font-bold"
                    />
                  </>
                ) : (
                  <>
                    <input
                      type="text"
                      required
                      value={withdrawBank}
                      onChange={(e) => setWithdrawBank(e.target.value)}
                      placeholder="Bank name"
                      className="w-full bg-slate-900 border border-slate-700 rounded-xl py-3 px-4 text-sm font-bold"
                    />
                    <input
                      type="text"
                      required
                      value={withdrawAccName}
                      onChange={(e) => setWithdrawAccName(e.target.value)}
                      placeholder="Account name"
                      className="w-full bg-slate-900 border border-slate-700 rounded-xl py-3 px-4 text-sm font-bold"
                    />
                    <input
                      type="text"
                      required
                      value={withdrawAccNum}
                      onChange={(e) => setWithdrawAccNum(e.target.value)}
                      placeholder="Account number"
                      className="w-full bg-slate-900 border border-slate-700 rounded-xl py-3 px-4 text-sm font-bold"
                    />
                  </>
                )}
                <input
                  type="number"
                  required
                  min={1}
                  max={user.balance}
                  value={withdrawAmount}
                  onChange={(e) => setWithdrawAmount(e.target.value)}
                  placeholder="Amount (₵)"
                  className="w-full bg-slate-900 border border-slate-700 rounded-xl py-3 px-4 text-sm font-bold"
                />
                {withdrawStatus && (
                  <p
                    className={cn(
                      'text-xs font-bold text-center py-2 rounded-lg',
                      withdrawStatus.type === 'success' ? 'text-brand-green' : 'text-red-400'
                    )}
                  >
                    {withdrawStatus.message}
                  </p>
                )}
                <button
                  type="submit"
                  disabled={isWithdrawing || !withdrawAmount}
                  className="w-full py-4 bg-white text-slate-950 rounded-2xl font-black uppercase tracking-widest text-xs disabled:opacity-50"
                >
                  {isWithdrawing ? 'Processing…' : 'Withdraw'}
                </button>
              </form>
            </motion.div>
          )}

          {tab === 'profile' && (
            <motion.div
              key="profile"
              className="absolute inset-0 overflow-y-auto p-4 pb-24"
              initial={{ opacity: 0, x: 20 }}
              animate={{ opacity: 1, x: 0 }}
            >
              <div className="flex items-center gap-4 mb-8">
                <ProfileAvatarUpload
                  name={user.name}
                  avatarUrl={user.avatar_url}
                  size="md"
                  onUpdated={(updatedUser, newToken) => {
                    setUser(updatedUser as typeof user);
                    localStorage.setItem('user', JSON.stringify(updatedUser));
                    localStorage.setItem('token', newToken);
                    addNotification?.('Profile photo updated', 'success');
                  }}
                  onError={(m) => addNotification?.(m, 'warning')}
                />
                <div>
                  <h2 className="text-xl font-black">{user.name}</h2>
                  <p className="text-sm text-slate-500">{user.email}</p>
                </div>
              </div>

              <div className="mb-8 p-4 rounded-2xl border border-slate-800 bg-slate-900/60">
                <h3 className="text-sm font-black uppercase tracking-widest text-slate-300 mb-1">Verification documents</h3>
                <p className="text-[10px] text-slate-500 font-bold mb-4">Upload JPEG photos of your licence, Ghana card, and a clear profile picture. Admin will review before you can go online.</p>
                {docsLoading ? (
                  <p className="text-xs text-slate-500">Loading…</p>
                ) : (
                  <div className="space-y-4">
                    {docSlots.map(({ type, label, icon: Icon }) => {
                      const doc = riderDocs.find((d) => d.doc_type === type);
                      return (
                        <div key={type} className="flex gap-3 items-start p-3 rounded-xl bg-slate-950 border border-slate-800">
                          {doc?.image_url ? (
                            <img src={doc.image_url} alt="" className="w-16 h-16 rounded-lg object-cover shrink-0" />
                          ) : (
                            <div className="w-16 h-16 rounded-lg bg-slate-800 flex items-center justify-center shrink-0">
                              <Icon size={20} className="text-slate-600" />
                            </div>
                          )}
                          <div className="flex-1 min-w-0">
                            <p className="text-xs font-black text-slate-300">{label}</p>
                            {doc?.review_status === 'rejected' && doc.rejection_reason && (
                              <p className="text-[10px] text-red-400 mt-1">{doc.rejection_reason}</p>
                            )}
                            <label className="mt-2 inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-slate-800 text-[10px] font-black uppercase tracking-widest cursor-pointer hover:bg-slate-700">
                              <Upload size={12} />
                              {docUploading === type ? 'Uploading…' : doc ? 'Replace' : 'Upload'}
                              <input
                                type="file"
                                accept="image/jpeg,.jpg"
                                className="hidden"
                                disabled={docUploading !== null}
                                onChange={(e) => {
                                  const file = e.target.files?.[0];
                                  if (file) uploadRiderDoc(type, file);
                                  e.target.value = '';
                                }}
                              />
                            </label>
                          </div>
                        </div>
                      );
                    })}
                    {docsComplete && (user.status === 'pending' || user.status === 'rejected') && (
                      <button
                        type="button"
                        disabled={submittingDocs}
                        onClick={submitDocsForReview}
                        className="w-full py-3 bg-brand-blue text-white rounded-xl font-black uppercase text-[10px] tracking-widest disabled:opacity-50"
                      >
                        {submittingDocs ? 'Submitting…' : 'Submit for admin review'}
                      </button>
                    )}
                    {user.status === 'active' && docsComplete && (
                      <p className="text-[10px] text-brand-green font-bold text-center">Verified — you can go online.</p>
                    )}
                  </div>
                )}
              </div>

              <form
                onSubmit={async (e) => {
                  e.preventDefault();
                  setProfileSaving(true);
                  try {
                    const res = await axios.patch('/api/auth/profile', profileForm);
                    setUser(res.data.user);
                    localStorage.setItem('user', JSON.stringify(res.data.user));
                    localStorage.setItem('token', res.data.token);
                    setProfileMsg('Saved');
                  } catch {
                    setProfileMsg('Failed');
                  } finally {
                    setProfileSaving(false);
                  }
                }}
                className="space-y-4"
              >
                <div>
                  <label className="text-[10px] font-black uppercase text-slate-500 ml-1">Region</label>
                  <select
                    value={profileForm.region}
                    onChange={(e) => setProfileForm({ ...profileForm, region: e.target.value })}
                    className="w-full mt-1 bg-slate-900 border border-slate-700 rounded-xl py-3 px-4 font-bold text-sm"
                  >
                    <option value="">Select region</option>
                    {GHANA_REGIONS.map((r) => (
                      <option key={r} value={r}>
                        {r}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="text-[10px] font-black uppercase text-slate-500 ml-1">Phone</label>
                  <div className="relative mt-1">
                    <Phone size={16} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-500" />
                    <input
                      type="tel"
                      value={profileForm.phone}
                      onChange={(e) => setProfileForm({ ...profileForm, phone: e.target.value })}
                      className="w-full bg-slate-900 border border-slate-700 rounded-xl py-3 pl-11 pr-4 font-bold text-sm"
                    />
                  </div>
                </div>
                {profileMsg && (
                  <p className="text-xs text-center text-brand-green font-bold">{profileMsg}</p>
                )}
                <button
                  type="submit"
                  disabled={profileSaving}
                  className="w-full py-4 bg-brand-green text-slate-950 rounded-2xl font-black uppercase tracking-widest text-xs"
                >
                  {profileSaving ? 'Saving…' : 'Save profile'}
                </button>
              </form>
              <button
                type="button"
                onClick={onLogout}
                className="w-full mt-6 py-4 rounded-2xl border border-red-500/30 text-red-400 font-black uppercase tracking-widest text-xs flex items-center justify-center gap-2"
              >
                <LogOut size={16} /> Sign out
              </button>
            </motion.div>
          )}
        </AnimatePresence>
      </main>

      {/* Bottom navigation */}
      <nav className="shrink-0 z-40 px-2 pb-3 pt-2 bg-slate-950/95 backdrop-blur-xl border-t border-slate-800 safe-area-inset-bottom">
        <div className="flex justify-around max-w-lg mx-auto">
          {navItems.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              type="button"
              onClick={() => setTab(id)}
              className={cn(
                'flex flex-col items-center gap-1 px-4 py-2 rounded-2xl transition-all min-w-[4rem]',
                tab === id ? 'text-brand-green' : 'text-slate-500'
              )}
            >
              <Icon size={22} strokeWidth={tab === id ? 2.5 : 2} />
              <span className="text-[9px] font-black uppercase tracking-widest">{label}</span>
              {tab === id && (
                <motion.div layoutId="rider-tab-dot" className="w-1 h-1 rounded-full bg-brand-green" />
              )}
            </button>
          ))}
        </div>
      </nav>

      <DeliveryPinModal
        order={pinModalOrder}
        onClose={() => setPinModalOrder(null)}
        onSuccess={() => {
          setNavigatingTo(null);
          setRouteSummary(null);
          addNotification?.('Delivery completed!', 'success');
          refreshData?.();
        }}
        onError={(msg) => addNotification?.(msg, 'warning')}
      />
    </motion.div>
  );
}
