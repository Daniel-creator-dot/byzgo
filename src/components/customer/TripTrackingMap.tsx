import { useEffect, useState } from 'react';
import { Map, Marker, useMap, useMapsLibrary } from '@vis.gl/react-google-maps';
import { motion } from 'motion/react';
import { RIDER_NAV_MAP_STYLE } from '../../lib/mapStyles';
import { MapDirections } from '../rider/MapDirections';
import { MapFollowCamera } from '../rider/MapFollowCamera';

export function TripTrackingMap({
  riderLocation,
  pickupLocation,
  destination,
  orderStatus,
  followRider = false,
  onEtaChange,
  showEtaBadge = true,
}: {
  riderLocation: { lat: number; lng: number } | null;
  pickupLocation: { lat: number; lng: number };
  destination: { lat: number; lng: number };
  orderStatus: string;
  followRider?: boolean;
  onEtaChange?: (eta: string) => void;
  showEtaBadge?: boolean;
}) {
  const map = useMap();
  const mapsLib = useMapsLibrary('core');
  const [eta, setEta] = useState('…');

  useEffect(() => {
    onEtaChange?.(eta);
  }, [eta, onEtaChange]);

  useEffect(() => {
    if (!map || !mapsLib || followRider) return;
    const bounds = new mapsLib.LatLngBounds();
    if (riderLocation) bounds.extend(riderLocation);
    bounds.extend(pickupLocation);
    bounds.extend(destination);
    map.fitBounds(bounds, { top: 100, right: 48, bottom: 200, left: 48 });
  }, [map, mapsLib, riderLocation, pickupLocation, destination, followRider]);

  if (!mapsLib) {
    return (
      <motion.div className="absolute inset-0 bg-slate-900 animate-pulse flex items-center justify-center text-[10px] font-black uppercase tracking-widest text-slate-500">
        Loading map…
      </motion.div>
    );
  }

  const routeDest = orderStatus === 'picked_up' || orderStatus === 'arrived' ? destination : pickupLocation;
  const mapCenter = riderLocation ?? pickupLocation;

  return (
    <>
      <Map
        defaultCenter={mapCenter}
        defaultZoom={15}
        gestureHandling="greedy"
        disableDefaultUI
        className="absolute inset-0 w-full h-full"
        styles={RIDER_NAV_MAP_STYLE}
      >
        {riderLocation && followRider && (
          <MapFollowCamera position={riderLocation} enabled zoom={16} />
        )}

        {riderLocation && (
          <Marker
            position={riderLocation}
            title="Your driver"
            zIndex={100}
            icon={{
              url: '/rider-icon.png',
              scaledSize: new mapsLib.Size(48, 48),
              anchor: new mapsLib.Point(24, 24),
            }}
          />
        )}

        <Marker
          position={pickupLocation}
          title="Pickup"
          zIndex={50}
          icon={{
            path: mapsLib.SymbolPath.CIRCLE,
            scale: 10,
            fillColor: '#3b82f6',
            fillOpacity: 1,
            strokeColor: '#ffffff',
            strokeWeight: 3,
          }}
        />

        <Marker
          position={destination}
          title="Drop-off"
          zIndex={50}
          icon={{
            path: mapsLib.SymbolPath.CIRCLE,
            scale: 10,
            fillColor: '#22c55e',
            fillOpacity: 1,
            strokeColor: '#ffffff',
            strokeWeight: 3,
          }}
        />

        {riderLocation && (
          <MapDirections
            origin={riderLocation}
            destination={routeDest}
            strokeColor="#22c55e"
            onRouteUpdate={(s) => setEta(s.eta)}
          />
        )}
      </Map>

      {showEtaBadge && riderLocation && (
        <motion.div className="absolute bottom-4 left-4 z-10 bg-slate-950/90 text-white px-3 py-2 rounded-xl border border-white/10 shadow-xl flex items-center gap-2">
          <motion.div className="w-2 h-2 bg-brand-green rounded-full animate-ping" />
          <div className="flex flex-col">
            <span className="text-[8px] font-black uppercase tracking-widest text-white/50">ETA</span>
            <span className="text-xs font-black">{eta}</span>
          </div>
        </motion.div>
      )}
    </>
  );
}
