import { type ComponentType, type ReactNode } from 'react';
import { LogOut, X } from 'lucide-react';
import { motion } from 'motion/react';
import { formatCedis } from '../../lib/format';
import { cn } from './ui';

export type NavItem = {
  id: string;
  label: string;
  icon: ComponentType<{ size?: number; className?: string }>;
  badge?: number;
};

export function DarkAppShell({
  title,
  subtitle,
  userName,
  balance,
  onLogout,
  navItems,
  activeTab,
  onTabChange,
  notifications,
  onDismissNotification,
  children,
  headerExtra,
}: {
  title: string;
  subtitle?: string;
  userName: string;
  balance: number;
  onLogout: () => void;
  navItems: NavItem[];
  activeTab: string;
  onTabChange: (id: string) => void;
  notifications: { id: string; message: string; type?: 'info' | 'success' | 'warning' }[];
  onDismissNotification: (id: string) => void;
  children: ReactNode;
  headerExtra?: ReactNode;
}) {
  return (
    <div className="min-h-[100dvh] bg-slate-950 text-white flex flex-col">
      <header className="shrink-0 z-30 px-4 pt-3 pb-2 border-b border-slate-800/80 bg-slate-950/95 backdrop-blur-md safe-area-inset-top">
        <div className="flex items-center justify-between gap-3">
          <div className="min-w-0">
            <p className="text-[10px] font-bold uppercase tracking-widest text-slate-500">BytzGo</p>
            <p className="font-bold text-base truncate">{title}</p>
            {subtitle && <p className="text-[11px] text-slate-500 mt-0.5">{subtitle}</p>}
          </div>
          <div className="flex items-center gap-2 shrink-0">
            <div className="flex flex-col items-end px-3 py-2 rounded-2xl bg-slate-900 border border-slate-800">
              <span className="text-[8px] font-bold uppercase tracking-widest text-slate-500">Wallet</span>
              <span className="text-sm font-bold font-mono text-brand-green">{formatCedis(balance)}</span>
            </div>
            <button
              type="button"
              onClick={onLogout}
              className="p-2.5 rounded-2xl bg-slate-900 border border-slate-800 text-slate-400 hover:text-red-400 hover:border-red-500/30 transition-colors"
              title="Sign out"
            >
              <LogOut size={18} />
            </button>
          </div>
        </div>
        {headerExtra}
      </header>

      <div className="fixed top-20 right-4 z-[9999] space-y-2 pointer-events-none max-w-sm">
        {notifications.map((n) => (
          <motion.div
            key={n.id}
            initial={{ opacity: 0, x: 40 }}
            animate={{ opacity: 1, x: 0 }}
            className={cn(
              'px-4 py-3 rounded-xl shadow-xl text-xs font-bold pointer-events-auto flex items-center gap-2',
              n.type === 'success'
                ? 'bg-brand-green text-white'
                : n.type === 'warning'
                  ? 'bg-red-500 text-white'
                  : 'bg-slate-800 text-white border border-slate-700',
            )}
          >
            <span className="flex-1">{n.message}</span>
            <button
              type="button"
              onClick={() => onDismissNotification(n.id)}
              className="opacity-70 hover:opacity-100"
            >
              <X size={14} />
            </button>
          </motion.div>
        ))}
      </div>

      <main className="flex-1 overflow-y-auto px-4 py-4 pb-28">{children}</main>

      <nav className="fixed bottom-0 left-0 right-0 z-[100] bg-slate-950/95 backdrop-blur-xl border-t border-slate-800 flex justify-around px-2 py-2 safe-area-inset-bottom sm:hidden">
        {navItems.map((item) => {
          const Icon = item.icon;
          const active = activeTab === item.id;
          return (
            <button
              key={item.id}
              type="button"
              onClick={() => onTabChange(item.id)}
              className={cn(
                'flex flex-col items-center gap-0.5 px-2 py-1.5 rounded-xl min-w-[3.5rem] transition-colors relative',
                active ? 'text-brand-blue' : 'text-slate-500',
              )}
            >
              <Icon size={20} className={active ? 'text-brand-blue' : ''} />
              <span className="text-[8px] font-bold uppercase tracking-wide">{item.label}</span>
              {item.badge != null && item.badge > 0 && (
                <span className="absolute top-0 right-1 min-w-[14px] h-[14px] px-1 rounded-full bg-red-500 text-white text-[8px] font-bold flex items-center justify-center">
                  {item.badge > 9 ? '9+' : item.badge}
                </span>
              )}
            </button>
          );
        })}
      </nav>
    </div>
  );
}
