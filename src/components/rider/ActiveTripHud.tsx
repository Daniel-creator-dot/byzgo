import { motion } from 'motion/react';
import { MapPin, Navigation, Phone, X } from 'lucide-react';
import type { Order } from '../../types';
import type { RouteSummary } from './MapDirections';
import type { TripPhase } from '../../lib/riderTrip';
import { openTurnByTurnNavigation, type LatLng } from '../../lib/riderTrip';

export function ActiveTripHud({
  order,
  phase,
  targetLabel,
  navTarget,
  riderOrigin,
  route,
  onStopNav,
  customerPhone,
}: {
  order: Order;
  phase: TripPhase;
  targetLabel: string;
  navTarget: { lat: number; lng: number; label: string };
  riderOrigin?: LatLng | null;
  route: RouteSummary | null;
  onStopNav: () => void;
  customerPhone?: string;
}) {
  const isCourier = (order as Order & { order_type?: string }).order_type === 'courier';
  const phaseTitle = phase === 'to_pickup' ? 'Heading to pickup' : 'Heading to drop-off';
  const phaseHint =
    phase === 'to_pickup'
      ? isCourier
        ? 'Collect the package'
        : 'Pick up the order'
      : 'Deliver to customer';

  return (
    <motion.div className="absolute top-3 left-3 right-3 z-20 pointer-events-none">
      <div className="pointer-events-auto rounded-2xl bg-slate-950/95 backdrop-blur-xl border border-slate-700/80 shadow-2xl overflow-hidden">
        <div className="h-1 bg-gradient-to-r from-brand-green via-emerald-400 to-brand-green" />
        <div className="p-4">
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-start gap-3 min-w-0">
              <div className="w-11 h-11 rounded-xl bg-brand-green/20 border border-brand-green/40 flex items-center justify-center shrink-0">
                <Navigation className="text-brand-green" size={22} />
              </div>
              <div className="min-w-0">
                <p className="text-[9px] font-black uppercase tracking-widest text-brand-green">
                  {phaseTitle}
                </p>
                <p className="text-sm font-black truncate">{targetLabel}</p>
                <p className="text-[10px] text-slate-500 font-bold uppercase tracking-wider mt-0.5">
                  {phaseHint} · #{order.id.slice(-4)}
                </p>
              </div>
            </div>
            <button
              type="button"
              onClick={onStopNav}
              className="p-2 rounded-xl bg-slate-800 text-slate-400 hover:text-white shrink-0"
              aria-label="End navigation view"
            >
              <X size={16} />
            </button>
          </div>

          <div className="mt-3 flex items-center gap-2">
            <div className="flex-1 flex items-center gap-4 px-3 py-2.5 rounded-xl bg-slate-900/80 border border-slate-800">
              <div>
                <p className="text-[8px] font-black uppercase tracking-widest text-slate-500">ETA</p>
                <p className="text-lg font-black text-white leading-none">{route?.eta || '—'}</p>
              </div>
              <div className="w-px h-8 bg-slate-700" />
              <div>
                <p className="text-[8px] font-black uppercase tracking-widest text-slate-500">Distance</p>
                <p className="text-lg font-black text-white leading-none">{route?.distance || '—'}</p>
              </div>
            </div>
          </div>

          <div className="mt-3 grid grid-cols-2 gap-2">
            <button
              type="button"
              onClick={() =>
                openTurnByTurnNavigation(
                  { ...navTarget, label: targetLabel },
                  riderOrigin ?? null
                )
              }
              className="flex items-center justify-center gap-2 py-3 rounded-xl bg-brand-green text-slate-950 font-black text-[10px] uppercase tracking-widest"
            >
              <MapPin size={14} /> Open in Google Maps
            </button>
            {customerPhone ? (
              <a
                href={`tel:${customerPhone}`}
                className="flex items-center justify-center gap-2 py-3 rounded-xl bg-brand-blue font-black text-[10px] uppercase tracking-widest text-white"
              >
                <Phone size={14} /> Call
              </a>
            ) : (
              <div className="py-3 rounded-xl bg-slate-900 border border-slate-800 text-center text-[10px] font-bold text-slate-600 uppercase tracking-widest">
                Trip active
              </div>
            )}
          </div>
        </div>
      </div>
    </motion.div>
  );
}
