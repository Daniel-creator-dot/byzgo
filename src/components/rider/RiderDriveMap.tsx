import { Map, Marker, useMapsLibrary } from '@vis.gl/react-google-maps';
import type { Order } from '../../types';
import { CLEAN_MAP_STYLE } from '../../lib/mapStyles';
import { MapDirections } from './MapDirections';

export function RiderDriveMap({
  riderPos,
  navigatingTo,
  isOnline,
  availableOrders,
  getPickupCoords,
  onETAUpdate,
}: {
  riderPos: { lat: number; lng: number };
  navigatingTo: { lat: number; lng: number } | null;
  isOnline: boolean;
  availableOrders: Order[];
  getPickupCoords: (order: Order) => { lat: number; lng: number } | null;
  onETAUpdate: (eta: string) => void;
}) {
  const mapsLib = useMapsLibrary('core');

  return (
    <Map
      defaultCenter={riderPos}
      defaultZoom={15}
      gestureHandling="greedy"
      disableDefaultUI
      styles={CLEAN_MAP_STYLE}
      className="w-full h-full"
    >
      <Marker
        position={riderPos}
        icon={
          mapsLib
            ? {
                path: google.maps.SymbolPath.CIRCLE,
                scale: 10,
                fillColor: '#10b981',
                fillOpacity: 1,
                strokeColor: '#fff',
                strokeWeight: 3,
              }
            : undefined
        }
      />
      {navigatingTo && (
        <>
          <MapDirections origin={riderPos} destination={navigatingTo} onETAUpdate={onETAUpdate} />
          <Marker position={navigatingTo} />
        </>
      )}
      {!navigatingTo &&
        isOnline &&
        availableOrders.map((order) => {
          const pickup = getPickupCoords(order);
          if (!pickup) return null;
          return (
            <Marker
              key={order.id}
              position={pickup}
              icon={
                mapsLib
                  ? {
                      path: google.maps.SymbolPath.CIRCLE,
                      scale: 7,
                      fillColor: '#0ea5e9',
                      fillOpacity: 1,
                      strokeColor: '#fff',
                      strokeWeight: 2,
                    }
                  : undefined
              }
            />
          );
        })}
    </Map>
  );
}
