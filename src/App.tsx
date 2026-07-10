import React, { useState, useEffect, useRef, useCallback } from 'react';
import { BrowserRouter, Routes, Route, useLocation, useNavigate } from 'react-router-dom';
import { socket } from './lib/socket';
import { Role, Order, OrderStatus } from './types.ts';
import { Layout, User as UserIcon, Store, Bike, Shield, ShoppingBag, MapPin, CreditCard, ChevronRight, CheckCircle2, Clock, Send, Navigation, Lock, Mail, Eye, EyeOff, LogOut, Package, Phone, Edit3, Save, X, Star, Home, Users, BarChart3, AlertCircle, AlertTriangle, Check, LocateFixed, Upload, Trash2, Settings, Tag } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import axios from 'axios';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Map, Marker, useMap, useMapsLibrary } from '@vis.gl/react-google-maps';
import { MapsProvider } from './components/MapsProvider';
import { Modal, ConfirmationModal, LoadingIndicator } from './components/UI';
import { GoogleLogin } from '@react-oauth/google';
import { isGoogleSignInConfigured } from './lib/googleAuth';
import { supabase } from './lib/supabase';
import {
  subscribeRiderPush,
  unsubscribeRiderPush,
  onServiceWorkerRideMessage,
} from './lib/pushNotifications';
import { needsDeviceSetup } from './lib/deviceSetup';
import { InstallPermissionsOnboarding } from './components/InstallPermissionsOnboarding';
import { RiderApp } from './components/rider/RiderApp';
import { ProfileAvatarUpload } from './components/ProfileAvatarUpload';
import { CustomerShell } from './components/customer/CustomerShell';
import { CustomerDeliveryHome } from './components/customer/CustomerDeliveryHome';
import { CustomerTripsView } from './components/customer/CustomerTripsView';
import { LocationAutocompleteInput } from './components/LocationAutocompleteInput';
import { GHANA_REGIONS } from './lib/constants';
import {
  GHANA_CENTER,
  detectCurrentLocation,
  ghanaPlacesAutocompleteOptions,
  reverseGeocodeGhana,
  resolveAddressLabel,
} from './lib/ghanaLocation';
import { openPaystackCheckout, paystackPaymentEmail } from './lib/paystackCheckout';
import {
  clearPendingWalletTopupRef,
  formatWalletTopupError,
  getPendingWalletTopupRef,
  setPendingWalletTopupRef,
  walletTopupReferenceHint,
} from './lib/walletTopup';
import { formatCedis } from './lib/format';
import {
  DEFAULT_DELIVERY_PRICE_PER_KM,
  deliveryFeeFromDistanceKm,
  haversineDistanceKm,
} from './lib/deliveryPricing';
import { getApiError } from './lib/api';
import { buildShopOrderExtra } from './lib/shopOrderExtra';
import {
  unlockIncomingRideAudio,
  playIncomingRidePulse,
  closeIncomingRideAudio,
} from './lib/incomingRideAudio';
import { DriverTierBadge, driverTierFrom } from './components/shared/DriverTier';
import { isOfferableToRider } from './lib/riderTrip';
import { DarkAppShell, type NavItem } from './components/shared/DarkAppShell';
import { DarkCard, DarkButton, DarkInput, StatusBadge, EmptyState, ErrorBanner } from './components/shared/ui';

// Helper for Tailwind classes
function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// Custom Motorbike Icon for better branding
const MotorIcon = ({ size = 24, className = "" }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" className={className}>
    <circle cx="7" cy="17" r="2"/><circle cx="17" cy="17" r="2"/><path d="M12 17h1c1 0 1-1 1-1V9l-5 1v1"/><path d="M17 17h1c1 0 1-1 1-1V9l-5 1"/><path d="M7 17H6c-1 0-1-1-1-1v-1"/><path d="M12 9L7 8l-2 3"/>
  </svg>
);

const CLEAN_MAP_STYLE = [
  {
    "featureType": "poi",
    "elementType": "labels",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "transit",
    "elementType": "labels",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "poi.business",
    "stylers": [{ "visibility": "off" }]
  },
  {
    "featureType": "poi.park",
    "elementType": "labels.text",
    "stylers": [{ "visibility": "off" }]
  }
];
 
export { GHANA_REGIONS };

// Types for Auth
interface AuthUser {
  id: string;
  name: string;
  email: string;
  role: Role;
  balance: number;
  status?: string;
  is_online?: boolean;
  region?: string;
  lat?: number;
  lng?: number;
  phone?: string;
  address?: string;
  cover_image?: string;
  avatar_url?: string;
}

function PullToRefresh({ onRefresh, refreshing, children }: { onRefresh: () => Promise<void>, refreshing: boolean, children: React.ReactNode }) {
  const [pullDistance, setPullDistance] = useState(0);
  const [isPulling, setIsPulling] = useState(false);
  const pullThreshold = 80;

  const handleTouchStart = (e: React.TouchEvent) => {
    if (window.scrollY <= 0) {
      setIsPulling(true);
      const touch = e.touches[0];
      (window as any).startY = touch.screenY;
    }
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (!isPulling) return;
    const touch = e.touches[0];
    const distance = touch.screenY - (window as any).startY;
    if (distance > 0) {
      setPullDistance(Math.min(distance * 0.4, pullThreshold + 20));
      if (distance > 10 && window.scrollY <= 0) {
        if (e.cancelable) e.preventDefault();
      }
    } else {
      setIsPulling(false);
      setPullDistance(0);
    }
  };

  const handleTouchEnd = () => {
    if (pullDistance >= pullThreshold) {
      onRefresh();
    }
    setPullDistance(0);
    setIsPulling(false);
  };

  return (
    <div 
      onTouchStart={handleTouchStart}
      onTouchMove={handleTouchMove}
      onTouchEnd={handleTouchEnd}
      className="relative"
    >
      <motion.div 
        animate={{ height: refreshing ? 60 : pullDistance }}
        transition={{ type: 'spring', damping: 20, stiffness: 200 }}
        className="overflow-hidden flex items-center justify-center bg-slate-50 text-brand-blue"
      >
        <div className={cn("flex items-center gap-2 font-black text-[10px] uppercase tracking-widest transition-opacity", (pullDistance > 10 || refreshing) ? "opacity-100" : "opacity-0")}>
          {refreshing ? (
            <div className="flex items-center gap-2">
              <LoadingIndicator size="sm" />
              <span>Refreshing...</span>
            </div>
          ) : (
            <div className="flex items-center gap-2">
              <Navigation size={14} className={cn("transition-transform duration-300", pullDistance >= pullThreshold ? "rotate-180" : "")} />
              <span>{pullDistance >= pullThreshold ? "Release to refresh" : "Pull to refresh"}</span>
            </div>
          )}
        </div>
      </motion.div>
      <div className={cn("transition-transform duration-200", isPulling && pullDistance > 0 ? "pointer-events-none" : "")} style={{ transform: `translateY(${refreshing ? 0 : pullDistance * 0.2}px)` }}>
        {children}
      </div>
    </div>
  );
}

export default function App() {
  return (
    <BrowserRouter>
      <MainApp />
    </BrowserRouter>
  );
}

function MainApp() {
  const location = useLocation();
  const navigate = useNavigate();

  // Determine current context from path
  const getExpectedRole = () => {
    if (location.pathname.startsWith('/admin')) return 'admin';
    if (location.pathname.startsWith('/vendor')) return 'vendor';
    if (location.pathname.startsWith('/motor')) return 'rider';
    return 'customer';
  };

  const forcedRole = getExpectedRole() as Role;
  const [user, setUser] = useState<AuthUser | null>(() => {
    try {
      const saved = localStorage.getItem('user');
      return saved ? JSON.parse(saved) : null;
    } catch (e) {
      return null;
    }
  });
  const [token, setToken] = useState<string | null>(localStorage.getItem('token'));
  const [vendors, setVendors] = useState<any[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [products, setProducts] = useState<any[]>([]);
  const [loading, setLoading] = useState(() => {
    try {
      const cachedToken = localStorage.getItem('token');
      const cachedUser = localStorage.getItem('user');
      return !(cachedToken && cachedUser);
    } catch (e) {
      return true;
    }
  });
  const [isLogoutModalOpen, setIsLogoutModalOpen] = useState(false);
  const [activeTab, setActiveTab] = useState<string>('courier');
  const [zones, setZones] = useState<any[]>([]);
  const [deliveryPricePerKm, setDeliveryPricePerKm] = useState(DEFAULT_DELIVERY_PRICE_PER_KM);
  const [cart, setCart] = useState<any[]>(() => {
    try {
      const saved = localStorage.getItem('bytzgo_cart');
      return saved ? JSON.parse(saved) : [];
    } catch (e) {
      return [];
    }
  });

  useEffect(() => {
    localStorage.setItem('bytzgo_cart', JSON.stringify(cart));
  }, [cart]);
  const [isCartOpen, setIsCartOpen] = useState(false);
  const subtotal = cart.reduce((acc, curr) => acc + (curr.price * curr.quantity), 0);
  const calculateDeliveryFee = () => {
    if (cart.length === 0 || !user) return 0;
    const vendorId = cart[0].vendor_id;
    const vendor = vendors.find(v => v.id === vendorId);
    const zone = zones.find(z => z.region === user.region && z.is_active);
    const bounds = zone
      ? { min: Number(zone.min_price), max: zone.max_price ? Number(zone.max_price) : null }
      : undefined;
    if (!vendor?.lat || !vendor?.lng || !user.lat || !user.lng) {
      return deliveryFeeFromDistanceKm(5, deliveryPricePerKm, bounds);
    }
    const distance = haversineDistanceKm(user.lat, user.lng, vendor.lat, vendor.lng);
    return deliveryFeeFromDistanceKm(distance, deliveryPricePerKm, bounds);
  };
  const deliveryFee = calculateDeliveryFee();
  const total = subtotal + deliveryFee;
  const [riderLocations, setRiderLocations] = useState<{ [key: string]: { lat: number, lng: number } }>({});
  const [notifications, setNotifications] = useState<{ id: string, message: string, type: 'info' | 'success' | 'warning' }[]>([]);
  const [incomingRideOffer, setIncomingRideOffer] = useState<Order | null>(null);
  const [paystackKey, setPaystackKey] = useState<string>('');
  const [refreshing, setRefreshing] = useState(false);
  const [showDeviceSetup, setShowDeviceSetup] = useState(false);
  const [adminPendingCount, setAdminPendingCount] = useState(0);
  const [adminPendingRiderCount, setAdminPendingRiderCount] = useState(0);
  const userRef = useRef(user);
  const ordersRef = useRef(orders);
  const riderTrackingNotifiedRef = useRef(new Set<string>());
  useEffect(() => { userRef.current = user; }, [user]);
  useEffect(() => { ordersRef.current = orders; }, [orders]);

  const pickBestRideOffer = useCallback((list: Order[]) => {
    return list
      .filter(
        (o) =>
          isOfferableToRider(o) &&
          (!o.expiresAt || new Date(o.expiresAt).getTime() > Date.now())
      )
      .sort((a, b) => {
        const ea = a.expiresAt ? new Date(a.expiresAt).getTime() : Number.MAX_SAFE_INTEGER;
        const eb = b.expiresAt ? new Date(b.expiresAt).getTime() : Number.MAX_SAFE_INTEGER;
        return ea - eb;
      })[0];
  }, []);

  const triggerIncomingRideCall = useCallback((order: Order) => {
    const u = userRef.current;
    if (!u || u.role !== 'rider' || u.status !== 'active' || !isOfferableToRider(order)) return;
    if (order.expiresAt && new Date(order.expiresAt).getTime() <= Date.now()) return;
    let isNewOffer = false;
    setIncomingRideOffer((prev) => {
      if (prev?.id === order.id) return { ...prev, ...order };
      isNewOffer = true;
      return order;
    });
    if (!isNewOffer) return;
    setActiveTab('dashboard');
    unlockIncomingRideAudio();
    playIncomingRidePulse();
    if (navigator.vibrate) navigator.vibrate([400, 200, 400, 200, 400]);
    if (typeof document !== 'undefined' && document.hidden && Notification.permission === 'granted') {
      const earnings = (order as Order & { delivery_fee?: number }).delivery_fee ?? order.total;
      try {
        new Notification('BytzGo — Incoming ride', {
          body: `${formatCedis(earnings)} · ${order.address || 'New pickup'}`,
          tag: `ride-${order.id}`,
          requireInteraction: true,
        });
      } catch {
        /* Notification constructor blocked */
      }
    }
  }, []);

  const refreshData = async () => {
    if (!token) return;
    setRefreshing(true);
    try {
      const storedUser = JSON.parse(localStorage.getItem('user') || '{}');
      const role = user?.role || storedUser.role;
      const region = user?.region || storedUser.region;

      // Always fetch wallet and paystack config
      const walletPromise = axios.get('/api/wallet');
      const paystackPromise = axios.get('/api/config/paystack').catch(() => ({ data: { publicKey: '' } }));
      const pricingPromise = axios.get('/api/config/pricing').catch(() => ({ data: { price_per_km: DEFAULT_DELIVERY_PRICE_PER_KM } }));

      // Conditional promises based on role
      const ordersPromise = axios.get('/api/orders'); // Everyone needs orders
      
      const productsPromise = role === 'vendor'
        ? axios.get('/api/products', { params: { vendor_id: user?.id || storedUser.id } })
        : role === 'customer'
          ? axios.get('/api/products')
          : Promise.resolve({ data: [] });

      const vendorsPromise = (role === 'customer' || role === 'rider') 
        ? axios.get('/api/vendors', { params: { region } }) 
        : Promise.resolve({ data: [] });

      const zonesPromise =
        role === 'customer' || role === 'rider' || role === 'admin' || role === 'vendor'
          ? axios.get('/api/delivery-zones').catch(() => ({ data: [] }))
          : Promise.resolve({ data: [] });

      const [profileRes, ordersRes, productsRes, vendorsRes, configRes, pricingRes, zonesRes] = await Promise.all([
        walletPromise,
        ordersPromise,
        productsPromise,
        vendorsPromise,
        paystackPromise,
        pricingPromise,
        zonesPromise
      ]);

      setPaystackKey(configRes.data.publicKey);
      const rate = Number(pricingRes.data?.price_per_km);
      setDeliveryPricePerKm(rate > 0 ? rate : DEFAULT_DELIVERY_PRICE_PER_KM);
      setUser(prev => prev ? { ...prev, balance: profileRes.data.balance } : { ...storedUser, balance: profileRes.data.balance });
      setOrders(ordersRes.data);
      setProducts(productsRes.data);
      setVendors(vendorsRes.data);
      setZones(zonesRes.data);
    } catch (err) {
      console.error('Fetch failed', err);
    } finally {
      setRefreshing(false);
    }
  };

  const addNotification = (message: string, type: 'info' | 'success' | 'warning' = 'info') => {
    const id = Math.random().toString(36).substr(2, 9);
    setNotifications(prev => [...prev, { id, message, type }]);
    setTimeout(() => {
      setNotifications(prev => prev.filter(n => n.id !== id));
    }, 5000);
    
    if (Notification.permission === 'granted') {
      new Notification('BytzGo', { body: message });
    }
  };

  useEffect(() => {
    if (user && token && needsDeviceSetup(user.role)) {
      setShowDeviceSetup(true);
    }
  }, [user?.id, user?.role, token]);

  useEffect(() => {
    if (user?.role !== 'admin' || !token) return;
    axios.get('/api/admin/pending-products').then((res) => setAdminPendingCount(res.data?.length || 0)).catch(() => {});
    axios.get('/api/admin/pending-riders').then((res) => setAdminPendingRiderCount(res.data?.length || 0)).catch(() => {});
  }, [user?.role, token, orders.length]);

  const handleIncomingRideFromExternal = useCallback(
    async (orderId: string, action?: string) => {
      let order = orders.find(o => o.id === orderId);
      if (!order && token) {
        try {
          const res = await axios.get('/api/orders');
          setOrders(res.data);
          order = res.data.find((o: Order) => o.id === orderId);
        } catch {
          /* ignore */
        }
      }
      if (!order || !isOfferableToRider(order)) return;
      triggerIncomingRideCall(order);
      if (action === 'accept' && userRef.current?.role === 'rider') {
        try {
          const res = await axios.patch(`/api/orders/${order.id}`, {
            status: order.status,
            riderId: userRef.current.id,
          });
          setOrders(prev => prev.map(o => (o.id === order.id ? res.data : o)));
          setIncomingRideOffer(null);
          addNotification('Ride accepted! Head to pickup.', 'success');
        } catch (err: unknown) {
          const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
          addNotification(msg || 'Could not accept ride. Go online and try again.', 'warning');
        }
      }
    },
    [orders, token, triggerIncomingRideCall]
  );

  useEffect(() => {
    if (showDeviceSetup || user?.role !== 'rider' || user.status !== 'active' || !user.is_online || !token) return;
    unlockIncomingRideAudio();
    if (Notification.permission === 'granted') {
      subscribeRiderPush().catch(err => console.warn('Push subscribe failed', err));
    }
  }, [user?.id, user?.role, user?.status, user?.is_online, token, showDeviceSetup]);

  // Show incoming-call UI for active dispatch offers (socket backup + refresh)
  useEffect(() => {
    if (user?.role !== 'rider' || user.status !== 'active' || !user.is_online) return;
    const best = pickBestRideOffer(orders);
    if (best) triggerIncomingRideCall(best);
  }, [orders, user?.role, user?.status, user?.is_online, pickBestRideOffer, triggerIncomingRideCall]);

  // Poll offers while online so missed socket events still ring
  useEffect(() => {
    if (showDeviceSetup || user?.role !== 'rider' || user.status !== 'active' || !user.is_online || !token) return;
    const poll = setInterval(() => {
      axios.get<Order[]>('/api/orders').then((res) => setOrders(res.data)).catch(() => {});
    }, 3000);
    return () => clearInterval(poll);
  }, [user?.role, user?.status, user?.is_online, token, showDeviceSetup]);

  useEffect(() => {
    return onServiceWorkerRideMessage(msg => {
      if (msg.orderId) handleIncomingRideFromExternal(msg.orderId, msg.action);
    });
  }, [handleIncomingRideFromExternal]);

  useEffect(() => {
    const params = new URLSearchParams(location.search);
    const offerId = params.get('offer');
    const action = params.get('action') || undefined;
    if (!offerId || user?.role !== 'rider') return;
    handleIncomingRideFromExternal(offerId, action);
    navigate(location.pathname, { replace: true });
  }, [location.search, user?.role, handleIncomingRideFromExternal, navigate, location.pathname]);

  // Axios base URL configured in main.tsx via configureApiClient()
  useEffect(() => {
    if (token) {
      axios.defaults.headers.common['Authorization'] = `Bearer ${token}`;
      localStorage.setItem('token', token);
    } else {
      delete axios.defaults.headers.common['Authorization'];
      localStorage.removeItem('token');
    }
  }, [token]);

  // Set up response interceptor to handle 401/403 (unauthorized/forbidden) and automatically logout
  useEffect(() => {
    const interceptor = axios.interceptors.response.use(
      (response) => response,
      (error) => {
        if (error.response && (error.response.status === 401 || error.response.status === 403)) {
          console.warn('Session expired or unauthorized. Logging out.');
          handleLogout();
        }
        return Promise.reject(error);
      }
    );
    return () => {
      axios.interceptors.response.eject(interceptor);
    };
  }, []);

  // Fetch initial data and setup sockets
  useEffect(() => {
    // Handle Google Redirect Result
    const initAuth = async () => {
      try {
        // 1. Check Supabase Auth redirect session
        const { data: { session } } = await supabase.auth.getSession();
        if (session && session.access_token) {
          const savedRole = localStorage.getItem('google_login_role') || 'customer';
          const res = await axios.post('/api/auth/supabase', {
            accessToken: session.access_token,
            role: savedRole
          });
          localStorage.removeItem('google_login_role');
          
          // Sign out of Supabase locally to keep local storage clean
          await supabase.auth.signOut();

          const expected = getExpectedRole();
          if (res.data.user.role !== expected) {
            console.warn(`Role mismatch: got ${res.data.user.role}, expected ${expected}`);
            return;
          }
          setUser(res.data.user);
          setToken(res.data.token);
          localStorage.setItem('user', JSON.stringify(res.data.user));
          return;
        }

      } catch (err) {
        console.error('Auth redirect failed', err);
      } finally {
        if (!localStorage.getItem('token')) {
          setLoading(false);
        }
      }
    };
    initAuth();
  }, []);

  // Fetch initial data and setup sockets when token is available
  useEffect(() => {
    if (!token) {
      socket.disconnect();
      setLoading(false);
      return;
    }

    const joinSocketRoom = () => {
      const storedUser = JSON.parse(localStorage.getItem('user') || '{}');
      if (storedUser?.id) socket.emit('join', storedUser.id);
    };

    const init = async () => {
      try {
        await refreshData();
        const storedUser = JSON.parse(localStorage.getItem('user') || '{}');
        // Set default tab based on role
        if (storedUser.role === 'vendor') setActiveTab('orders');
        else if (storedUser.role === 'rider') setActiveTab('dashboard');
        else if (storedUser.role === 'admin') setActiveTab('orders');
        else setActiveTab('courier');

        if (!socket.connected) socket.connect();
        joinSocketRoom();
      } catch (err: any) {
        console.error('Initialization failed', err);
        if (err.response && (err.response.status === 401 || err.response.status === 403)) {
          handleLogout();
        }
      } finally {
        setLoading(false);
      }
    };

    init();

    socket.on('connect', joinSocketRoom);

    socket.on('ride:incoming', (order: Order) => {
      if (order.expiresAt && new Date(order.expiresAt).getTime() <= Date.now()) return;
      setOrders(prev => {
        const exists = prev.some(o => o.id === order.id);
        return exists ? prev.map(o => (o.id === order.id ? { ...o, ...order } : o)) : [order, ...prev];
      });
      const u = userRef.current;
      if (u?.role === 'rider' && u.status === 'active' && isOfferableToRider(order)) {
        triggerIncomingRideCall(order);
      }
    });

    socket.on('ride:taken', ({ orderId, reason }: { orderId: string; reason?: string }) => {
      const u = userRef.current;
      const wasIncoming = ordersRef.current.some(
        (o) => o.id === orderId && isOfferableToRider(o)
      );
      setIncomingRideOffer(prev => (prev?.id === orderId ? null : prev));
      setOrders(prev =>
        prev.filter(o => {
          if (o.id !== orderId) return true;
          return u?.role === 'rider' && (o.rider_id === u.id || (o as Order & { riderId?: string }).riderId === u.id);
        })
      );
      if (u?.role === 'rider' && u.status === 'active' && wasIncoming) {
        addNotification(
          reason === 'cancelled'
            ? 'Customer cancelled this request'
            : 'Another driver took this ride',
          'info'
        );
      }
    });

    socket.on('order:new', (order: Order) => {
      setOrders(prev => [order, ...prev]);
      const u = userRef.current;
      if (u?.role === 'vendor' && order.vendor_id === u.id) {
        addNotification('New order received!', 'success');
      }
      if (
        u?.role === 'vendor' &&
        order.customer_id === u.id &&
        ((order as Order & { order_type?: string }).order_type === 'courier' ||
          (order as Order & { orderType?: string }).orderType === 'courier')
      ) {
        addNotification('Package delivery booked', 'success');
      }
    });

    socket.on('order:updated', (updatedOrder: Order) => {
      const prevOrder = ordersRef.current.find((o) => o.id === updatedOrder.id);
      setOrders(prev => prev.map(o => o.id === updatedOrder.id ? updatedOrder : o));
      const u = userRef.current;
      if (
        u?.role === 'customer' &&
        updatedOrder.customer_id === u.id &&
        updatedOrder.rider_id &&
        !prevOrder?.rider_id
      ) {
        addNotification('Your driver accepted — track them on the map', 'success');
        setActiveTab('courier');
      }
      if (u?.role === 'customer' && updatedOrder.status === 'picked_up' && updatedOrder.customer_id === u.id) {
        addNotification('Your order has been picked up!', 'info');
        setActiveTab('courier');
      }
      if (u?.role === 'customer' && updatedOrder.status === 'arrived' && updatedOrder.customer_id === u.id) {
        addNotification('Your driver has arrived — complete payment to get your PIN', 'info');
        setActiveTab('courier');
      }
      if (u?.role === 'customer' && updatedOrder.status === 'delivered' && updatedOrder.customer_id === u.id) {
        addNotification('Your order has been delivered!', 'success');
      }
      if (
        u?.role === 'vendor' &&
        updatedOrder.customer_id === u.id &&
        ((updatedOrder as Order & { order_type?: string }).order_type === 'courier' ||
          (updatedOrder as Order & { orderType?: string }).orderType === 'courier')
      ) {
        if (updatedOrder.status === 'picked_up') {
          addNotification('Your package was picked up', 'info');
        }
        if (updatedOrder.status === 'delivered') {
          addNotification('Package delivered', 'success');
        }
        if (
          updatedOrder.rider_id &&
          !prevOrder?.rider_id
        ) {
          addNotification('Rider assigned to your package', 'success');
        }
      }
      setIncomingRideOffer(prev =>
        prev?.id === updatedOrder.id && updatedOrder.rider_id ? null : prev
      );
    });

    socket.on('location:updated', ({ riderId, lat, lng }) => {
      setRiderLocations((prev) => ({ ...prev, [riderId]: { lat, lng } }));

      const u = userRef.current;
      if (u?.role !== 'customer' || riderId === u.id) return;
      if (riderTrackingNotifiedRef.current.has(riderId)) return;

      const trackingMyOrder = ordersRef.current.some(
        (o) =>
          o.customer_id === u.id &&
          (o.rider_id === riderId || (o as Order & { riderId?: string }).riderId === riderId) &&
          !['delivered', 'cancelled'].includes(o.status)
      );
      if (!trackingMyOrder) return;

      riderTrackingNotifiedRef.current.add(riderId);
      addNotification('Your rider is sharing live location', 'success');
    });

    socket.on('wallet:updated', (data: { balance: number }) => {
      setUser(prev => prev ? { ...prev, balance: data.balance } : null);
    });

    socket.on('status:updated', (payload: { status: string; is_online?: boolean }) => {
      setUser(prev => (prev ? { ...prev, status: payload.status, is_online: payload.is_online ?? prev.is_online } : null));
      const stored = JSON.parse(localStorage.getItem('user') || '{}');
      localStorage.setItem('user', JSON.stringify({ ...stored, status: payload.status, is_online: payload.is_online ?? stored.is_online }));
    });

    return () => {
      socket.off('connect', joinSocketRoom);
      socket.off('ride:incoming');
      socket.off('ride:taken');
      socket.off('order:new');
      socket.off('order:updated');
      socket.off('location:updated');
      socket.off('wallet:updated');
      socket.off('status:updated');
    };
  }, [token, triggerIncomingRideCall]);

  // Re-fetch region-specific data when user region changes
  useEffect(() => {
    if (user?.id) {
      axios.get('/api/vendors', { params: { region: user.region } }).then(res => setVendors(res.data));
      axios.get('/api/orders').then(res => setOrders(res.data));
    }
  }, [user?.region]);

  const handleLogin = (userData: AuthUser, authToken: string) => {
    // Block login if user role doesn't match the expected role for this path
    const expected = getExpectedRole();
    if (userData.role !== expected) {
      return false; // Signal rejection to AuthScreen
    }
    setUser(userData);
    setToken(authToken);
    localStorage.setItem('user', JSON.stringify(userData));
    if (needsDeviceSetup(userData.role)) {
      setShowDeviceSetup(true);
    }
    return true;
  };

  const handleLogout = () => {
    setUser(null);
    setToken(null);
    localStorage.removeItem('user');
    localStorage.removeItem('token');
    localStorage.removeItem('bytzgo_cart');
  };

  const updateOrderStatus = async (orderId: string, status: OrderStatus, extra = {}) => {
    try {
      const res = await axios.patch(`/api/orders/${orderId}`, { status, ...extra });
      setOrders(prev => prev.map(o => (o.id === orderId ? res.data : o)));
      return true;
    } catch (err: unknown) {
      const axiosErr = err as { response?: { status?: number; data?: { message?: string } } };
      const statusCode = axiosErr.response?.status;
      const msg = axiosErr.response?.data?.message;
      if (statusCode === 409) {
        addNotification(msg || 'Another driver took this ride', 'warning');
        setIncomingRideOffer(prev => (prev?.id === orderId ? null : prev));
        setOrders(prev => prev.filter(o => o.id !== orderId || o.rider_id === userRef.current?.id));
      } else {
        addNotification(msg || 'Could not update order. Try again.', 'warning');
      }
      console.error('Update failed', err);
      return false;
    }
  };

  // Redirect logged-in users to their correct dashboard paths if they land elsewhere
  useEffect(() => {
    if (user) {
      const path = location.pathname;
      if (user.role === 'rider' && !path.startsWith('/motor')) {
        navigate('/motor');
      } else if (user.role === 'vendor' && !path.startsWith('/vendor')) {
        navigate('/vendor');
      } else if (user.role === 'admin' && !path.startsWith('/admin')) {
        navigate('/admin');
      } else if (user.role === 'customer' && (path.startsWith('/motor') || path.startsWith('/vendor') || path.startsWith('/admin'))) {
        navigate('/');
      }
    }
  }, [user, location.pathname, navigate]);

  if (loading) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center bg-slate-50 gap-8">
        <LoadingIndicator size="xl" withText text="Loading flavors..." />
        <div className="text-center">
          <h2 className="text-3xl font-black italic tracking-tighter mb-2">
            <span className="text-brand-blue">bytz</span>
            <span className="text-brand-green">go</span>
          </h2>
        </div>
      </div>
    );
  }

  if (!token || !user) {
    return (
      <AuthScreen onLogin={handleLogin} forcedRole={forcedRole} />
    );
  }

  if (user.role === 'rider') {
    return (
      <MapsProvider>
        <InstallPermissionsOnboarding
          open={showDeviceSetup}
          role={user.role}
          user={user}
          onComplete={() => setShowDeviceSetup(false)}
          onUserRefresh={(updatedUser, newToken) => {
            setUser(updatedUser as unknown as AuthUser);
            setToken(newToken);
            localStorage.setItem('user', JSON.stringify(updatedUser));
            localStorage.setItem('token', newToken);
          }}
        />
        <ConfirmationModal
          isOpen={isLogoutModalOpen}
          onClose={() => setIsLogoutModalOpen(false)}
          onConfirm={handleLogout}
          title="Sign Out"
          message="Are you sure you want to log out of BytzGo?"
          confirmLabel="Sign Out"
          type="danger"
        />
        <IncomingRideCallModal
          order={incomingRideOffer}
          vendors={vendors}
          onAccept={async (orderId, status) => {
            const ok = await updateOrderStatus(orderId, status, { riderId: user.id });
            if (!ok) return;
            setIncomingRideOffer(null);
            addNotification('Ride accepted! Head to pickup.', 'success');
          }}
          onDecline={() => setIncomingRideOffer(null)}
        />
        <PullToRefresh onRefresh={refreshData} refreshing={refreshing}>
          <div className="fixed top-4 right-4 z-[9999] space-y-2 pointer-events-none max-w-sm">
            {notifications.map((n) => (
              <motion.div
                key={n.id}
                initial={{ opacity: 0, x: 40 }}
                animate={{ opacity: 1, x: 0 }}
                className={cn(
                  'px-4 py-3 rounded-xl shadow-xl text-xs font-black uppercase tracking-widest pointer-events-auto',
                  n.type === 'success' ? 'bg-brand-green text-white' : n.type === 'warning' ? 'bg-red-500 text-white' : 'bg-slate-800 text-white border border-slate-700'
                )}
              >
                {n.message}
              </motion.div>
            ))}
          </div>
          <RiderApp
            user={user}
            setUser={setUser}
            orders={orders}
            vendors={vendors}
            onUpdateStatus={updateOrderStatus}
            onLogout={() => setIsLogoutModalOpen(true)}
            pendingApproval={user.status === 'pending' || user.status === 'rejected'}
            addNotification={addNotification}
            refreshData={refreshData}
            paystackKey={paystackKey}
            setPaystackKey={setPaystackKey}
          />
        </PullToRefresh>
      </MapsProvider>
    );
  }

  if (user.role === 'customer') {
    return (
      <MapsProvider>
        <InstallPermissionsOnboarding
          open={showDeviceSetup}
          role={user.role}
          user={user}
          onComplete={() => setShowDeviceSetup(false)}
          onUserRefresh={(updatedUser, newToken) => {
            setUser(updatedUser as unknown as AuthUser);
            setToken(newToken);
            localStorage.setItem('user', JSON.stringify(updatedUser));
            localStorage.setItem('token', newToken);
          }}
        />
        <ConfirmationModal
          isOpen={isLogoutModalOpen}
          onClose={() => setIsLogoutModalOpen(false)}
          onConfirm={handleLogout}
          title="Sign Out"
          message="Are you sure you want to log out of BytzGo?"
          confirmLabel="Sign Out"
          type="danger"
        />
        <PullToRefresh onRefresh={refreshData} refreshing={refreshing}>
          <CustomerShell
            user={user}
            vendors={vendors}
            activeTab={activeTab}
            setActiveTab={setActiveTab}
            cart={cart}
            setCart={setCart}
            isCartOpen={isCartOpen}
            setIsCartOpen={setIsCartOpen}
            subtotal={subtotal}
            deliveryFee={deliveryFee}
            total={total}
            orders={orders}
            notifications={notifications}
            setNotifications={setNotifications}
            onLogout={() => setIsLogoutModalOpen(true)}
            paystackKey={paystackKey}
            setPaystackKey={setPaystackKey}
            addNotification={addNotification}
            refreshData={refreshData}
          >
            <CustomerView
              user={user}
              orders={orders}
              products={products}
              vendors={vendors}
              riderLocations={riderLocations}
              paystackKey={paystackKey}
              setPaystackKey={setPaystackKey}
              addNotification={addNotification}
              cart={cart}
              setCart={setCart}
              isCartOpen={isCartOpen}
              setIsCartOpen={setIsCartOpen}
              activeTab={activeTab}
              setActiveTab={setActiveTab}
              onPlaceOrder={async (items, totalAmt, vendorId, extra = {}) => {
                try {
                  const vendor = vendorId
                    ? vendors.find((v) => v.id === vendorId)
                    : undefined;
                  const payload = vendorId
                    ? {
                        items,
                        total: totalAmt,
                        vendorId,
                        ...buildShopOrderExtra({
                          user,
                          vendor,
                          deliveryFee,
                          extra,
                        }),
                      }
                    : {
                        items,
                        total: totalAmt,
                        vendorId,
                        address: extra.address || user.address || 'East Legon, Accra',
                        lat: extra.lat || user.lat,
                        lng: extra.lng || user.lng,
                        ...extra,
                      };
                  await axios.post('/api/orders', payload);
                  await refreshData();
                  addNotification('Order placed', 'success');
                } catch (err) {
                  console.error('Order failed', err);
                  addNotification(getApiError(err, 'Failed to place order'), 'warning');
                }
              }}
              zones={zones}
              deliveryPricePerKm={deliveryPricePerKm}
              subtotal={subtotal}
              deliveryFee={deliveryFee}
              total={total}
              refreshData={refreshData}
              onUserUpdate={(updatedUser, newToken) => {
                setUser(updatedUser);
                setToken(newToken);
                localStorage.setItem('user', JSON.stringify(updatedUser));
                localStorage.setItem('token', newToken);
              }}
            />
          </CustomerShell>
        </PullToRefresh>
      </MapsProvider>
    );
  }

  return (
    <MapsProvider>
      <InstallPermissionsOnboarding
        open={showDeviceSetup}
        role={user.role}
        user={user}
        onComplete={() => setShowDeviceSetup(false)}
        onUserRefresh={(updatedUser, newToken) => {
          setUser(updatedUser as unknown as AuthUser);
          setToken(newToken);
          localStorage.setItem('user', JSON.stringify(updatedUser));
          localStorage.setItem('token', newToken);
        }}
      />
      <ConfirmationModal
        isOpen={isLogoutModalOpen}
        onClose={() => setIsLogoutModalOpen(false)}
        onConfirm={handleLogout}
        title="Sign Out"
        message="Are you sure you want to log out of BytzGo?"
        confirmLabel="Sign Out"
        type="danger"
      />
      <DarkAppShell
        title={user.role === 'vendor' ? 'Merchant' : 'Control Tower'}
        subtitle={user.name}
        userName={user.name}
        balance={Number(user.balance || 0)}
        onLogout={() => setIsLogoutModalOpen(true)}
        activeTab={activeTab}
        onTabChange={setActiveTab}
        notifications={notifications}
        onDismissNotification={(id) => setNotifications((prev) => prev.filter((n) => n.id !== id))}
        navItems={
          user.role === 'vendor'
            ? ([
                { id: 'orders', label: 'Orders', icon: ShoppingBag },
                { id: 'send', label: 'Send', icon: Package },
                { id: 'products', label: 'Menu', icon: Layout },
                { id: 'store', label: 'Store', icon: Store },
                { id: 'wallet', label: 'Wallet', icon: CreditCard },
              ] as NavItem[])
            : ([
                { id: 'orders', label: 'Orders', icon: ShoppingBag },
                { id: 'users', label: 'Users', icon: Users },
                { id: 'drivers', label: 'Drivers', icon: Bike, badge: adminPendingRiderCount },
                { id: 'products', label: 'Approve', icon: Package, badge: adminPendingCount },
                { id: 'revenue', label: 'Revenue', icon: BarChart3 },
                { id: 'promotions', label: 'Promos', icon: Tag },
                { id: 'zones', label: 'Zones', icon: MapPin },
                { id: 'settings', label: 'Settings', icon: Settings },
              ] as NavItem[])
        }
      >
        <PullToRefresh onRefresh={refreshData} refreshing={refreshing}>
          <div className="max-w-7xl mx-auto">
            {user.status === 'pending' && user.role === 'vendor' && (
              <div className="mb-6 p-4 rounded-2xl bg-amber-500/10 border border-amber-500/30 flex items-center gap-4">
                <AlertCircle className="text-amber-400 shrink-0" size={24} />
                <p className="text-sm text-amber-200">Account pending ? orders unlock after approval.</p>
              </div>
            )}
            <AnimatePresence mode="wait">
              {user.role === 'vendor' && (
                <VendorView user={user} orders={orders} products={products} riderLocations={riderLocations} zones={zones} deliveryPricePerKm={deliveryPricePerKm} paystackKey={paystackKey} setPaystackKey={setPaystackKey} onPlaceOrder={async (items, totalAmt, vendorId, extra = {}) => {
                  try {
                    const vendor = vendorId ? vendors.find((v) => v.id === vendorId) : undefined;
                    const payload = vendorId
                      ? { items, total: totalAmt, vendorId, ...buildShopOrderExtra({ user, vendor, deliveryFee, extra }) }
                      : { items, total: totalAmt, vendorId, address: extra.address || user.address || 'East Legon, Accra', lat: extra.lat || user.lat, lng: extra.lng || user.lng, ...extra };
                    await axios.post('/api/orders', payload);
                    await refreshData();
                    addNotification('Delivery booked', 'success');
                  } catch (err) {
                    console.error('Order failed', err);
                    addNotification(getApiError(err, 'Failed to book delivery'), 'warning');
                  }
                }} onUpdateStatus={updateOrderStatus} addNotification={addNotification} onBalanceUpdate={(bal) => setUser((prev) => (prev ? { ...prev, balance: bal } : prev))} onAddProduct={(p) => setProducts((prev) => { const exists = prev.find((item) => item.id === p.id); if (exists) return prev.map((item) => (item.id === p.id ? p : item)); return [...prev, p]; })} onDeleteProduct={async (id) => { await axios.delete(`/api/products/${id}`); setProducts((prev) => prev.filter((p) => p.id !== id)); }} activeTab={activeTab} setActiveTab={setActiveTab} refreshData={refreshData} onUserUpdate={(updatedUser, newToken) => { setUser(updatedUser); setToken(newToken); localStorage.setItem('user', JSON.stringify(updatedUser)); localStorage.setItem('token', newToken); }} />
              )}
              {user.role === 'admin' && (
                <AdminView user={user} orders={orders} addNotification={addNotification} activeTab={activeTab} setActiveTab={setActiveTab} onPendingCountChange={setAdminPendingCount} onPendingRiderCountChange={setAdminPendingRiderCount} />
              )}
            </AnimatePresence>
          </div>
        </PullToRefresh>
      </DarkAppShell>
    </MapsProvider>
  );
}

function rolePortalHint(r: Role): string {
  switch (r) {
    case 'rider': return 'the rider app (/motor)';
    case 'vendor': return 'the vendor portal (/vendor)';
    case 'admin': return 'the admin portal (/admin)';
    default: return 'the customer app (home page)';
  }
}

function loginRejectedMessage(actualRole: Role, expectedRole: Role): string {
  return `This account is registered as ${actualRole}. Use ${rolePortalHint(actualRole)}, or sign up as ${expectedRole} on this page.`;
}

function isValidGhanaPhoneClient(phone: string): boolean {
  const d = phone.trim().replace(/\s+/g, '');
  return /^0\d{9}$/.test(d) || /^233\d{9}$/.test(d) || /^\d{9}$/.test(d);
}

function mapAuthError(err: unknown, fallback: string): string {
  const e = err as { code?: string; response?: { data?: { message?: string } }; message?: string };
  if (e.code === 'auth/popup-closed-by-user') return 'Sign-in was cancelled.';
  if (e.code === 'auth/popup-blocked') return 'Redirecting to Google sign-in…';
  if (e.code === 'auth/cancelled-popup-request') return 'Please wait and try Google sign-in again.';
  return e.response?.data?.message || e.message || fallback;
}

function AuthScreen({ onLogin, forcedRole }: { onLogin: (user: AuthUser, token: string) => boolean | void, forcedRole?: Role }) {
  const [isLogin, setIsLogin] = useState(true);
  const [role, setRole] = useState<Role>(forcedRole || 'customer');

  useEffect(() => {
    if (forcedRole) setRole(forcedRole);
  }, [forcedRole]);

  // Auth fields
  const [loginId, setLoginId] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [adminInviteSecret, setAdminInviteSecret] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  // OTP Verification state
  const [otp, setOtp] = useState('');
  const [isOtpModalOpen, setIsOtpModalOpen] = useState(false);
  const [otpPurpose, setOtpPurpose] = useState<'signup_verify' | 'forgot_password'>('signup_verify');
  const [otpError, setOtpError] = useState('');
  const [otpLoading, setOtpLoading] = useState(false);
  const [resendLoading, setResendLoading] = useState(false);

  // Forgot Password state (phone + email, no SMS)
  const [isForgotPassword, setIsForgotPassword] = useState(false);
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showNewPassword, setShowNewPassword] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    if (!isLogin && role === 'customer') {
      if (!phone) {
        setError('Phone number is required.');
        return;
      }
      if (!isValidGhanaPhoneClient(phone)) {
        setError('Enter a valid Ghana phone number (e.g. 0247904675).');
        return;
      }
    }

    if (!isLogin && role === 'admin' && !adminInviteSecret.trim()) {
      setError('Admin invite code is required.');
      return;
    }

    // Standard Login / Non-customer signup flow
    setLoading(true);
    try {
      const endpoint = isLogin ? '/api/auth/login' : '/api/auth/register';
      const payload = isLogin
        ? { login: loginId.trim(), password }
        : {
            name,
            email,
            password,
            role,
            ...(role === 'customer' ? { phone } : {}),
            ...(role === 'admin' ? { adminInviteSecret: adminInviteSecret.trim() } : {}),
          };

      const res = await axios.post(endpoint, payload);
      const accepted = onLogin(res.data.user, res.data.token);
      if (accepted === false) {
        setError(loginRejectedMessage(res.data.user.role as Role, forcedRole || role));
      }
    } catch (err: unknown) {
      setError(mapAuthError(err, 'Invalid phone/email or password. Please try again.'));
    } finally {
      setLoading(false);
    }
  };

  const handleVerifySignupOtp = async (e: React.FormEvent) => {
    e.preventDefault();
    setOtpError('');
    setOtpLoading(true);

    try {
      // 1. Verify OTP first
      await axios.post('/api/auth/verify-otp', { phone, otp, purpose: 'signup_verify' });
      
      // 2. Verified successfully! complete the registration
      setIsOtpModalOpen(false);
      setLoading(true);
      
      const res = await axios.post('/api/auth/register', { name, email, password, role, phone, otp });
      const accepted = onLogin(res.data.user, res.data.token);
      if (accepted === false) {
        setError(loginRejectedMessage(res.data.user.role as Role, forcedRole || role));
      }
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string } } };
      setOtpError(e.response?.data?.message || 'Invalid or expired verification code. Please try again.');
    } finally {
      setOtpLoading(false);
      setLoading(false);
    }
  };

  const handleResendOtp = async () => {
    setOtpError('');
    setError('');
    setResendLoading(true);
    try {
      await axios.post('/api/auth/resend-otp', {
        phone,
        purpose: otpPurpose,
        ...(otpPurpose === 'signup_verify' ? { email } : {}),
      });
      setOtpError('');
      if (isForgotPassword) {
        setError('');
        alert('A new reset code was sent to your phone.');
      } else {
        alert('A new verification code was sent to your phone.');
      }
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string } } };
      setOtpError(e.response?.data?.message || 'Could not resend code. Try again shortly.');
    } finally {
      setResendLoading(false);
    }
  };

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (!phone) {
      setError('Registered phone number is required.');
      return;
    }
    if (!isValidGhanaPhoneClient(phone)) {
      setError('Enter a valid Ghana phone number (e.g. 0247904675).');
      return;
    }
    if (!email.trim()) {
      setError('Registered email address is required.');
      return;
    }
    if (newPassword.length < 6) {
      setError('Password must be at least 6 characters.');
      return;
    }
    if (newPassword !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    setLoading(true);
    try {
      await axios.post('/api/auth/reset-password', { phone, email: email.trim(), newPassword });
      setIsForgotPassword(false);
      setIsLogin(true);
      setError('');
      alert('Password updated! Sign in with your phone number or email and new password.');
    } catch (err: any) {
      setError(err.response?.data?.message || 'Could not reset password. Check phone and email match your account.');
    } finally {
      setLoading(false);
    }
  };

  const finishGoogleLogin = async (idToken: string) => {
    const res = await axios.post('/api/auth/google', {
      credential: idToken,
      role,
    });
    const accepted = onLogin(res.data.user, res.data.token);
    if (accepted === false) {
      setError(loginRejectedMessage(res.data.user.role as Role, forcedRole || role));
    }
  };

  const onGoogleCredential = async (credential: string) => {
    setLoading(true);
    setError('');
    try {
      localStorage.setItem('google_login_role', role);
      await finishGoogleLogin(credential);
    } catch (err: unknown) {
      console.error('Google sign-in failed:', err);
      setError(mapAuthError(err, 'Google sign-in failed. Try email and password instead.'));
    } finally {
      setLoading(false);
    }
  };

  const heroImage =
    forcedRole === 'rider'
      ? '/branding/hero_rider.png'
      : forcedRole === 'vendor'
        ? '/branding/hero_delivery.png'
        : '/branding/hero_login.png';

  return (
    <>
    <motion.div className="min-h-screen relative overflow-hidden bg-slate-950">
      <motion.div
        className="absolute inset-0 bg-cover bg-center scale-105"
        style={{ backgroundImage: `url(${heroImage})` }}
        aria-hidden
      />
      <div className="absolute inset-0 bg-gradient-to-b from-black/40 via-black/55 to-black/90" aria-hidden />
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="relative z-10 min-h-screen flex flex-col items-center justify-end sm:justify-center p-4 pb-8"
      >
        <motion.div className="w-full max-w-md mb-6 sm:mb-8 text-center px-2">
          <img
            src="/app-logo.png"
            alt="BytzGO"
            className="mx-auto mb-2 h-16 sm:h-20 w-auto max-w-[min(100%,320px)] object-contain drop-shadow-lg"
          />
          <p className="text-white/90 font-semibold text-sm sm:text-base drop-shadow">
            {forcedRole === 'rider'
              ? 'Sign in to continue to BytzGo Rider'
              : forcedRole === 'vendor'
                ? 'Sign in to continue to BytzGo Vendor'
                : forcedRole === 'admin'
                  ? 'Sign in to continue to BytzGo Admin'
                  : 'Sign in to continue to BytzGo'}
          </p>
          <p className="text-white/70 text-xs sm:text-sm mt-1 drop-shadow">
            {forcedRole === 'admin'
              ? 'Approve vendors, menu items, and platform settings'
              : forcedRole === 'rider'
                ? 'Accept jobs, navigate trips, and get paid'
                : forcedRole === 'vendor'
                  ? 'Manage your shop and incoming orders'
                  : 'Fast bike delivery — track every trip live'}
          </p>
          {forcedRole === 'admin' && (
            <motion.div className="mt-4 mx-auto max-w-sm p-3 rounded-2xl bg-black/50 backdrop-blur-md text-left border border-white/10">
              <p className="text-[10px] font-black uppercase tracking-widest text-red-400 mb-1">Admin sign-in</p>
              <p className="text-xs text-slate-200 leading-relaxed">
                Use an <strong className="text-white">admin</strong> account only. Run{' '}
                <code className="text-[10px] bg-black/40 px-1 rounded">npm run create:admin</code> for a local account, or Join with your invite code.
              </p>
              <p className="text-[10px] text-slate-400 mt-2 font-mono">Default: admin@bytzgo.net / Admin@2026</p>
            </motion.div>
          )}
          {forcedRole === 'rider' && (
            <motion.div className="mt-4 mx-auto max-w-sm p-3 rounded-2xl bg-black/50 backdrop-blur-md text-left border border-white/10">
              <p className="text-[10px] font-black uppercase tracking-widest text-brand-green mb-1">Rider sign-in</p>
              <p className="text-xs text-slate-200 leading-relaxed">
                Use a <strong className="text-white">rider</strong> account here. A Google account registered as customer must use the home app, or tap Join to register as rider.
              </p>
              <p className="text-[10px] text-slate-400 mt-2 font-mono">Demo: rider@bytzgo.net / Rider@2026</p>
            </motion.div>
          )}
        </motion.div>

        <motion.div className="w-full max-w-md bg-white/95 backdrop-blur-md p-8 rounded-[2.5rem] shadow-2xl shadow-black/40 border border-white/20">
          {isForgotPassword ? (
            // Forgot Password Flow
            <div className="space-y-6">
              <div className="text-center mb-4">
                <h3 className="text-xl font-black italic tracking-tighter text-slate-800 uppercase">Recover Password</h3>
                <p className="text-xs font-medium text-slate-400 mt-1 uppercase tracking-widest">
                  Use your registered phone and email
                </p>
              </div>

              {error && (
                <p className="text-[10px] font-black text-red-500 uppercase tracking-widest text-center px-2">
                  {error}
                </p>
              )}

              <form onSubmit={handleResetPassword} className="space-y-6">
                <div className="space-y-2">
                  <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Registered Phone</label>
                  <div className="relative">
                    <Phone className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                    <input
                      type="tel"
                      required
                      value={phone}
                      onChange={(e) => setPhone(e.target.value)}
                      placeholder="e.g. 024XXXXXXX"
                      className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Registered Email</label>
                  <div className="relative">
                    <Mail className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                    <input
                      type="email"
                      required
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      placeholder="name@example.com"
                      className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                    />
                  </div>
                </div>

                <div className="space-y-2">
                  <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">New Password</label>
                  <div className="relative">
                    <Lock className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                    <input
                      type={showNewPassword ? 'text' : 'password'}
                      required
                      value={newPassword}
                      onChange={(e) => setNewPassword(e.target.value)}
                      placeholder="New password (min 6 chars)"
                      className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 pr-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                    />
                    <button
                      type="button"
                      onClick={() => setShowNewPassword(!showNewPassword)}
                      className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-300 hover:text-slate-500 transition-colors"
                    >
                      {showNewPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                    </button>
                  </div>
                </div>

                <div className="space-y-2">
                  <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Confirm Password</label>
                  <div className="relative">
                    <Lock className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                    <input
                      type={showNewPassword ? 'text' : 'password'}
                      required
                      value={confirmPassword}
                      onChange={(e) => setConfirmPassword(e.target.value)}
                      placeholder="Re-enter new password"
                      className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                    />
                  </div>
                </div>

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full py-4 bg-brand-green text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all shadow-xl shadow-brand-green/20 flex items-center justify-center gap-2"
                >
                  {loading ? <LoadingIndicator size="sm" variant="white" /> : 'Reset Password'}
                </button>
              </form>

              <div className="text-center mt-6">
                <button
                  type="button"
                  onClick={() => {
                    setIsForgotPassword(false);
                    setError('');
                  }}
                  className="text-[10px] font-black uppercase tracking-widest text-slate-400 hover:text-slate-600 hover:underline"
                >
                  ← Back to Login
                </button>
              </div>
            </div>
          ) : (
            // Regular Login/Signup Flows
            <>
              <div className="flex p-1 bg-slate-100 rounded-2xl mb-8">
                <button 
                  onClick={() => {
                    setIsLogin(true);
                    setError('');
                  }}
                  className={cn("flex-1 py-3 text-sm font-black rounded-xl transition-all uppercase tracking-widest", isLogin ? "bg-white text-brand-blue shadow-sm" : "text-slate-500")}
                >
                  Login
                </button>
                <button 
                  onClick={() => {
                    setIsLogin(false);
                    setError('');
                  }}
                  className={cn("flex-1 py-3 text-sm font-black rounded-xl transition-all uppercase tracking-widest", !isLogin ? "bg-white text-brand-blue shadow-sm" : "text-slate-500")}
                >
                  Join
                </button>
              </div>

              <form onSubmit={handleSubmit} className="space-y-6">
                {!isLogin && (
                  <div className="space-y-2">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Full Name</label>
                    <div className="relative">
                      <UserIcon className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                      <input 
                        type="text" 
                        required
                        value={name}
                        onChange={(e) => setName(e.target.value)}
                        placeholder="Enter your name"
                        className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                      />
                    </div>
                  </div>
                )}

                {isLogin ? (
                  <div className="space-y-2">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Phone or Email</label>
                    <div className="relative">
                      <Phone className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                      <input
                        type="text"
                        required
                        autoComplete="username"
                        value={loginId}
                        onChange={(e) => setLoginId(e.target.value)}
                        placeholder="0247904675 or name@example.com"
                        className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                      />
                    </div>
                  </div>
                ) : (
                  <div className="space-y-2">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Email Address</label>
                    <div className="relative">
                      <Mail className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                      <input
                        type="email"
                        required
                        value={email}
                        onChange={(e) => setEmail(e.target.value)}
                        placeholder="name@example.com"
                        className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                      />
                    </div>
                  </div>
                )}

                {!isLogin && role === 'customer' && (
                  <div className="space-y-2">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Phone Number</label>
                    <div className="relative">
                      <Phone className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                      <input 
                        type="tel" 
                        required
                        value={phone}
                        onChange={(e) => setPhone(e.target.value)}
                        placeholder="e.g. 024XXXXXXX"
                        className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                      />
                    </div>
                  </div>
                )}

                {!isLogin && forcedRole === 'admin' && (
                  <div className="space-y-2">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Admin invite code</label>
                    <div className="relative">
                      <Shield className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                      <input
                        type="password"
                        required
                        value={adminInviteSecret}
                        onChange={(e) => setAdminInviteSecret(e.target.value)}
                        placeholder="From ADMIN_INVITE_SECRET in backend/.env"
                        className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                      />
                    </div>
                  </div>
                )}

                <div className="space-y-2">
                  <div className="flex justify-between items-center px-4">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400">Password</label>
                    {isLogin && (
                      <button 
                        type="button" 
                        onClick={() => {
                          setIsForgotPassword(true);
                          setError('');
                        }} 
                        className="text-[9px] font-black uppercase tracking-widest text-brand-blue hover:underline"
                      >
                        Forgot?
                      </button>
                    )}
                  </div>
                  <div className="relative">
                    <Lock className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                    <input 
                      type={showPassword ? "text" : "password"} 
                      required
                      value={password}
                      onChange={(e) => setPassword(e.target.value)}
                      placeholder="????????"
                      className="w-full bg-slate-50 border border-slate-100 p-4 pl-12 rounded-2xl focus:outline-none focus:border-brand-blue font-bold text-sm"
                    />
                    <button 
                      type="button"
                      onClick={() => setShowPassword(!showPassword)}
                      className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-300 hover:text-slate-500 transition-colors"
                    >
                      {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                    </button>
                  </div>
                </div>

                <button 
                  type="submit"
                  disabled={loading}
                  className="w-full py-4 bg-brand-green text-slate-900 rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all shadow-xl shadow-brand-green/30 flex items-center justify-center gap-2"
                >
                  {loading ? <LoadingIndicator size="sm" variant="white" /> : (isLogin ? 'Sign In' : 'Create Account')}
                </button>
              </form>

              {forcedRole !== 'admin' && (
              <div className="mt-6">
                <div className="flex items-center gap-4 mb-5">
                  <div className="flex-1 h-px bg-slate-200"></div>
                  <span className="text-[10px] font-black uppercase tracking-widest text-slate-300">or</span>
                  <div className="flex-1 h-px bg-slate-200"></div>
                </div>
                <div className="flex justify-center">
                  {isGoogleSignInConfigured ? (
                    <GoogleLogin
                      onSuccess={(res) => {
                        if (res.credential) void onGoogleCredential(res.credential);
                        else setError('Google sign-in failed. Try email and password instead.');
                      }}
                      onError={() =>
                        setError('Google sign-in failed. Try email and password instead.')
                      }
                      useOneTap={false}
                      theme="outline"
                      size="large"
                      shape="pill"
                      text={isLogin ? 'signin_with' : 'signup_with'}
                      width={320}
                    />
                  ) : (
                    <p className="text-[10px] font-bold text-slate-400 uppercase tracking-widest text-center">
                      Google sign-in not configured
                    </p>
                  )}
                </div>
              </div>
              )}
            </>
          )}
        </motion.div>
      </motion.div>
    </motion.div>

      {/* Global Error Modal */}
      <Modal 
        isOpen={!!error} 
        onClose={() => setError('')} 
        title="Authentication Issue"
      >
        <div className="space-y-6">
          <div className="flex gap-4 items-start">
            <div className="w-12 h-12 rounded-2xl bg-red-50 text-red-500 flex items-center justify-center shrink-0">
              <AlertCircle size={24} />
            </div>
            <p className="text-slate-500 font-medium leading-relaxed">{error}</p>
          </div>
          <button
            type="button"
            onClick={() => setError('')}
            className="w-full py-4 bg-slate-900 text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all"
          >
            Understood
          </button>
        </div>
      </Modal>

      {/* Signup OTP Verification Modal */}
      <Modal
        isOpen={isOtpModalOpen}
        onClose={() => setIsOtpModalOpen(false)}
        title="Phone Verification"
      >
        <form onSubmit={handleVerifySignupOtp} className="space-y-6">
          <div className="text-center">
            <div className="w-12 h-12 rounded-2xl bg-brand-blue/10 text-brand-blue flex items-center justify-center mx-auto mb-4">
              <Phone size={24} />
            </div>
            <p className="text-slate-600 font-medium text-sm leading-relaxed">
              We sent a 6-digit verification code to <span className="font-bold text-slate-800">{phone}</span> via SMS.
            </p>
          </div>

          <div className="space-y-2">
            <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Verification Code (6 Digits)</label>
            <input 
              type="text" 
              required
              maxLength={6}
              value={otp}
              onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
              placeholder="e.g. 123456"
              className="w-full bg-slate-50 border border-slate-100 p-4 text-center rounded-2xl focus:outline-none focus:border-brand-blue font-mono font-black text-xl tracking-[0.5em]"
            />
            {otpError && <p className="text-[10px] font-black text-red-500 uppercase tracking-widest ml-2">{otpError}</p>}
            <button
              type="button"
              disabled={resendLoading}
              onClick={handleResendOtp}
              className="w-full text-[10px] font-black uppercase tracking-widest text-brand-blue hover:underline disabled:opacity-50"
            >
              {resendLoading ? 'Sending…' : 'Resend code'}
            </button>
          </div>

          <div className="flex gap-3">
            <button
              type="button"
              onClick={() => setIsOtpModalOpen(false)}
              className="flex-1 py-4 bg-slate-100 text-slate-500 rounded-2xl font-black uppercase tracking-widest text-xs hover:bg-slate-200 transition-all"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={otpLoading}
              className="flex-1 py-4 bg-brand-blue text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all shadow-lg shadow-brand-blue/20 flex items-center justify-center gap-2"
            >
              {otpLoading ? <LoadingIndicator size="sm" variant="white" /> : 'Verify & Join'}
            </button>
          </div>
        </form>
      </Modal>
    </>
  );
}

function isPharmacyShop(vendor: { name?: string; shop_category?: string } | null) {
  if (!vendor) return false;
  if ((vendor.shop_category || '').toLowerCase() === 'pharmacy') return true;
  return /prime\s*care/i.test(vendor.name || '');
}

function productFallbackImage(item: { image_url?: string; category?: string; name?: string }, vendor: { name?: string; shop_category?: string } | null) {
  if (item.image_url?.trim()) return item.image_url.trim();
  if (isPharmacyShop(vendor)) return '/primecare_logo.png';
  const cat = `${item.category || ''} ${item.name || ''}`.toLowerCase();
  if (/pharm|medic|capsule|tablet|drug|analges|vitamin|syrup/.test(cat)) return '/primecare_logo.png';
  return 'https://images.unsplash.com/photo-1567333328061-6d7aae8e2e6b?auto=format&fit=crop&q=80&w=400';
}

// Location Autocomplete Component (Ghana-only Places search)
// REST OF THE VIEW COMPONENTS (CustomerView, VendorView, etc.) 
// UPDATED TO USE REAL DATA FROM PROPS AND API
function CustomerView({ user, orders, products, vendors, riderLocations, paystackKey, setPaystackKey, onPlaceOrder, addNotification, cart, setCart, isCartOpen, setIsCartOpen, activeTab, setActiveTab, zones, deliveryPricePerKm, subtotal, deliveryFee, total, refreshData, onUserUpdate }: { user: AuthUser, orders: Order[], products: any[], vendors: any[], riderLocations: { [key: string]: { lat: number, lng: number } }, paystackKey: string, setPaystackKey: (k: string) => void, onPlaceOrder: (items: any[], total: number, vendorId?: string, extra?: any) => void, addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void, cart: any[], setCart: React.Dispatch<React.SetStateAction<any[]>>, isCartOpen: boolean, setIsCartOpen: (v: boolean) => void, activeTab: string, setActiveTab: (v: any) => void, zones: any[], deliveryPricePerKm: number, subtotal: number, deliveryFee: number, total: number, refreshData: () => Promise<void>, onUserUpdate: (user: AuthUser, token: string) => void }) {
  const [selectedVendor, setSelectedVendor] = useState<any | null>(null);
  const [isTopUpOpen, setIsTopUpOpen] = useState(false);
  const [topUpAmount, setTopUpAmount] = useState('50');
  const [orderToCancel, setOrderToCancel] = useState<Order | null>(null);
  const [walletTab, setWalletTab] = useState<'topup' | 'withdraw'>('topup');
  const [walletPaying, setWalletPaying] = useState(false);
  const [pendingTopupRef, setPendingTopupRef] = useState(getPendingWalletTopupRef);
  const [manualTopupRef, setManualTopupRef] = useState('');
  const [creditingWallet, setCreditingWallet] = useState(false);

  useEffect(() => {
    const saved = getPendingWalletTopupRef();
    if (saved) {
      setPendingTopupRef(saved);
      setManualTopupRef(saved);
      setIsTopUpOpen(true);
    }
  }, []);
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [withdrawMethod, setWithdrawMethod] = useState<'momo' | 'bank'>('momo');
  const [withdrawPhone, setWithdrawPhone] = useState(user.phone || '');
  const [withdrawNetwork, setWithdrawNetwork] = useState('mtn');
  const [withdrawBank, setWithdrawBank] = useState('');
  const [withdrawAccount, setWithdrawAccount] = useState('');
  const [withdrawName, setWithdrawName] = useState(user.name);
  
  const [courierForm, setCourierForm] = useState({
    pickup: null as { lat: number, lng: number, address: string } | null,
    destination: null as { lat: number, lng: number, address: string } | null,
    itemDesc: '',
    scheduledTime: 'now',
    scheduleDate: '',
    scheduleClock: '',
    senderContact: '',
    receiverContact: ''
  });
  const [mapMode, setMapMode] = useState<'pickup' | 'destination'>('pickup');
  const [isMapOpen, setIsMapOpen] = useState(false);
  const [showDeliveryDetails, setShowDeliveryDetails] = useState(false);
  const [profileForm, setProfileForm] = useState({ 
    email: user.email, 
    phone: user.phone || '',
    address: user.address || '',
    lat: user.lat || GHANA_CENTER.lat,
    lng: user.lng || GHANA_CENTER.lng,
    region: user.region || ''
  });

  const profileGeoSet = useRef(false);

  useEffect(() => {
    if (activeTab !== 'profile') return;
    if (profileGeoSet.current) return;
    if (user.address && user.lat && user.lng) return;
    profileGeoSet.current = true;
    detectCurrentLocation().then((loc) => {
      if (!loc) return;
      setProfileForm((prev) => ({
        ...prev,
        lat: loc.lat,
        lng: loc.lng,
        address: prev.address || loc.address,
      }));
    });
  }, [activeTab, user.address, user.lat, user.lng]);

  const calculateCourierFee = () => {
    if (!courierForm.pickup || !courierForm.destination) return 0;
    const distance = haversineDistanceKm(
      courierForm.pickup.lat, courierForm.pickup.lng,
      courierForm.destination.lat, courierForm.destination.lng
    );
    const zone = zones.find(z => z.region === user.region && z.is_active) || zones[0];
    const bounds = zone
      ? { min: Number(zone.min_price), max: zone.max_price ? Number(zone.max_price) : null }
      : undefined;
    return deliveryFeeFromDistanceKm(distance, deliveryPricePerKm, bounds);
  };
  const courierFee = calculateCourierFee();

  const [profileSaving, setProfileSaving] = useState(false);
  const [profileMsg, setProfileMsg] = useState('');
  const [vendorConflict, setVendorConflict] = useState<any>(null);

  const myOrders = orders.filter(o => o.customer_id === user.id);
  const liveOrders = myOrders.filter((o) => !['delivered', 'cancelled'].includes(o.status));
  const tripHistory = myOrders.filter((o) => o.status !== 'cancelled');

  const vendorProducts = selectedVendor 
    ? products.filter(p => p.vendor_id === selectedVendor.id)
    : [];

  const marketplace = selectedVendor ? vendorProducts : vendors;

  const addToCart = (item: any) => {
    if (cart.length > 0 && cart[0].vendor_id !== item.vendor_id) {
      setVendorConflict(item);
      return;
    }
    setCart(prev => {
      const existing = prev.find(i => i.id === item.id);
      if (existing) {
        return prev.map(i => i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i);
      }
      return [...prev, { ...item, quantity: 1 }];
    });
    if (cart.length === 0) setIsCartOpen(true);
  };

  const updateQuantity = (id: string, delta: number) => {
    setCart(prev => prev.map(i => {
      if (i.id === id) {
        const newQty = Math.max(1, i.quantity + delta);
        return { ...i, quantity: newQty };
      }
      return i;
    }));
  };

  const walletPayingRef = useRef(false);

  const creditWalletFromPaystack = async (reference: string) => {
    setCreditingWallet(true);
    try {
      const res = await axios.post('/api/wallet/topup', { reference });
      clearPendingWalletTopupRef();
      setPendingTopupRef('');
      await refreshData();
      const credited = res.data?.balance != null ? Number(res.data.balance).toFixed(2) : null;
      addNotification(
        res.data?.alreadyProcessed
          ? `Wallet already credited. Balance: ?${credited}`
          : `Wallet topped up! Balance: ?${credited}`,
        'success'
      );
      setIsTopUpOpen(false);
    } catch (err: unknown) {
      setPendingWalletTopupRef(reference);
      setPendingTopupRef(reference);
      setManualTopupRef(reference);
      setIsTopUpOpen(true);
      const msg = axios.isAxiosError(err) ? err.response?.data?.message : null;
      addNotification(formatWalletTopupError(typeof msg === 'string' ? msg : null), 'warning');
    } finally {
      setCreditingWallet(false);
      walletPayingRef.current = false;
      setWalletPaying(false);
    }
  };

  const handleWalletTopUp = async () => {
    if (walletPayingRef.current) return;

    const amountGhs = Number(topUpAmount);
    if (!Number.isFinite(amountGhs) || amountGhs < 1) {
      addNotification('Enter at least ?1 to top up', 'warning');
      return;
    }

    let currentKey = paystackKey;
    if (!currentKey) {
      try {
        const res = await axios.get('/api/config/paystack');
        currentKey = res.data.publicKey;
        if (currentKey) setPaystackKey(currentKey);
      } catch {
        /* handled below */
      }
    }
    if (!currentKey) {
      addNotification('Payment system is offline. Check Paystack keys in admin settings.', 'warning');
      return;
    }

    walletPayingRef.current = true;
    setWalletPaying(true);

    try {
      await openPaystackCheckout({
        publicKey: currentKey,
        email: paystackPaymentEmail(user),
        amountGhs,
        metadata: { type: 'wallet_topup', user_id: user.id },
        onReferenceReady: (reference) => {
          setPendingWalletTopupRef(reference);
          setPendingTopupRef(reference);
          setManualTopupRef(reference);
        },
        onSuccess: (reference) => {
          void creditWalletFromPaystack(reference);
        },
        onClose: () => {
          if (!creditingWallet) {
            walletPayingRef.current = false;
            setWalletPaying(false);
          }
        },
      });
    } catch (err: unknown) {
      walletPayingRef.current = false;
      setWalletPaying(false);
      const msg = err instanceof Error ? err.message : 'Could not open payment window';
      addNotification(msg, 'warning');
    }
  };

  const handlePay = async () => {
    console.log('handlePay triggered. Cart length:', cart.length);
    if (cart.length === 0) return;

    let currentKey = paystackKey;
    if (!currentKey) {
      console.log('Paystack key missing, attempting emergency fetch...');
      try {
        const res = await axios.get('/api/config/paystack');
        currentKey = res.data.publicKey;
        setPaystackKey(currentKey);
      } catch (e) {
        console.error('Emergency key fetch failed', e);
      }
    }

    if (!currentKey) {
      console.error('Paystack key is still empty. Cannot proceed.');
      addNotification('Payment system is offline. Please try again in a moment.', 'warning');
      return;
    }

    setIsCartOpen(false);
    try {
      await openPaystackCheckout({
        publicKey: currentKey,
        email: paystackPaymentEmail(user),
        amountGhs: total,
        metadata: { type: 'order', vendor_id: selectedVendor?.id },
        onSuccess: (reference) => {
          onPlaceOrder(
            cart.map((item) => ({
              id: item.id,
              name: item.name,
              quantity: item.quantity,
              price: item.price,
            })),
            total,
            selectedVendor?.id,
            { payment_reference: reference, payment_method: 'paystack' }
          );
          setCart([]);
          setActiveTab('tracking');
        },
      });
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Could not open payment window';
      addNotification(msg, 'warning');
    }
  };

  const creditPendingOrManual = () => {
    const ref = (manualTopupRef || pendingTopupRef).trim();
    if (!ref) {
      addNotification('Paste your Paystack reference (e.g. T1234567890) or pay again below.', 'warning');
      return;
    }
    const hint = walletTopupReferenceHint(ref);
    if (hint) {
      addNotification(hint, 'warning');
      return;
    }
    void creditWalletFromPaystack(ref);
  };

  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="relative space-y-6">
      {(pendingTopupRef || manualTopupRef) && (
        <motion.div
          role="alert"
          className="sticky top-0 z-50 -mx-1 px-4 py-3 rounded-2xl bg-amber-400 text-slate-900 shadow-lg shadow-amber-400/30 border border-amber-300"
        >
          <p className="text-[10px] font-black uppercase tracking-widest mb-1">Payment received</p>
          <p className="text-xs font-bold mb-3 leading-snug">
            Your MoMo/card payment went through. Tap below to add it to your wallet (no extra charge).
          </p>
          <button
            type="button"
            disabled={creditingWallet}
            onClick={creditPendingOrManual}
            className="w-full py-3.5 bg-slate-900 text-white rounded-xl font-black uppercase tracking-widest text-xs disabled:opacity-60"
          >
            {creditingWallet ? 'Crediting wallet?' : 'Credit my wallet'}
          </button>
        </motion.div>
      )}

      {/* Modals and Cart Logic same as before */}
      {/* Modals */}
      <AnimatePresence>
        {isTopUpOpen && (
          <>
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => !walletPaying && setIsTopUpOpen(false)} className="fixed inset-0 bg-black/70 backdrop-blur-sm z-[280]" />
            <motion.div initial={{ scale: 0.9, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} exit={{ scale: 0.9, opacity: 0 }} className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-[calc(100%-2rem)] max-w-sm bg-slate-900 p-6 sm:p-8 rounded-[2rem] shadow-2xl z-[290] border border-slate-800 text-white overflow-y-auto max-h-[85vh]">
               <div className="flex p-1 bg-slate-800 rounded-2xl mb-6">
                 <button type="button" onClick={() => setWalletTab('topup')} className={cn("flex-1 py-2 text-[10px] font-black uppercase tracking-widest rounded-xl transition-all", walletTab === 'topup' ? "bg-white text-brand-blue shadow-sm" : "text-slate-400")}>Top Up</button>
                 <button type="button" onClick={() => setWalletTab('withdraw')} className={cn("flex-1 py-2 text-[10px] font-black uppercase tracking-widest rounded-xl transition-all", walletTab === 'withdraw' ? "bg-white text-brand-blue shadow-sm" : "text-slate-400")}>Withdraw</button>
               </div>

               {walletTab === 'topup' ? (
                 <>
                   <h3 className="text-xl font-black italic tracking-tighter mb-4 text-white">Top Up Wallet</h3>
                   {typeof window !== 'undefined' &&
                     (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') &&
                     paystackKey.startsWith('pk_live_') && (
                       <p className="mb-4 p-3 rounded-xl bg-amber-500/15 border border-amber-500/40 text-[11px] text-amber-200 leading-relaxed">
                         Live Paystack keys often fail on localhost. For local testing, set <strong>pk_test_</strong> keys in Admin → Settings.
                       </p>
                     )}
                   <div className="mb-5 p-4 rounded-2xl bg-slate-800/80 border border-slate-700">
                     <p className="text-[10px] font-black uppercase tracking-widest text-amber-400 mb-2">Already paid?</p>
                     <p className="text-[11px] text-slate-500 mb-2">
                       Use the <strong className="text-slate-400">Paystack</strong> reference (starts with{' '}
                       <span className="font-mono text-slate-400">T</span> or{' '}
                       <span className="font-mono text-slate-400">bytzgo_</span>), not your MTN/Vodafone MoMo ID.
                     </p>
                     <input
                       type="text"
                       value={manualTopupRef}
                       onChange={(e) => setManualTopupRef(e.target.value)}
                       placeholder="e.g. bytzgo_1716123456_abc12 or T1234567890"
                       className="w-full mb-2 bg-slate-900 border border-slate-600 text-white placeholder:text-slate-500 p-3 rounded-xl font-mono text-sm focus:outline-none focus:border-brand-blue"
                     />
                     <button
                       type="button"
                       disabled={creditingWallet || !manualTopupRef.trim()}
                       onClick={creditPendingOrManual}
                       className="w-full py-3 bg-amber-400 text-slate-900 rounded-xl font-black uppercase tracking-widest text-[10px] disabled:opacity-50"
                     >
                       {creditingWallet ? 'Crediting?' : 'Credit my wallet'}
                     </button>
                   </div>
                   <div className="grid grid-cols-2 gap-2 mb-6">
                      {['20', '50', '100', '200'].map(val => (
                        <button key={val} type="button" onClick={() => setTopUpAmount(val)} className={cn("py-3 rounded-xl font-bold transition-all border text-sm", topUpAmount === val ? "bg-brand-blue text-white border-brand-blue shadow-lg" : "bg-slate-800 text-slate-300 border-slate-700 hover:border-slate-600")}>?{val}</button>
                      ))}
                   </div>
                   <div className="mb-6">
                      <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Custom Amount</label>
                      <input
                        type="number"
                        min={1}
                        step={1}
                        inputMode="decimal"
                        value={topUpAmount}
                        onChange={e => setTopUpAmount(e.target.value)}
                        className="w-full mt-2 bg-slate-800 border border-slate-700 text-white placeholder:text-slate-500 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-mono font-black text-lg"
                        placeholder="Enter amount"
                      />
                   </div>
                   <button
                     type="button"
                     disabled={walletPaying}
                     onClick={handleWalletTopUp}
                     className="w-full py-4 bg-brand-blue text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all shadow-xl disabled:opacity-50 disabled:pointer-events-none"
                   >
                     {walletPaying ? 'Opening payment?' : 'Pay with Card/Momo'}
                   </button>
                 </>
               ) : (
                 <form onSubmit={async (e) => {
                   e.preventDefault();
                   if (Number(withdrawAmount) > user.balance) return addNotification('Insufficient balance', 'warning');
                   try {
                     await axios.post('/api/wallet/withdraw', {
                       amount: Number(withdrawAmount),
                       phone: withdrawPhone,
                       network: withdrawNetwork,
                       method: withdrawMethod,
                       bank: withdrawBank,
                       account: withdrawAccount
                     });
                     await refreshData();
                     addNotification('Withdrawal requested successfully!', 'success');
                     setIsTopUpOpen(false);
                   } catch (err: unknown) {
                     const msg = axios.isAxiosError(err) ? err.response?.data?.message : null;
                     addNotification(msg || 'Withdrawal failed', 'warning');
                   }
                 }} className="space-y-4">
                    <h3 className="text-xl font-black italic tracking-tighter text-white">Withdraw Funds</h3>
                    <div>
                      <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Amount to Withdraw</label>
                      <input type="number" required min={1} value={withdrawAmount} onChange={e => setWithdrawAmount(e.target.value)} className="w-full mt-2 bg-slate-800 border border-slate-700 text-white placeholder:text-slate-500 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-mono font-black text-lg" placeholder="0.00" />
                    </div>

                    <div className="flex gap-2">
                      <button type="button" onClick={() => setWithdrawMethod('momo')} className={cn("flex-1 py-3 rounded-xl border text-[10px] font-black uppercase tracking-widest transition-all", withdrawMethod === 'momo' ? "bg-brand-blue text-white border-brand-blue" : "bg-slate-800 text-slate-400 border-slate-700")}>MoMo</button>
                      <button type="button" onClick={() => setWithdrawMethod('bank')} className={cn("flex-1 py-3 rounded-xl border text-[10px] font-black uppercase tracking-widest transition-all", withdrawMethod === 'bank' ? "bg-brand-blue text-white border-brand-blue" : "bg-slate-800 text-slate-400 border-slate-700")}>Bank</button>
                    </div>

                    {withdrawMethod === 'momo' ? (
                      <div className="space-y-3">
                         <select value={withdrawNetwork} onChange={e => setWithdrawNetwork(e.target.value)} className="w-full bg-slate-800 border border-slate-700 text-white p-4 rounded-xl focus:outline-none font-bold text-xs">
                           <option value="mtn">MTN Mobile Money</option>
                           <option value="vodafone">Vodafone Cash</option>
                           <option value="airteltigo">AirtelTigo Money</option>
                         </select>
                         <input type="tel" placeholder="Mobile Number" required value={withdrawPhone} onChange={e => setWithdrawPhone(e.target.value)} className="w-full bg-slate-800 border border-slate-700 text-white placeholder:text-slate-500 p-4 rounded-xl focus:outline-none font-bold text-xs" />
                      </div>
                    ) : (
                      <div className="space-y-3">
                         <input type="text" placeholder="Bank Name" required value={withdrawBank} onChange={e => setWithdrawBank(e.target.value)} className="w-full bg-slate-800 border border-slate-700 text-white placeholder:text-slate-500 p-4 rounded-xl focus:outline-none font-bold text-xs" />
                         <input type="text" placeholder="Account Number" required value={withdrawAccount} onChange={e => setWithdrawAccount(e.target.value)} className="w-full bg-slate-800 border border-slate-700 text-white placeholder:text-slate-500 p-4 rounded-xl focus:outline-none font-bold text-xs" />
                      </div>
                    )}

                    <button type="submit" className="w-full py-4 bg-brand-green text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all shadow-xl">Confirm Withdrawal</button>
                 </form>
               )}
            </motion.div>
          </>
        )}
      </AnimatePresence>

      <button id="customer-wallet-open" type="button" className="hidden" onClick={() => setIsTopUpOpen(true)} />


      {activeTab === 'menu' && (
        <div className="space-y-6">
           <div className="flex items-center gap-3">
             <button
               type="button"
               onClick={() => { setSelectedVendor(null); setActiveTab('courier'); }}
               className="p-2 rounded-xl bg-slate-900 border border-slate-800 text-slate-400 hover:text-white"
             >
               <ChevronRight size={20} className="rotate-180" />
             </button>
             <div>
               <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">Optional</p>
               <h3 className="text-lg font-black text-white">
                 {selectedVendor ? selectedVendor.name : 'Browse shops'}
               </h3>
             </div>
             {selectedVendor && (
               <button type="button" onClick={() => setSelectedVendor(null)} className="ml-auto p-2 hover:bg-slate-800 rounded-xl text-slate-300">
                 <X size={20} />
               </button>
             )}
           </div>

            <div className={cn("grid gap-4 sm:gap-8", selectedVendor ? "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4" : "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3")}>
             {selectedVendor ? (
               vendorProducts.length > 0 ? (
                 vendorProducts.map(item => (
                   <div key={item.id} className="bg-slate-900/90 p-4 sm:p-6 rounded-[2rem] sm:rounded-[2.5rem] border border-slate-800 hover:shadow-2xl hover:shadow-brand-blue/10 transition-all group flex flex-col justify-between">
                      <div>
                        <div className="h-40 sm:h-56 bg-slate-800 rounded-2xl sm:rounded-3xl mb-4 sm:mb-6 flex items-center justify-center relative overflow-hidden group-hover:scale-105 transition-transform">
                          <img src={productFallbackImage(item, selectedVendor)} alt={item.name} className="w-full h-full object-contain p-2 bg-slate-800" />
                          <span className="absolute top-3 left-3 sm:top-4 sm:left-4 bg-white/90 backdrop-blur-md px-3 sm:px-4 py-1 rounded-full text-[8px] sm:text-[10px] font-black uppercase tracking-widest text-slate-400 border border-slate-100">{item.category}</span>
                        </div>
                        <h4 className="font-black text-xl sm:text-2xl text-white tracking-tight leading-tight mb-1 sm:mb-2">{item.name}</h4>
                        <p className="text-slate-400 text-[10px] sm:text-sm mb-6 sm:mb-8 font-medium leading-relaxed line-clamp-2 sm:line-clamp-none">{item.description}</p>
                      </div>
                      <div className="flex items-center justify-between gap-3 sm:gap-4">
                        <div className="flex flex-col">
                          <span className="text-[8px] sm:text-[10px] font-black text-slate-300 uppercase tracking-widest">Price</span>
                          <span className="font-mono font-black text-lg sm:text-xl text-brand-blue">{formatCedis(item.price)}</span>
                        </div>
                         <button onClick={() => addToCart(item)} className="flex-1 py-3 sm:py-4 bg-slate-900 text-white rounded-xl sm:rounded-2xl font-black text-[10px] sm:text-xs hover:bg-brand-blue transition-all uppercase tracking-widest shadow-lg">Add</button>
                      </div>
                    </div>
                  ))
                ) : (
                 <div className="col-span-full text-center py-32 bg-slate-900/90 rounded-[3rem] border border-slate-800">
                    <p className="text-slate-400 font-bold italic">No items found for this vendor.</p>
                 </div>
               )
             ) : (
               vendors.map(vendor => (
                 <div key={vendor.id} onClick={() => setSelectedVendor(vendor)} className="bg-slate-900/90 rounded-[2.5rem] border border-slate-800 hover:shadow-2xl hover:shadow-brand-blue/10 transition-all cursor-pointer group overflow-hidden flex flex-col">
                    <div className="h-48 bg-slate-100 relative overflow-hidden group-hover:scale-105 transition-transform">
                      <img src={vendor.cover_image || 'https://images.unsplash.com/photo-1441986300917-64674bd600d8?auto=format&fit=crop&q=80&w=600'} alt={vendor.name} className="w-full h-full object-cover" />
                      <div className="absolute inset-0 bg-gradient-to-t from-black/60 to-transparent" />
                      <div className="absolute bottom-4 left-4 right-4 flex justify-between items-end">
                        <div className="w-12 h-12 bg-white rounded-2xl flex items-center justify-center text-brand-blue shadow-lg">
                           <Store size={24} />
                        </div>
                      </div>
                    </div>
                    <div className="p-6 flex flex-col flex-1">
                      <h4 className="font-black text-2xl text-white tracking-tight leading-tight mb-2">{vendor.name}</h4>
                      <p className="text-slate-500 font-medium text-sm flex items-center gap-2 mb-6">
                        <MapPin size={14} className="text-brand-blue" />
                        {vendor.address || 'Accra, Ghana'}
                      </p>
                      <div className="mt-auto flex items-center justify-between">
                        <span className="text-slate-400 text-[10px] font-black uppercase tracking-widest">{vendor.email}</span>
                        <div className="flex items-center gap-2 text-brand-blue font-black text-[10px] uppercase tracking-widest group-hover:translate-x-1 transition-transform">
                           Explore <ChevronRight size={12} />
                        </div>
                      </div>
                    </div>
                 </div>
               ))
             )}
           </div>
        </div>
      )}

      {activeTab === 'courier' && (
        <CustomerDeliveryHome
          liveOrders={liveOrders}
          user={user}
          courierForm={courierForm}
          setCourierForm={setCourierForm}
          courierFee={courierFee}
          mapMode={mapMode}
          setMapMode={setMapMode}
          isMapOpen={isMapOpen}
          setIsMapOpen={setIsMapOpen}
          showDeliveryDetails={showDeliveryDetails}
          setShowDeliveryDetails={setShowDeliveryDetails}
          onPlaceOrder={onPlaceOrder}
          addNotification={addNotification}
          setActiveTab={setActiveTab}
          paystackKey={paystackKey}
          setPaystackKey={setPaystackKey}
          vendors={vendors}
          riderLocations={riderLocations}
          refreshData={refreshData}
        />
      )}

      {activeTab === 'tracking' && (
        <CustomerTripsView
          tripHistory={tripHistory}
          vendors={vendors}
          riderLocations={riderLocations}
          user={user}
          paystackKey={paystackKey}
          setPaystackKey={setPaystackKey}
          addNotification={addNotification}
          refreshData={refreshData}
          onCancelOrder={setOrderToCancel}
        />
      )}

      <ConfirmationModal 
        isOpen={!!vendorConflict}
        onClose={() => setVendorConflict(null)}
        onConfirm={() => {
          setCart([{ ...vendorConflict, quantity: 1 }]);
          setVendorConflict(null);
          setIsCartOpen(true);
        }}
        title="Switch Vendor?"
        message="Your cart contains items from another vendor. Would you like to clear your cart and start a new order from this vendor?"
        confirmLabel="Clear Cart & Switch"
        type="danger"
      />

      <ConfirmationModal 
        isOpen={!!orderToCancel}
        onClose={() => setOrderToCancel(null)}
        onConfirm={async () => {
          if (!orderToCancel) return;
          try {
            const res = await axios.post(`/api/orders/${orderToCancel.id}/cancel`);
            await refreshData();
            const msg =
              res.data?.refundMessage ||
              (res.data?.refundCredited
                ? `Refund of ₵${Number(res.data.refundAmount || 0).toFixed(2)} added to wallet`
                : 'Order cancelled');
            addNotification(msg, res.data?.refundCredited ? 'success' : 'info');
            setOrderToCancel(null);
          } catch (err: any) {
            addNotification(err.response?.data?.message || 'Cancellation failed', 'warning');
            setOrderToCancel(null);
          }
        }}
        title="Cancel Order"
        message={`Cancel order #${orderToCancel?.id.slice(-6)}? If you already paid (wallet or card), the amount is returned to your BytzGo wallet. Pay-on-delivery orders that were not paid yet are cancelled with no charge.`}
        confirmLabel="Yes, Cancel Order"
        type="danger"
      />

      {activeTab === 'profile' && (
        <div className="bg-slate-900/90 rounded-[2rem] sm:rounded-[3rem] p-6 sm:p-12 shadow-xl border border-slate-800 max-w-2xl mx-auto">
          <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 sm:gap-6 mb-8 sm:mb-10">
            <ProfileAvatarUpload
              name={user.name}
              avatarUrl={user.avatar_url}
              onUpdated={(updatedUser, newToken) => {
                onUserUpdate(updatedUser as unknown as AuthUser, newToken);
                addNotification('Profile photo updated', 'success');
              }}
              onError={(m) => addNotification(m, 'warning')}
            />
            <div>
              <h3 className="text-3xl font-black italic tracking-tighter text-white">{user.name}</h3>
              <p className="text-slate-400 font-bold uppercase tracking-widest text-[10px]">Account Settings</p>
            </div>
          </div>

          <form onSubmit={async (e) => {
            e.preventDefault();
            setProfileSaving(true);
            setProfileMsg('');
            try {
              const res = await axios.patch('/api/auth/profile', profileForm);
              onUserUpdate(res.data.user as AuthUser, res.data.token);
              setProfileMsg('Profile updated successfully!');
            } catch (err: any) {
              setProfileMsg(err.response?.data?.message || 'Failed to update profile');
            } finally {
              setProfileSaving(false);
            }
          }} className="space-y-6">
            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Full Name</label>
              <div className="relative">
                <UserIcon size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" />
                <input type="text" disabled value={user.name} className="w-full bg-slate-100 border border-slate-100 rounded-2xl py-4 pl-12 pr-4 font-bold text-sm text-slate-400 cursor-not-allowed" />
                <Lock size={14} className="absolute right-4 top-1/2 -translate-y-1/2 text-slate-300" />
              </div>
              <p className="text-[9px] font-bold text-slate-300 ml-2 uppercase tracking-widest">Name cannot be changed</p>
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Delivery Address (Ghana)</label>
              <LocationAutocompleteInput
                placeholder="e.g. East Legon, Accra"
                icon={MapPin}
                value={profileForm.address}
                onChange={(val) => setProfileForm((prev) => ({
                  ...prev,
                  address: val.address,
                  lat: val.lat || prev.lat,
                  lng: val.lng || prev.lng,
                }))}
                onMapClick={() => {}}
                showMapButton={false}
                onLocationError={(m) => addNotification(m, 'warning')}
              />
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Pin Delivery Location</label>
              <div className="h-48 rounded-3xl overflow-hidden border border-slate-100 shadow-inner">
                <Map 
                  defaultCenter={{ lat: profileForm.lat, lng: profileForm.lng }} 
                  defaultZoom={15} 
                  disableDefaultUI={true}
                  styles={CLEAN_MAP_STYLE}
                >
                  <Marker position={{ lat: profileForm.lat, lng: profileForm.lng }} draggable={true} onDragEnd={async (e: any) => {
                    const newLat = e.latLng?.lat() || profileForm.lat;
                    const newLng = e.latLng?.lng() || profileForm.lng;
                    setProfileForm(prev => ({...prev, lat: newLat, lng: newLng}));
                    const address = await resolveAddressLabel(newLat, newLng);
                    setProfileForm((prev) => ({ ...prev, address }));
                  }} />
                </Map>
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Email Address</label>
              <div className="relative">
                <Mail size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" />
                <input type="email" required value={profileForm.email} onChange={e => setProfileForm({...profileForm, email: e.target.value})} className="w-full bg-slate-800 border border-slate-700 rounded-2xl py-4 text-white pl-12 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Operating Zone (Region)</label>
              <div className="relative">
                <MapPin size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" />
                <select 
                  required 
                  value={profileForm.region} 
                  onChange={e => setProfileForm({...profileForm, region: e.target.value})} 
                  className="w-full bg-slate-800 border border-slate-700 rounded-2xl py-4 text-white pl-12 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all"
                >
                  <option value="">Select Region</option>
                  {GHANA_REGIONS.map(r => <option key={r} value={r}>{r}</option>)}
                </select>
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Phone Number</label>
              <div className="relative">
                <Phone size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" />
                <input type="tel" placeholder="024 000 0000" value={profileForm.phone} onChange={e => setProfileForm({...profileForm, phone: e.target.value})} className="w-full bg-slate-800 border border-slate-700 rounded-2xl py-4 text-white pl-12 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Role</label>
              <div className="relative">
                <Shield size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" />
                <input type="text" disabled value={user.role.toUpperCase()} className="w-full bg-slate-100 border border-slate-100 rounded-2xl py-4 pl-12 pr-4 font-bold text-sm text-slate-400 cursor-not-allowed" />
              </div>
            </div>

            {profileMsg && (
              <p className={cn("text-xs font-bold text-center uppercase tracking-widest py-3 rounded-xl border", profileMsg.includes('success') ? "text-brand-green bg-brand-green/10 border-brand-green/20" : "text-red-500 bg-red-50 border-red-100")}>{profileMsg}</p>
            )}

            <div className="pt-4">
              <button type="submit" disabled={profileSaving} className="w-full py-5 bg-slate-900 text-white rounded-[2rem] font-black uppercase tracking-widest text-sm hover:scale-[1.02] active:scale-[0.98] transition-all shadow-2xl flex items-center justify-center gap-3">
                {profileSaving ? <LoadingIndicator size="sm" /> : <><Save size={18} /> Save Changes</>}
              </button>
            </div>
          </form>
        </div>
      )}
    </motion.div>
  );
}


function PaymentStatusBadge({ order }: { order: Order }) {
  if (!order.payment_status) return null;
  const isPaid = order.payment_status === 'paid';
  return (
    <div className={cn(
      "px-3 py-1.5 rounded-lg text-[8px] font-black uppercase tracking-widest flex items-center gap-1.5",
      isPaid ? "bg-emerald-500 text-white shadow-lg shadow-emerald-500/20" : "bg-orange-500 text-white shadow-lg shadow-orange-500/20"
    )}>
      {isPaid ? <Check size={10} strokeWidth={4} /> : <AlertCircle size={10} strokeWidth={4} />}
      {isPaid ? 'Paid Online' : 'Cash on Delivery'}
    </div>
  );
}


function TrackingStep({ label, active }: { label: string, active: boolean }) {
  return (
    <div className="flex items-center gap-6 relative">
      <div className={cn("z-10 w-8 h-8 rounded-2xl flex items-center justify-center transition-all shadow-sm", active ? "bg-brand-green text-white rotate-6" : "bg-slate-800 text-slate-500 border border-slate-700")}>
        <CheckCircle2 size={16} />
      </div>
      <span className={cn("text-base font-black tracking-tight", active ? "text-white" : "text-slate-500")}>{label}</span>
    </div>
  );
}

function VendorView({
  user,
  orders,
  products,
  riderLocations,
  zones,
  deliveryPricePerKm,
  paystackKey,
  setPaystackKey,
  onPlaceOrder,
  onUpdateStatus,
  onAddProduct,
  onDeleteProduct,
  addNotification,
  onBalanceUpdate,
  activeTab,
  setActiveTab,
  refreshData,
  onUserUpdate,
}: {
  user: AuthUser;
  orders: Order[];
  products: any[];
  riderLocations: { [key: string]: { lat: number; lng: number } };
  zones: any[];
  deliveryPricePerKm: number;
  paystackKey: string;
  setPaystackKey: (k: string) => void;
  onPlaceOrder: (items: unknown[], total: number, vendorId?: string, extra?: Record<string, unknown>) => void | Promise<void>;
  onUpdateStatus: (id: string, s: OrderStatus, extra?: any) => void | Promise<boolean>;
  onAddProduct: (p: any) => void;
  onDeleteProduct: (id: string) => void;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  onBalanceUpdate: (balance: number) => void;
  activeTab: any;
  setActiveTab: (v: any) => void;
  refreshData: () => Promise<void>;
  onUserUpdate: (user: AuthUser, token: string) => void;
}) {
  const vendorActive = user.status === 'active';
  const [isAddProductOpen, setIsAddProductOpen] = useState(false);
  const [editingProduct, setEditingProduct] = useState<any | null>(null);
  const [productToDelete, setProductToDelete] = useState<any | null>(null);
  const [newProduct, setNewProduct] = useState({ name: '', description: '', price: '', category: 'Food', image_url: '' });
  const [uploading, setUploading] = useState(false);
  
  const [storeForm, setStoreForm] = useState({ 
    cover_image: user.cover_image || '', 
    address: user.address || '', 
    lat: user.lat || GHANA_CENTER.lat, 
    lng: user.lng || GHANA_CENTER.lng,
    region: user.region || '',
    shop_category: (user as { shop_category?: string }).shop_category || 'food',
  });
  const storeGeoSet = useRef(false);

  useEffect(() => {
    if (activeTab !== 'store') return;
    if (storeGeoSet.current) return;
    if (user.address && user.lat && user.lng) return;
    storeGeoSet.current = true;
    detectCurrentLocation().then((loc) => {
      if (!loc) return;
      setStoreForm((prev) => ({
        ...prev,
        lat: loc.lat,
        lng: loc.lng,
        address: prev.address || loc.address,
      }));
    });
  }, [activeTab, user.address, user.lat, user.lng]);

  useEffect(() => {
    if (user.cover_image) {
      setStoreForm((prev) => ({ ...prev, cover_image: user.cover_image || prev.cover_image }));
    }
  }, [user.cover_image]);
  const [storeSaving, setStoreSaving] = useState(false);
  const [storeMsg, setStoreMsg] = useState('');

  const [courierForm, setCourierForm] = useState({
    pickup: null as { lat: number; lng: number; address: string } | null,
    destination: null as { lat: number; lng: number; address: string } | null,
    itemDesc: '',
    scheduledTime: 'now',
    scheduleDate: '',
    scheduleClock: '',
    senderContact: '',
    receiverContact: '',
  });
  const [mapMode, setMapMode] = useState<'pickup' | 'destination'>('pickup');
  const [isMapOpen, setIsMapOpen] = useState(false);
  const [showDeliveryDetails, setShowDeliveryDetails] = useState(false);
  const courierPickupSeeded = useRef(false);

  useEffect(() => {
    if (activeTab !== 'send') return;
    if (courierPickupSeeded.current) return;
    if (courierForm.pickup?.lat && courierForm.pickup?.address) return;
    if (user.lat && user.lng && user.address) {
      courierPickupSeeded.current = true;
      setCourierForm((prev) => ({
        ...prev,
        pickup: { lat: user.lat!, lng: user.lng!, address: user.address! },
        senderContact: prev.senderContact || user.phone || '',
      }));
      return;
    }
    courierPickupSeeded.current = true;
    detectCurrentLocation().then((loc) => {
      if (!loc) return;
      setCourierForm((prev) => ({
        ...prev,
        pickup: loc,
        senderContact: prev.senderContact || user.phone || '',
      }));
    });
  }, [activeTab, user.lat, user.lng, user.address, user.phone, courierForm.pickup]);

  const calculateCourierFee = () => {
    if (!courierForm.pickup || !courierForm.destination) return 0;
    const distance = haversineDistanceKm(
      courierForm.pickup.lat,
      courierForm.pickup.lng,
      courierForm.destination.lat,
      courierForm.destination.lng
    );
    const zone = zones.find((z) => z.region === user.region && z.is_active) || zones[0];
    const bounds = zone
      ? { min: Number(zone.min_price), max: zone.max_price ? Number(zone.max_price) : null }
      : undefined;
    return deliveryFeeFromDistanceKm(distance, deliveryPricePerKm, bounds);
  };
  const courierFee = calculateCourierFee();

  const myPackages = orders.filter(
    (o) =>
      o.customer_id === user.id &&
      ((o as Order & { order_type?: string }).order_type === 'courier' ||
        (o as Order & { orderType?: string }).orderType === 'courier')
  );
  const livePackages = myPackages.filter((o) => !['delivered', 'cancelled'].includes(o.status));

  // Wallet State
  const [withdrawMethod, setWithdrawMethod] = useState<'momo' | 'bank'>('momo');
  const [withdrawAmount, setWithdrawAmount] = useState('');
  const [withdrawPhone, setWithdrawPhone] = useState('');
  const [withdrawNetwork, setWithdrawNetwork] = useState('mtn');
  const [withdrawBank, setWithdrawBank] = useState('');
  const [withdrawAccName, setWithdrawAccName] = useState('');
  const [withdrawAccNum, setWithdrawAccNum] = useState('');
  const [withdrawStatus, setWithdrawStatus] = useState<{message: string, type: 'error' | 'success'} | null>(null);
  const [isWithdrawing, setIsWithdrawing] = useState(false);

  const handleWithdraw = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!withdrawAmount || isNaN(Number(withdrawAmount))) return;
    setIsWithdrawing(true);
    setWithdrawStatus(null);
    try {
      const payload: Record<string, unknown> = { amount: Number(withdrawAmount) };
      if (withdrawMethod === 'momo') {
        payload.phone = withdrawPhone;
        payload.network = withdrawNetwork;
      }
      const res = await axios.post('/api/wallet/withdraw', payload);
      onBalanceUpdate(res.data.balance);
      setWithdrawStatus({ message: 'Withdrawal successful!', type: 'success' });
      setWithdrawAmount('');
      addNotification('Withdrawal submitted', 'success');
      await refreshData();
    } catch (err: unknown) {
      setWithdrawStatus({ message: getApiError(err, 'Withdrawal failed'), type: 'error' });
    } finally {
      setIsWithdrawing(false);
    }
  };

  const shopOrders = orders.filter((o) => o.vendor_id === user.id);
  const activeShopOrders = shopOrders.filter(
    (o) => o.status !== 'delivered' && o.status !== 'cancelled'
  );
  const activeOrders = [...activeShopOrders, ...livePackages];

  const handleFileUpload = async (
    file: File,
    onSuccess: (url: string) => void,
    folder: 'products' | 'covers' | 'avatars' = 'products'
  ) => {
    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('image', file);
      formData.append('folder', folder);
      const res = await axios.post('/api/upload', formData, { headers: { 'Content-Type': 'multipart/form-data' } });
      onSuccess(res.data.url);
      addNotification('Image uploaded', 'success');
    } catch (err) {
      addNotification(getApiError(err, 'Upload failed'), 'warning');
    } finally {
      setUploading(false);
    }
  };

  const handleSubmitProduct = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!vendorActive) {
      addNotification('Your vendor account is pending approval', 'warning');
      return;
    }
    try {
      const payload = { ...newProduct, price: parseFloat(newProduct.price) };
      let res;
      if (editingProduct) {
        res = await axios.patch(`/api/products/${editingProduct.id}`, payload);
      } else {
        res = await axios.post('/api/products', payload);
      }
      onAddProduct(res.data);
      setIsAddProductOpen(false);
      setEditingProduct(null);
      setNewProduct({ name: '', description: '', price: '', category: 'Food', image_url: '' });
      addNotification(editingProduct ? 'Menu item updated' : 'Item saved ? pending admin approval', 'success');
      await refreshData();
    } catch (err) {
      addNotification(getApiError(err, 'Failed to save product'), 'warning');
    }
  };

  const handleDeleteProduct = async (id: string) => {
    try {
      await onDeleteProduct(id);
      setProductToDelete(null);
      addNotification('Item removed from menu', 'success');
    } catch (err) {
      addNotification(getApiError(err, 'Delete failed'), 'warning');
    }
  };

  const handleEditClick = (product: any) => {
    setEditingProduct(product);
    setNewProduct({
      name: product.name,
      description: product.description || '',
      price: product.price.toString(),
      category: product.category || 'Food',
      image_url: product.image_url || ''
    });
    setIsAddProductOpen(true);
  };

  return (
    <div className="space-y-6 sm:space-y-10 pb-24 sm:pb-0 relative">
       <header className="flex flex-col gap-4 sm:gap-6">
        <div>
          <h2 className="text-2xl sm:text-4xl font-black tracking-tighter text-slate-800 uppercase italic">Kitchen Command</h2>
          <p className="text-slate-400 font-bold uppercase tracking-[0.2em] text-[10px] sm:text-xs">Merchant Terminal v1.0</p>
        </div>
        <div className="flex gap-2 sm:gap-4 overflow-x-auto pb-1">
           <button onClick={() => setActiveTab('orders')} className={cn("px-4 sm:px-6 py-2 rounded-xl text-[10px] sm:text-xs font-black uppercase tracking-widest transition-all whitespace-nowrap", activeTab === 'orders' ? "bg-brand-blue text-white" : "bg-slate-100 text-slate-500")}>Orders</button>
           <button onClick={() => setActiveTab('send')} className={cn("px-4 sm:px-6 py-2 rounded-xl text-[10px] sm:text-xs font-black uppercase tracking-widest transition-all whitespace-nowrap", activeTab === 'send' ? "bg-brand-blue text-white" : "bg-slate-100 text-slate-500")}>Send package</button>
           <button onClick={() => setActiveTab('products')} className={cn("px-4 sm:px-6 py-2 rounded-xl text-[10px] sm:text-xs font-black uppercase tracking-widest transition-all whitespace-nowrap", activeTab === 'products' ? "bg-brand-blue text-white" : "bg-slate-100 text-slate-500")}>Menu</button>
           <button onClick={() => setActiveTab('store')} className={cn("px-4 sm:px-6 py-2 rounded-xl text-[10px] sm:text-xs font-black uppercase tracking-widest transition-all whitespace-nowrap", activeTab === 'store' ? "bg-brand-blue text-white" : "bg-slate-100 text-slate-500")}>Store</button>
           <button onClick={() => setActiveTab('wallet')} className={cn("px-4 sm:px-6 py-2 rounded-xl text-[10px] sm:text-xs font-black uppercase tracking-widest transition-all whitespace-nowrap", activeTab === 'wallet' ? "bg-brand-blue text-white" : "bg-slate-100 text-slate-500")}>Wallet</button>
        </div>
      </header>

      {activeTab === 'send' ? (
        <CustomerDeliveryHome
          liveOrders={livePackages}
          user={user}
          courierForm={courierForm}
          setCourierForm={setCourierForm}
          courierFee={courierFee}
          mapMode={mapMode}
          setMapMode={setMapMode}
          isMapOpen={isMapOpen}
          setIsMapOpen={setIsMapOpen}
          showDeliveryDetails={showDeliveryDetails}
          setShowDeliveryDetails={setShowDeliveryDetails}
          onPlaceOrder={onPlaceOrder}
          addNotification={addNotification}
          setActiveTab={setActiveTab}
          afterBookTab="orders"
          paystackKey={paystackKey}
          setPaystackKey={setPaystackKey}
        />
      ) : activeTab === 'orders' ? (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-8">
            {activeOrders.length === 0 && (
              <div className="col-span-full text-center py-20 bg-white rounded-[3rem] border border-slate-100 border-dashed">
                <Clock className="mx-auto text-slate-200 mb-4" size={48} />
                <p className="text-slate-400 font-black italic uppercase tracking-tighter">No active orders</p>
              </div>
            )}
            {activeOrders.map(order => {
              const riderLoc = order.rider_id ? riderLocations[order.rider_id] : null;
              const isTrackingActive = ['pending', 'preparing', 'ready', 'picked_up'].includes(order.status) && !!order.rider_id;
              const isOutgoingPackage =
                order.customer_id === user.id &&
                ((order as Order & { order_type?: string }).order_type === 'courier' ||
                  (order as Order & { orderType?: string }).orderType === 'courier');
              const isShopOrder = order.vendor_id === user.id;

              return (
                <div key={order.id} className="bg-white p-5 sm:p-8 rounded-[2rem] sm:rounded-[2.5rem] border border-slate-100 shadow-sm hover:shadow-xl transition-all">
                   <div className="flex justify-between items-start mb-4 sm:mb-6">
                    <div>
                      <h4 className="font-black text-lg sm:text-2xl tracking-tighter">
                        {isOutgoingPackage ? `Package #${order.id.slice(-4)}` : `Order #${order.id.slice(-4)}`}
                      </h4>
                      <p className="text-brand-green font-mono text-xs uppercase tracking-widest mt-1">
                        {isOutgoingPackage ? 'Sent from your store' : order.customerName}
                      </p>
                    </div>
                    <div className="font-mono font-black text-base sm:text-xl text-slate-800">{formatCedis(order.total)}</div>
                  </div>

                  {isTrackingActive && (
                    <div className="mb-6 h-64 rounded-2xl overflow-hidden border border-slate-100 shadow-inner relative">
                      {!riderLoc && (
                        <div className="absolute inset-0 bg-slate-900/10 backdrop-blur-sm z-10 flex items-center justify-center">
                          <div className="bg-white px-6 py-3 rounded-2xl shadow-xl flex items-center gap-3">
                            <div className="w-2 h-2 bg-brand-blue rounded-full animate-ping" />
                            <p className="text-xs font-black uppercase tracking-widest text-slate-800">Waiting for rider GPS...</p>
                          </div>
                        </div>
                      )}
                      <TrackingMap 
                        riderLocation={riderLoc}
                        pickupLocation={{
                          lat: (order as Order & { pickup_lat?: number }).pickup_lat || user.lat || 5.6037,
                          lng: (order as Order & { pickup_lng?: number }).pickup_lng || user.lng || -0.1870,
                        }}
                        destination={{ lat: order.lat || 5.6037, lng: order.lng || -0.1870 }}
                        orderStatus={order.status}
                      />
                    </div>
                  )}

                  <div className="bg-slate-50 p-3 sm:p-4 rounded-xl sm:rounded-2xl mb-4 sm:mb-8 space-y-2">
                    {order.items.map((item, idx) => (
                      <div key={idx} className="flex justify-between text-xs sm:text-sm font-bold">
                        <span className="text-slate-600">{item.quantity}x {item.name}</span>
                        <span className="text-slate-400">{formatCedis(item.price)}</span>
                      </div>
                    ))}
                  </div>

                  <div className="flex gap-2 sm:gap-3 flex-wrap items-center">
                     {isShopOrder && order.status === 'pending' && <button onClick={() => onUpdateStatus(order.id, 'preparing')} className="flex-1 py-3 sm:py-4 bg-brand-blue text-white rounded-xl sm:rounded-2xl font-black uppercase tracking-widest text-[10px] sm:text-xs">Start Cook</button>}
                     {isShopOrder && order.status === 'preparing' && <button onClick={() => onUpdateStatus(order.id, 'ready')} className="flex-1 py-3 sm:py-4 bg-brand-green text-white rounded-xl sm:rounded-2xl font-black uppercase tracking-widest text-[10px] sm:text-xs">Mark Ready</button>}
                     <div className="px-3 sm:px-4 py-2 bg-slate-100 rounded-xl text-[10px] font-black uppercase tracking-widest self-center">{order.status}</div>
                     <PaymentStatusBadge order={order} />
                  </div>
                </div>
              );
            })}
        </div>
      ) : activeTab === 'products' ? (
        <div className="space-y-6 sm:space-y-8">
           <div className="flex justify-between items-center">
             <h3 className="text-xl font-black uppercase tracking-widest text-slate-800">Your Menu</h3>
             <button onClick={() => { setEditingProduct(null); setNewProduct({ name: '', description: '', price: '', category: 'Food', image_url: '' }); setIsAddProductOpen(true); }} className="px-6 sm:px-8 py-3 sm:py-4 bg-slate-900 text-white rounded-2xl font-black uppercase tracking-widest text-[10px] sm:text-xs hover:scale-105 transition-transform">Add New Item</button>
           </div>
           
           <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 sm:gap-6">
             {products.filter(p => p.vendor_id === user.id).length === 0 && (
               <div className="col-span-full text-center py-20 bg-white rounded-[2rem] border border-slate-100 border-dashed">
                 <p className="text-slate-400 font-bold uppercase tracking-widest text-sm">No items in your menu yet.</p>
               </div>
             )}
             {products.filter(p => p.vendor_id === user.id).map(product => (
               <div key={product.id} className="bg-white rounded-[2rem] border border-slate-100 overflow-hidden shadow-sm hover:shadow-md transition-shadow">
                 <div className="h-40 bg-slate-100 relative">
                   {product.image_url ? (
                     <img src={product.image_url} alt={product.name} className="w-full h-full object-cover" />
                   ) : (
                     <div className="w-full h-full flex items-center justify-center text-slate-300">
                       <ShoppingBag size={48} />
                     </div>
                   )}
                   <div className="absolute top-4 right-4 bg-white/90 backdrop-blur px-3 py-1 rounded-lg text-xs font-black text-brand-blue">
                     {formatCedis(product.price)}
                   </div>
                 </div>
                 <div className="p-6">
                   <div className="flex justify-between items-start mb-1">
                     <h4 className="font-black text-lg">{product.name}</h4>
                     <div className="flex gap-1">
                     <button type="button" onClick={() => handleEditClick(product)} className="p-2 hover:bg-slate-100 rounded-lg text-slate-400 hover:text-brand-blue transition-colors">
                       <Edit3 size={16} />
                     </button>
                     <button type="button" onClick={() => setProductToDelete(product)} className="p-2 hover:bg-red-500/10 rounded-lg text-slate-400 hover:text-red-400 transition-colors">
                       <Trash2 size={16} />
                     </button>
                     </div>
                   </div>
                   <p className="text-slate-400 text-xs font-bold uppercase tracking-widest mb-4">{product.category}</p>
                   <p className="text-slate-500 text-sm line-clamp-2">{product.description}</p>
                 </div>
               </div>
             ))}
           </div>
           
           <AnimatePresence>
             {isAddProductOpen && (
                <div className="fixed inset-0 z-[100] flex items-center justify-center p-4">
                  <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => setIsAddProductOpen(false)} className="absolute inset-0 bg-slate-900/40 backdrop-blur-sm" />
                  <motion.div initial={{ opacity: 0, scale: 0.9 }} animate={{ opacity: 1, scale: 1 }} exit={{ opacity: 0, scale: 0.9 }} className="bg-white p-6 sm:p-8 rounded-[2.5rem] border border-slate-100 shadow-xl max-w-md w-full relative z-10 overflow-y-auto max-h-[90vh]">
                     <h3 className="text-xl sm:text-2xl font-black italic tracking-tighter mb-6 text-center">{editingProduct ? 'Edit Menu Item' : 'New Menu Item'}</h3>
                  <form onSubmit={handleSubmitProduct} className="space-y-4">
                     <input type="text" placeholder="Item Name" required className="w-full bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-bold text-sm" value={newProduct.name} onChange={(e) => setNewProduct({...newProduct, name: e.target.value})} />
                     <textarea placeholder="Description" className="w-full bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-bold text-sm h-24" value={newProduct.description} onChange={(e) => setNewProduct({...newProduct, description: e.target.value})} />
                     
                     <div className="space-y-2">
                       <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Product Image</label>
                       <div className="flex gap-2">
                         <input type="text" placeholder="Paste URL or upload" className="flex-1 bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-bold text-sm" value={newProduct.image_url} onChange={(e) => setNewProduct({...newProduct, image_url: e.target.value})} />
                         <label className={cn("px-4 py-4 rounded-xl font-black uppercase tracking-widest text-[10px] cursor-pointer transition-all flex items-center gap-1", uploading ? "bg-slate-200 text-slate-400" : "bg-brand-blue text-white hover:scale-105")}>
                           {uploading ? <LoadingIndicator size="sm" /> : 'Upload'}
                           <input type="file" accept="image/*" className="hidden" disabled={uploading} onChange={(e) => {
                             const file = e.target.files?.[0];
                             if (file) handleFileUpload(file, (url) => setNewProduct({...newProduct, image_url: url}), 'products');
                           }} />
                         </label>
                       </div>
                       {newProduct.image_url && (
                         <div className="h-32 rounded-xl overflow-hidden border border-slate-100">
                           <img src={newProduct.image_url} alt="Preview" className="w-full h-full object-cover" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                         </div>
                       )}
                     </div>

                     <div className="flex gap-4">
                        <input type="number" step="0.01" placeholder="Price" required className="flex-1 bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-bold text-sm" value={newProduct.price} onChange={(e) => setNewProduct({...newProduct, price: e.target.value})} />
                        <select className="flex-1 bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-bold text-sm" value={newProduct.category} onChange={(e) => setNewProduct({...newProduct, category: e.target.value})}>
                           <option>Food</option>
                           <option>Drinks</option>
                           <option>Groceries</option>
                           <option>Pharmacy</option>
                           <option>Retail</option>
                        </select>
                     </div>
                     <div className="flex gap-3 pt-2">
                        <button type="button" onClick={() => { setIsAddProductOpen(false); setEditingProduct(null); }} className="flex-1 py-4 bg-slate-100 text-slate-500 rounded-xl font-black uppercase tracking-widest text-xs">Cancel</button>
                        <button type="submit" className="flex-[2] py-4 bg-brand-blue text-white rounded-xl font-black uppercase tracking-widest text-xs shadow-lg shadow-brand-blue/20">{editingProduct ? 'Update Item' : 'Save Item'}</button>
                     </div>
                   </form>
                </motion.div>
               </div>
              )}
            </AnimatePresence>
           
        </div>
      ) : activeTab === 'store' ? (
        <DarkCard className="max-w-2xl mx-auto">
          <div className="flex items-center gap-4 mb-6">
            <ProfileAvatarUpload
              name={user.name}
              avatarUrl={user.avatar_url}
              size="md"
              onUpdated={(updatedUser, newToken) => {
                onUserUpdate(updatedUser as unknown as AuthUser, newToken);
                addNotification('Profile photo updated', 'success');
              }}
              onError={(m) => addNotification(m, 'warning')}
            />
            <div>
              <h3 className="text-3xl font-black italic tracking-tighter text-slate-800">Store Profile</h3>
              <p className="text-slate-400 font-bold uppercase tracking-widest text-[10px]">Your photo & how customers see your store</p>
            </div>
          </div>
          
          <form onSubmit={async (e) => {
            e.preventDefault();
            setStoreSaving(true);
            setStoreMsg('');
            try {
              const res = await axios.patch('/api/auth/profile', storeForm);
              onUserUpdate(res.data.user as AuthUser, res.data.token);
              setStoreForm((prev) => ({
                ...prev,
                cover_image: (res.data.user as AuthUser).cover_image || prev.cover_image,
              }));
              void refreshData();
              setStoreMsg('Store profile updated successfully!');
            } catch (err: any) {
              setStoreMsg('Failed to update store profile');
            } finally {
              setStoreSaving(false);
            }
          }} className="space-y-8">
            
            <div className="space-y-3">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Cover Image</label>
              <div className="flex gap-2">
                <input type="text" placeholder="Paste URL or upload" value={storeForm.cover_image} onChange={e => setStoreForm({...storeForm, cover_image: e.target.value})} className="flex-1 bg-slate-50 border border-slate-100 rounded-2xl py-4 px-6 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all" />
                <label className={cn("px-5 py-4 rounded-2xl font-black cursor-pointer transition-all flex items-center", uploading ? "bg-slate-200 text-slate-400" : "bg-brand-green text-white hover:scale-105")}>
                  {uploading ? <LoadingIndicator size="sm" /> : 'Upload'}
                  <input type="file" accept="image/*" className="hidden" disabled={uploading} onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) handleFileUpload(file, (url) => setStoreForm({...storeForm, cover_image: url}), 'covers');
                  }} />
                </label>
              </div>
              {storeForm.cover_image && (
                <div className="rounded-3xl overflow-hidden h-40 border border-slate-100 shadow-inner">
                  <img key={storeForm.cover_image} src={storeForm.cover_image} alt="Cover Preview" className="w-full h-full object-cover" />
                </div>
              )}
            </div>

            <div className="space-y-3">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Shop category (customer browse)</label>
              <select
                required
                value={storeForm.shop_category}
                onChange={e => setStoreForm({ ...storeForm, shop_category: e.target.value })}
                className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 px-6 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all"
              >
                <option value="pharmacy">Pharmacy</option>
                <option value="restaurant">Restaurant</option>
                <option value="food">Food &amp; Drinks</option>
                <option value="fashion">Fashion</option>
                <option value="groceries">Groceries</option>
              </select>
            </div>

            <div className="space-y-3">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Operating Region</label>
              <div className="relative">
                <MapPin size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" />
                <select 
                  required 
                  value={storeForm.region} 
                  onChange={e => setStoreForm({...storeForm, region: e.target.value})} 
                  className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 pl-12 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all"
                >
                  <option value="">Select Region</option>
                  {GHANA_REGIONS.map(r => <option key={r} value={r}>{r}</option>)}
                </select>
              </div>
            </div>

            <div className="space-y-3">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Physical Address (Ghana)</label>
              <LocationAutocompleteInput
                placeholder="e.g. East Legon, Accra"
                icon={MapPin}
                value={storeForm.address}
                onChange={(val) => setStoreForm((prev) => ({
                  ...prev,
                  address: val.address,
                  lat: val.lat || prev.lat,
                  lng: val.lng || prev.lng,
                }))}
                onMapClick={() => {}}
                showMapButton={false}
                onLocationError={(m) => addNotification(m, 'warning')}
              />
            </div>

            <div className="space-y-3">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Pin Your Location (Drag the pin)</label>
              <div className="h-64 rounded-3xl overflow-hidden border border-slate-100 shadow-inner">
                <Map 
                  defaultCenter={{ lat: storeForm.lat, lng: storeForm.lng }} 
                  defaultZoom={15} 
                  disableDefaultUI={true}
                  styles={CLEAN_MAP_STYLE}
                >
                  <Marker position={{ lat: storeForm.lat, lng: storeForm.lng }} draggable={true} onDragEnd={async (e: any) => {
                    const newLat = e.latLng?.lat() || storeForm.lat;
                    const newLng = e.latLng?.lng() || storeForm.lng;
                    setStoreForm(prev => ({...prev, lat: newLat, lng: newLng}));
                    const address = await resolveAddressLabel(newLat, newLng);
                    setStoreForm((prev) => ({ ...prev, address }));
                  }} />
                </Map>
              </div>
            </div>

            {storeMsg && (
              <p className={cn("text-xs font-bold text-center uppercase tracking-widest py-3 rounded-xl border", storeMsg.includes('success') ? "text-brand-green bg-brand-green/10 border-brand-green/20" : "text-red-500 bg-red-50 border-red-100")}>{storeMsg}</p>
            )}

            <button type="submit" disabled={storeSaving} className="w-full py-5 bg-brand-green text-white rounded-[2rem] font-black uppercase tracking-widest text-sm hover:scale-[1.02] active:scale-[0.98] transition-all shadow-2xl shadow-brand-green/20 flex items-center justify-center gap-3">
              {storeSaving ? <LoadingIndicator size="sm" /> : <><Save size={18} /> Update Store</>}
            </button>
          </form>
        </DarkCard>
      ) : null}

      {activeTab === 'wallet' && (
        <div className="bg-white rounded-[1.5rem] sm:rounded-[2rem] border border-slate-100 shadow-sm p-4 sm:p-10 max-w-xl mx-auto min-h-[50vh] flex flex-col justify-center">
          <div className="text-center mb-6 sm:mb-8">
            <div className="w-12 h-12 sm:w-16 sm:h-16 bg-brand-green/10 text-brand-green rounded-full flex items-center justify-center mx-auto mb-3 sm:mb-4">
              <CreditCard size={24} className="sm:w-8 sm:h-8" />
            </div>
            <h3 className="font-black uppercase tracking-widest text-slate-800 text-sm sm:text-lg">Available Balance</h3>
            <p className="text-4xl sm:text-5xl font-black tracking-tighter text-brand-green mt-1 sm:mt-2">{formatCedis(user.balance || 0)}</p>
          </div>
          
          <form onSubmit={handleWithdraw} className="space-y-4 bg-slate-50 p-4 sm:p-8 rounded-[1.5rem] sm:rounded-[2rem] border border-slate-100">
            {/* Withdrawal Method */}
            <div>
              <label className="block text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2 ml-2 sm:ml-4">Withdrawal Method</label>
              <div className="flex flex-col sm:flex-row gap-2">
                <button type="button" onClick={() => setWithdrawMethod('momo')} className={cn("flex-1 py-3 sm:py-4 rounded-xl sm:rounded-2xl font-black uppercase tracking-widest text-[10px] transition-all border flex items-center justify-center gap-2", withdrawMethod === 'momo' ? "bg-brand-blue text-white border-brand-blue shadow-lg" : "bg-white text-slate-500 border-slate-200")}>
                  <Phone size={14} /> Mobile Money
                </button>
                <button type="button" onClick={() => setWithdrawMethod('bank')} className={cn("flex-1 py-3 sm:py-4 rounded-xl sm:rounded-2xl font-black uppercase tracking-widest text-[10px] transition-all border flex items-center justify-center gap-2", withdrawMethod === 'bank' ? "bg-brand-blue text-white border-brand-blue shadow-lg" : "bg-white text-slate-500 border-slate-200")}>
                  <CreditCard size={14} /> Bank Account
                </button>
              </div>
            </div>

            {/* Mobile Money Fields */}
            {withdrawMethod === 'momo' && (
              <div className="space-y-3">
                <div>
                  <label className="block text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2 ml-2 sm:ml-4">Network</label>
                  <select 
                    value={withdrawNetwork}
                    onChange={e => setWithdrawNetwork(e.target.value)}
                    className="w-full bg-white border border-slate-200 px-4 sm:px-6 py-3 sm:py-4 rounded-xl sm:rounded-2xl font-bold focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all text-xs sm:text-sm"
                  >
                    <option value="mtn">MTN Mobile Money</option>
                    <option value="vodafone">Vodafone Cash</option>
                    <option value="airteltigo">AirtelTigo Money</option>
                  </select>
                </div>
                <div>
                  <label className="block text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2 ml-2 sm:ml-4">Phone Number</label>
                  <input 
                    type="tel" 
                    required 
                    value={withdrawPhone}
                    onChange={e => setWithdrawPhone(e.target.value)}
                    className="w-full bg-white border border-slate-200 px-4 sm:px-6 py-3 sm:py-4 rounded-xl sm:rounded-2xl font-bold focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all placeholder:text-slate-300 text-xs sm:text-sm"
                    placeholder="0XX XXX XXXX"
                  />
                </div>
              </div>
            )}

            {/* Bank Account Fields */}
            {withdrawMethod === 'bank' && (
              <div className="space-y-3">
                <div>
                  <label className="block text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2 ml-2 sm:ml-4">Bank Name</label>
                  <select 
                    value={withdrawBank}
                    onChange={e => setWithdrawBank(e.target.value)}
                    className="w-full bg-white border border-slate-200 px-4 sm:px-6 py-3 sm:py-4 rounded-xl sm:rounded-2xl font-bold focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all text-xs sm:text-sm"
                  >
                    <option value="">Select Bank</option>
                    <option value="gcb">GCB Bank</option>
                    <option value="ecobank">Ecobank Ghana</option>
                    <option value="stanbic">Stanbic Bank</option>
                    <option value="absa">Absa Bank Ghana</option>
                    <option value="fidelity">Fidelity Bank</option>
                    <option value="calbank">CalBank</option>
                    <option value="uba">UBA Ghana</option>
                    <option value="zenith">Zenith Bank Ghana</option>
                  </select>
                </div>
                <div>
                  <label className="block text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2 ml-2 sm:ml-4">Account Name</label>
                  <input 
                    type="text" 
                    required 
                    value={withdrawAccName}
                    onChange={e => setWithdrawAccName(e.target.value)}
                    className="w-full bg-white border border-slate-200 px-4 sm:px-6 py-3 sm:py-4 rounded-xl sm:rounded-2xl font-bold focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all placeholder:text-slate-300 text-xs sm:text-sm"
                    placeholder="Full name on account"
                  />
                </div>
                <div>
                  <label className="block text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2 ml-2 sm:ml-4">Account Number</label>
                  <input 
                    type="text" 
                    required 
                    value={withdrawAccNum}
                    onChange={e => setWithdrawAccNum(e.target.value)}
                    className="w-full bg-white border border-slate-200 px-4 sm:px-6 py-3 sm:py-4 rounded-xl sm:rounded-2xl font-bold focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all placeholder:text-slate-300 text-xs sm:text-sm"
                    placeholder="Account number"
                  />
                </div>
              </div>
            )}

            {/* Amount */}
            <div>
              <label className="block text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2 ml-2 sm:ml-4">Withdraw Amount (?)</label>
              <input 
                type="number" 
                required 
                min="1" 
                max={user.balance} 
                step="0.01"
                value={withdrawAmount}
                onChange={e => setWithdrawAmount(e.target.value)}
                className="w-full bg-white border border-slate-200 px-4 sm:px-6 py-3 sm:py-4 rounded-xl sm:rounded-2xl font-bold focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all placeholder:text-slate-300 text-xs sm:text-sm"
                placeholder="Enter amount"
              />
            </div>
            
            {withdrawStatus && (
              <p className={cn("text-[10px] sm:text-xs font-bold text-center uppercase tracking-widest py-3 rounded-xl border", withdrawStatus.type === 'success' ? "text-brand-green bg-brand-green/10 border-brand-green/20" : "text-red-500 bg-red-50 border-red-100")}>{withdrawStatus.message}</p>
            )}

            <button type="submit" disabled={isWithdrawing || !withdrawAmount || Number(withdrawAmount) > Number(user.balance) || Number(user.balance) <= 0} className="w-full py-4 sm:py-5 bg-slate-900 text-white rounded-xl sm:rounded-[2rem] font-black uppercase tracking-widest text-[10px] sm:text-sm hover:scale-[1.02] active:scale-[0.98] transition-all disabled:opacity-50 disabled:hover:scale-100">
              {isWithdrawing ? 'Processing...' : `Withdraw via ${withdrawMethod === 'momo' ? 'Mobile Money' : 'Bank Transfer'}`}
            </button>
          </form>
        </div>
      )}

      <ConfirmationModal
        isOpen={!!productToDelete}
        onClose={() => setProductToDelete(null)}
        onConfirm={() => productToDelete && handleDeleteProduct(productToDelete.id)}
        title="Delete menu item"
        message={`Remove "${productToDelete?.name}" from your menu?`}
        confirmLabel="Delete"
        type="danger"
      />
    </div>
  );
}

function Directions({ origin, destination, onETAUpdate }: { origin: google.maps.LatLngLiteral, destination: google.maps.LatLngLiteral, onETAUpdate?: (eta: string) => void }) {
  const map = useMap();
  const routesLibrary = useMapsLibrary('routes');
  const [directionsService, setDirectionsService] = useState<google.maps.DirectionsService>();
  const [directionsRenderer, setDirectionsRenderer] = useState<google.maps.DirectionsRenderer>();
  const lastOriginRef = useRef<google.maps.LatLngLiteral | null>(null);

  useEffect(() => {
    if (!routesLibrary || !map) return;
    const renderer = new routesLibrary.DirectionsRenderer({ 
      map,
      suppressMarkers: true,
      polylineOptions: {
        strokeColor: '#3b82f6',
        strokeWeight: 5,
        strokeOpacity: 0.8
      }
    });
    setDirectionsService(new routesLibrary.DirectionsService());
    setDirectionsRenderer(renderer);
    return () => renderer.setMap(null);
  }, [routesLibrary, map]);

  useEffect(() => {
    if (!directionsService || !directionsRenderer || !origin || !destination) return;

    // Skip update if movement is negligible (less than ~10 meters)
    if (lastOriginRef.current) {
      const dist = Math.sqrt(
        Math.pow(origin.lat - lastOriginRef.current.lat, 2) + 
        Math.pow(origin.lng - lastOriginRef.current.lng, 2)
      );
      if (dist < 0.0001 && lastOriginRef.current.lat !== 0) return;
    }

    directionsService.route({
      origin,
      destination,
      travelMode: google.maps.TravelMode.DRIVING
    }).then(response => {
      directionsRenderer.setDirections(response);
      if (onETAUpdate && response.routes[0]?.legs[0]?.duration) {
        onETAUpdate(response.routes[0].legs[0].duration.text);
      }
      lastOriginRef.current = origin;
    }).catch(err => console.warn("Routing failed", err));
  }, [directionsService, directionsRenderer, origin, destination]);

  return null;
}

const INCOMING_RIDE_TIMEOUT_SEC = 30;

function getOfferSecondsLeft(order: Order | null): number {
  if (!order?.expiresAt) return INCOMING_RIDE_TIMEOUT_SEC;
  const sec = Math.ceil((new Date(order.expiresAt).getTime() - Date.now()) / 1000);
  return Math.max(0, Math.min(INCOMING_RIDE_TIMEOUT_SEC, sec));
}

function IncomingRideCallModal({
  order,
  vendors,
  onAccept,
  onDecline,
}: {
  order: Order | null;
  vendors: any[];
  onAccept: (orderId: string, status: OrderStatus) => Promise<void>;
  onDecline: () => void | Promise<void>;
}) {
  const [secondsLeft, setSecondsLeft] = useState(INCOMING_RIDE_TIMEOUT_SEC);
  const [offerTtlSec, setOfferTtlSec] = useState(INCOMING_RIDE_TIMEOUT_SEC);
  const [accepting, setAccepting] = useState(false);
  const [declining, setDeclining] = useState(false);
  const ringStopRef = useRef(false);
  const ringCleanupRef = useRef<(() => void) | null>(null);
  const onDeclineRef = useRef(onDecline);
  onDeclineRef.current = onDecline;

  const dismissOfferUi = useCallback(async () => {
    ringStopRef.current = true;
    ringCleanupRef.current?.();
    await onDeclineRef.current();
  }, []);

  const handleDecline = useCallback(async () => {
    if (!order || declining) return;
    setDeclining(true);
    ringStopRef.current = true;
    ringCleanupRef.current?.();
    try {
      await axios.post(`/api/orders/${order.id}/decline`);
    } catch {
      /* offer may already be closed */
    }
    await onDeclineRef.current();
    setDeclining(false);
  }, [order, declining]);

  useEffect(() => {
    if (!order) {
      ringStopRef.current = true;
      ringCleanupRef.current?.();
      ringCleanupRef.current = null;
      return;
    }

    ringStopRef.current = false;
    const initialSec = getOfferSecondsLeft(order);
    setOfferTtlSec(initialSec > 0 ? initialSec : INCOMING_RIDE_TIMEOUT_SEC);
    setSecondsLeft(initialSec);
    if (initialSec <= 0) {
      void dismissOfferUi();
      return;
    }

    let wakeLock: WakeLockSentinel | null = null;
    if ('wakeLock' in navigator) {
      navigator.wakeLock.request('screen').then(w => { wakeLock = w; }).catch(() => {});
    }

    unlockIncomingRideAudio();
    playIncomingRidePulse();
    const ringInterval = setInterval(() => {
      if (ringStopRef.current) return;
      playIncomingRidePulse();
      if (navigator.vibrate) navigator.vibrate([300, 150, 300]);
    }, 1400);

    const countdown = setInterval(() => {
      setSecondsLeft(prev => {
        if (prev <= 1) {
          void dismissOfferUi();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    ringCleanupRef.current = () => {
      ringStopRef.current = true;
      clearInterval(ringInterval);
      clearInterval(countdown);
      wakeLock?.release().catch(() => {});
    };

    return ringCleanupRef.current;
  }, [order?.id, order?.expiresAt, dismissOfferUi]);

  if (!order) return null;

  const isCourier = (order as any).order_type === 'courier' || order.orderType === 'courier';
  const vendor = vendors.find(v => v.id === order.vendor_id);
  const pickupLabel = isCourier
    ? ((order as any).pickup_address || 'Pickup location')
    : (vendor?.name || vendor?.address || 'Vendor pickup');
  const earnings = (order as any).delivery_fee ?? order.total;

  return (
    <AnimatePresence>
      <motion.div
        key={order.id}
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        exit={{ opacity: 0 }}
        className="fixed inset-0 z-[20000] flex items-center justify-center bg-slate-950/95 backdrop-blur-md p-4"
      >
        <div className="absolute inset-0 overflow-hidden pointer-events-none">
          {[0, 1, 2].map(i => (
            <motion.div
              key={i}
              className="absolute left-1/2 top-1/3 -translate-x-1/2 -translate-y-1/2 rounded-full border-2 border-brand-green/40"
              initial={{ width: 120, height: 120, opacity: 0.6 }}
              animate={{ width: 320 + i * 80, height: 320 + i * 80, opacity: 0 }}
              transition={{ duration: 2, repeat: Infinity, delay: i * 0.5, ease: 'easeOut' }}
            />
          ))}
        </div>

        <motion.div
          initial={{ scale: 0.9, y: 24 }}
          animate={{ scale: 1, y: 0 }}
          exit={{ scale: 0.9, y: 24 }}
          className="relative w-full max-w-md bg-gradient-to-b from-slate-900 to-slate-950 rounded-[2.5rem] border border-white/10 shadow-2xl overflow-hidden"
        >
          <motion.div
            className="absolute top-0 left-0 right-0 h-1 bg-brand-green origin-left"
            initial={{ scaleX: 1 }}
            animate={{ scaleX: offerTtlSec > 0 ? secondsLeft / offerTtlSec : 0 }}
            transition={{ duration: 1, ease: 'linear' }}
          />

          <motion.div
            className="mx-auto mt-10 w-24 h-24 rounded-full bg-brand-green/20 border-4 border-brand-green flex items-center justify-center shadow-[0_0_40px_rgba(34,197,94,0.4)]"
            animate={{ scale: [1, 1.06, 1] }}
            transition={{ duration: 1.2, repeat: Infinity }}
          >
            <Phone size={40} className="text-brand-green" />
          </motion.div>

          <div className="text-center px-6 mt-6">
            <p className="text-[10px] font-black uppercase tracking-[0.3em] text-brand-green animate-pulse">
              Incoming ride request
            </p>
            <h2 className="text-2xl font-black text-white mt-2 tracking-tight">
              {isCourier ? 'Courier mission' : 'Delivery pickup'}
            </h2>
            {(order.offerDistanceKm ?? order.pickupDistanceKm) != null &&
              (order.offerDistanceKm ?? order.pickupDistanceKm)! > 0 && (
              <p className="text-brand-green text-base font-black mt-2">
                {(order.offerDistanceKm ?? order.pickupDistanceKm)!.toFixed(1)} km to pickup
              </p>
            )}
            <p className="text-slate-400 text-sm font-bold mt-1">
              #{order.id.slice(-6).toUpperCase()} · {secondsLeft}s to respond
            </p>
          </div>

          <motion.div
            className="mx-6 mt-8 p-5 rounded-3xl bg-white/5 border border-white/10 space-y-4"
            animate={{ opacity: [0.85, 1, 0.85] }}
            transition={{ duration: 2, repeat: Infinity }}
          >
            <motion.div
              className="text-center"
              animate={{ scale: [1, 1.02, 1] }}
              transition={{ duration: 1.5, repeat: Infinity }}
            >
              <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">You earn</p>
              <p className="text-4xl font-black text-brand-green font-mono">{formatCedis(earnings)}</p>
            </motion.div>
            <motion.div className="flex items-start gap-3" initial={{ x: -8, opacity: 0.8 }} animate={{ x: 0, opacity: 1 }}>
              <div className="w-9 h-9 rounded-xl bg-brand-blue/20 flex items-center justify-center shrink-0">
                <MapPin size={16} className="text-brand-blue" />
              </div>
              <motion.div animate={{ opacity: [0.7, 1, 0.7] }} transition={{ duration: 1.8, repeat: Infinity }}>
                <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">Pickup</p>
                <p className="text-sm font-bold text-white">{pickupLabel}</p>
              </motion.div>
            </motion.div>
            <motion.div className="flex items-start gap-3" initial={{ x: 8, opacity: 0.8 }} animate={{ x: 0, opacity: 1 }}>
              <motion.div
                className="w-9 h-9 rounded-xl bg-brand-green/20 flex items-center justify-center shrink-0"
                animate={{ scale: [1, 1.1, 1] }}
                transition={{ duration: 1, repeat: Infinity }}
              >
                <Navigation size={16} className="text-brand-green" />
              </motion.div>
              <div>
                <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">Drop-off</p>
                <p className="text-sm font-bold text-white">{order.address || 'Destination'}</p>
              </div>
            </motion.div>
          </motion.div>

          <div className="grid grid-cols-2 gap-3 p-6 mt-4">
            <button
              type="button"
              onClick={() => void handleDecline()}
              disabled={accepting || declining}
              className="py-4 rounded-2xl bg-white/10 text-white font-black uppercase tracking-widest text-xs hover:bg-white/15 transition-all flex flex-col items-center gap-1 disabled:opacity-60"
            >
              <X size={22} />
              {declining ? 'Declining?' : 'Decline'}
            </button>
            <button
              type="button"
              disabled={accepting}
              onClick={async () => {
                setAccepting(true);
                try {
                  await onAccept(order.id, order.status);
                } finally {
                  setAccepting(false);
                }
              }}
              className="py-4 rounded-2xl bg-brand-green text-white font-black uppercase tracking-widest text-xs hover:bg-brand-green/90 transition-all shadow-lg shadow-brand-green/30 flex flex-col items-center gap-1 disabled:opacity-60"
            >
              <Check size={22} />
              {accepting ? 'Accepting?' : 'Accept ride'}
            </button>
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
function AdminView({
  user,
  orders,
  addNotification,
  activeTab,
  setActiveTab,
  onPendingCountChange,
  onPendingRiderCountChange,
}: {
  user: AuthUser;
  orders: Order[];
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  activeTab: any;
  setActiveTab: (v: any) => void;
  onPendingCountChange?: (count: number) => void;
  onPendingRiderCountChange?: (count: number) => void;
}) {
  const [allUsers, setAllUsers] = useState<any[]>([]);
  const [adminVendors, setAdminVendors] = useState<any[]>([]);
  const [vendorsLoading, setVendorsLoading] = useState(false);
  const [vendorSearch, setVendorSearch] = useState('');
  const [pendingRiders, setPendingRiders] = useState<any[]>([]);
  const [ridersLoading, setRidersLoading] = useState(false);
  const [rejectRiderId, setRejectRiderId] = useState<string | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [zones, setZones] = useState<any[]>([]);
  const [pendingProducts, setPendingProducts] = useState<any[]>([]);
  const [revenueData, setRevenueData] = useState<any>(null);
  const [revenueLoading, setRevenueLoading] = useState(false);
  const [revenueError, setRevenueError] = useState('');
  const [settings, setSettings] = useState({
    paystack_public_key: '',
    paystack_secret_key: '',
    platform_fee_percent: '10',
    delivery_price_per_km: '4',
    delivery_min_fee: '',
    delivery_max_fee: '',
    okada_price_per_km: '3.5',
    okada_min_fee: '6',
    keke_price_per_km: '2.5',
    keke_min_fee: '5',
    surge_enabled: false,
    surge_multiplier: '1.5',
    surge_start_time: '17:00',
    surge_end_time: '21:00',
    surge_active_now: false,
    ghana_time: '',
    sms_base_url: 'https://www.inteksms.top/api/v1',
    sms_api_key: '',
    sms_sender_id: 'bytzee',
    sms_config_source: '',
  });
  const [settingsSaving, setSettingsSaving] = useState(false);
  const [smsTestPhone, setSmsTestPhone] = useState('');
  const [smsTestLoading, setSmsTestLoading] = useState(false);
  const [editingZone, setEditingZone] = useState<any | null>(null);
  const [zoneForm, setZoneForm] = useState({ name: '', region: '', base_price: '10', price_per_km: '2', min_price: '5', max_price: '' });
  const [showZoneForm, setShowZoneForm] = useState(false);
  const [zoneToDelete, setZoneToDelete] = useState<any | null>(null);
  const [promotions, setPromotions] = useState<any[]>([]);
  const [promoLoading, setPromoLoading] = useState(false);
  const [showPromoForm, setShowPromoForm] = useState(false);
  const [promoForm, setPromoForm] = useState({
    name: '',
    code: '',
    service_types: 'okada,keke,package',
    customer_discount_percent: '0',
    customer_discount_fixed: '0',
    rider_bonus_amount: '0',
    target_region: '',
    enabled: true,
    max_redemptions: '',
  });
  const [promoSaving, setPromoSaving] = useState(false);

  useEffect(() => {
    axios.get('/api/admin/users').then((res) => setAllUsers(res.data)).catch(() => addNotification('Failed to load users', 'warning'));
    axios.get('/api/admin/pending-products').then((res) => {
      setPendingProducts(res.data);
      onPendingCountChange?.(res.data?.length || 0);
    }).catch(() => {});
    axios.get('/api/admin/pending-riders').then((res) => {
      setPendingRiders(res.data);
      onPendingRiderCountChange?.(res.data?.length || 0);
    }).catch(() => {});
    axios.get('/api/delivery-zones').then((res) => setZones(res.data)).catch(() => {});
  }, []);

  useEffect(() => {
    if (activeTab === 'products') {
      axios.get('/api/admin/pending-products').then((res) => {
        setPendingProducts(res.data);
        onPendingCountChange?.(res.data?.length || 0);
      }).catch(() => addNotification('Failed to load pending products', 'warning'));
    }
    if (activeTab === 'revenue') {
      setRevenueLoading(true);
      setRevenueError('');
      axios.get('/api/admin/revenue')
        .then((res) => setRevenueData(res.data))
        .catch((err) => setRevenueError(getApiError(err, 'Failed to load revenue')))
        .finally(() => setRevenueLoading(false));
    }
    if (activeTab === 'settings') {
      axios.get('/api/admin/settings').then((res) => setSettings({
        paystack_public_key: res.data.paystack_public_key || '',
        paystack_secret_key: '',
        platform_fee_percent: res.data.platform_fee_percent || '10',
        delivery_price_per_km: res.data.delivery_price_per_km || '4',
        delivery_min_fee: res.data.delivery_min_fee || '',
        delivery_max_fee: res.data.delivery_max_fee || '',
        okada_price_per_km: res.data.okada_price_per_km || '3.5',
        okada_min_fee: res.data.okada_min_fee || '6',
        keke_price_per_km: res.data.keke_price_per_km || '2.5',
        keke_min_fee: res.data.keke_min_fee || '5',
        surge_enabled: res.data.surge_enabled === 'true' || res.data.surge_enabled === true,
        surge_multiplier: res.data.surge_multiplier || '1.5',
        surge_start_time: res.data.surge_start_time || '17:00',
        surge_end_time: res.data.surge_end_time || '21:00',
        surge_active_now: res.data.surge_active_now === true,
        ghana_time: res.data.ghana_time || '',
        sms_base_url: res.data.sms_base_url || 'https://www.inteksms.top/api/v1',
        sms_api_key: '',
        sms_sender_id: res.data.sms_sender_id || 'bytzee',
        sms_config_source: res.data.sms_config_source || '',
      })).catch(() => addNotification('Failed to load settings', 'warning'));
    }
    if (activeTab === 'promotions') {
      setPromoLoading(true);
      axios.get('/api/admin/promotions')
        .then((res) => setPromotions(res.data || []))
        .catch(() => addNotification('Failed to load promotions', 'warning'))
        .finally(() => setPromoLoading(false));
    }
    if (activeTab === 'stores') {
      setVendorsLoading(true);
      axios.get('/api/admin/vendors')
        .then((res) => setAdminVendors(res.data))
        .catch(() => addNotification('Failed to load stores', 'warning'))
        .finally(() => setVendorsLoading(false));
    }
    if (activeTab === 'drivers') {
      setRidersLoading(true);
      axios.get('/api/admin/pending-riders')
        .then((res) => {
          setPendingRiders(res.data);
          onPendingRiderCountChange?.(res.data?.length || 0);
        })
        .catch(() => addNotification('Failed to load driver applications', 'warning'))
        .finally(() => setRidersLoading(false));
    }
  }, [activeTab]);

  const refreshPendingRiders = async () => {
    const res = await axios.get('/api/admin/pending-riders');
    setPendingRiders(res.data);
    onPendingRiderCountChange?.(res.data?.length || 0);
  };

  useEffect(() => {
    onPendingCountChange?.(pendingProducts.length);
  }, [pendingProducts.length, onPendingCountChange]);

  const handleSaveZone = async () => {
    try {
      if (editingZone) {
        const res = await axios.patch(`/api/delivery-zones/${editingZone.id}`, {
          name: zoneForm.name, region: zoneForm.region,
          base_price: Number(zoneForm.base_price), price_per_km: Number(zoneForm.price_per_km),
          min_price: Number(zoneForm.min_price), max_price: zoneForm.max_price ? Number(zoneForm.max_price) : null
        });
        setZones(zones.map(z => z.id === editingZone.id ? res.data : z));
      } else {
        const res = await axios.post('/api/delivery-zones', {
          name: zoneForm.name, region: zoneForm.region,
          base_price: Number(zoneForm.base_price), price_per_km: Number(zoneForm.price_per_km),
          min_price: Number(zoneForm.min_price), max_price: zoneForm.max_price ? Number(zoneForm.max_price) : null
        });
        setZones([...zones, res.data]);
      }
      setShowZoneForm(false);
      setEditingZone(null);
      setZoneForm({ name: '', region: '', base_price: '10', price_per_km: '2', min_price: '5', max_price: '' });
    } catch (err) {
      console.error('Save zone failed', err);
    }
  };

  const handleDeleteZone = async (id: string) => {
    try {
      await axios.delete(`/api/delivery-zones/${id}`);
      setZones(zones.filter(z => z.id !== id));
    } catch (err) {
      console.error('Delete zone failed', err);
    }
  };

  const handleToggleZone = async (zone: any) => {
    try {
      const res = await axios.patch(`/api/delivery-zones/${zone.id}`, { is_active: !zone.is_active });
      setZones(zones.map(z => z.id === zone.id ? res.data : z));
    } catch (err) {
      console.error('Toggle zone failed', err);
    }
  };

  return (
    <div className="space-y-10 pb-24 sm:pb-0 relative">
       {/* Mobile Bottom Navigation - Moved to App component */}

       <header className="flex flex-col lg:flex-row justify-between items-start lg:items-end gap-6">
          <div>
            <h2 className="text-3xl font-black tracking-tighter text-slate-800 uppercase italic">Control Tower</h2>
            <p className="text-slate-400 font-bold uppercase tracking-widest text-[10px]">Global Operations Oversight</p>
          </div>
          <div className="flex flex-wrap gap-2">
             <button onClick={() => setActiveTab('orders')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'orders' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Orders</button>
             <button onClick={() => setActiveTab('users')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'users' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Users</button>
             <button onClick={() => setActiveTab('stores')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'stores' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Stores</button>
             <button onClick={() => setActiveTab('drivers')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'drivers' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Drivers {pendingRiders.length > 0 && <span className="ml-1 bg-red-500 text-white px-1.5 py-0.5 rounded-full text-[8px]">{pendingRiders.length}</span>}</button>
             <button onClick={() => setActiveTab('products')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'products' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Approval {pendingProducts.length > 0 && <span className="ml-1 bg-red-500 text-white px-1.5 py-0.5 rounded-full text-[8px]">{pendingProducts.length}</span>}</button>
             <button onClick={() => setActiveTab('revenue')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'revenue' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Revenue</button>
             <button onClick={() => setActiveTab('promotions')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'promotions' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Promos</button>
             <button onClick={() => setActiveTab('zones')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'zones' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Zones</button>
             <button onClick={() => setActiveTab('settings')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'settings' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Settings</button>
          </div>
       </header>

       <div className="grid grid-cols-1 md:grid-cols-3 gap-4 sm:gap-6">
          <StatBox label="Total Orders" value={orders.length} color="blue" />
          <StatBox label="Revenue" value={formatCedis(orders.reduce((a, b) => a + Number(b.total), 0))} color="green" />
          <StatBox label="Total Users" value={allUsers.length || '...'} color="blue" />
       </div>

       {activeTab === 'orders' ? (
         <div className="space-y-4">
            <div className="hidden md:block bg-white rounded-[2.5rem] border border-slate-100 overflow-hidden shadow-sm">
               <table className="w-full text-left">
                 <thead className="bg-slate-50 border-b border-slate-100">
                    <tr>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Order ID</th>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Status</th>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Customer</th>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Total</th>
                     <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Payment</th>
                    </tr>
                 </thead>
                 <tbody>
                    {orders.map(o => (
                      <tr key={o.id} className="border-b border-slate-50 hover:bg-slate-50 transition-colors">
                        <td className="px-8 py-6 font-mono font-black text-sm">#{o.id.slice(-4)}</td>
                        <td className="px-8 py-6"><span className="px-3 py-1 bg-slate-100 rounded-lg text-[10px] font-black uppercase">{o.status}</span></td>
                        <td className="px-8 py-6 text-sm font-bold text-slate-600">{o.customerName}</td>
                        <td className="px-8 py-6 font-mono font-black text-brand-blue">{formatCedis(o.total)}</td>
                        <td className="px-8 py-6"><PaymentStatusBadge order={o} /></td>
                      </tr>
                    ))}
                 </tbody>
               </table>
            </div>

            <div className="md:hidden space-y-4">
               {orders.map(o => (
                 <div key={o.id} className="bg-white p-6 rounded-[2rem] border border-slate-100 shadow-sm">
                    <div className="flex justify-between items-start mb-4">
                       <h4 className="font-black text-lg tracking-tighter italic uppercase underline decoration-brand-blue/50">#{o.id.slice(-4)}</h4>
                       <span className="font-mono font-black text-brand-blue">{formatCedis(o.total)}</span>
                    </div>
                    <div className="flex justify-between items-center">
                       <div className="flex flex-col gap-1">
                         <span className="px-3 py-1 bg-slate-100 rounded-lg text-[10px] font-black uppercase inline-block">{o.status}</span>
                         <PaymentStatusBadge order={o} />
                       </div>
                       <span className="text-[10px] font-black text-slate-400 uppercase tracking-widest">{o.customerName}</span>
                    </div>
                 </div>
               ))}
            </div>
         </div>
       ) : activeTab === 'stores' ? (
         <div className="space-y-4">
            <input
              type="search"
              placeholder="Search stores by name, email, phone…"
              value={vendorSearch}
              onChange={(e) => setVendorSearch(e.target.value)}
              className="w-full max-w-md px-4 py-3 rounded-2xl border border-slate-200 text-sm font-bold"
            />
            {vendorsLoading ? (
              <p className="text-slate-400 text-sm">Loading stores…</p>
            ) : (
              <div className="space-y-4">
                {adminVendors
                  .filter((v: any) => {
                    const q = vendorSearch.trim().toLowerCase();
                    if (!q) return true;
                    return (
                      String(v.name || '').toLowerCase().includes(q) ||
                      String(v.email || '').toLowerCase().includes(q) ||
                      String(v.phone || '').toLowerCase().includes(q)
                    );
                  })
                  .map((v: any) => (
                  <div key={v.id} className="bg-white p-6 rounded-[2rem] border border-slate-100 shadow-sm">
                    <div className="flex flex-wrap justify-between items-start gap-4">
                      <div>
                        <h4 className="font-black text-lg text-slate-800">{v.name}</h4>
                        <p className="text-slate-500 text-xs">{v.email}{v.phone ? ` · ${v.phone}` : ''}</p>
                        <p className="text-slate-400 text-[10px] font-bold uppercase mt-1">
                          {v.status} · {v.product_count ?? 0} items
                          {(v.pending_products ?? 0) > 0 ? ` · ${v.pending_products} pending menu` : ''}
                          {(v.active_orders ?? 0) > 0 ? ` · ${v.active_orders} active orders` : ''}
                        </p>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        {v.status === 'pending' && (
                          <button
                            onClick={async () => {
                              await axios.patch(`/api/admin/users/${v.id}/status`, { status: 'active' });
                              setAdminVendors(adminVendors.map((x: any) => x.id === v.id ? { ...x, status: 'active' } : x));
                              addNotification(`${v.name} approved`, 'success');
                            }}
                            className="px-3 py-1.5 bg-brand-green text-white rounded-lg text-[10px] font-black uppercase"
                          >
                            Approve
                          </button>
                        )}
                        <button
                          onClick={async () => {
                            const newStatus = v.status === 'disabled' ? 'active' : 'disabled';
                            await axios.patch(`/api/admin/users/${v.id}/status`, { status: newStatus });
                            setAdminVendors(adminVendors.map((x: any) => x.id === v.id ? { ...x, status: newStatus } : x));
                          }}
                          className={cn("px-3 py-1.5 rounded-lg text-[10px] font-black uppercase", v.status === 'disabled' ? "bg-brand-blue text-white" : "bg-red-500 text-white")}
                        >
                          {v.status === 'disabled' ? 'Enable' : 'Disable'}
                        </button>
                        <button
                          onClick={async () => {
                            if ((v.active_orders ?? 0) > 0) {
                              addNotification(`Cannot delete: ${v.active_orders} active order(s)`, 'warning');
                              return;
                            }
                            if (!window.confirm(`Delete store "${v.name}"? All menu items will be removed.`)) return;
                            try {
                              await axios.delete(`/api/admin/vendors/${v.id}`);
                              setAdminVendors(adminVendors.filter((x: any) => x.id !== v.id));
                              addNotification(`${v.name} deleted`, 'success');
                            } catch (err: any) {
                              addNotification(getApiError(err, 'Delete failed'), 'warning');
                            }
                          }}
                          className="px-3 py-1.5 bg-slate-900 text-white rounded-lg text-[10px] font-black uppercase"
                        >
                          Delete
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
                {adminVendors.length === 0 && !vendorsLoading && (
                  <p className="text-slate-400 text-sm">No vendor accounts yet.</p>
                )}
              </div>
            )}
         </div>
       ) : activeTab === 'users' ? (
         <div className="space-y-4">
            <div className="hidden md:block bg-white rounded-[2.5rem] border border-slate-100 overflow-hidden shadow-sm">
               <table className="w-full text-left">
                 <thead className="bg-slate-50 border-b border-slate-100">
                    <tr>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Name</th>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Role</th>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Email</th>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Balance</th>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Status</th>
                      <th className="px-8 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Actions</th>
                    </tr>
                 </thead>
                 <tbody>
                    {allUsers.map(u => (
                      <tr key={u.id} className="border-b border-slate-50 hover:bg-slate-50 transition-colors">
                        <td className="px-8 py-6 font-bold text-sm">
                          <div className="flex flex-col gap-1.5">
                            <span>{u.name}</span>
                            {u.role === 'rider' && (
                              <DriverTierBadge
                                tier={u.riderTier || driverTierFrom(u.riderAvgRating, u.riderRatingCount ?? 0)}
                                avgRating={u.riderAvgRating}
                                ratingCount={u.riderRatingCount}
                                className="self-start"
                                light
                              />
                            )}
                          </div>
                        </td>
                        <td className="px-8 py-6"><span className={cn("px-3 py-1 rounded-lg text-[10px] font-black uppercase", u.role === 'admin' ? "bg-red-50 text-red-500" : "bg-slate-100 text-slate-500")}>{u.role}</span></td>
                        <td className="px-8 py-6 text-sm text-slate-500">{u.email}</td>
                        <td className="px-8 py-6 font-mono font-black text-brand-green">{formatCedis(u.balance)}</td>
                         <td className="px-8 py-6">
                           <span className={cn(
                             "px-3 py-1 rounded-lg text-[10px] font-black uppercase",
                             u.status === 'active' ? "bg-brand-green/10 text-brand-green" :
                             u.status === 'pending' ? "bg-amber-100 text-amber-600" :
                             "bg-red-50 text-red-500"
                           )}>
                             {u.status || 'active'}
                           </span>
                         </td>
                         <td className="px-8 py-6">
                           <div className="flex gap-2">
                             {u.status === 'pending' && (
                               <button 
                                 onClick={async () => {
                                   await axios.patch(`/api/admin/users/${u.id}/status`, { status: 'active' });
                                   setAllUsers(allUsers.map(usr => usr.id === u.id ? { ...usr, status: 'active' } : usr));
                                   addNotification(`${u.name} approved!`, 'success');
                                 }}
                                 className="px-3 py-1.5 bg-brand-green text-white rounded-lg text-[10px] font-black uppercase hover:scale-105 transition-all"
                               >
                                 Approve
                               </button>
                             )}
                             <button 
                               onClick={async () => {
                                 const newStatus = u.status === 'disabled' ? 'active' : 'disabled';
                                 await axios.patch(`/api/admin/users/${u.id}/status`, { status: newStatus });
                                 setAllUsers(allUsers.map(usr => usr.id === u.id ? { ...usr, status: newStatus } : usr));
                               }}
                               className={cn("px-3 py-1.5 rounded-lg text-[10px] font-black uppercase hover:scale-105 transition-all", u.status === 'disabled' ? "bg-brand-blue text-white" : "bg-red-500 text-white")}
                             >
                               {u.status === 'disabled' ? 'Enable' : 'Disable'}
                             </button>
                           </div>
                         </td>
                      </tr>
                    ))}
                 </tbody>
               </table>
            </div>

             <div className="md:hidden space-y-4">
               {allUsers.map(u => (
                 <div key={u.id} className="bg-white p-6 rounded-[2rem] border border-slate-100 shadow-sm">
                    <div className="flex justify-between items-start mb-2">
                       <h4 className="font-black text-sm uppercase tracking-tight">{u.name}</h4>
                       <span className={cn("px-3 py-1 rounded-lg text-[8px] font-black uppercase", u.role === 'admin' ? "bg-red-50 text-red-500" : "bg-slate-100 text-slate-500")}>{u.role}</span>
                    </div>
                    <p className="text-[10px] text-slate-400 mb-2">{u.email}</p>
                    {u.role === 'rider' && (
                      <div className="mb-4">
                        <DriverTierBadge
                          tier={u.riderTier || driverTierFrom(u.riderAvgRating, u.riderRatingCount ?? 0)}
                          avgRating={u.riderAvgRating}
                          ratingCount={u.riderRatingCount}
                          light
                        />
                      </div>
                    )}
                    <div className="flex justify-between items-center">
                       <div className="flex flex-col">
                          <span className="text-[8px] font-black text-slate-300 uppercase tracking-widest">Balance</span>
                          <span className="font-mono font-black text-brand-green text-sm">{formatCedis(u.balance)}</span>
                       </div>
                       <div className="flex gap-2">
                           {u.status === 'pending' && (
                             <button 
                               onClick={async () => {
                                 await axios.patch(`/api/admin/users/${u.id}/status`, { status: 'active' });
                                 setAllUsers(allUsers.map(usr => usr.id === u.id ? { ...usr, status: 'active' } : usr));
                                 addNotification(`${u.name} approved!`, 'success');
                               }}
                               className="px-4 py-2 bg-brand-green text-white rounded-xl text-[8px] font-black uppercase tracking-widest"
                             >
                               Approve
                             </button>
                           )}
                           <button 
                             onClick={async () => {
                               const newStatus = u.status === 'disabled' ? 'active' : 'disabled';
                               await axios.patch(`/api/admin/users/${u.id}/status`, { status: newStatus });
                               setAllUsers(allUsers.map(usr => usr.id === u.id ? { ...usr, status: newStatus } : usr));
                             }}
                             className={cn("px-4 py-2 rounded-xl text-[8px] font-black uppercase tracking-widest", u.status === 'disabled' ? "bg-brand-blue text-white" : "bg-red-500 text-white")}
                           >
                             {u.status === 'disabled' ? 'Enable' : 'Disable'}
                           </button>
                        </div>
                    </div>
                 </div>
               ))}
            </div>
         </div>
       ) : activeTab === 'drivers' ? (
         <div className="space-y-6">
            <h3 className="text-xl font-black italic tracking-tighter text-slate-800 uppercase">Driver verification</h3>
            {ridersLoading && <p className="text-slate-400 text-sm">Loading applications…</p>}
            {!ridersLoading && pendingRiders.length === 0 ? (
              <div className="bg-white rounded-[3rem] p-20 text-center border border-slate-100">
                <p className="text-slate-400 font-bold italic">No driver applications waiting for review.</p>
              </div>
            ) : (
              <div className="space-y-8">
                {pendingRiders.map((r: any) => {
                  const docs = Array.isArray(r.documents) ? r.documents : [];
                  const docLabel: Record<string, string> = { license: 'Driver licence', ghana_card: 'Ghana card', photo: 'Profile photo' };
                  return (
                    <div key={r.id} className="bg-white rounded-[2rem] border border-slate-100 p-6 sm:p-8 shadow-sm">
                      <div className="flex flex-wrap justify-between items-start gap-4 mb-6">
                        <div>
                          <h4 className="font-black text-lg text-slate-800">{r.name}</h4>
                          <p className="text-slate-400 text-xs font-bold uppercase tracking-widest">{r.email}</p>
                          {r.phone && <p className="text-slate-500 text-xs mt-1">{r.phone}</p>}
                          {r.region && <p className="text-slate-500 text-xs">{r.region}</p>}
                          {r.rider_vehicle_type && (
                            <p className="text-brand-green text-xs font-black uppercase tracking-widest mt-1">
                              Vehicle: {({ motorcycle: 'Okada', keke: 'Keke', bicycle: 'Bicycle' } as Record<string, string>)[r.rider_vehicle_type] || r.rider_vehicle_type}
                            </p>
                          )}
                        </div>
                        <span className={cn(
                          'px-3 py-1 rounded-lg text-[10px] font-black uppercase',
                          r.status === 'rejected' ? 'bg-red-50 text-red-500' : 'bg-amber-100 text-amber-600'
                        )}>
                          {r.status}
                        </span>
                      </div>
                      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-6">
                        {(['license', 'ghana_card', 'photo'] as const).map((type) => {
                          const doc = docs.find((d: any) => d.doc_type === type);
                          return (
                            <div key={type} className="rounded-2xl border border-slate-100 overflow-hidden bg-slate-50">
                              <p className="px-3 py-2 text-[9px] font-black uppercase tracking-widest text-slate-500">{docLabel[type]}</p>
                              {doc?.image_url ? (
                                <a href={doc.image_url} target="_blank" rel="noreferrer" className="block aspect-[4/3] bg-slate-200">
                                  <img src={doc.image_url} alt={docLabel[type]} className="w-full h-full object-cover" />
                                </a>
                              ) : (
                                <div className="aspect-[4/3] flex items-center justify-center text-slate-300 text-xs font-bold">Not uploaded</div>
                              )}
                            </div>
                          );
                        })}
                      </div>
                      <div className="flex flex-wrap gap-2">
                        <button
                          type="button"
                          onClick={async () => {
                            try {
                              await axios.patch(`/api/admin/riders/${r.id}/approve`);
                              await refreshPendingRiders();
                              setAllUsers((prev) => prev.map((u) => (u.id === r.id ? { ...u, status: 'active', is_online: false } : u)));
                              addNotification(`${r.name} approved as driver`, 'success');
                            } catch (err) {
                              addNotification(getApiError(err, 'Approve failed'), 'warning');
                            }
                          }}
                          className="px-5 py-3 bg-brand-green text-white rounded-xl font-black uppercase text-[10px] tracking-widest"
                        >
                          Approve driver
                        </button>
                        <button
                          type="button"
                          onClick={() => { setRejectRiderId(r.id); setRejectReason(''); }}
                          className="px-5 py-3 bg-red-500 text-white rounded-xl font-black uppercase text-[10px] tracking-widest"
                        >
                          Reject
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
            {rejectRiderId && (
              <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50">
                <div className="bg-white rounded-[2rem] p-8 max-w-md w-full shadow-xl">
                  <h4 className="font-black text-lg mb-4">Reject application</h4>
                  <textarea
                    value={rejectReason}
                    onChange={(e) => setRejectReason(e.target.value)}
                    placeholder="Reason (optional)"
                    className="w-full border border-slate-200 rounded-xl p-4 text-sm font-bold min-h-[100px] mb-4"
                  />
                  <div className="flex gap-2">
                    <button type="button" onClick={() => setRejectRiderId(null)} className="flex-1 py-3 bg-slate-100 rounded-xl font-bold text-[10px] uppercase">Cancel</button>
                    <button
                      type="button"
                      onClick={async () => {
                        try {
                          await axios.patch(`/api/admin/riders/${rejectRiderId}/reject`, { reason: rejectReason });
                          await refreshPendingRiders();
                          setAllUsers((prev) => prev.map((u) => (u.id === rejectRiderId ? { ...u, status: 'rejected' } : u)));
                          addNotification('Driver application rejected', 'success');
                          setRejectRiderId(null);
                        } catch (err) {
                          addNotification(getApiError(err, 'Reject failed'), 'warning');
                        }
                      }}
                      className="flex-1 py-3 bg-red-500 text-white rounded-xl font-bold text-[10px] uppercase"
                    >
                      Confirm reject
                    </button>
                  </div>
                </div>
              </div>
            )}
         </div>
       ) : activeTab === 'products' ? (
         <div className="space-y-6">
            <h3 className="text-xl font-black italic tracking-tighter text-slate-800 uppercase">Pending Approvals</h3>
            {pendingProducts.length === 0 ? (
              <div className="bg-white rounded-[3rem] p-20 text-center border border-slate-100">
                 <p className="text-slate-400 font-bold italic">No products waiting for approval.</p>
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                 {pendingProducts.map(p => (
                   <div key={p.id} className="bg-white rounded-[2rem] border border-slate-100 p-6 flex flex-col justify-between">
                      <div>
                         <div className="h-40 bg-slate-50 rounded-2xl mb-4 overflow-hidden">
                            <img src={p.image_url} alt={p.name} className="w-full h-full object-cover" />
                         </div>
                         <h4 className="font-black text-lg text-slate-800">{p.name}</h4>
                         <p className="text-slate-400 text-xs font-bold uppercase tracking-widest mb-4">Vendor: {p.vendor_name}</p>
                         <p className="text-slate-500 text-xs line-clamp-2 mb-6">{p.description}</p>
                      </div>
                      <div className="flex items-center justify-between gap-4">
                         <span className="font-mono font-black text-brand-blue">{formatCedis(p.price)}</span>
                         <div className="flex gap-2 flex-1">
                         <button 
                           type="button"
                           onClick={async () => {
                             try {
                               await axios.patch(`/api/admin/products/${p.id}/reject`);
                               setPendingProducts(pendingProducts.filter(item => item.id !== p.id));
                               addNotification('Product rejected', 'success');
                             } catch (err) {
                               addNotification(getApiError(err, 'Reject failed'), 'warning');
                             }
                           }}
                           className="flex-1 py-3 bg-slate-800 text-slate-300 rounded-xl font-bold text-[10px]"
                         >
                           Reject
                         </button>
                         <button 
                           type="button"
                           onClick={async () => {
                             try {
                               await axios.patch(`/api/admin/products/${p.id}/approve`);
                               setPendingProducts(pendingProducts.filter(item => item.id !== p.id));
                               addNotification('Product approved!', 'success');
                             } catch (err) {
                               addNotification(getApiError(err, 'Approve failed'), 'warning');
                             }
                           }}
                           className="flex-1 py-3 bg-brand-green text-white rounded-xl font-bold text-[10px]"
                         >
                           Approve
                         </button>
                         </div>
                      </div>
                   </div>
                 ))}
              </div>
            )}
         </div>
       ) : activeTab === 'revenue' ? (
         <div className="space-y-10">
            {revenueLoading && <p className="text-slate-400 text-sm">Loading revenue?</p>}
            {revenueError && <ErrorBanner message={revenueError} onRetry={() => setActiveTab('revenue')} />}
            {!revenueLoading && !revenueError && revenueData && (
              <>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                   <div className="bg-slate-900 p-10 rounded-[3rem] text-white">
                      <p className="text-[10px] font-black uppercase tracking-widest text-slate-400 mb-2">Gross Revenue</p>
                      <h3 className="text-5xl font-black tracking-tighter italic">{formatCedis(revenueData.summary.gross_revenue || 0)}</h3>
                   </div>
                   <div className="bg-brand-blue p-10 rounded-[3rem] text-white">
                      <p className="text-[10px] font-black uppercase tracking-widest text-white/50 mb-2">System Earnings (10%)</p>
                      <h3 className="text-5xl font-black tracking-tighter italic">{formatCedis(revenueData.summary.system_earnings || 0)}</h3>
                   </div>
                </div>

                <div className="bg-white rounded-[3rem] border border-slate-100 overflow-hidden shadow-sm">
                   <div className="px-10 py-8 border-b border-slate-50">
                      <h4 className="text-xl font-black italic tracking-tighter text-slate-800 uppercase">Recent Transactions</h4>
                   </div>
                   <div className="overflow-x-auto">
                      <table className="w-full text-left">
                         <thead className="bg-slate-50/50 border-b border-slate-100">
                            <tr>
                               <th className="px-10 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">User / Reference</th>
                               <th className="px-10 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Activity</th>
                               <th className="px-10 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Amount</th>
                               <th className="px-10 py-4 text-[10px] font-black uppercase tracking-widest text-slate-400">Date</th>
                            </tr>
                         </thead>
                         <tbody>
                            {revenueData.transactions.map((t: any) => (
                               <tr key={t.id} className="border-b border-slate-50 hover:bg-slate-50/50 transition-colors">
                                  <td className="px-10 py-6">
                                     <div className="flex flex-col">
                                        <span className="font-bold text-sm text-slate-800">{t.user_name || 'Platform Account'}</span>
                                        <span className="text-[10px] font-bold text-slate-400 uppercase tracking-widest truncate max-w-[200px]">{t.reference || 'No reference'}</span>
                                     </div>
                                  </td>
                                  <td className="px-10 py-6">
                                     <span className={cn(
                                       "px-3 py-1 rounded-lg text-[10px] font-black uppercase tracking-widest",
                                       t.type === 'topup' ? "bg-brand-green/10 text-brand-green" :
                                       t.type === 'withdrawal' ? "bg-red-50 text-red-500" :
                                       t.type === 'commission' ? "bg-brand-blue/10 text-brand-blue" :
                                       "bg-slate-100 text-slate-600"
                                     )}>
                                       {t.type}
                                     </span>
                                  </td>
                                  <td className="px-10 py-6">
                                     <span className={cn("font-mono font-black", t.type === 'withdrawal' ? "text-red-500" : "text-brand-green")}>
                                       {t.type === 'withdrawal' ? '-' : '+'}{formatCedis(t.amount)}
                                     </span>
                                  </td>
                                  <td className="px-10 py-6">
                                     <span className="text-[10px] font-black text-slate-400 uppercase tracking-widest">{new Date(t.created_at).toLocaleDateString()}</span>
                                  </td>
                               </tr>
                            ))}
                         </tbody>
                      </table>
                   </div>
                </div>
              </>
            )}
            {!revenueLoading && !revenueError && !revenueData && (
              <EmptyState title="No revenue data" description="Delivered orders will appear here." />
            )}
         </div>
       ) : activeTab === 'settings' ? (
         <DarkCard className="max-w-xl">
           <h3 className="text-lg font-bold text-white mb-4">Platform settings</h3>
           <form
             className="space-y-4"
             onSubmit={async (e) => {
               e.preventDefault();
               setSettingsSaving(true);
               try {
                 await axios.patch('/api/admin/settings', settings);
                 addNotification('Settings saved', 'success');
               } catch (err) {
                 addNotification(getApiError(err, 'Failed to save settings'), 'warning');
               } finally {
                 setSettingsSaving(false);
               }
             }}
           >
             <DarkInput label="Paystack public key" value={settings.paystack_public_key} onChange={(e) => setSettings({ ...settings, paystack_public_key: e.target.value })} placeholder="pk_test_..." />
             <DarkInput label="Paystack secret key" type="password" value={settings.paystack_secret_key} onChange={(e) => setSettings({ ...settings, paystack_secret_key: e.target.value })} placeholder="sk_test_... (leave blank to keep)" />
             <DarkInput label="Platform fee %" value={settings.platform_fee_percent} onChange={(e) => setSettings({ ...settings, platform_fee_percent: e.target.value })} />
             <DarkInput
               label="Package delivery price per km (₵)"
               type="number"
               step="0.01"
               min="0.01"
               value={settings.delivery_price_per_km}
               onChange={(e) => setSettings({ ...settings, delivery_price_per_km: e.target.value })}
               placeholder="4.00"
             />
             <p className="text-[10px] text-slate-500 font-bold">
               Package courier fees = distance (km) × this rate. Zone min/max caps still apply when set.
             </p>

             <div className="pt-4 border-t border-slate-700 space-y-3">
               <h4 className="text-sm font-bold text-white">Okada & Keke pricing</h4>
               <div className="grid grid-cols-2 gap-3">
                 <DarkInput
                   label="Okada ₵/km"
                   type="number"
                   step="0.01"
                   min="0.01"
                   value={settings.okada_price_per_km}
                   onChange={(e) => setSettings({ ...settings, okada_price_per_km: e.target.value })}
                 />
                 <DarkInput
                   label="Okada min fee (₵)"
                   type="number"
                   step="0.01"
                   min="0"
                   value={settings.okada_min_fee}
                   onChange={(e) => setSettings({ ...settings, okada_min_fee: e.target.value })}
                 />
                 <DarkInput
                   label="Keke ₵/km"
                   type="number"
                   step="0.01"
                   min="0.01"
                   value={settings.keke_price_per_km}
                   onChange={(e) => setSettings({ ...settings, keke_price_per_km: e.target.value })}
                 />
                 <DarkInput
                   label="Keke min fee (₵)"
                   type="number"
                   step="0.01"
                   min="0"
                   value={settings.keke_min_fee}
                   onChange={(e) => setSettings({ ...settings, keke_min_fee: e.target.value })}
                 />
               </div>
               <p className="text-[10px] text-slate-500 font-bold">
                 Motorcycle (Okada) and tricycle (Keke) rides use separate rates. Surge still applies during peak hours.
               </p>
             </div>

             <div className="pt-4 border-t border-slate-700 space-y-3">
               <div className="flex items-center justify-between gap-3">
                 <div>
                   <h4 className="text-sm font-bold text-white">Surge pricing</h4>
                   <p className="text-[10px] text-slate-500 font-bold">
                     Peak hours (Ghana time{settings.ghana_time ? ` · now ${settings.ghana_time}` : ''})
                     {settings.surge_active_now ? ' · surge active now' : ''}
                   </p>
                 </div>
                 <label className="flex items-center gap-2 text-[10px] font-black uppercase text-slate-400">
                   <input
                     type="checkbox"
                     checked={settings.surge_enabled}
                     onChange={(e) => setSettings({ ...settings, surge_enabled: e.target.checked })}
                     className="rounded border-slate-600"
                   />
                   On
                 </label>
               </div>
               <DarkInput
                 label="Surge multiplier (×)"
                 type="number"
                 step="0.05"
                 min="1"
                 value={settings.surge_multiplier}
                 onChange={(e) => setSettings({ ...settings, surge_multiplier: e.target.value })}
                 placeholder="1.50"
               />
               <div className="grid grid-cols-2 gap-3">
                 <DarkInput
                   label="Surge start (HH:MM)"
                   value={settings.surge_start_time}
                   onChange={(e) => setSettings({ ...settings, surge_start_time: e.target.value })}
                   placeholder="17:00"
                 />
                 <DarkInput
                   label="Surge end (HH:MM)"
                   value={settings.surge_end_time}
                   onChange={(e) => setSettings({ ...settings, surge_end_time: e.target.value })}
                   placeholder="21:00"
                 />
               </div>
               <p className="text-[10px] text-slate-500 font-bold">
                 Delivery fee is multiplied during this window. Overnight ranges supported (e.g. 22:00 → 06:00).
               </p>
             </div>

             <div className="pt-4 border-t border-slate-700">
               <h4 className="text-sm font-bold text-white mb-1">SMS / OTP (INTEK)</h4>
               <p className="text-[10px] text-slate-500 font-bold mb-3">
                 Customer signup and password reset codes. Config source: {settings.sms_config_source || 'unknown'}.
                 Use your own API key from inteksms.top and an approved Sender ID.
               </p>
               <DarkInput label="SMS API base URL" value={settings.sms_base_url} onChange={(e) => setSettings({ ...settings, sms_base_url: e.target.value })} />
               <DarkInput label="SMS API key" type="password" value={settings.sms_api_key} onChange={(e) => setSettings({ ...settings, sms_api_key: e.target.value })} placeholder="INTEK_… (leave blank to keep)" />
               <DarkInput label="Sender ID (brand name)" value={settings.sms_sender_id} onChange={(e) => setSettings({ ...settings, sms_sender_id: e.target.value })} placeholder="bytzee" />
               <div className="flex gap-2 mt-2">
                 <input
                   type="tel"
                   value={smsTestPhone}
                   onChange={(e) => setSmsTestPhone(e.target.value)}
                   placeholder="024XXXXXXX test phone"
                   className="flex-1 bg-slate-900 border border-slate-700 rounded-xl py-3 px-4 text-sm font-bold text-white"
                 />
                 <button
                   type="button"
                   disabled={smsTestLoading || !smsTestPhone}
                   onClick={async () => {
                     setSmsTestLoading(true);
                     try {
                       const res = await axios.post('/api/admin/sms-test', { phone: smsTestPhone });
                       addNotification(res.data?.message || 'Test SMS sent', 'success');
                     } catch (err) {
                       addNotification(getApiError(err, 'SMS test failed'), 'warning');
                     } finally {
                       setSmsTestLoading(false);
                     }
                   }}
                   className="px-4 py-3 bg-brand-green text-slate-950 rounded-xl text-[10px] font-black uppercase disabled:opacity-50"
                 >
                   {smsTestLoading ? '…' : 'Test SMS'}
                 </button>
               </div>
             </div>

             <DarkButton type="submit" disabled={settingsSaving} className="w-full">{settingsSaving ? 'Saving…' : 'Save settings'}</DarkButton>
           </form>
         </DarkCard>
       ) : activeTab === 'promotions' ? (
         <div className="space-y-6">
           <div className="flex justify-between items-center gap-4">
             <div>
               <h3 className="text-lg font-bold text-slate-800">Ride promotions</h3>
               <p className="text-[10px] text-slate-500 font-bold uppercase tracking-widest">
                 Customer discounts + rider bonuses (Uber/Yango style)
               </p>
             </div>
             <button
               type="button"
               onClick={() => setShowPromoForm(true)}
               className="px-4 py-2 bg-slate-900 text-white rounded-xl text-[10px] font-black uppercase"
             >
               New promo
             </button>
           </div>
           {showPromoForm && (
             <DarkCard className="max-w-2xl">
               <h4 className="text-white font-bold mb-4">Create promotion</h4>
               <form
                 className="space-y-3"
                 onSubmit={async (e) => {
                   e.preventDefault();
                   setPromoSaving(true);
                   try {
                     await axios.post('/api/admin/promotions', {
                       ...promoForm,
                       customer_discount_percent: Number(promoForm.customer_discount_percent) || 0,
                       customer_discount_fixed: Number(promoForm.customer_discount_fixed) || 0,
                       rider_bonus_amount: Number(promoForm.rider_bonus_amount) || 0,
                       max_redemptions: promoForm.max_redemptions ? Number(promoForm.max_redemptions) : null,
                       target_region: promoForm.target_region || null,
                       code: promoForm.code || null,
                     });
                     addNotification('Promotion created', 'success');
                     setShowPromoForm(false);
                     setPromoForm({
                       name: '',
                       code: '',
                       service_types: 'okada,keke,package',
                       customer_discount_percent: '0',
                       customer_discount_fixed: '0',
                       rider_bonus_amount: '0',
                       target_region: '',
                       enabled: true,
                       max_redemptions: '',
                     });
                     const res = await axios.get('/api/admin/promotions');
                     setPromotions(res.data || []);
                   } catch (err) {
                     addNotification(getApiError(err, 'Failed to create promotion'), 'warning');
                   } finally {
                     setPromoSaving(false);
                   }
                 }}
               >
                 <DarkInput label="Name" value={promoForm.name} onChange={(e) => setPromoForm({ ...promoForm, name: e.target.value })} />
                 <DarkInput label="Promo code (optional)" value={promoForm.code} onChange={(e) => setPromoForm({ ...promoForm, code: e.target.value.toUpperCase() })} />
                 <DarkInput label="Services (comma-separated)" value={promoForm.service_types} onChange={(e) => setPromoForm({ ...promoForm, service_types: e.target.value })} placeholder="okada,keke,package" />
                 <div className="grid grid-cols-3 gap-3">
                   <DarkInput label="Customer % off" type="number" value={promoForm.customer_discount_percent} onChange={(e) => setPromoForm({ ...promoForm, customer_discount_percent: e.target.value })} />
                   <DarkInput label="Customer ₵ off" type="number" value={promoForm.customer_discount_fixed} onChange={(e) => setPromoForm({ ...promoForm, customer_discount_fixed: e.target.value })} />
                   <DarkInput label="Rider bonus ₵" type="number" value={promoForm.rider_bonus_amount} onChange={(e) => setPromoForm({ ...promoForm, rider_bonus_amount: e.target.value })} />
                 </div>
                 <DarkInput label="Target region (blank = all)" value={promoForm.target_region} onChange={(e) => setPromoForm({ ...promoForm, target_region: e.target.value })} />
                 <DarkInput label="Max redemptions" type="number" value={promoForm.max_redemptions} onChange={(e) => setPromoForm({ ...promoForm, max_redemptions: e.target.value })} />
                 <div className="flex gap-2">
                   <DarkButton type="submit" disabled={promoSaving || !promoForm.name.trim()}>{promoSaving ? 'Saving…' : 'Create'}</DarkButton>
                   <button type="button" onClick={() => setShowPromoForm(false)} className="px-4 py-2 text-slate-400 text-xs font-bold uppercase">Cancel</button>
                 </div>
               </form>
             </DarkCard>
           )}
           {promoLoading ? (
             <LoadingIndicator />
           ) : promotions.length === 0 ? (
             <EmptyState title="No promotions" description="Create a promo to discount rides or pay rider bonuses." />
           ) : (
             <div className="grid gap-3">
               {promotions.map((p: any) => (
                 <div key={p.id} className="bg-white rounded-2xl border border-slate-100 p-5 flex flex-wrap justify-between gap-4 items-start">
                   <div>
                     <div className="flex items-center gap-2">
                       <span className="font-black text-slate-800">{p.name}</span>
                       {!p.enabled && <span className="text-[9px] font-black uppercase bg-slate-200 text-slate-600 px-2 py-0.5 rounded">Disabled</span>}
                     </div>
                     <p className="text-[11px] text-slate-500 font-bold mt-1">
                       {p.code ? `Code ${p.code} · ` : ''}{p.service_types}
                       {p.customer_discount_percent > 0 ? ` · ${p.customer_discount_percent}% off` : ''}
                       {p.customer_discount_fixed > 0 ? ` · ₵${p.customer_discount_fixed} off` : ''}
                       {p.rider_bonus_amount > 0 ? ` · Rider +₵${p.rider_bonus_amount}` : ''}
                       {p.target_region ? ` · ${p.target_region}` : ''}
                       {` · ${p.redemption_count}${p.max_redemptions ? `/${p.max_redemptions}` : ''} used`}
                     </p>
                   </div>
                   <div className="flex gap-2">
                     <button
                       type="button"
                       onClick={async () => {
                         try {
                           await axios.patch(`/api/admin/promotions/${p.id}`, { enabled: !p.enabled });
                           const res = await axios.get('/api/admin/promotions');
                           setPromotions(res.data || []);
                         } catch (err) {
                           addNotification(getApiError(err, 'Failed to update'), 'warning');
                         }
                       }}
                       className="px-3 py-2 bg-slate-100 rounded-lg text-[10px] font-black uppercase"
                     >
                       {p.enabled ? 'Disable' : 'Enable'}
                     </button>
                     <button
                       type="button"
                       onClick={async () => {
                         if (!confirm('Delete this promotion?')) return;
                         try {
                           await axios.delete(`/api/admin/promotions/${p.id}`);
                           setPromotions((prev) => prev.filter((x) => x.id !== p.id));
                         } catch (err) {
                           addNotification(getApiError(err, 'Failed to delete'), 'warning');
                         }
                       }}
                       className="px-3 py-2 bg-red-50 text-red-600 rounded-lg text-[10px] font-black uppercase"
                     >
                       Delete
                     </button>
                   </div>
                 </div>
               ))}
             </div>
           )}
         </div>
       ) : activeTab === 'zones' ? (
         <div className="space-y-6">
           {/* Zone Form Modal */}
           {showZoneForm && (
             <div className="bg-white rounded-[2rem] border border-slate-100 shadow-lg p-4 sm:p-8">
               <div className="flex justify-between items-center mb-6">
                 <h3 className="text-lg sm:text-xl font-black tracking-tighter text-slate-800 uppercase italic">{editingZone ? 'Edit Zone' : 'New Delivery Zone'}</h3>
                 <button onClick={() => { setShowZoneForm(false); setEditingZone(null); }} className="p-2 hover:bg-slate-100 rounded-xl transition-colors"><X size={20} /></button>
               </div>
               <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Zone Name</label>
                   <input type="text" placeholder="e.g. Accra Metro" value={zoneForm.name} onChange={e => setZoneForm({...zoneForm, name: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
                 </div>
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Region</label>
                   <select value={zoneForm.region} onChange={e => setZoneForm({...zoneForm, region: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all">
                     <option value="">Select Region</option>
                     {GHANA_REGIONS.map(r => <option key={r} value={r}>{r}</option>)}
                   </select>
                 </div>
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Base Price (?)</label>
                   <input type="number" step="0.01" placeholder="10.00" value={zoneForm.base_price} onChange={e => setZoneForm({...zoneForm, base_price: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
                 </div>
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Price per KM (?)</label>
                   <input type="number" step="0.01" placeholder="2.00" value={zoneForm.price_per_km} onChange={e => setZoneForm({...zoneForm, price_per_km: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
                 </div>
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Minimum Price (?)</label>
                   <input type="number" step="0.01" placeholder="5.00" value={zoneForm.min_price} onChange={e => setZoneForm({...zoneForm, min_price: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
                 </div>
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Maximum Price (?) <span className="text-slate-300">? optional</span></label>
                   <input type="number" step="0.01" placeholder="No limit" value={zoneForm.max_price} onChange={e => setZoneForm({...zoneForm, max_price: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
                 </div>
               </div>
               <div className="flex gap-3 mt-6">
                 <button onClick={handleSaveZone} disabled={!zoneForm.name || !zoneForm.region} className="flex-1 py-3 sm:py-4 bg-slate-900 text-white rounded-xl font-black uppercase tracking-widest text-[10px] sm:text-xs hover:scale-[1.02] active:scale-[0.98] transition-all disabled:opacity-50">
                   {editingZone ? 'Update Zone' : 'Create Zone'}
                 </button>
                 <button onClick={() => { setShowZoneForm(false); setEditingZone(null); }} className="px-6 py-3 sm:py-4 bg-slate-100 text-slate-500 rounded-xl font-black uppercase tracking-widest text-[10px] sm:text-xs hover:bg-slate-200 transition-all">Cancel</button>
               </div>
             </div>
           )}

           {/* Add Zone Button */}
           {!showZoneForm && (
             <button onClick={() => { setShowZoneForm(true); setEditingZone(null); setZoneForm({ name: '', region: '', base_price: '10', price_per_km: '2', min_price: '5', max_price: '' }); }} className="w-full py-4 bg-brand-blue/5 border-2 border-dashed border-brand-blue/20 rounded-2xl text-brand-blue font-black uppercase tracking-widest text-xs hover:bg-brand-blue/10 hover:border-brand-blue/40 transition-all flex items-center justify-center gap-2">
               <MapPin size={16} /> Add Delivery Zone
             </button>
           )}

           {/* Zones List */}
           {zones.length === 0 && !showZoneForm ? (
             <div className="text-center py-20 bg-white rounded-[3rem] border border-slate-200 border-dashed">
               <MapPin className="mx-auto text-slate-200 mb-4" size={48} />
               <p className="text-slate-400 font-black text-lg italic uppercase tracking-tighter">No delivery zones yet</p>
               <p className="text-slate-300 text-xs font-bold mt-2">Create zones to set region-based delivery pricing</p>
             </div>
           ) : (
             <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
               {zones.map(zone => (
                 <div key={zone.id} className={cn("bg-white rounded-[2rem] border shadow-sm p-5 sm:p-6 flex flex-col justify-between transition-all hover:shadow-md", zone.is_active ? "border-slate-100" : "border-red-100 opacity-60")}>
                   <div>
                     <div className="flex justify-between items-start mb-3">
                       <div>
                         <h4 className="font-black text-lg tracking-tight text-slate-800">{zone.name}</h4>
                         <span className="text-[10px] font-black uppercase tracking-widest text-brand-blue bg-brand-blue/10 px-2 py-0.5 rounded-md">{zone.region}</span>
                       </div>
                       <button onClick={() => handleToggleZone(zone)} className={cn("px-2.5 py-1 rounded-lg text-[8px] font-black uppercase tracking-widest transition-all", zone.is_active ? "bg-brand-green/10 text-brand-green" : "bg-red-50 text-red-500")}>
                         {zone.is_active ? 'Active' : 'Off'}
                       </button>
                     </div>
                     <div className="grid grid-cols-2 gap-3 mt-4">
                       <div className="bg-slate-50 rounded-xl p-3">
                         <span className="text-[8px] font-black uppercase tracking-widest text-slate-400 block">Base</span>
                         <span className="font-mono font-black text-brand-blue text-sm">{formatCedis(zone.base_price)}</span>
                       </div>
                       <div className="bg-slate-50 rounded-xl p-3">
                         <span className="text-[8px] font-black uppercase tracking-widest text-slate-400 block">Per KM</span>
                         <span className="font-mono font-black text-brand-blue text-sm">{formatCedis(zone.price_per_km)}</span>
                       </div>
                       <div className="bg-slate-50 rounded-xl p-3">
                         <span className="text-[8px] font-black uppercase tracking-widest text-slate-400 block">Min</span>
                         <span className="font-mono font-black text-slate-600 text-sm">{formatCedis(zone.min_price)}</span>
                       </div>
                       <div className="bg-slate-50 rounded-xl p-3">
                         <span className="text-[8px] font-black uppercase tracking-widest text-slate-400 block">Max</span>
                         <span className="font-mono font-black text-slate-600 text-sm">{zone.max_price ? formatCedis(zone.max_price) : 'No limit'}</span>
                       </div>
                     </div>
                   </div>
                   <div className="flex gap-2 mt-4 pt-4 border-t border-slate-100">
                     <button onClick={() => { setEditingZone(zone); setZoneForm({ name: zone.name, region: zone.region, base_price: String(zone.base_price), price_per_km: String(zone.price_per_km), min_price: String(zone.min_price), max_price: zone.max_price ? String(zone.max_price) : '' }); setShowZoneForm(true); }} className="flex-1 py-2.5 bg-slate-100 text-slate-600 rounded-xl text-[10px] font-black uppercase tracking-widest hover:bg-slate-200 transition-all flex items-center justify-center gap-1.5">
                       <Edit3 size={12} /> Edit
                     </button>
                     <button onClick={() => setZoneToDelete(zone)} className="px-4 py-2.5 bg-red-50 text-red-500 rounded-xl text-[10px] font-black uppercase tracking-widest hover:bg-red-100 transition-all flex items-center justify-center gap-1.5">
                       <X size={12} /> Delete
                     </button>
                   </div>
                 </div>
               ))}
               <ConfirmationModal 
                 isOpen={!!zoneToDelete}
                 onClose={() => setZoneToDelete(null)}
                 onConfirm={() => zoneToDelete && handleDeleteZone(zoneToDelete.id)}
                 title="Delete Zone"
                 message={`Are you sure you want to delete the ${zoneToDelete?.name} zone? This action cannot be undone.`}
                 confirmLabel="Delete"
                 type="danger"
               />
             </div>
           )}
         </div>
       ) : null}
    </div>
  );
}

function TrackingMap({ riderLocation, pickupLocation, destination, orderStatus }: { riderLocation: { lat: number, lng: number } | null, pickupLocation: { lat: number, lng: number }, destination: { lat: number, lng: number }, orderStatus: string }) {
  const map = useMap();
  const mapsLib = useMapsLibrary('core');
  
  useEffect(() => {
    if (map && mapsLib) {
      const bounds = new mapsLib.LatLngBounds();
      if (riderLocation) bounds.extend(riderLocation);
      bounds.extend(pickupLocation);
      bounds.extend(destination);
      map.fitBounds(bounds, 80);
    }
  }, [map, mapsLib, riderLocation, pickupLocation, destination]);

  if (!mapsLib) return <div className="w-full h-full bg-slate-100 animate-pulse flex items-center justify-center text-[10px] font-black uppercase tracking-widest text-slate-400">Loading Map Engine...</div>;

  return (
    <>
      <Map
        defaultCenter={pickupLocation}
        defaultZoom={15}
        defaultTilt={45}
        gestureHandling={'greedy'}
        disableDefaultUI={true}
        className="w-full h-full"
        styles={CLEAN_MAP_STYLE}
      >
        {/* Rider Marker - Motorbike Icon */}
        {riderLocation && (
          <Marker 
            position={riderLocation} 
            title="Motor Rider" 
            icon={{ 
              url: '/rider-icon.png', 
              scaledSize: new mapsLib.Size(40, 40),
              anchor: new mapsLib.Point(20, 20)
            }} 
          />
        )}
        
        {/* Pickup Marker - Store Icon */}
        <Marker 
          position={pickupLocation} 
          title="Vendor" 
          icon={{
            url: 'https://cdn-icons-png.flaticon.com/512/606/606363.png',
            scaledSize: new mapsLib.Size(32, 32)
          }}
        />
        
        {/* Destination Marker - Home/Pin Icon */}
        <Marker 
          position={destination} 
          title="Customer" 
          icon={{
            url: 'https://cdn-icons-png.flaticon.com/512/1216/1216844.png',
            scaledSize: new mapsLib.Size(32, 32)
          }}
        />

        {/* Draw route if possible */}
        {riderLocation && (
          <Directions 
            origin={riderLocation} 
            destination={orderStatus === 'picked_up' ? destination : pickupLocation} 
            onETAUpdate={(val) => {
              const el = document.getElementById('eta-display');
              if (el) el.innerText = val;
            }}
          />
        )}
      </Map>
      
      <div className="absolute bottom-4 left-4 bg-slate-900/90 text-white px-4 py-2 rounded-xl border border-white/10 shadow-xl flex items-center gap-3">
         <div className="w-2 h-2 bg-brand-green rounded-full animate-ping" />
         <div className="flex flex-col">
            <span className="text-[8px] font-black uppercase tracking-widest text-white/50">Arrival Estimate</span>
            <span id="eta-display" className="text-xs font-black">Calculating...</span>
         </div>
      </div>
    </>
  );
}

function StatBox({ label, value, color }: { label: string, value: string | number, color: 'blue' | 'green' }) {
  return (
    <div className={cn("p-6 rounded-[2rem] border", color === 'blue' ? "bg-brand-blue/5 border-brand-blue/10" : "bg-brand-green/5 border-brand-green/10")}>
       <p className="text-[10px] font-black uppercase tracking-widest text-slate-400 mb-1">{label}</p>
       <p className={cn("text-2xl font-black tracking-tighter italic", color === 'blue' ? "text-brand-blue" : "text-brand-green")}>{value}</p>
    </div>
  );
}
