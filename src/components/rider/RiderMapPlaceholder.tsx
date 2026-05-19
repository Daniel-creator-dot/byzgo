import { MapPin, Navigation } from 'lucide-react';
import { motion } from 'motion/react';

export function RiderMapPlaceholder({
  riderPos,
  navigatingTo,
  eta,
}: {
  riderPos: { lat: number; lng: number };
  navigatingTo: { lat: number; lng: number } | null;
  eta?: string;
}) {
  return (
    <motion.div className="w-full h-full bg-slate-950 relative overflow-hidden">
      <div
        className="absolute inset-0 opacity-30"
        style={{
          backgroundImage:
            'linear-gradient(rgba(16,185,129,0.15) 1px, transparent 1px), linear-gradient(90deg, rgba(16,185,129,0.15) 1px, transparent 1px)',
          backgroundSize: '28px 28px',
        }}
      />
      <div className="absolute inset-0 flex flex-col items-center justify-center p-6 text-center">
        <div className="w-14 h-14 rounded-full bg-brand-green/20 border-2 border-brand-green flex items-center justify-center mb-4">
          <MapPin className="text-brand-green" size={28} />
        </div>
        <p className="text-sm font-black text-white uppercase tracking-widest">Live map</p>
        <p className="text-xs text-slate-400 mt-2 max-w-[240px] leading-relaxed">
          Map preview unavailable. You can still accept rides and use navigation below.
        </p>
        <p className="text-[10px] font-mono text-slate-500 mt-4">
          {riderPos.lat.toFixed(4)}, {riderPos.lng.toFixed(4)}
        </p>
      </div>
      {navigatingTo && (
        <div className="absolute top-3 left-3 right-3 flex items-center gap-2 p-3 rounded-2xl bg-slate-900/95 backdrop-blur border border-slate-700 shadow-xl">
          <Navigation className="text-brand-green shrink-0" size={18} />
          <motion.div className="min-w-0 text-left">
            <p className="text-[9px] font-black uppercase tracking-widest text-brand-green">Navigating</p>
            <p className="text-xs font-bold truncate">{eta || 'Open in Google Maps from the ride card'}</p>
          </motion.div>
        </div>
      )}
    </motion.div>
  );
}
