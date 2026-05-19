import { useEffect, useState } from 'react';
import { Map, Marker, useMap, useMapsLibrary } from '@vis.gl/react-google-maps';
import { motion } from 'motion/react';
import { CLEAN_MAP_STYLE } from '../../lib/mapStyles';
import { MapDirections } from '../rider/MapDirections';

export function TripTrackingMap({
  riderLocation,
  pickupLocation,
  destination,
  orderStatus,
}: {
  riderLocation: { lat: number; lng: number } | null;
  pickupLocation: { lat: number; lng: number };
  destination: { lat: number; lng: number };
  orderStatus: string;
}) {
  const map = useMap();
  const mapsLib = useMapsLibrary('core');
  const [eta, setEta] = useState('Calculating...');

  useEffect(() => {
    if (map && mapsLib) {
      const bounds = new mapsLib.LatLngBounds();
      if (riderLocation) bounds.extend(riderLocation);
      bounds.extend(pickupLocation);
      bounds.extend(destination);
      map.fitBounds(bounds, 80);
    }
  }, [map, mapsLib, riderLocation, pickupLocation, destination]);

  if (!mapsLib) {
    return (
      <motion.div className="w-full h-full bg-slate-800 animate-pulse flex items-center justify-center text-[10px] font-black uppercase tracking-widest text-slate-500">
        Loading map...
      </motion.div>
    );
  }

  const routeDest = orderStatus === 'picked_up' ? destination : pickupLocation;

  return (
    <>
      <Map
        defaultCenter={pickupLocation}
        defaultZoom={15}
        gestureHandling="greedy"
        disableDefaultUI
        className="w-full h-full"
        styles={CLEAN_MAP_STYLE}
      >
        {riderLocation && (
          <Marker
            position={riderLocation}
            title="Driver"
            icon={{
              url: '/rider-icon.png',
              scaledSize: new mapsLib.Size(40, 40),
              anchor: new mapsLib.Point(20, 20),
            }}
          />
        )}
        <Marker
          position={pickupLocation}
          title="Pickup"
          icon={{
            url: 'https://cdn-icons-png.flaticon.com/512/606/606363.png',
            scaledSize: new mapsLib.Size(32, 32),
          }}
        />
        <Marker
          position={destination}
          title="Drop-off"
          icon={{
            url: 'https://cdn-icons-png.flaticon.com/512/1216/1216844.png',
            scaledSize: new mapsLib.Size(32, 32),
          }}
        />
        {riderLocation && (
          <MapDirections
            origin={riderLocation}
            destination={routeDest}
            onRouteUpdate={(s) => setEta(s.eta)}
          />
        )}
      </Map>
      <motion.div className="absolute bottom-3 left-3 bg-slate-900/90 text-white px-3 py-2 rounded-xl border border-white/10 shadow-xl flex items-center gap-2">
        <motion.div className="w-2 h-2 bg-brand-green rounded-full animate-ping" />
        <div className="flex flex-col">
          <span className="text-[8px] font-black uppercase tracking-widest text-white/50">ETA</span>
          <span className="text-xs font-black">{eta}</span>
        </div>
      </motion.div>
    </>
  );
}
