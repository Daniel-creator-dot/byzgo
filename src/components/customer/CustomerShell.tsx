import { type Dispatch, type ReactNode, type SetStateAction, useEffect, useState } from 'react';
import { getPendingWalletTopupRef, WALLET_PENDING_EVENT } from '../../lib/walletTopup';
import { motion, AnimatePresence } from 'motion/react';
import {
  CreditCard,
  LogOut,
  Navigation,
  ShoppingBag,
  Store,
  User,
  X,
  Zap,
} from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import axios from 'axios';
import { Order } from '../../types';
import { openPaystackCheckout, paystackPaymentEmail } from '../../lib/paystackCheckout';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

type CustomerTab = 'menu' | 'courier' | 'tracking' | 'profile';

interface AuthUser {
  id: string;
  name: string;
  email: string;
  role: string;
  balance: number;
}

export function CustomerShell({
  user,
  activeTab,
  setActiveTab,
  cart,
  setCart,
  isCartOpen,
  setIsCartOpen,
  subtotal,
  deliveryFee,
  total,
  orders,
  notifications,
  setNotifications,
  onLogout,
  paystackKey,
  setPaystackKey,
  addNotification,
  refreshData,
  children,
}: {
  user: AuthUser;
  activeTab: string;
  setActiveTab: (tab: CustomerTab) => void;
  cart: { id: string; name: string; quantity: number; price: number; vendor_id?: string }[];
  setCart: Dispatch<SetStateAction<typeof cart>>;
  isCartOpen: boolean;
  setIsCartOpen: (v: boolean) => void;
  subtotal: number;
  deliveryFee: number;
  total: number;
  orders: Order[];
  notifications: { id: number; message: string; type?: string }[];
  setNotifications: Dispatch<SetStateAction<{ id: number; message: string; type?: string }[]>>;
  onLogout: () => void;
  paystackKey: string;
  setPaystackKey: (k: string) => void;
  addNotification: (m: string, t?: 'info' | 'success' | 'warning') => void;
  refreshData: () => void | Promise<void>;
  children: ReactNode;
}) {
  const tab = activeTab as CustomerTab;
  const [hasPendingTopup, setHasPendingTopup] = useState(() => !!getPendingWalletTopupRef());

  useEffect(() => {
    const sync = () => setHasPendingTopup(!!getPendingWalletTopupRef());
    sync();
    window.addEventListener(WALLET_PENDING_EVENT, sync);
    window.addEventListener('storage', sync);
    return () => {
      window.removeEventListener(WALLET_PENDING_EVENT, sync);
      window.removeEventListener('storage', sync);
    };
  }, []);

  const activeOrders = orders.filter(
    (o) => o.customer_id === user.id && o.status !== 'delivered' && o.status !== 'cancelled'
  );
  const arrivedOrders = activeOrders.filter((o) => o.status === 'arrived');
  const firstName = user.name.split(' ')[0] || user.name;

  const navItems: { id: CustomerTab; label: string; icon: typeof Zap }[] = [
    { id: 'courier', label: 'Ride', icon: Zap },
    { id: 'menu', label: 'Shops', icon: Store },
    { id: 'tracking', label: 'Activity', icon: Navigation },
    { id: 'profile', label: 'Account', icon: User },
  ];

  const headerTitle =
    tab === 'courier' ? 'Book a delivery' : tab === 'menu' ? 'Shops' : tab === 'tracking' ? 'Your trips' : '';

  return (
    <div className="min-h-[100dvh] bg-slate-950 text-white flex flex-col">
      <header className="shrink-0 z-30 px-4 pt-3 pb-2 border-b border-slate-800/80 bg-slate-950/95 backdrop-blur-md">
        <motion.div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[10px] font-black uppercase tracking-widest text-slate-500">BytzGo</p>
            <p className="font-black text-base truncate">
              {headerTitle || (
                <>
                  Hey, <span className="text-brand-green">{firstName}</span>
                </>
              )}
            </p>
            {tab === 'courier' && (
              <p className="text-[11px] text-slate-500 font-medium mt-0.5">Pickup → drop-off in minutes</p>
            )}
          </div>

          <div className="flex items-center gap-2 shrink-0">
            <button
              type="button"
              onClick={() => document.getElementById('customer-wallet-open')?.click()}
              className={cn(
                'flex flex-col items-end px-3 py-2 rounded-2xl bg-slate-900 border transition-colors',
                hasPendingTopup
                  ? 'border-amber-400 ring-2 ring-amber-400/50 hover:border-amber-300'
                  : 'border-slate-800 hover:border-brand-blue/50'
              )}
            >
              <span className="text-[8px] font-black uppercase tracking-widest text-slate-500">Wallet</span>
              <span className="text-sm font-black font-mono text-brand-green">
                ₵{Number(user.balance || 0).toFixed(2)}
              </span>
            </button>
            <button
              type="button"
              onClick={onLogout}
              className="p-2.5 rounded-2xl bg-slate-900 border border-slate-800 text-slate-400 hover:text-red-400 hover:border-red-500/30 transition-colors"
              title="Sign out"
            >
              <LogOut size={18} />
            </button>
          </div>
        </motion.div>

      </header>

      <button
        type="button"
        onClick={() => document.getElementById('customer-wallet-open')?.click()}
        className={cn(
          'mx-4 mb-2 w-[calc(100%-2rem)] py-3 rounded-2xl text-center transition-colors shrink-0',
          hasPendingTopup
            ? 'bg-amber-400 text-slate-900 font-black shadow-lg shadow-amber-400/25'
            : 'bg-amber-500/10 border border-amber-500/30 text-amber-300 hover:bg-amber-500/20'
        )}
      >
        <span className="text-[10px] font-black uppercase tracking-widest">
          {hasPendingTopup ? 'Tap to credit your wallet →' : 'Paid with MoMo / card? Credit wallet →'}
        </span>
      </button>

      <div className="fixed top-20 right-4 z-[9999] space-y-2 pointer-events-none max-w-sm">
        {notifications.map((n) => (
          <motion.div
            key={n.id}
            initial={{ opacity: 0, x: 40 }}
            animate={{ opacity: 1, x: 0 }}
            className={cn(
              'px-4 py-3 rounded-xl shadow-xl text-xs font-black uppercase tracking-widest pointer-events-auto flex items-center gap-2',
              n.type === 'success'
                ? 'bg-brand-green text-white'
                : n.type === 'warning'
                  ? 'bg-red-500 text-white'
                  : 'bg-slate-800 text-white border border-slate-700'
            )}
          >
            <span className="flex-1">{n.message}</span>
            <button
              type="button"
              onClick={() => setNotifications((prev) => prev.filter((nn) => nn.id !== n.id))}
              className="opacity-70 hover:opacity-100"
            >
              <X size={14} />
            </button>
          </motion.div>
        ))}
      </div>

      <main className="flex-1 overflow-y-auto px-4 py-4 pb-28">{children}</main>

      {tab === 'menu' && cart.length > 0 && (
        <button
          type="button"
          onClick={() => setIsCartOpen(true)}
          className="fixed bottom-24 right-4 z-[60] bg-brand-blue text-white px-4 py-3 rounded-2xl shadow-2xl shadow-brand-blue/40 flex items-center gap-3 hover:scale-105 active:scale-95 transition-all"
        >
          <motion.div className="relative">
            <ShoppingBag size={22} />
            {cart.length > 0 && (
              <span className="absolute -top-2 -right-2 bg-brand-green text-white text-[10px] font-black w-5 h-5 rounded-full flex items-center justify-center border-2 border-brand-blue">
                {cart.reduce((a, b) => a + b.quantity, 0)}
              </span>
            )}
          </motion.div>
          <span className="font-black text-sm">₵{subtotal.toFixed(2)}</span>
        </button>
      )}

      {activeOrders.length > 0 && tab !== 'tracking' && (
        <button
          type="button"
          onClick={() => setActiveTab('tracking')}
          className={cn(
            'fixed bottom-24 left-4 z-[60] text-white px-4 py-3 rounded-2xl shadow-xl flex items-center gap-2 hover:scale-105 active:scale-95 transition-all max-w-[calc(100%-8rem)]',
            arrivedOrders.length > 0
              ? 'bg-amber-500 border border-amber-400 text-slate-950 shadow-amber-500/30'
              : 'bg-slate-800 border border-slate-700'
          )}
        >
          <Navigation size={18} className={arrivedOrders.length > 0 ? 'animate-pulse' : 'text-brand-green animate-pulse'} />
          <span className="font-black text-[10px] uppercase tracking-widest truncate">
            {arrivedOrders.length > 0 ? 'Pay & get PIN' : `Track · ${activeOrders.length}`}
          </span>
        </button>
      )}

      <nav className="fixed bottom-0 left-0 right-0 z-[100] px-4 pb-4 pt-2 bg-slate-950/95 backdrop-blur-xl border-t border-slate-800">
        <div className="flex justify-around items-center max-w-lg mx-auto bg-slate-900 rounded-2xl border border-slate-800 p-1">
          {navItems.map(({ id, label, icon: Icon }) => (
            <button
              key={id}
              type="button"
              onClick={() => setActiveTab(id)}
              className={cn(
                'flex flex-col items-center gap-0.5 flex-1 py-2 rounded-xl transition-all',
                tab === id ? 'text-brand-blue bg-slate-800' : 'text-slate-500'
              )}
            >
              <Icon size={20} className={tab === id ? 'text-brand-blue' : ''} />
              <span className="text-[8px] font-black uppercase tracking-widest">{label}</span>
            </button>
          ))}
        </div>
      </nav>

      <AnimatePresence>
        {isCartOpen && (
          <>
            <motion.div
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setIsCartOpen(false)}
              className="fixed inset-0 bg-black/60 backdrop-blur-sm z-[200]"
            />
            <motion.div
              initial={{ y: '100%' }}
              animate={{ y: 0 }}
              exit={{ y: '100%' }}
              transition={{ type: 'spring', damping: 25, stiffness: 200 }}
              className="fixed bottom-0 left-0 right-0 max-h-[92vh] bg-slate-900 border-t border-slate-800 z-[210] shadow-2xl p-6 pb-8 flex flex-col rounded-t-[2rem]"
            >
              <motion.div className="w-12 h-1 bg-slate-700 rounded-full mx-auto mb-5" />
              <div className="flex justify-between items-center mb-6">
                <h3 className="text-2xl font-black italic tracking-tighter">Your cart</h3>
                <button
                  type="button"
                  onClick={() => setIsCartOpen(false)}
                  className="p-2 rounded-xl bg-slate-800 text-slate-400 hover:text-white"
                >
                  <X size={20} />
                </button>
              </div>

              <div className="flex-1 overflow-y-auto space-y-3 min-h-0">
                {cart.length === 0 ? (
                  <div className="text-center py-16">
                    <ShoppingBag size={48} className="mx-auto text-slate-700 mb-4" />
                    <p className="text-slate-500 font-bold text-sm uppercase tracking-widest">Cart is empty</p>
                  </div>
                ) : (
                  cart.map((item) => (
                    <motion.div
                      key={item.id}
                      className="bg-slate-800/80 p-4 rounded-2xl flex items-center justify-between border border-slate-700"
                    >
                      <div className="flex items-center gap-3">
                        <motion.div className="w-11 h-11 bg-slate-900 rounded-xl flex items-center justify-center text-brand-blue font-black">
                          {item.name[0]}
                        </motion.div>
                        <div>
                          <h4 className="font-black text-sm">{item.name}</h4>
                          <p className="text-xs font-mono text-brand-green">₵{Number(item.price).toFixed(2)}</p>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <button
                          type="button"
                          onClick={() => {
                            const newCart = cart
                              .map((i) =>
                                i.id === item.id ? { ...i, quantity: Math.max(0, i.quantity - 1) } : i
                              )
                              .filter((i) => i.quantity > 0);
                            setCart(newCart);
                          }}
                          className="w-8 h-8 rounded-lg bg-slate-900 border border-slate-600 font-black"
                        >
                          -
                        </button>
                        <span className="font-mono font-black text-sm w-6 text-center">{item.quantity}</span>
                        <button
                          type="button"
                          onClick={() => {
                            setCart(cart.map((i) => (i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i)));
                          }}
                          className="w-8 h-8 rounded-lg bg-slate-900 border border-slate-600 font-black"
                        >
                          +
                        </button>
                      </div>
                    </motion.div>
                  ))
                )}
              </div>

              {cart.length > 0 && (
                <div className="mt-6 pt-6 border-t border-slate-800 space-y-3">
                  <div className="flex justify-between text-slate-400 text-[10px] font-black uppercase tracking-widest">
                    <span>Subtotal</span>
                    <span className="font-mono">₵{subtotal.toFixed(2)}</span>
                  </div>
                  <motion.div className="flex justify-between text-brand-green bg-brand-green/10 p-3 rounded-xl border border-brand-green/20 text-[10px] font-black uppercase tracking-widest">
                    <span>Delivery</span>
                    <span className="font-mono">₵{deliveryFee.toFixed(2)}</span>
                  </motion.div>
                  <div className="flex justify-between items-end">
                    <span className="text-slate-500 text-xs font-black uppercase">Total</span>
                    <span className="text-2xl font-black text-brand-blue italic">₵{total.toFixed(2)}</span>
                  </div>
                  <div className="grid grid-cols-1 gap-2 pt-2">
                    <button
                      type="button"
                      onClick={async () => {
                        let currentKey = paystackKey;
                        if (!currentKey) {
                          try {
                            const res = await axios.get('/api/config/paystack');
                            currentKey = res.data.publicKey;
                            setPaystackKey(currentKey);
                          } catch {
                            /* ignore */
                          }
                        }
                        if (!currentKey) return addNotification('Payment system offline', 'warning');
                        setIsCartOpen(false);
                        try {
                          await openPaystackCheckout({
                            publicKey: currentKey,
                            email: paystackPaymentEmail(user),
                            amountGhs: total,
                            metadata: { type: 'order', vendor_id: cart[0]?.vendor_id },
                            onSuccess: async (reference) => {
                              await axios.post('/api/orders', {
                                items: cart.map((item) => ({
                                  id: item.id,
                                  name: item.name,
                                  quantity: item.quantity,
                                  price: item.price,
                                })),
                                total,
                                delivery_fee: deliveryFee,
                                vendorId: cart[0].vendor_id,
                                payment_reference: reference,
                                payment_method: 'paystack',
                              });
                              setCart([]);
                              setActiveTab('tracking');
                              refreshData();
                            },
                          });
                        } catch (err: unknown) {
                          const msg = err instanceof Error ? err.message : 'Could not open payment';
                          addNotification(msg, 'warning');
                        }
                      }}
                      className="py-4 bg-white text-slate-900 rounded-2xl font-black uppercase tracking-widest text-[10px] flex items-center justify-center gap-2"
                    >
                      <CreditCard size={14} /> Card / MoMo
                    </button>
                    <button
                      type="button"
                      disabled={user.balance < total}
                      onClick={async () => {
                        await axios.post('/api/orders', {
                          items: cart.map((item) => ({
                            id: item.id,
                            name: item.name,
                            quantity: item.quantity,
                            price: item.price,
                          })),
                          total,
                          delivery_fee: deliveryFee,
                          vendorId: cart[0].vendor_id,
                          payment_method: 'wallet',
                        });
                        setCart([]);
                        setIsCartOpen(false);
                        setActiveTab('tracking');
                        refreshData();
                      }}
                      className="py-4 bg-brand-blue text-white rounded-2xl font-black uppercase tracking-widest text-[10px] disabled:opacity-30"
                    >
                      Pay with wallet
                    </button>
                    <button
                      type="button"
                      onClick={async () => {
                        await axios.post('/api/orders', {
                          items: cart.map((item) => ({
                            id: item.id,
                            name: item.name,
                            quantity: item.quantity,
                            price: item.price,
                          })),
                          total,
                          delivery_fee: deliveryFee,
                          vendorId: cart[0].vendor_id,
                          payment_method: 'pay_on_delivery',
                        });
                        setCart([]);
                        setIsCartOpen(false);
                        setActiveTab('tracking');
                        refreshData();
                      }}
                      className="py-4 bg-brand-green text-white rounded-2xl font-black uppercase tracking-widest text-[10px]"
                    >
                      Pay on delivery
                    </button>
                  </div>
                </div>
              )}
            </motion.div>
          </>
        )}
      </AnimatePresence>
    </div>
  );
}
