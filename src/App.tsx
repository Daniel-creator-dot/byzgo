import React, { useState, useEffect, useRef, useCallback } from 'react';
import { BrowserRouter, Routes, Route, useLocation, useNavigate } from 'react-router-dom';
import { socket } from './lib/socket';
import { Role, Order, OrderStatus } from './types.ts';
import { Layout, User as UserIcon, Store, Bike, Shield, ShoppingBag, MapPin, CreditCard, ChevronRight, CheckCircle2, Clock, Send, Navigation, Lock, Mail, Eye, EyeOff, LogOut, Package, Phone, Edit3, Save, X, Star, Home, Users, BarChart3, AlertCircle, AlertTriangle, Check, LocateFixed } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import axios from 'axios';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { Map, Marker, useMap, useMapsLibrary } from '@vis.gl/react-google-maps';
import { MapsProvider } from './components/MapsProvider';
import { Modal, ConfirmationModal, LoadingIndicator } from './components/UI';
import { auth, googleProvider } from './lib/firebase';
import { signInWithPopup, signInWithRedirect, getRedirectResult } from 'firebase/auth';
import { supabase } from './lib/supabase';
import {
  subscribeRiderPush,
  unsubscribeRiderPush,
  onServiceWorkerRideMessage,
} from './lib/pushNotifications';
import { needsDeviceSetup } from './lib/deviceSetup';
import { InstallPermissionsOnboarding } from './components/InstallPermissionsOnboarding';
import { RiderApp } from './components/rider/RiderApp';
import { GHANA_REGIONS } from './lib/constants';
import {
  GHANA_CENTER,
  detectCurrentLocation,
  ghanaPlacesAutocompleteOptions,
  reverseGeocodeGhana,
} from './lib/ghanaLocation';

// Helper for Tailwind classes
function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// Helper to calculate distance between two coordinates in km (Haversine formula)
function calculateDistance(lat1: number, lon1: number, lat2: number, lon2: number) {
  if (!lat1 || !lon1 || !lat2 || !lon2) return 0;
  const R = 6371; // km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
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

// Paystack Window augmentation
declare global {
  interface Window {
    PaystackPop: any;
  }
}

// Types for Auth
interface AuthUser {
  id: string;
  name: string;
  email: string;
  role: Role;
  balance: number;
  status?: string;
  region?: string;
  lat?: number;
  lng?: number;
  phone?: string;
  address?: string;
  cover_image?: string;
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
  const [activeTab, setActiveTab] = useState<string>('menu');
  const [zones, setZones] = useState<any[]>([]);
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
    if (!vendor || !vendor.lat || !vendor.lng || !user.lat || !user.lng) return 10;
    const distance = calculateDistance(user.lat, user.lng, vendor.lat, vendor.lng);
    const zone = zones.find(z => z.region === user.region && z.is_active);
    if (!zone) return 10;
    const fee = Number(zone.base_price) + (distance * Number(zone.price_per_km));
    const min = Number(zone.min_price);
    const max = zone.max_price ? Number(zone.max_price) : Infinity;
    return Math.max(min, Math.min(fee, max));
  };
  const deliveryFee = calculateDeliveryFee();
  const total = subtotal + deliveryFee;
  const [riderLocations, setRiderLocations] = useState<{ [key: string]: { lat: number, lng: number } }>({});
  const [notifications, setNotifications] = useState<{ id: string, message: string, type: 'info' | 'success' | 'warning' }[]>([]);
  const [incomingRideOffer, setIncomingRideOffer] = useState<Order | null>(null);
  const [paystackKey, setPaystackKey] = useState<string>('');
  const [refreshing, setRefreshing] = useState(false);
  const [showDeviceSetup, setShowDeviceSetup] = useState(false);
  const userRef = useRef(user);
  useEffect(() => { userRef.current = user; }, [user]);

  const isOfferableToRider = (order: Order) =>
    order.status === 'ready' && !order.rider_id && !(order as any).riderId;

  const triggerIncomingRideCall = useCallback((order: Order) => {
    const u = userRef.current;
    if (!u || u.role !== 'rider' || u.status !== 'active' || !isOfferableToRider(order)) return;
    setIncomingRideOffer(prev => (prev?.id === order.id ? prev : order));
    setActiveTab('dashboard');
    if (navigator.vibrate) navigator.vibrate([400, 200, 400, 200, 400]);
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

      // Conditional promises based on role
      const ordersPromise = axios.get('/api/orders'); // Everyone needs orders
      
      const productsPromise = (role === 'customer' || role === 'vendor') 
        ? axios.get('/api/products') 
        : Promise.resolve({ data: [] });

      const vendorsPromise = (role === 'customer' || role === 'rider') 
        ? axios.get('/api/vendors', { params: { region } }) 
        : Promise.resolve({ data: [] });

      const zonesPromise = (role === 'customer' || role === 'rider' || role === 'admin') 
        ? axios.get('/api/delivery-zones').catch(() => ({ data: [] })) 
        : Promise.resolve({ data: [] });

      const [profileRes, ordersRes, productsRes, vendorsRes, configRes, zonesRes] = await Promise.all([
        walletPromise,
        ordersPromise,
        productsPromise,
        vendorsPromise,
        paystackPromise,
        zonesPromise
      ]);

      setPaystackKey(configRes.data.publicKey);
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
    if (showDeviceSetup || user?.role !== 'rider' || user.status !== 'active' || !token) return;
    if (Notification.permission === 'granted') {
      subscribeRiderPush().catch(err => console.warn('Push subscribe failed', err));
    }
  }, [user?.id, user?.role, user?.status, token, showDeviceSetup]);

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

  // Initialize Axios
  axios.defaults.baseURL = import.meta.env.VITE_API_URL || '';
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

        // 2. Check Firebase Redirect result
        const result = await getRedirectResult(auth);
        if (result) {
          const idToken = await result.user.getIdToken();
          const savedRole = localStorage.getItem('google_login_role') || 'customer';
          const res = await axios.post('/api/auth/google', {
            credential: idToken,
            role: savedRole
          });
          localStorage.removeItem('google_login_role');
          
          const expected = getExpectedRole();
          if (res.data.user.role !== expected) {
            console.warn(`Role mismatch: got ${res.data.user.role}, expected ${expected}`);
            return;
          }
          setUser(res.data.user);
          setToken(res.data.token);
          localStorage.setItem('user', JSON.stringify(res.data.user));
        }
      } catch (err) {
        console.error('Redirect result failed', err);
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
      setLoading(false);
      return;
    }

    const init = async () => {
      try {
        await refreshData();
        const storedUser = JSON.parse(localStorage.getItem('user') || '{}');
        // Set default tab based on role
        if (storedUser.role === 'vendor') setActiveTab('orders');
        else if (storedUser.role === 'rider') setActiveTab('dashboard');
        else if (storedUser.role === 'admin') setActiveTab('orders');
        else setActiveTab('menu');

        socket.connect();
        socket.emit('join', storedUser.id);
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

    socket.on('ride:incoming', (order: Order) => {
      setOrders(prev => {
        const exists = prev.some(o => o.id === order.id);
        return exists ? prev.map(o => (o.id === order.id ? order : o)) : [order, ...prev];
      });
      const u = userRef.current;
      if (u?.role === 'rider' && u.status === 'active' && isOfferableToRider(order)) {
        triggerIncomingRideCall(order);
      }
    });

    socket.on('order:new', (order: Order) => {
      setOrders(prev => [order, ...prev]);
      const u = userRef.current;
      if (u?.role === 'vendor' && order.vendor_id === u.id) {
        addNotification('New order received!', 'success');
      }
    });

    socket.on('order:updated', (updatedOrder: Order) => {
      setOrders(prev => prev.map(o => o.id === updatedOrder.id ? updatedOrder : o));
      const u = userRef.current;
      if (u?.role === 'customer' && updatedOrder.status === 'picked_up' && updatedOrder.customer_id === u.id) {
        addNotification('Your order has been picked up!', 'info');
      }
      if (u?.role === 'customer' && updatedOrder.status === 'delivered' && updatedOrder.customer_id === u.id) {
        addNotification('Your order has been delivered!', 'success');
      }
      setIncomingRideOffer(prev =>
        prev?.id === updatedOrder.id && updatedOrder.rider_id ? null : prev
      );
    });

    socket.on('location:updated', ({ riderId, lat, lng }) => {
      setRiderLocations(prev => {
        if (!prev[riderId]) {
          addNotification('Rider is now online and tracking!', 'success');
        }
        return { ...prev, [riderId]: { lat, lng } };
      });
    });

    socket.on('wallet:updated', (data: { balance: number }) => {
      setUser(prev => prev ? { ...prev, balance: data.balance } : null);
    });

    return () => {
      socket.off('ride:incoming');
      socket.off('order:new');
      socket.off('order:updated');
      socket.off('wallet:updated');
      socket.disconnect();
    };
  }, [token]);

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
      const msg = (err as { response?: { data?: { message?: string } } })?.response?.data?.message;
      addNotification(msg || 'Could not update order. Try again.', 'warning');
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
            setUser(updatedUser as AuthUser);
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
            pendingApproval={user.status === 'pending'}
          />
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
          setUser(updatedUser as AuthUser);
          setToken(newToken);
          localStorage.setItem('user', JSON.stringify(updatedUser));
          localStorage.setItem('token', newToken);
        }}
      />
      <div className="min-h-screen bg-slate-50">
        <nav className="bg-white border-b border-slate-200 px-4 sm:px-6 py-4 flex items-center justify-between sticky top-0 z-50 shadow-sm">
          <div className="flex items-center gap-2 cursor-pointer shrink-0">
            <div className="text-brand-blue">
              <MotorIcon size={28} className="transform -scale-x-100" />
            </div>
            <span className="font-black text-xl sm:text-2xl tracking-tighter">
              <span className="text-brand-blue">bytz</span>
              <span className="text-brand-green">go</span>
            </span>
          </div>
          <div className="flex items-center gap-2 sm:gap-6">
            <div className="flex items-center gap-2 bg-slate-50 px-3 py-1.5 sm:px-4 sm:py-2 rounded-xl sm:rounded-2xl border border-slate-100 shadow-inner">
              <span className="text-[8px] sm:text-[10px] font-black uppercase tracking-widest text-slate-400 hidden xs:block">Balance</span>
              <span className="font-mono font-black text-xs sm:text-base text-brand-blue">₵{Number(user.balance || 0).toFixed(2)}</span>
            </div>
            <div className="flex items-center gap-1 sm:gap-3">
              <div className="text-right hidden md:block">
                <p className="text-xs font-black text-slate-800 leading-none">{user.name}</p>
                <p className="text-[10px] font-medium text-slate-400 mt-1 uppercase tracking-widest">{user.email}</p>
              </div>
              <div className="w-9 h-9 sm:w-10 sm:h-10 rounded-xl sm:rounded-2xl bg-slate-100 flex items-center justify-center border border-slate-200 shadow-inner cursor-pointer hover:bg-brand-blue/10 transition-all" onClick={() => {
                const el = document.getElementById('profile-toggle');
                if (el) el.click();
              }}>
                <UserIcon size={16} sm:size={18} className="text-slate-500" />
              </div>
              <button 
                onClick={() => setIsLogoutModalOpen(true)}
                className="p-2 hover:bg-red-50 text-slate-400 hover:text-red-500 rounded-xl transition-all"
                title="Logout"
              >
                <LogOut size={18} sm:size={20} />
              </button>
            </div>
          </div>
        </nav>

        <ConfirmationModal 
          isOpen={isLogoutModalOpen}
          onClose={() => setIsLogoutModalOpen(false)}
          onConfirm={handleLogout}
          title="Sign Out"
          message="Are you sure you want to log out of BytzGo? You'll need to sign in again to access your account."
          confirmLabel="Sign Out"
          type="danger"
        />

        <PullToRefresh onRefresh={refreshData} refreshing={refreshing}>
          <main className="p-4 sm:p-8 max-w-7xl mx-auto pb-24">
            <AnimatePresence>
              <div className="fixed top-4 right-4 z-[9999] space-y-2 pointer-events-none">
                {notifications.map(n => (
                  <motion.div 
                    key={n.id} 
                    initial={{ opacity: 0, x: 50, scale: 0.9 }} 
                    animate={{ opacity: 1, x: 0, scale: 1 }} 
                    exit={{ opacity: 0, x: 50, scale: 0.9 }}
                    className={cn(
                      "px-6 py-4 rounded-2xl shadow-2xl border flex items-center gap-3 pointer-events-auto",
                      n.type === 'success' ? "bg-brand-green text-white border-brand-green/20" : 
                      n.type === 'warning' ? "bg-red-500 text-white border-red-500/20" : 
                      "bg-slate-900 text-white border-slate-700"
                    )}
                  >
                    <span className="text-sm font-black uppercase tracking-widest">{n.message}</span>
                    <button onClick={() => setNotifications(prev => prev.filter(nn => nn.id !== n.id))} className="ml-2 hover:opacity-50 transition-opacity">
                      <X size={14} />
                    </button>
                  </motion.div>
                ))}
              </div>
            </AnimatePresence>
  
            {user && user.status === 'pending' && (user.role === 'vendor' || user.role === 'rider') && (
              <motion.div 
                initial={{ opacity: 0, y: -20 }} 
                animate={{ opacity: 1, y: 0 }} 
                className="mb-8 p-4 sm:p-6 bg-amber-50 border border-amber-200 rounded-[1.5rem] sm:rounded-[2.5rem] flex items-center gap-4 sm:gap-6 shadow-sm shadow-amber-500/5"
              >
                <div className="w-10 h-10 sm:w-12 sm:h-12 bg-amber-500 rounded-xl sm:rounded-2xl flex items-center justify-center text-white shrink-0 shadow-lg shadow-amber-500/20">
                  <AlertCircle size={20} className="sm:w-6 sm:h-6" />
                </div>
                <div>
                  <h4 className="text-sm sm:text-base font-black tracking-tight text-amber-900 uppercase italic">Account Pending Approval</h4>
                  <p className="text-[10px] sm:text-xs font-bold text-amber-700/80 uppercase tracking-widest leading-relaxed">Our team is reviewing your details. You will be notified once you are cleared to start operations.</p>
                </div>
              </motion.div>
            )}

            <AnimatePresence mode="wait">
              {user.role === 'customer' && <CustomerView 
                user={user} orders={orders} products={products} vendors={vendors} 
                riderLocations={riderLocations} paystackKey={paystackKey} setPaystackKey={setPaystackKey} 
                addNotification={addNotification} 
                cart={cart} setCart={setCart} isCartOpen={isCartOpen} setIsCartOpen={setIsCartOpen}
                activeTab={activeTab} setActiveTab={setActiveTab}
                onPlaceOrder={async (items, total, vendorId, extra = {}) => {
                  try {
                    await axios.post('/api/orders', { 
                      items, 
                      total, 
                      vendorId,
                      address: extra.address || user.address || 'East Legon, Accra', 
                      lat: extra.lat || user.lat,
                      lng: extra.lng || user.lng,
                      ...extra
                    });
                    await refreshData();
                  } catch (err) {
                    console.error('Order failed', err);
                    addNotification('Failed to place order', 'warning');
                  }
                }} 
                zones={zones}
                subtotal={subtotal}
                deliveryFee={deliveryFee}
                total={total}
              />}
              {user.role === 'vendor' && <VendorView user={user} orders={orders} products={products} riderLocations={riderLocations} onUpdateStatus={updateOrderStatus} addNotification={addNotification} onAddProduct={(p) => setProducts(prev => {
                const exists = prev.find(item => item.id === p.id);
                if (exists) return prev.map(item => item.id === p.id ? p : item);
                return [...prev, p];
              })} onDeleteProduct={async (id) => {
                try {
                  await axios.delete(`/api/products/${id}`);
                  setProducts(prev => prev.filter(p => p.id !== id));
                } catch (err) {
                  console.error('Delete product failed', err);
                }
              }} activeTab={activeTab} setActiveTab={setActiveTab} />}
              {user.role === 'admin' && <AdminView user={user} orders={orders} addNotification={addNotification} activeTab={activeTab} setActiveTab={setActiveTab} />}
            </AnimatePresence>
          </main>
        </PullToRefresh>

        {/* Global Mobile Bottom Navigation - Moved outside PullToRefresh to fix "middle of screen" issue */}
        {!loading && user && (
          <nav className="fixed bottom-0 left-0 right-0 bg-white/80 backdrop-blur-xl border-t border-slate-100 flex sm:hidden z-[100] px-6 py-3 justify-around shadow-[0_-10px_30px_rgba(0,0,0,0.05)]">
            {user.role === 'customer' && (
              <>
                <button onClick={() => setActiveTab('menu')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'menu' ? "text-brand-blue" : "text-slate-400")}>
                  <Home size={20} className={activeTab === 'menu' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Home</span>
                </button>
                <button onClick={() => setActiveTab('tracking')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'tracking' ? "text-brand-blue" : "text-slate-400")}>
                  <Navigation size={20} className={activeTab === 'tracking' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Orders</span>
                </button>
                <button onClick={() => setActiveTab('courier')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'courier' ? "text-brand-blue" : "text-slate-400")}>
                  <Package size={20} className={activeTab === 'courier' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Courier</span>
                </button>
              </>
            )}
            {user.role === 'vendor' && (
              <>
                <button onClick={() => setActiveTab('orders')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'orders' ? "text-brand-blue" : "text-slate-400")}>
                  <ShoppingBag size={20} className={activeTab === 'orders' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Orders</span>
                </button>
                <button onClick={() => setActiveTab('products')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'products' ? "text-brand-blue" : "text-slate-400")}>
                  <Layout size={20} className={activeTab === 'products' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Menu</span>
                </button>
                <button onClick={() => setActiveTab('wallet')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'wallet' ? "text-brand-blue" : "text-slate-400")}>
                  <CreditCard size={20} className={activeTab === 'wallet' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Wallet</span>
                </button>
              </>
            )}
            {user.role === 'admin' && (
              <>
                <button onClick={() => setActiveTab('orders')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'orders' ? "text-brand-blue" : "text-slate-400")}>
                  <ShoppingBag size={20} className={activeTab === 'orders' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Orders</span>
                </button>
                <button onClick={() => setActiveTab('users')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'users' ? "text-brand-blue" : "text-slate-400")}>
                  <Users size={20} className={activeTab === 'users' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Users</span>
                </button>
                <button onClick={() => setActiveTab('zones')} className={cn("flex flex-col items-center gap-1 transition-all", activeTab === 'zones' ? "text-brand-blue" : "text-slate-400")}>
                  <MapPin size={20} className={activeTab === 'zones' ? "fill-brand-blue/10" : ""} />
                  <span className="text-[8px] font-black uppercase tracking-widest">Zones</span>
                </button>
              </>
            )}
          </nav>
        )}

        {/* Global Floating Elements for Customer */}
        {user?.role === 'customer' && (
          <AnimatePresence>
            {/* Cart Floating Button */}
            {activeTab !== 'profile' && (
              <button 
                onClick={() => setIsCartOpen(true)}
                className="fixed bottom-28 sm:bottom-8 right-4 sm:right-8 z-[60] bg-brand-blue text-white p-4 rounded-3xl shadow-2xl shadow-brand-blue/40 flex items-center gap-3 hover:scale-110 active:scale-95 transition-all"
              >
                <div className="relative">
                  <ShoppingBag size={24} />
                  {cart.length > 0 && (
                    <span className="absolute -top-2 -right-2 bg-brand-green text-white text-[10px] font-black w-5 h-5 rounded-full flex items-center justify-center border-2 border-brand-blue">
                      {cart.reduce((a, b) => a + b.quantity, 0)}
                    </span>
                  )}
                </div>
                <span className="font-black text-sm pr-2">GH₵{subtotal.toFixed(2)}</span>
              </button>
            )}

            {/* Track Order Floating Button */}
            {orders.filter(o => o.customer_id === user.id && o.status !== 'delivered' && o.status !== 'cancelled').length > 0 && activeTab !== 'tracking' && (
              <button
                onClick={() => setActiveTab('tracking')}
                className="fixed bottom-28 sm:bottom-8 left-4 sm:left-8 z-[60] bg-slate-900 text-white px-5 sm:px-6 py-3 sm:py-4 rounded-3xl shadow-2xl flex items-center gap-3 hover:scale-105 active:scale-95 transition-all group"
              >
                <div className="relative">
                  <Navigation size={20} className="animate-pulse" />
                  <span className="absolute -top-1 -right-1 w-3 h-3 bg-brand-green rounded-full border-2 border-slate-900 animate-ping" />
                  <span className="absolute -top-1 -right-1 w-3 h-3 bg-brand-green rounded-full border-2 border-slate-900" />
                </div>
                <span className="font-black text-xs uppercase tracking-widest">Track · {orders.filter(o => o.customer_id === user.id && o.status !== 'delivered' && o.status !== 'cancelled').length}</span>
              </button>
            )}

            {/* Global Cart Modal */}
            {isCartOpen && (
              <>
                <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => setIsCartOpen(false)} className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-[200]" />
                <motion.div 
                  initial={{ y: '100%' }} 
                  animate={{ y: 0 }} 
                  exit={{ y: '100%' }} 
                  transition={{ type: 'spring', damping: 25, stiffness: 200 }}
                  className="fixed bottom-0 left-0 right-0 sm:inset-y-0 sm:right-0 sm:left-auto w-full sm:max-w-md h-auto sm:h-full max-h-[95vh] sm:max-h-none bg-white z-[210] shadow-2xl p-6 sm:p-8 pb-32 sm:pb-8 flex flex-col rounded-t-[3rem] sm:rounded-none"
                >
                  <div className="w-12 h-1.5 bg-slate-100 rounded-full mx-auto mb-6 sm:hidden" />
                  <div className="flex justify-between items-center mb-8">
                    <h3 className="text-3xl font-black italic tracking-tighter">Your Bytz</h3>
                    <button onClick={() => setIsCartOpen(false)} className="p-2 hover:bg-slate-100 rounded-xl transition-colors">
                      <X size={20} />
                    </button>
                  </div>

                  <div className="flex-1 overflow-y-auto space-y-4 pr-2">
                    {cart.length === 0 ? (
                      <div className="text-center py-20">
                        <ShoppingBag size={48} className="mx-auto text-slate-200 mb-4" />
                        <p className="text-slate-400 font-bold italic uppercase tracking-tighter">Empty stomach, empty cart.</p>
                      </div>
                    ) : (
                      cart.map(item => (
                        <div key={item.id} className="bg-slate-50 p-4 rounded-2xl flex items-center justify-between border border-slate-100">
                          <div className="flex items-center gap-4">
                            <div className="w-12 h-12 bg-white rounded-xl shadow-sm flex items-center justify-center text-brand-blue font-black">
                              {item.name[0]}
                            </div>
                            <div>
                              <h4 className="font-black text-sm">{item.name}</h4>
                              <p className="text-xs font-mono text-brand-blue">GH₵{Number(item.price).toFixed(2)}</p>
                            </div>
                          </div>
                          <div className="flex items-center gap-3">
                            <button onClick={() => {
                              const newCart = cart.map(i => i.id === item.id ? { ...i, quantity: Math.max(0, i.quantity - 1) } : i).filter(i => i.quantity > 0);
                              setCart(newCart);
                            }} className="w-8 h-8 rounded-lg bg-white border border-slate-200 flex items-center justify-center font-black">-</button>
                            <span className="font-mono font-black text-sm">{item.quantity}</span>
                            <button onClick={() => {
                              const newCart = cart.map(i => i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i);
                              setCart(newCart);
                            }} className="w-8 h-8 rounded-lg bg-white border border-slate-200 flex items-center justify-center font-black">+</button>
                          </div>
                        </div>
                      ))
                    )}
                  </div>

                    {cart.length > 0 && (
                      <div className="mt-8 pt-8 border-t border-slate-100 space-y-4">
                        <div className="flex justify-between items-center text-slate-500">
                          <span className="text-[10px] font-black uppercase tracking-widest">Subtotal</span>
                          <span className="font-mono font-bold">GH₵{subtotal.toFixed(2)}</span>
                        </div>
                        <div className="flex justify-between items-center text-brand-green bg-brand-green/5 p-3 rounded-2xl border border-brand-green/10">
                          <span className="text-[10px] font-black uppercase tracking-widest">Delivery Fee (Rider Payout)</span>
                          <span className="font-mono font-bold">GH₵{deliveryFee.toFixed(2)}</span>
                        </div>
                        <div className="flex justify-between items-end pt-2">
                          <span className="text-slate-400 font-black uppercase tracking-widest text-xs">Total Bill</span>
                          <span className="text-3xl font-black tracking-tighter text-brand-blue italic">GH₵{total.toFixed(2)}</span>
                        </div>
                      
                      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
                        <button onClick={async () => {
                          // Handle Pay logic moved to App or duplicated
                          let currentKey = paystackKey;
                          if (!currentKey) {
                            try {
                              const res = await axios.get('/api/config/paystack');
                              currentKey = res.data.publicKey;
                              setPaystackKey(currentKey);
                            } catch (e) {}
                          }
                          if (!currentKey) return addNotification('Payment system offline', 'warning');
                          if (!(window as any).PaystackPop) return addNotification('Paystack not loaded', 'warning');

                          const handler = (window as any).PaystackPop.setup({
                            key: currentKey,
                            email: user.email,
                            amount: Math.round(total * 100),
                            currency: 'GHS',
                            callback: (response: any) => {
                              axios.post('/api/orders', { 
                                items: cart.map(item => ({ id: item.id, name: item.name, quantity: item.quantity, price: item.price })), 
                                total: total, 
                                delivery_fee: deliveryFee,
                                vendorId: cart[0].vendor_id, // Assuming same vendor for all items
                                payment_reference: response.reference, 
                                payment_method: 'paystack' 
                              }).then(() => {
                                setCart([]);
                                setIsCartOpen(false);
                                setActiveTab('tracking');
                                refreshData();
                              });
                            }
                          });
                          handler.openIframe();
                        }} className="py-4 bg-slate-900 text-white rounded-2xl font-black uppercase tracking-widest text-[10px] hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center justify-center gap-2">
                          <CreditCard size={14} /> Card/Momo
                        </button>
                        <button 
                          disabled={user.balance < total}
                          onClick={async () => {
                            await axios.post('/api/orders', { 
                              items: cart.map(item => ({ id: item.id, name: item.name, quantity: item.quantity, price: item.price })), 
                              total: total, 
                              delivery_fee: deliveryFee,
                              vendorId: cart[0].vendor_id,
                              payment_method: 'wallet' 
                            });
                            setCart([]);
                            setIsCartOpen(false);
                            setActiveTab('tracking');
                            refreshData();
                          }}
                          className="py-4 bg-brand-blue text-white rounded-2xl font-black uppercase tracking-widest text-[10px] hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center justify-center gap-2 disabled:opacity-30"
                        >
                          <ShoppingBag size={14} /> Wallet
                        </button>
                        <button 
                          onClick={async () => {
                            await axios.post('/api/orders', { 
                              items: cart.map(item => ({ id: item.id, name: item.name, quantity: item.quantity, price: item.price })), 
                              total: total, 
                              delivery_fee: deliveryFee,
                              vendorId: cart[0].vendor_id,
                              payment_method: 'pay_on_delivery' 
                            });
                            setCart([]);
                            setIsCartOpen(false);
                            setActiveTab('tracking');
                            refreshData();
                          }}
                          className="py-4 bg-brand-green text-white rounded-2xl font-black uppercase tracking-widest text-[10px] hover:scale-[1.02] active:scale-[0.98] transition-all flex items-center justify-center gap-2"
                        >
                          <Package size={14} /> Pay on Delivery
                        </button>
                      </div>
                    </div>
                  )}
                </motion.div>
              </>
            )}
          </AnimatePresence>
        )}
      </div>
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

function mapAuthError(err: unknown, fallback: string): string {
  const e = err as { code?: string; response?: { data?: { message?: string } }; message?: string };
  if (e.code === 'auth/popup-closed-by-user') return 'Sign-in was cancelled.';
  if (e.code === 'auth/popup-blocked') return 'Pop-up blocked. Allow pop-ups for localhost and try again.';
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
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [phone, setPhone] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  // OTP Verification state
  const [otp, setOtp] = useState('');
  const [isOtpModalOpen, setIsOtpModalOpen] = useState(false);
  const [otpPurpose, setOtpPurpose] = useState<'signup_verify' | 'forgot_password'>('signup_verify');
  const [otpError, setOtpError] = useState('');
  const [otpLoading, setOtpLoading] = useState(false);

  // Forgot Password state
  const [isForgotPassword, setIsForgotPassword] = useState(false);
  const [forgotStep, setForgotStep] = useState(1); // 1 = enter phone, 2 = enter otp + new password
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showNewPassword, setShowNewPassword] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');

    // If joining/signing up as customer, send SMS OTP first
    if (!isLogin && role === 'customer') {
      if (!phone) {
        setError('Phone number is required for verification.');
        return;
      }
      setLoading(true);
      try {
        await axios.post('/api/auth/send-signup-otp', { phone, email });
        setOtpPurpose('signup_verify');
        setOtpError('');
        setOtp('');
        setIsOtpModalOpen(true);
      } catch (err: any) {
        setError(err.response?.data?.message || 'Failed to send verification code. Please check your details.');
      } finally {
        setLoading(false);
      }
      return;
    }

    // Standard Login / Non-customer signup flow
    setLoading(true);
    try {
      const endpoint = isLogin ? '/api/auth/login' : '/api/auth/register';
      const payload = isLogin ? { email, password } : { name, email, password, role, phone };
      
      const res = await axios.post(endpoint, payload);
      const accepted = onLogin(res.data.user, res.data.token);
      if (accepted === false) {
        setError(loginRejectedMessage(res.data.user.role as Role, forcedRole || role));
      }
    } catch (err: unknown) {
      setError(mapAuthError(err, 'Invalid email or password. Please try again.'));
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
      
      const res = await axios.post('/api/auth/register', { name, email, password, role, phone });
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

  const handleSendForgotOtp = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (!phone) {
      setError('Registered phone number is required.');
      return;
    }
    setLoading(true);
    try {
      await axios.post('/api/auth/send-forgot-otp', { phone });
      setForgotStep(2);
      setOtp('');
      setNewPassword('');
      setConfirmPassword('');
    } catch (err: any) {
      setError(err.response?.data?.message || 'Failed to send recovery code. Phone number might not be registered.');
    } finally {
      setLoading(false);
    }
  };

  const handleResetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    if (!otp) {
      setError('Verification code is required.');
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
      await axios.post('/api/auth/reset-password-otp', { phone, otp, newPassword });
      setIsForgotPassword(false);
      setIsLogin(true);
      setForgotStep(1);
      setError('');
      alert('Password updated successfully! Please log in with your new password.');
    } catch (err: any) {
      setError(err.response?.data?.message || 'Failed to update password. Code may be invalid or expired.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-slate-50 flex flex-col items-center justify-center p-4">
      <motion.div 
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        className="max-w-md w-full"
      >
        <div className="text-center mb-10">
          <div className="flex justify-center mb-6">
            <div className="w-20 h-20 bg-white shadow-2xl shadow-brand-blue/20 rounded-3xl flex items-center justify-center transform rotate-6 border border-slate-100">
              <MotorIcon size={40} className="text-brand-blue transform -scale-x-100" />
            </div>
          </div>
          <h1 className="text-5xl font-black tracking-tighter mb-2">
            <span className="text-brand-blue">bytz</span>
            <span className="text-brand-green">go</span>
          </h1>
          <p className="text-slate-500 font-medium italic">
            {forcedRole === 'rider' ? 'Rider driver app' : forcedRole === 'vendor' ? 'Vendor portal' : 'Your daily delivery partner'}
          </p>
          {forcedRole === 'rider' && (
            <motion.div className="mt-4 mx-auto max-w-sm p-3 rounded-2xl bg-slate-900 text-left border border-slate-800">
              <p className="text-[10px] font-black uppercase tracking-widest text-brand-green mb-1">Rider sign-in</p>
              <p className="text-xs text-slate-400 leading-relaxed">
                Use a <strong className="text-white">rider</strong> account here. A Google account registered as customer must use the home app, or tap Join to register as rider.
              </p>
              <p className="text-[10px] text-slate-500 mt-2 font-mono">Demo: rider@bytzgo.com / Test@1234</p>
            </motion.div>
          )}
        </div>

        <div className="bg-white p-8 rounded-[2.5rem] shadow-xl shadow-slate-200/50 border border-slate-100">
          {isForgotPassword ? (
            // Forgot Password Flow
            <div className="space-y-6">
              <div className="text-center mb-4">
                <h3 className="text-xl font-black italic tracking-tighter text-slate-800 uppercase">Recover Password</h3>
                <p className="text-xs font-medium text-slate-400 mt-1 uppercase tracking-widest">Via INTEK SMS OTP Verification</p>
              </div>

              {forgotStep === 1 ? (
                <form onSubmit={handleSendForgotOtp} className="space-y-6">
                  <div className="space-y-2">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">Registered Phone Number</label>
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

                  <button 
                    type="submit"
                    disabled={loading}
                    className="w-full py-4 bg-brand-blue text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all shadow-xl shadow-brand-blue/20 flex items-center justify-center gap-2"
                  >
                    {loading ? <LoadingIndicator size="sm" variant="white" /> : 'Send Verification Code'}
                  </button>
                </form>
              ) : (
                <form onSubmit={handleResetPassword} className="space-y-6">
                  <div className="p-4 bg-slate-50 rounded-2xl border border-slate-100 flex items-center justify-between">
                    <div>
                      <p className="text-[8px] font-black uppercase tracking-widest text-slate-400">Sending Code To</p>
                      <p className="font-bold text-sm text-slate-700">{phone}</p>
                    </div>
                    <button type="button" onClick={() => setForgotStep(1)} className="text-[8px] font-black uppercase tracking-widest text-brand-blue hover:underline">Change</button>
                  </div>

                  <div className="space-y-2">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">6-Digit Code (SMS OTP)</label>
                    <input 
                      type="text" 
                      required
                      maxLength={6}
                      value={otp}
                      onChange={(e) => setOtp(e.target.value.replace(/\D/g, ''))}
                      placeholder="Enter 6-digit OTP"
                      className="w-full bg-slate-50 border border-slate-100 p-4 text-center rounded-2xl focus:outline-none focus:border-brand-blue font-mono font-black text-xl tracking-[0.5em]"
                    />
                  </div>

                  <div className="space-y-2">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-4">New Password</label>
                    <div className="relative">
                      <Lock className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" size={18} />
                      <input 
                        type={showNewPassword ? "text" : "password"} 
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
                        type={showNewPassword ? "text" : "password"} 
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
              )}

              <div className="text-center mt-6">
                <button 
                  type="button" 
                  onClick={() => {
                    setIsForgotPassword(false);
                    setForgotStep(1);
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

                {!isLogin && (
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

                <div className="space-y-2">
                  <div className="flex justify-between items-center px-4">
                    <label className="text-[10px] font-black uppercase tracking-widest text-slate-400">Password</label>
                    {isLogin && (
                      <button 
                        type="button" 
                        onClick={() => {
                          setIsForgotPassword(true);
                          setForgotStep(1);
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
                      placeholder="••••••••"
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
                  className="w-full py-4 bg-brand-blue text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-[1.02] active:scale-[0.98] transition-all shadow-xl shadow-brand-blue/20 flex items-center justify-center gap-2"
                >
                  {loading ? <LoadingIndicator size="sm" variant="white" /> : (isLogin ? 'Sign In' : 'Create Account')}
                </button>
              </form>

              <div className="mt-6">
                <div className="flex items-center gap-4 mb-5">
                  <div className="flex-1 h-px bg-slate-200"></div>
                  <span className="text-[10px] font-black uppercase tracking-widest text-slate-300">or</span>
                  <div className="flex-1 h-px bg-slate-200"></div>
                </div>
                <div className="flex justify-center">
                  <button
                    onClick={async () => {
                      setLoading(true);
                      setError('');
                      try {
                        localStorage.setItem('google_login_role', role);
                        const result = await signInWithPopup(auth, googleProvider);
                        const idToken = await result.user.getIdToken();
                        const res = await axios.post('/api/auth/google', {
                          credential: idToken,
                          role,
                        });
                        const accepted = onLogin(res.data.user, res.data.token);
                        if (accepted === false) {
                          setError(loginRejectedMessage(res.data.user.role as Role, forcedRole || role));
                        }
                      } catch (err: unknown) {
                        console.error('Google sign-in failed:', err);
                        setError(mapAuthError(err, 'Google sign-in failed. Try email and password instead.'));
                      } finally {
                        setLoading(false);
                      }
                    }}
                    className="w-full max-w-[320px] py-4 bg-white border border-slate-200 rounded-full font-black uppercase tracking-widest text-[10px] flex items-center justify-center gap-3 hover:bg-slate-50 transition-all shadow-sm disabled:opacity-50"
                    disabled={loading}
                  >
                    {loading ? (
                      <LoadingIndicator size="sm" variant="white" />
                    ) : (
                      <>
                        <svg width="18" height="18" viewBox="0 0 24 24">
                          <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
                          <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
                          <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l3.66-2.84z" fill="#FBBC05"/>
                          <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
                        </svg>
                        {isLogin ? 'Sign in with Google' : 'Sign up with Google'}
                      </>
                    )}
                  </button>
                </div>
              </div>
            </>
          )}
        </div>
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
    </div>
  );
}

// Location Autocomplete Component (Ghana-only Places search)
function LocationAutocompleteInput({
  placeholder,
  icon: Icon,
  value,
  onChange,
  onMapClick,
  showUseMyLocation = true,
  showMapButton = true,
  onLocationError,
}: {
  placeholder: string;
  icon: React.ComponentType<{ size?: number; className?: string }>;
  value: string;
  onChange: (val: { address: string; lat: number; lng: number }) => void;
  onMapClick: () => void;
  showUseMyLocation?: boolean;
  showMapButton?: boolean;
  onLocationError?: (message: string) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const places = useMapsLibrary('places');
  const onChangeRef = useRef(onChange);
  const [locating, setLocating] = useState(false);

  useEffect(() => {
    onChangeRef.current = onChange;
  }, [onChange]);

  useEffect(() => {
    if (!places || !inputRef.current || typeof google === 'undefined') return;
    const autocomplete = new places.Autocomplete(
      inputRef.current,
      ghanaPlacesAutocompleteOptions(google.maps)
    );
    
    const listener = autocomplete.addListener('place_changed', () => {
      const place = autocomplete.getPlace();
      if (place.geometry?.location) {
        onChangeRef.current({
          address: place.formatted_address || place.name || '',
          lat: place.geometry.location.lat(),
          lng: place.geometry.location.lng(),
        });
      }
    });

    return () => {
      if (listener) {
        google.maps.event.removeListener(listener);
      }
    };
  }, [places]);

  const handleUseMyLocation = async () => {
    setLocating(true);
    const loc = await detectCurrentLocation();
    setLocating(false);
    if (loc) onChangeRef.current(loc);
    else onLocationError?.('Could not get your location. Allow location access in your browser.');
  };

  return (
    <div className="relative flex items-center">
      <Icon size={18} className="absolute left-4 text-slate-300 z-10" />
      <input
        ref={inputRef}
        required
        type="text"
        placeholder={placeholder}
        className={cn(
          'w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 pl-12 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all',
          showUseMyLocation && showMapButton ? 'pr-28' : showUseMyLocation || showMapButton ? 'pr-20' : 'pr-4'
        )}
        value={value}
        onChange={(e) => onChange({ address: e.target.value, lat: 0, lng: 0 })}
      />
      {showUseMyLocation && (
        <button
          type="button"
          title="Use my location"
          disabled={locating}
          onClick={handleUseMyLocation}
          className={cn(
            'absolute z-10 p-2 rounded-xl bg-slate-100 text-brand-blue hover:bg-brand-blue/10 transition-all disabled:opacity-50',
            showMapButton ? 'right-14' : 'right-2'
          )}
        >
          {locating ? <LoadingIndicator size="sm" /> : <LocateFixed size={16} />}
        </button>
      )}
      {showMapButton && (
        <button
          type="button"
          onClick={onMapClick}
          className="absolute right-2 z-10 text-[10px] font-black uppercase tracking-widest bg-brand-blue text-white px-3 py-2 rounded-xl"
        >
          Map
        </button>
      )}
    </div>
  );
}

// REST OF THE VIEW COMPONENTS (CustomerView, VendorView, etc.) 
// UPDATED TO USE REAL DATA FROM PROPS AND API
function CustomerView({ user, orders, products, vendors, riderLocations, paystackKey, setPaystackKey, onPlaceOrder, addNotification, cart, setCart, isCartOpen, setIsCartOpen, activeTab, setActiveTab, zones, subtotal, deliveryFee, total }: { user: AuthUser, orders: Order[], products: any[], vendors: any[], riderLocations: { [key: string]: { lat: number, lng: number } }, paystackKey: string, setPaystackKey: (k: string) => void, onPlaceOrder: (items: any[], total: number, vendorId?: string, extra?: any) => void, addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void, cart: any[], setCart: React.Dispatch<React.SetStateAction<any[]>>, isCartOpen: boolean, setIsCartOpen: (v: boolean) => void, activeTab: string, setActiveTab: (v: any) => void, zones: any[], subtotal: number, deliveryFee: number, total: number }) {
  const [selectedVendor, setSelectedVendor] = useState<any | null>(null);
  const [isTopUpOpen, setIsTopUpOpen] = useState(false);
  const [topUpAmount, setTopUpAmount] = useState('50');
  const [orderToCancel, setOrderToCancel] = useState<Order | null>(null);
  const [walletTab, setWalletTab] = useState<'topup' | 'withdraw'>('topup');
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
  const [profileForm, setProfileForm] = useState({ 
    email: user.email, 
    phone: user.phone || '',
    address: user.address || '',
    lat: user.lat || GHANA_CENTER.lat,
    lng: user.lng || GHANA_CENTER.lng,
    region: user.region || ''
  });

  const courierPickupAutoSet = useRef(false);
  const profileGeoSet = useRef(false);

  useEffect(() => {
    if (activeTab !== 'courier') return;
    if (courierPickupAutoSet.current || courierForm.pickup?.lat) return;
    courierPickupAutoSet.current = true;
    detectCurrentLocation().then((loc) => {
      if (loc) setCourierForm((prev) => ({ ...prev, pickup: loc }));
    });
  }, [activeTab, courierForm.pickup?.lat]);

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
    const distance = calculateDistance(
      courierForm.pickup.lat, courierForm.pickup.lng,
      courierForm.destination.lat, courierForm.destination.lng
    );
    const zone = zones.find(z => z.region === user.region && z.is_active) || zones[0];
    if (!zone) return 50;
    const fee = Number(zone.base_price) + (distance * Number(zone.price_per_km));
    const min = Number(zone.min_price);
    const max = zone.max_price ? Number(zone.max_price) : Infinity;
    return Math.max(min, Math.min(fee, max));
  };
  const courierFee = calculateCourierFee();

  const [profileSaving, setProfileSaving] = useState(false);
  const [profileMsg, setProfileMsg] = useState('');
  const [vendorConflict, setVendorConflict] = useState<any>(null);

  const myOrders = orders.filter(o => o.customer_id === user.id);

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

    console.log('Opening Paystack with key:', currentKey.slice(0, 10) + '...');
    try {
      if (!(window as any).PaystackPop) {
        console.error('Paystack script (inline.js) not found in window!');
        addNotification('Payment library not loaded. Please refresh.', 'warning');
        return;
      }

      const handler = (window as any).PaystackPop.setup({
        key: currentKey,
        email: user.email,
        amount: Math.round(total * 100),
        currency: 'GHS',
        callback: (response: any) => {
          console.log('Paystack payment successful:', response.reference);
          onPlaceOrder(cart.map(item => ({ id: item.id, name: item.name, quantity: item.quantity, price: item.price })), total, selectedVendor?.id, { payment_reference: response.reference, payment_method: 'paystack' });
          setCart([]);
          setIsCartOpen(false);
          setActiveTab('tracking');
        },
        onClose: () => {
          console.log('Paystack window closed by user');
          setIsCartOpen(false);
        }
      });
      handler.openIframe();
    } catch (err) {
      console.error('Critical Paystack Error:', err);
      addNotification('Could not open payment window', 'warning');
    }
  };

  return (
    <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="relative space-y-8 pb-24 sm:pb-0">
      {/* Mobile Bottom Navigation - Moved to App component */}

      {/* Modals and Cart Logic same as before */}
      {/* Modals */}
      <AnimatePresence>
        {isTopUpOpen && (
          <>
            <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} onClick={() => setIsTopUpOpen(false)} className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-[100]" />
            <motion.div initial={{ scale: 0.9, opacity: 0 }} animate={{ scale: 1, opacity: 1 }} exit={{ scale: 0.9, opacity: 0 }} className="fixed top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 w-full max-w-sm bg-white p-6 sm:p-8 rounded-[3rem] shadow-2xl z-[110] border border-slate-100 overflow-y-auto max-h-[90vh]">
               <div className="flex p-1 bg-slate-100 rounded-2xl mb-6">
                 <button onClick={() => setWalletTab('topup')} className={cn("flex-1 py-2 text-[10px] font-black uppercase tracking-widest rounded-xl transition-all", walletTab === 'topup' ? "bg-white text-brand-blue shadow-sm" : "text-slate-400")}>Top Up</button>
                 <button onClick={() => setWalletTab('withdraw')} className={cn("flex-1 py-2 text-[10px] font-black uppercase tracking-widest rounded-xl transition-all", walletTab === 'withdraw' ? "bg-white text-brand-blue shadow-sm" : "text-slate-400")}>Withdraw</button>
               </div>

               {walletTab === 'topup' ? (
                 <>
                   <h3 className="text-xl font-black italic tracking-tighter mb-4 text-slate-800">Top Up Wallet</h3>
                   <div className="grid grid-cols-2 gap-2 mb-6">
                      {['20', '50', '100', '200'].map(val => (
                        <button key={val} onClick={() => setTopUpAmount(val)} className={cn("py-3 rounded-xl font-bold transition-all border text-sm", topUpAmount === val ? "bg-brand-blue text-white border-brand-blue shadow-lg" : "bg-slate-50 text-slate-500 border-slate-100")}>₵{val}</button>
                      ))}
                   </div>
                   <div className="mb-6">
                      <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Custom Amount</label>
                      <input type="number" value={topUpAmount} onChange={e => setTopUpAmount(e.target.value)} className="w-full bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-mono font-black text-lg" />
                   </div>
                   <button 
                     onClick={async () => {
                        let currentKey = paystackKey;
                        if (!currentKey) {
                          try {
                            const res = await axios.get('/api/config/paystack');
                            currentKey = res.data.publicKey;
                            setPaystackKey(currentKey);
                          } catch (e) {}
                        }
                        if (!currentKey) return addNotification('Payment system offline', 'warning');

                        if (!(window as any).PaystackPop) return addNotification('Paystack not loaded', 'warning');

                        const handler = (window as any).PaystackPop.setup({
                          key: currentKey,
                          email: user.email,
                          amount: Number(topUpAmount) * 100,
                          currency: 'GHS',
                          callback: async (response: any) => {
                            await axios.post('/api/wallet/topup', { reference: response.reference });
                            addNotification('Wallet topped up successfully!', 'success');
                            setIsTopUpOpen(false);
                          }
                        });
                        handler.openIframe();
                     }}
                     className="w-full py-4 bg-brand-blue text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-105 active:scale-95 transition-all shadow-xl"
                   >
                     Pay with Card/Momo
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
                     addNotification('Withdrawal requested successfully!', 'success');
                     setIsTopUpOpen(false);
                   } catch (err: any) {
                     addNotification(err.response?.data?.message || 'Withdrawal failed', 'warning');
                   }
                 }} className="space-y-4">
                    <h3 className="text-xl font-black italic tracking-tighter text-slate-800">Withdraw Funds</h3>
                    <div>
                      <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Amount to Withdraw</label>
                      <input type="number" required value={withdrawAmount} onChange={e => setWithdrawAmount(e.target.value)} className="w-full bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-mono font-black text-lg" placeholder="0.00" />
                    </div>

                    <div className="flex gap-2">
                      <button type="button" onClick={() => setWithdrawMethod('momo')} className={cn("flex-1 py-3 rounded-xl border text-[10px] font-black uppercase tracking-widest transition-all", withdrawMethod === 'momo' ? "bg-brand-blue text-white border-brand-blue" : "bg-white text-slate-400 border-slate-100")}>MoMo</button>
                      <button type="button" onClick={() => setWithdrawMethod('bank')} className={cn("flex-1 py-3 rounded-xl border text-[10px] font-black uppercase tracking-widest transition-all", withdrawMethod === 'bank' ? "bg-brand-blue text-white border-brand-blue" : "bg-white text-slate-400 border-slate-100")}>Bank</button>
                    </div>

                    {withdrawMethod === 'momo' ? (
                      <div className="space-y-3">
                         <select value={withdrawNetwork} onChange={e => setWithdrawNetwork(e.target.value)} className="w-full bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none font-bold text-xs">
                           <option value="mtn">MTN Mobile Money</option>
                           <option value="vodafone">Vodafone Cash</option>
                           <option value="airteltigo">AirtelTigo Money</option>
                         </select>
                         <input type="tel" placeholder="Mobile Number" required value={withdrawPhone} onChange={e => setWithdrawPhone(e.target.value)} className="w-full bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none font-bold text-xs" />
                      </div>
                    ) : (
                      <div className="space-y-3">
                         <input type="text" placeholder="Bank Name" required value={withdrawBank} onChange={e => setWithdrawBank(e.target.value)} className="w-full bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none font-bold text-xs" />
                         <input type="text" placeholder="Account Number" required value={withdrawAccount} onChange={e => setWithdrawAccount(e.target.value)} className="w-full bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none font-bold text-xs" />
                      </div>
                    )}

                    <button type="submit" className="w-full py-4 bg-slate-900 text-white rounded-2xl font-black uppercase tracking-widest text-xs hover:scale-105 active:scale-95 transition-all shadow-xl">Confirm Withdrawal</button>
                 </form>
               )}
            </motion.div>
          </>
        )}
        {isCartOpen && null}
      </AnimatePresence>

      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4">
        <div className="flex items-center justify-between w-full sm:w-auto gap-4">
          <div>
            <h2 className="text-2xl sm:text-3xl font-black tracking-tighter text-slate-800 italic uppercase">Flavor Port</h2>
            <p className="text-slate-500 font-bold text-[10px] sm:text-sm tracking-tight">{user.name.split(' ')[0]}, what's on the menu today?</p>
          </div>
          <div onClick={() => setIsTopUpOpen(true)} className="group cursor-pointer bg-brand-blue px-4 sm:px-6 py-2 sm:py-3 rounded-xl sm:rounded-2xl text-white shadow-xl shadow-brand-blue/20 flex flex-col items-start hover:scale-105 transition-all">
             <span className="text-[7px] sm:text-[8px] font-black uppercase tracking-widest opacity-60">Wallet</span>
             <span className="text-xs sm:text-sm font-black font-mono">₵{Number(user.balance || 0).toFixed(2)}</span>
          </div>
        </div>
        <div className="flex p-1 bg-slate-200 rounded-2xl w-full sm:w-auto shadow-inner">
          <button onClick={() => setActiveTab('menu')} className={cn("flex-1 sm:flex-none px-8 py-2.5 text-xs font-black rounded-xl transition-all uppercase tracking-widest", activeTab === 'menu' ? "bg-white text-brand-blue shadow-sm" : "text-slate-500")}>MARKET</button>
          <button onClick={() => setActiveTab('courier')} className={cn("flex-1 sm:flex-none px-8 py-2.5 text-xs font-black rounded-xl transition-all uppercase tracking-widest", activeTab === 'courier' ? "bg-white text-brand-blue shadow-sm" : "text-slate-500")}>SEND</button>
          <button onClick={() => setActiveTab('tracking')} className={cn("flex-1 sm:flex-none px-8 py-2.5 text-xs font-black rounded-xl transition-all uppercase tracking-widest", activeTab === 'tracking' ? "bg-white text-brand-green shadow-sm" : "text-slate-500")}>HISTORY</button>
        </div>
        <button id="profile-toggle" className="hidden" onClick={() => setActiveTab(activeTab === 'profile' ? 'menu' : 'profile')} />
      </div>

      {activeTab === 'menu' && (
        <div className="space-y-6">
           <div className="flex items-center gap-4">
             {selectedVendor && (
               <button onClick={() => setSelectedVendor(null)} className="p-2 hover:bg-slate-200 rounded-xl transition-colors">
                  <X size={20} />
               </button>
             )}
             <h3 className="text-xl font-black uppercase tracking-widest text-slate-400">
               {selectedVendor ? selectedVendor.name : "Choose a Vendor"}
             </h3>
           </div>

            <div className={cn("grid gap-4 sm:gap-8", selectedVendor ? "grid-cols-1 sm:grid-cols-2 lg:grid-cols-4" : "grid-cols-1 sm:grid-cols-2 lg:grid-cols-3")}>
             {selectedVendor ? (
               vendorProducts.length > 0 ? (
                 vendorProducts.map(item => (
                   <div key={item.id} className="bg-white p-4 sm:p-6 rounded-[2rem] sm:rounded-[2.5rem] border border-slate-100 hover:shadow-2xl hover:shadow-brand-blue/10 transition-all group flex flex-col justify-between">
                      <div>
                        <div className="h-40 sm:h-56 bg-slate-50 rounded-2xl sm:rounded-3xl mb-4 sm:mb-6 flex items-center justify-center relative overflow-hidden group-hover:scale-105 transition-transform">
                          <img src={item.image_url || 'https://images.unsplash.com/photo-1567333328061-6d7aae8e2e6b?auto=format&fit=crop&q=80&w=400'} alt={item.name} className="w-full h-full object-cover" />
                          <span className="absolute top-3 left-3 sm:top-4 sm:left-4 bg-white/90 backdrop-blur-md px-3 sm:px-4 py-1 rounded-full text-[8px] sm:text-[10px] font-black uppercase tracking-widest text-slate-400 border border-slate-100">{item.category}</span>
                        </div>
                        <h4 className="font-black text-xl sm:text-2xl text-slate-800 tracking-tight leading-tight mb-1 sm:mb-2">{item.name}</h4>
                        <p className="text-slate-400 text-[10px] sm:text-sm mb-6 sm:mb-8 font-medium leading-relaxed line-clamp-2 sm:line-clamp-none">{item.description}</p>
                      </div>
                      <div className="flex items-center justify-between gap-3 sm:gap-4">
                        <div className="flex flex-col">
                          <span className="text-[8px] sm:text-[10px] font-black text-slate-300 uppercase tracking-widest">Price</span>
                          <span className="font-mono font-black text-lg sm:text-xl text-brand-blue">₵{Number(item.price).toFixed(2)}</span>
                        </div>
                         <button onClick={() => addToCart(item)} className="flex-1 py-3 sm:py-4 bg-slate-900 text-white rounded-xl sm:rounded-2xl font-black text-[10px] sm:text-xs hover:bg-brand-blue transition-all uppercase tracking-widest shadow-lg">Add</button>
                      </div>
                    </div>
                  ))
                ) : (
                 <div className="col-span-full text-center py-20 bg-white rounded-[3rem] border border-slate-100">
                    <p className="text-slate-400 font-bold italic">No items found for this vendor.</p>
                 </div>
               )
             ) : (
               vendors.map(vendor => (
                 <div key={vendor.id} onClick={() => setSelectedVendor(vendor)} className="bg-white rounded-[2.5rem] border border-slate-100 hover:shadow-2xl hover:shadow-brand-blue/10 transition-all cursor-pointer group overflow-hidden flex flex-col">
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
                      <h4 className="font-black text-2xl text-slate-800 tracking-tight leading-tight mb-2">{vendor.name}</h4>
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
        <div className="bg-white rounded-[2rem] sm:rounded-[3rem] p-5 sm:p-12 shadow-xl border border-slate-100 max-w-3xl mx-auto">
          <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 sm:gap-6 mb-8 sm:mb-10">
            <div className="w-14 h-14 sm:w-16 sm:h-16 bg-brand-blue rounded-2xl sm:rounded-3xl flex items-center justify-center text-white shadow-lg rotate-3 shrink-0">
              <Package size={28} className="sm:hidden" />
              <Package size={32} className="hidden sm:block" />
            </div>
            <div>
              <h3 className="text-2xl sm:text-3xl font-black italic tracking-tighter text-slate-800">Send a Package</h3>
              <p className="text-slate-400 font-bold uppercase tracking-widest text-[9px] sm:text-[10px]">Fast, secure courier delivery across the city</p>
            </div>
          </div>

          <form onSubmit={(e) => {
            e.preventDefault();
            if (!courierForm.pickup || !courierForm.destination) return addNotification('Please select pickup and destination', 'warning');
            onPlaceOrder([{ id: 'courier-1', name: `Delivery: ${courierForm.itemDesc}`, quantity: 1, price: courierFee }], courierFee, undefined, {
               order_type: 'courier',
               address: courierForm.destination.address,
               pickup: courierForm.pickup.address,
               lat: courierForm.destination.lat,
               lng: courierForm.destination.lng,
               pickup_lat: courierForm.pickup.lat,
               pickup_lng: courierForm.pickup.lng,
               delivery_fee: courierFee,
               payment_method: 'pay_on_delivery',
               scheduled_time: courierForm.scheduledTime === 'later' ? `${courierForm.scheduleDate} ${courierForm.scheduleClock}` : null
            });
            setActiveTab('tracking');
          }} className="space-y-5 sm:space-y-6">
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 sm:gap-6">
              <div className="space-y-2">
                <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Pickup Location</label>
                <LocationAutocompleteInput 
                   placeholder="Where from? (Ghana)" 
                   icon={MapPin} 
                   value={courierForm.pickup?.address || ''} 
                   onChange={(val) => setCourierForm({...courierForm, pickup: { ...(courierForm.pickup || {}), ...val }})}
                   onMapClick={() => { setMapMode('pickup'); setIsMapOpen(true); }}
                   onLocationError={(m) => addNotification(m, 'warning')}
                />
              </div>
              <div className="space-y-2">
                <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Destination</label>
                <LocationAutocompleteInput 
                   placeholder="Where to? (Ghana)" 
                   icon={Navigation} 
                   value={courierForm.destination?.address || ''} 
                   onChange={(val) => setCourierForm({...courierForm, destination: { ...(courierForm.destination || {}), ...val }})}
                   onMapClick={() => { setMapMode('destination'); setIsMapOpen(true); }}
                   onLocationError={(m) => addNotification(m, 'warning')}
                />
              </div>
            </div>

            <AnimatePresence>
              {isMapOpen && (
                 <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
                    <div className="bg-slate-50 border border-slate-100 rounded-[2rem] p-2 mb-6 shadow-inner relative mt-2">
                      <div className="flex justify-between items-center px-4 py-3 border-b border-slate-200/50 mb-2">
                         <span className="text-[10px] font-black uppercase tracking-widest text-slate-500">Select {mapMode} on Map</span>
                         <button type="button" onClick={() => setIsMapOpen(false)} className="text-[10px] font-black uppercase tracking-widest bg-brand-blue/10 text-brand-blue px-4 py-2 rounded-full">Done</button>
                      </div>
                      <div className="h-56 sm:h-64 rounded-2xl overflow-hidden relative">
                        <Map 
                          defaultCenter={courierForm.pickup ? { lat: courierForm.pickup.lat, lng: courierForm.pickup.lng } : GHANA_CENTER} 
                          defaultZoom={15} 
                          defaultTilt={45}
                          gestureHandling={'greedy'}
                          disableDefaultUI={true}
                          styles={CLEAN_MAP_STYLE}
                          onClick={async (e) => {
                           if (!e.detail.latLng) return;
                           const lat = e.detail.latLng.lat;
                           const lng = e.detail.latLng.lng;
                           const address = (await reverseGeocodeGhana(lat, lng)) || `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
                           const loc = { lat, lng, address };
                           if (mapMode === 'pickup') {
                               setCourierForm({...courierForm, pickup: loc});
                           } else {
                               setCourierForm({...courierForm, destination: loc});
                           }
                        }}>
                           {courierForm.pickup && <Marker position={{lat: courierForm.pickup.lat, lng: courierForm.pickup.lng}} />}
                           {courierForm.destination && <Marker position={{lat: courierForm.destination.lat, lng: courierForm.destination.lng}} />}
                        </Map>
                      </div>
                    </div>
                 </motion.div>
              )}
            </AnimatePresence>

            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 sm:gap-6">
              <div className="space-y-2">
                <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Sender's Contact</label>
                <div className="relative">
                  <input required type="tel" placeholder="054..." className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 pl-4 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" value={courierForm.senderContact} onChange={e => setCourierForm({...courierForm, senderContact: e.target.value})} />
                </div>
              </div>
              <div className="space-y-2">
                <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Receiver's Contact</label>
                <div className="relative">
                  <input required type="tel" placeholder="024..." className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 pl-4 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" value={courierForm.receiverContact} onChange={e => setCourierForm({...courierForm, receiverContact: e.target.value})} />
                </div>
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">What are you sending?</label>
              <div className="relative">
                <Package size={16} className="absolute left-4 top-4 text-slate-300" />
                <textarea required placeholder="Brief description of the item..." className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 pl-12 pr-4 font-bold text-sm h-32 focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all resize-none" value={courierForm.itemDesc} onChange={e => setCourierForm({...courierForm, itemDesc: e.target.value})} />
              </div>
            </div>

            <div className="grid grid-cols-2 gap-3 sm:gap-4 pt-4 border-t border-slate-100">
               <button type="button" onClick={() => setCourierForm({...courierForm, scheduledTime: 'now'})} className={cn("py-4 rounded-2xl font-black uppercase tracking-widest text-[10px] sm:text-xs border transition-all", courierForm.scheduledTime === 'now' || !courierForm.scheduledTime ? "bg-brand-blue text-white border-brand-blue shadow-lg" : "bg-slate-50 text-slate-400 border-slate-100 hover:bg-slate-100")}>Send Now</button>
               <button type="button" onClick={() => setCourierForm({...courierForm, scheduledTime: 'later'})} className={cn("py-4 rounded-2xl font-black uppercase tracking-widest text-[10px] sm:text-xs border transition-all flex items-center justify-center gap-2", courierForm.scheduledTime === 'later' ? "bg-brand-blue text-white border-brand-blue shadow-lg" : "bg-slate-50 text-slate-400 border-slate-100 hover:bg-slate-100")}><Clock size={14} /> Schedule</button>
            </div>

            <AnimatePresence>
               {courierForm.scheduledTime === 'later' && (
                 <motion.div initial={{ opacity: 0, height: 0 }} animate={{ opacity: 1, height: 'auto' }} exit={{ opacity: 0, height: 0 }} className="overflow-hidden">
                    <div className="grid grid-cols-2 gap-4 sm:gap-6 pt-2">
                       <div className="space-y-2">
                         <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Date</label>
                         <input type="date" required className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all text-slate-700" value={courierForm.scheduleDate} onChange={e => setCourierForm({...courierForm, scheduleDate: e.target.value})} />
                       </div>
                       <div className="space-y-2">
                         <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Time</label>
                         <input type="time" required className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all text-slate-700" value={courierForm.scheduleClock} onChange={e => setCourierForm({...courierForm, scheduleClock: e.target.value})} />
                       </div>
                    </div>
                 </motion.div>
               )}
            </AnimatePresence>

            <div className="pt-4 sm:pt-8">
              <button type="submit" className="w-full py-4 sm:py-5 bg-slate-900 text-white rounded-2xl sm:rounded-[2rem] font-black uppercase tracking-widest text-[11px] sm:text-sm hover:scale-[1.02] active:scale-[0.98] transition-all shadow-2xl flex items-center justify-center gap-3">
                 <Package size={18} /> Request Courier {courierFee > 0 && ` · GH₵${courierFee.toFixed(2)}`}
              </button>
            </div>
          </form>
        </div>
      )}

      {/* (Tracking view same as before but using real order data) */}
      {activeTab === 'tracking' && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
           {myOrders.length === 0 && (
            <div className="col-span-full text-center py-32 bg-white rounded-[3rem] border border-slate-200 border-dashed">
              <Clock className="mx-auto text-slate-200 mb-6" size={64} />
              <p className="text-slate-400 font-black text-xl italic uppercase tracking-tighter">No active history...</p>
            </div>
          )}
          {myOrders.map(order => {
            const vendor = vendors.find(v => v.id === order.vendor_id);
            const riderLoc = order.rider_id ? riderLocations[order.rider_id] : null;
            const isActive = ['pending', 'preparing', 'ready', 'picked_up'].includes(order.status) && !!order.rider_id;
            
            return (
              <div key={order.id} className="bg-white p-8 rounded-[2.5rem] border border-slate-200 shadow-sm flex flex-col justify-between hover:border-brand-blue transition-colors">
                 <div className="flex justify-between items-center mb-6">
                    <div className="flex items-center gap-3">
                      <div className="w-12 h-12 bg-slate-900 rounded-2xl flex items-center justify-center text-white">
                        {(order as any).order_type === 'courier' ? <Package size={20} /> : <ShoppingBag size={20} />}
                      </div>
                      <div>
                        <h4 className="font-black text-2xl tracking-tighter italic uppercase underline decoration-brand-blue/50">#{order.id.slice(-4)}</h4>
                        <div className="flex flex-col">
                          {order.vendor_id && (
                            <p className="text-[10px] font-black text-brand-blue uppercase tracking-widest">
                              {vendor?.name || 'Order'}
                            </p>
                          )}
                          <p className="text-[10px] font-mono text-slate-400 uppercase tracking-widest">
                            {new Date((order as any).created_at || order.createdAt).toDateString()}
                          </p>
                        </div>
                      </div>
                    </div>
                    <div className="flex flex-col items-end gap-2">
                      <div className={cn(
                        "px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest",
                        order.status === 'delivered' ? "bg-brand-green/10 text-brand-green" : "bg-brand-blue/10 text-brand-blue"
                      )}>
                        {order.status.replace('_', ' ')}
                      </div>
                      <PaymentStatusBadge order={order} />
                    </div>
                  </div>
                  
                  {order.status === 'pending' && (
                    <button 
                      onClick={() => setOrderToCancel(order)}
                      className="mb-8 w-full py-4 bg-red-50 text-red-500 rounded-2xl font-black uppercase tracking-widest text-[10px] hover:bg-red-100 transition-all active:scale-95"
                    >
                      Cancel Order
                    </button>
                  )}

                  {isActive && (
                    <div className="mb-8 h-64 rounded-3xl overflow-hidden border border-slate-100 shadow-inner relative">
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
                        pickupLocation={{ lat: vendor?.lat || 5.6037, lng: vendor?.lng || -0.1870 }}
                        destination={{ lat: order.lat || 5.6037, lng: order.lng || -0.1870 }}
                        orderStatus={order.status}
                      />
                    </div>
                  )}
                  
                  <div className="space-y-6 mb-10 border-l-2 border-slate-50 ml-4 pl-8">
                    <TrackingStep label="Mission Started" active={['pending', 'preparing', 'ready', 'picked_up', 'delivered'].includes(order.status)} />
                    <TrackingStep label={(order as any).order_type === 'courier' ? "Rider at Pickup" : "Kitchen Magic"} active={['preparing', 'ready', 'picked_up', 'delivered'].includes(order.status)} />
                    <TrackingStep label="Bytz on Wheels" active={['picked_up', 'delivered'].includes(order.status)} />
                    <TrackingStep label={(order as any).order_type === 'courier' ? "Mission Accomplished" : "Enjoy your Meal"} active={order.status === 'delivered'} />
                  </div>

                  {order.status === 'delivered' && (
                    <div className="mt-6 pt-6 border-t border-slate-50">
                      <p className="text-[10px] font-black uppercase tracking-widest text-slate-400 mb-3">Rate your experience</p>
                      {(order as any).rating ? (
                        <div className="flex items-center gap-2">
                          {[1, 2, 3, 4, 5].map(star => (
                            <Star key={star} size={16} className={cn(star <= (order as any).rating ? "text-yellow-400 fill-yellow-400" : "text-slate-300")} />
                          ))}
                        </div>
                      ) : (
                        <div className="flex items-center gap-2">
                          {[1, 2, 3, 4, 5].map(star => (
                            <button 
                              key={star} 
                              onClick={async () => {
                                try {
                                  await axios.post(`/api/orders/${order.id}/rate`, { rating: star, comment: '' });
                                  addNotification('Thanks for your rating!', 'success');
                                  // Update local state if needed
                                } catch (err) {
                                  console.error('Rating failed', err);
                                  addNotification('Failed to save rating', 'warning');
                                }
                              }}
                              className="hover:scale-125 transition-all group"
                            >
                              <Star size={20} className="text-slate-300 group-hover:text-yellow-400 transition-colors" />
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  )}
                  {order.status === 'delivered' && (
                    <div className="mt-6 flex justify-center">
                      <button className="text-[9px] font-black uppercase tracking-widest text-slate-300 hover:text-red-500 transition-colors flex items-center gap-2">
                        <AlertTriangle size={12} /> Report a problem with this order
                      </button>
                    </div>
                  )}
              </div>
            );
          })}
        </div>
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
            await axios.post(`/api/orders/${orderToCancel.id}/cancel`);
            addNotification('Order cancelled and refunded!', 'success');
            setOrderToCancel(null);
          } catch (err: any) {
            addNotification(err.response?.data?.message || 'Cancellation failed', 'warning');
            setOrderToCancel(null);
          }
        }}
        title="Cancel Order"
        message={`Are you sure you want to cancel order #${orderToCancel?.id.slice(-6)}? The full amount will be refunded to your wallet instantly.`}
        confirmLabel="Yes, Cancel Order"
        type="danger"
      />

      {activeTab === 'profile' && (
        <div className="bg-white rounded-[2rem] sm:rounded-[3rem] p-6 sm:p-12 shadow-xl border border-slate-100 max-w-2xl mx-auto">
          <div className="flex flex-col sm:flex-row items-start sm:items-center gap-4 sm:gap-6 mb-8 sm:mb-10">
            <div className="w-16 h-16 sm:w-20 sm:h-20 bg-brand-blue rounded-2xl sm:rounded-3xl flex items-center justify-center text-white shadow-lg rotate-3 shrink-0 text-2xl sm:text-3xl font-black italic">
              {user.name[0]}
            </div>
            <div>
              <h3 className="text-3xl font-black italic tracking-tighter text-slate-800">{user.name}</h3>
              <p className="text-slate-400 font-bold uppercase tracking-widest text-[10px]">Account Settings</p>
            </div>
          </div>

          <form onSubmit={async (e) => {
            e.preventDefault();
            setProfileSaving(true);
            setProfileMsg('');
            try {
              const res = await axios.patch('/api/auth/profile', profileForm);
              localStorage.setItem('user', JSON.stringify(res.data.user));
              localStorage.setItem('token', res.data.token);
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
                    const address = await reverseGeocodeGhana(newLat, newLng);
                    if (address) setProfileForm(prev => ({ ...prev, address }));
                  }} />
                </Map>
              </div>
            </div>

            <div className="space-y-2">
              <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Email Address</label>
              <div className="relative">
                <Mail size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-slate-300" />
                <input type="email" required value={profileForm.email} onChange={e => setProfileForm({...profileForm, email: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 pl-12 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
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
                  className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 pl-12 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all"
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
                <input type="tel" placeholder="024 000 0000" value={profileForm.phone} onChange={e => setProfileForm({...profileForm, phone: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-2xl py-4 pl-12 pr-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
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
      <div className={cn("z-10 w-8 h-8 rounded-2xl flex items-center justify-center transition-all shadow-sm", active ? "bg-brand-green text-white rotate-6" : "bg-slate-100 text-slate-300")}>
        <CheckCircle2 size={16} />
      </div>
      <span className={cn("text-base font-black tracking-tight", active ? "text-slate-800" : "text-slate-300")}>{label}</span>
    </div>
  );
}

function VendorView({ user, orders, products, riderLocations, onUpdateStatus, onAddProduct, onDeleteProduct, addNotification, activeTab, setActiveTab }: { user: AuthUser, orders: Order[], products: any[], riderLocations: { [key: string]: { lat: number, lng: number } }, onUpdateStatus: (id: string, s: OrderStatus, extra?: any) => void, onAddProduct: (p: any) => void, onDeleteProduct: (id: string) => void, addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void, activeTab: any, setActiveTab: (v: any) => void }) {
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
    region: user.region || ''
  });
  const storeGeoSet = useRef(false);

  useEffect(() => {
    if (activeTab !== 'profile') return;
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
  const [storeSaving, setStoreSaving] = useState(false);
  const [storeMsg, setStoreMsg] = useState('');

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
      const res = await axios.post('/api/wallet/withdraw', { amount: Number(withdrawAmount) });
      user.balance = res.data.balance; // Update local user balance
      setWithdrawStatus({ message: 'Withdrawal successful!', type: 'success' });
      setWithdrawAmount('');
    } catch (err: any) {
      setWithdrawStatus({ message: err.response?.data?.error || 'Withdrawal failed', type: 'error' });
    } finally {
      setIsWithdrawing(false);
    }
  };

  const activeOrders = orders.filter(o => o.status !== 'delivered' && o.status !== 'cancelled');

  const handleFileUpload = async (file: File, onSuccess: (url: string) => void) => {
    setUploading(true);
    try {
      const formData = new FormData();
      formData.append('image', file);
      const res = await axios.post('/api/upload', formData, { headers: { 'Content-Type': 'multipart/form-data' } });
      onSuccess(res.data.url);
    } catch (err) {
      console.error('Upload failed', err);
    } finally {
      setUploading(false);
    }
  };

  const handleSubmitProduct = async (e: React.FormEvent) => {
    e.preventDefault();
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
      // addNotification('Product saved successfully!', 'success');
    } catch (err) {
      console.error('Failed to save product', err);
    }
  };

  const handleDeleteProduct = async (id: string) => {
    try {
      await onDeleteProduct(id);
      setProductToDelete(null);
    } catch (err) {
      console.error('Delete product failed', err);
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
           <button onClick={() => setActiveTab('products')} className={cn("px-4 sm:px-6 py-2 rounded-xl text-[10px] sm:text-xs font-black uppercase tracking-widest transition-all whitespace-nowrap", activeTab === 'products' ? "bg-brand-blue text-white" : "bg-slate-100 text-slate-500")}>Menu</button>
           <button onClick={() => setActiveTab('store')} className={cn("px-4 sm:px-6 py-2 rounded-xl text-[10px] sm:text-xs font-black uppercase tracking-widest transition-all whitespace-nowrap", activeTab === 'store' ? "bg-brand-blue text-white" : "bg-slate-100 text-slate-500")}>Store</button>
           <button onClick={() => setActiveTab('wallet')} className={cn("px-4 sm:px-6 py-2 rounded-xl text-[10px] sm:text-xs font-black uppercase tracking-widest transition-all whitespace-nowrap", activeTab === 'wallet' ? "bg-brand-blue text-white" : "bg-slate-100 text-slate-500")}>Wallet</button>
        </div>
      </header>

      {activeTab === 'orders' ? (
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

              return (
                <div key={order.id} className="bg-white p-5 sm:p-8 rounded-[2rem] sm:rounded-[2.5rem] border border-slate-100 shadow-sm hover:shadow-xl transition-all">
                   <div className="flex justify-between items-start mb-4 sm:mb-6">
                    <div>
                      <h4 className="font-black text-lg sm:text-2xl tracking-tighter">Order #{order.id.slice(-4)}</h4>
                      <p className="text-brand-green font-mono text-xs uppercase tracking-widest mt-1">{order.customerName}</p>
                    </div>
                    <div className="font-mono font-black text-base sm:text-xl text-slate-800">GH₵{order.total}</div>
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
                        pickupLocation={{ lat: user.lat || 5.6037, lng: user.lng || -0.1870 }}
                        destination={{ lat: order.lat || 5.6037, lng: order.lng || -0.1870 }}
                        orderStatus={order.status}
                      />
                    </div>
                  )}

                  <div className="bg-slate-50 p-3 sm:p-4 rounded-xl sm:rounded-2xl mb-4 sm:mb-8 space-y-2">
                    {order.items.map((item, idx) => (
                      <div key={idx} className="flex justify-between text-xs sm:text-sm font-bold">
                        <span className="text-slate-600">{item.quantity}x {item.name}</span>
                        <span className="text-slate-400">GH₵{item.price}</span>
                      </div>
                    ))}
                  </div>

                  <div className="flex gap-2 sm:gap-3 flex-wrap items-center">
                     {order.status === 'pending' && <button onClick={() => onUpdateStatus(order.id, 'preparing')} className="flex-1 py-3 sm:py-4 bg-brand-blue text-white rounded-xl sm:rounded-2xl font-black uppercase tracking-widest text-[10px] sm:text-xs">Start Cook</button>}
                     {order.status === 'preparing' && <button onClick={() => onUpdateStatus(order.id, 'ready')} className="flex-1 py-3 sm:py-4 bg-brand-green text-white rounded-xl sm:rounded-2xl font-black uppercase tracking-widest text-[10px] sm:text-xs">Mark Ready</button>}
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
                     GH₵{product.price}
                   </div>
                 </div>
                 <div className="p-6">
                   <div className="flex justify-between items-start mb-1">
                     <h4 className="font-black text-lg">{product.name}</h4>
                     <button onClick={() => handleEditClick(product)} className="p-2 hover:bg-slate-100 rounded-lg text-slate-400 hover:text-brand-blue transition-colors">
                       <Edit3 size={16} />
                     </button>
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
                         <input type="text" placeholder="Paste URL or upload →" className="flex-1 bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-bold text-sm" value={newProduct.image_url} onChange={(e) => setNewProduct({...newProduct, image_url: e.target.value})} />
                         <label className={cn("px-4 py-4 rounded-xl font-black uppercase tracking-widest text-[10px] cursor-pointer transition-all flex items-center gap-1", uploading ? "bg-slate-200 text-slate-400" : "bg-brand-blue text-white hover:scale-105")}>
                           {uploading ? <LoadingIndicator size="sm" /> : '📷'}
                           <input type="file" accept="image/*" className="hidden" disabled={uploading} onChange={(e) => {
                             const file = e.target.files?.[0];
                             if (file) handleFileUpload(file, (url) => setNewProduct({...newProduct, image_url: url}));
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
                        <input type="number" step="0.01" placeholder="Price (GH₵)" required className="flex-1 bg-slate-50 border border-slate-100 p-4 rounded-xl focus:outline-none focus:border-brand-blue font-bold text-sm" value={newProduct.price} onChange={(e) => setNewProduct({...newProduct, price: e.target.value})} />
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
      ) : (
        <div className="bg-white p-8 sm:p-12 rounded-[3rem] border border-slate-100 shadow-xl max-w-2xl mx-auto">
          <div className="flex items-center gap-4 mb-10">
            <div className="w-16 h-16 bg-brand-green rounded-2xl flex items-center justify-center text-white text-2xl font-black rotate-3 shadow-lg">{user.name[0]}</div>
            <div>
              <h3 className="text-3xl font-black italic tracking-tighter text-slate-800">Store Profile</h3>
              <p className="text-slate-400 font-bold uppercase tracking-widest text-[10px]">How customers see your store</p>
            </div>
          </div>
          
          <form onSubmit={async (e) => {
            e.preventDefault();
            setStoreSaving(true);
            setStoreMsg('');
            try {
              const res = await axios.patch('/api/auth/profile', storeForm);
              localStorage.setItem('user', JSON.stringify(res.data.user));
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
                <input type="text" placeholder="Paste URL or upload →" value={storeForm.cover_image} onChange={e => setStoreForm({...storeForm, cover_image: e.target.value})} className="flex-1 bg-slate-50 border border-slate-100 rounded-2xl py-4 px-6 font-bold text-sm focus:outline-none focus:border-brand-blue transition-all" />
                <label className={cn("px-5 py-4 rounded-2xl font-black cursor-pointer transition-all flex items-center", uploading ? "bg-slate-200 text-slate-400" : "bg-brand-green text-white hover:scale-105")}>
                  {uploading ? <LoadingIndicator size="sm" /> : '📷'}
                  <input type="file" accept="image/*" className="hidden" disabled={uploading} onChange={(e) => {
                    const file = e.target.files?.[0];
                    if (file) handleFileUpload(file, (url) => setStoreForm({...storeForm, cover_image: url}));
                  }} />
                </label>
              </div>
              {storeForm.cover_image && (
                <div className="rounded-3xl overflow-hidden h-40 border border-slate-100 shadow-inner">
                  <img src={storeForm.cover_image} alt="Cover Preview" className="w-full h-full object-cover" onError={(e) => { (e.target as HTMLImageElement).style.display = 'none'; }} />
                </div>
              )}
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
                    const address = await reverseGeocodeGhana(newLat, newLng);
                    if (address) setStoreForm(prev => ({ ...prev, address }));
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
        </div>
      )}

      {activeTab === 'wallet' && (
        <div className="bg-white rounded-[1.5rem] sm:rounded-[2rem] border border-slate-100 shadow-sm p-4 sm:p-10 max-w-xl mx-auto min-h-[50vh] flex flex-col justify-center">
          <div className="text-center mb-6 sm:mb-8">
            <div className="w-12 h-12 sm:w-16 sm:h-16 bg-brand-green/10 text-brand-green rounded-full flex items-center justify-center mx-auto mb-3 sm:mb-4">
              <CreditCard size={24} className="sm:w-8 sm:h-8" />
            </div>
            <h3 className="font-black uppercase tracking-widest text-slate-800 text-sm sm:text-lg">Available Balance</h3>
            <p className="text-4xl sm:text-5xl font-black tracking-tighter text-brand-green mt-1 sm:mt-2">₵{Number(user.balance || 0).toFixed(2)}</p>
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
              <label className="block text-[10px] font-black uppercase tracking-widest text-slate-500 mb-2 ml-2 sm:ml-4">Withdraw Amount (₵)</label>
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

function IncomingRideCallModal({
  order,
  vendors,
  onAccept,
  onDecline,
}: {
  order: Order | null;
  vendors: any[];
  onAccept: (orderId: string, status: OrderStatus) => Promise<void>;
  onDecline: () => void;
}) {
  const [secondsLeft, setSecondsLeft] = useState(INCOMING_RIDE_TIMEOUT_SEC);
  const [accepting, setAccepting] = useState(false);
  const ringStopRef = useRef(false);
  const ringCleanupRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    if (!order) {
      ringStopRef.current = true;
      ringCleanupRef.current?.();
      ringCleanupRef.current = null;
      return;
    }

    ringStopRef.current = false;
    setSecondsLeft(INCOMING_RIDE_TIMEOUT_SEC);

    let wakeLock: WakeLockSentinel | null = null;
    if ('wakeLock' in navigator) {
      navigator.wakeLock.request('screen').then(w => { wakeLock = w; }).catch(() => {});
    }

    let audioCtx: AudioContext | null = null;
    try {
      audioCtx = new AudioContext();
    } catch {
      /* audio unavailable */
    }

    const playPulse = () => {
      if (!audioCtx || ringStopRef.current) return;
      const t = audioCtx.currentTime;
      [523.25, 659.25].forEach((freq, i) => {
        const osc = audioCtx!.createOscillator();
        const gain = audioCtx!.createGain();
        osc.type = 'sine';
        osc.frequency.value = freq;
        gain.gain.setValueAtTime(0.0001, t + i * 0.22);
        gain.gain.exponentialRampToValueAtTime(0.35, t + i * 0.22 + 0.02);
        gain.gain.exponentialRampToValueAtTime(0.0001, t + i * 0.22 + 0.18);
        osc.connect(gain);
        gain.connect(audioCtx!.destination);
        osc.start(t + i * 0.22);
        osc.stop(t + i * 0.22 + 0.2);
      });
    };

    playPulse();
    const ringInterval = setInterval(() => {
      playPulse();
      if (navigator.vibrate) navigator.vibrate([300, 150, 300]);
    }, 1400);

    const countdown = setInterval(() => {
      setSecondsLeft(prev => {
        if (prev <= 1) {
          onDecline();
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    ringCleanupRef.current = () => {
      ringStopRef.current = true;
      clearInterval(ringInterval);
      clearInterval(countdown);
      audioCtx?.close().catch(() => {});
      wakeLock?.release().catch(() => {});
    };

    return ringCleanupRef.current;
  }, [order?.id, onDecline]);

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
            animate={{ scaleX: secondsLeft / INCOMING_RIDE_TIMEOUT_SEC }}
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
              <p className="text-4xl font-black text-brand-green font-mono">₵{Number(earnings).toFixed(2)}</p>
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
              onClick={onDecline}
              disabled={accepting}
              className="py-4 rounded-2xl bg-white/10 text-white font-black uppercase tracking-widest text-xs hover:bg-white/15 transition-all flex flex-col items-center gap-1"
            >
              <X size={22} />
              Decline
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
              {accepting ? 'Accepting…' : 'Accept ride'}
            </button>
          </div>
        </motion.div>
      </motion.div>
    </AnimatePresence>
  );
}
function AdminView({ user, orders, addNotification, activeTab, setActiveTab }: { user: AuthUser, orders: Order[], addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void, activeTab: any, setActiveTab: (v: any) => void }) {
  const [allUsers, setAllUsers] = useState<any[]>([]);
  const [zones, setZones] = useState<any[]>([]);
  const [pendingProducts, setPendingProducts] = useState<any[]>([]);
  const [revenueData, setRevenueData] = useState<any>(null);
  const [editingZone, setEditingZone] = useState<any | null>(null);
  const [zoneForm, setZoneForm] = useState({ name: '', region: '', base_price: '10', price_per_km: '2', min_price: '5', max_price: '' });
  const [showZoneForm, setShowZoneForm] = useState(false);
  const [zoneToDelete, setZoneToDelete] = useState<any | null>(null);

  useEffect(() => {
    if (activeTab === 'users') axios.get('/api/admin/users').then(res => setAllUsers(res.data));
    if (activeTab === 'zones') axios.get('/api/delivery-zones').then(res => setZones(res.data));
    if (activeTab === 'products') axios.get('/api/admin/pending-products').then(res => setPendingProducts(res.data));
    if (activeTab === 'revenue') axios.get('/api/admin/revenue').then(res => setRevenueData(res.data));
  }, [activeTab]);

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
             <button onClick={() => setActiveTab('products')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'products' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Approval {pendingProducts.length > 0 && <span className="ml-1 bg-red-500 text-white px-1.5 py-0.5 rounded-full text-[8px]">{pendingProducts.length}</span>}</button>
             <button onClick={() => setActiveTab('revenue')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'revenue' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Revenue</button>
             <button onClick={() => setActiveTab('zones')} className={cn("px-4 py-2 rounded-xl text-[10px] font-black uppercase tracking-widest transition-all", activeTab === 'zones' ? "bg-slate-900 text-white" : "bg-slate-100 text-slate-500")}>Zones</button>
          </div>
       </header>

       <div className="grid grid-cols-1 md:grid-cols-3 gap-4 sm:gap-6">
          <StatBox label="Total Orders" value={orders.length} color="blue" />
          <StatBox label="Revenue" value={`₵${orders.reduce((a,b) => a + Number(b.total), 0).toFixed(2)}`} color="green" />
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
                        <td className="px-8 py-6 font-mono font-black text-brand-blue">₵{o.total}</td>
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
                       <span className="font-mono font-black text-brand-blue">₵{o.total}</span>
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
                        <td className="px-8 py-6 font-bold text-sm">{u.name}</td>
                        <td className="px-8 py-6"><span className={cn("px-3 py-1 rounded-lg text-[10px] font-black uppercase", u.role === 'admin' ? "bg-red-50 text-red-500" : "bg-slate-100 text-slate-500")}>{u.role}</span></td>
                        <td className="px-8 py-6 text-sm text-slate-500">{u.email}</td>
                        <td className="px-8 py-6 font-mono font-black text-brand-green">₵{Number(u.balance).toFixed(2)}</td>
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
                    <p className="text-[10px] text-slate-400 mb-4">{u.email}</p>
                    <div className="flex justify-between items-center">
                       <div className="flex flex-col">
                          <span className="text-[8px] font-black text-slate-300 uppercase tracking-widest">Status</span>
                          <span className="font-mono font-black text-brand-green text-sm">₵{Number(u.balance).toFixed(2)}</span>
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
                         <span className="font-mono font-black text-brand-blue">₵{p.price}</span>
                         <button 
                           onClick={async () => {
                             await axios.patch(`/api/admin/products/${p.id}/approve`);
                             setPendingProducts(pendingProducts.filter(item => item.id !== p.id));
                             addNotification('Product approved!', 'success');
                           }}
                           className="flex-1 py-3 bg-brand-green text-white rounded-xl font-black uppercase tracking-widest text-[10px] hover:shadow-lg transition-all"
                         >
                           Approve
                         </button>
                      </div>
                   </div>
                 ))}
              </div>
            )}
         </div>
       ) : activeTab === 'revenue' ? (
         <div className="space-y-10">
            {revenueData && (
              <>
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-6">
                   <div className="bg-slate-900 p-10 rounded-[3rem] text-white">
                      <p className="text-[10px] font-black uppercase tracking-widest text-slate-400 mb-2">Gross Revenue</p>
                      <h3 className="text-5xl font-black tracking-tighter italic">₵{Number(revenueData.summary.gross_revenue || 0).toFixed(2)}</h3>
                   </div>
                   <div className="bg-brand-blue p-10 rounded-[3rem] text-white">
                      <p className="text-[10px] font-black uppercase tracking-widest text-white/50 mb-2">System Earnings (10%)</p>
                      <h3 className="text-5xl font-black tracking-tighter italic">₵{Number(revenueData.summary.system_earnings || 0).toFixed(2)}</h3>
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
                                       {t.type === 'withdrawal' ? '-' : '+'}₵{Number(t.amount).toFixed(2)}
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
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Base Price (₵)</label>
                   <input type="number" step="0.01" placeholder="10.00" value={zoneForm.base_price} onChange={e => setZoneForm({...zoneForm, base_price: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
                 </div>
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Price per KM (₵)</label>
                   <input type="number" step="0.01" placeholder="2.00" value={zoneForm.price_per_km} onChange={e => setZoneForm({...zoneForm, price_per_km: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
                 </div>
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Minimum Price (₵)</label>
                   <input type="number" step="0.01" placeholder="5.00" value={zoneForm.min_price} onChange={e => setZoneForm({...zoneForm, min_price: e.target.value})} className="w-full bg-slate-50 border border-slate-100 rounded-xl py-3 px-4 font-bold text-sm focus:outline-none focus:border-brand-blue focus:ring-4 focus:ring-brand-blue/10 transition-all" />
                 </div>
                 <div className="space-y-1.5">
                   <label className="text-[10px] font-black uppercase tracking-widest text-slate-400 ml-2">Maximum Price (₵) <span className="text-slate-300">• optional</span></label>
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
                         <span className="font-mono font-black text-brand-blue text-sm">₵{Number(zone.base_price).toFixed(2)}</span>
                       </div>
                       <div className="bg-slate-50 rounded-xl p-3">
                         <span className="text-[8px] font-black uppercase tracking-widest text-slate-400 block">Per KM</span>
                         <span className="font-mono font-black text-brand-blue text-sm">₵{Number(zone.price_per_km).toFixed(2)}</span>
                       </div>
                       <div className="bg-slate-50 rounded-xl p-3">
                         <span className="text-[8px] font-black uppercase tracking-widest text-slate-400 block">Min</span>
                         <span className="font-mono font-black text-slate-600 text-sm">₵{Number(zone.min_price).toFixed(2)}</span>
                       </div>
                       <div className="bg-slate-50 rounded-xl p-3">
                         <span className="text-[8px] font-black uppercase tracking-widest text-slate-400 block">Max</span>
                         <span className="font-mono font-black text-slate-600 text-sm">{zone.max_price ? `₵${Number(zone.max_price).toFixed(2)}` : '∞'}</span>
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
