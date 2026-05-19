import { Fragment, useMemo } from 'react';
import { Map, Marker, useMapsLibrary } from '@vis.gl/react-google-maps';
import type { Order } from '../../types';
import { RIDER_NAV_MAP_STYLE } from '../../lib/mapStyles';
import type { LatLng, TripPhase, TripStop } from '../../lib/riderTrip';
import { MapDirections, type RouteSummary } from './MapDirections';
import { MapFollowCamera } from './MapFollowCamera';

function RiderBikeMarker({
  position,
  heading,
}: {
  position: LatLng;
  heading: number | null;
}) {
  const mapsLib = useMapsLibrary('core');
  const icon = useMemo(() => {
    if (!mapsLib) return undefined;
    return {
      path: google.maps.SymbolPath.FORWARD_CLOSED_ARROW,
      scale: 5.5,
      fillColor: '#10b981',
      fillOpacity: 1,
      strokeColor: '#ffffff',
      strokeWeight: 2.5,
      rotation: heading ?? 0,
    };
  }, [mapsLib, heading]);

  return <Marker position={position} icon={icon} zIndex={100} />;
}

function StopMarker({
  position,
  color,
  scale,
  label,
}: {
  position: LatLng;
  color: string;
  scale: number;
  label?: string;
}) {
  const mapsLib = useMapsLibrary('core');
  return (
    <>
      <Marker
        position={position}
        title={label}
        icon={
          mapsLib
            ? {
                path: google.maps.SymbolPath.CIRCLE,
                scale,
                fillColor: color,
                fillOpacity: 1,
                strokeColor: '#ffffff',
                strokeWeight: 3,
              }
            : undefined
        }
        zIndex={80}
      />
    </>
  );
}

export function RiderDriveMap({
  riderPos,
  riderHeading,
  navTarget,
  tripPhase,
  pickup,
  dropoff,
  isNavigating,
  isOnline,
  availableOrders,
  getPickupCoords,
  onRouteUpdate,
}: {
  riderPos: LatLng;
  riderHeading: number | null;
  navTarget: LatLng | null;
  tripPhase: TripPhase | null;
  pickup: TripStop | null;
  dropoff: TripStop | null;
  isNavigating: boolean;
  isOnline: boolean;
  availableOrders: Order[];
  getPickupCoords: (order: Order) => LatLng | null;
  onRouteUpdate: (route: RouteSummary) => void;
}) {
  const showRoute = Boolean(isNavigating && navTarget);

  return (
    <Map
      defaultCenter={riderPos}
      defaultZoom={16}
      gestureHandling="greedy"
      disableDefaultUI
      styles={RIDER_NAV_MAP_STYLE}
      className="w-full h-full"
    >
      <MapFollowCamera position={riderPos} enabled={isNavigating} zoom={17} />

      <RiderBikeMarker position={riderPos} heading={riderHeading} />

      {showRoute && navTarget && (
        <>
          <MapDirections
            origin={riderPos}
            destination={navTarget}
            onRouteUpdate={onRouteUpdate}
            strokeColor={tripPhase === 'to_dropoff' ? '#38bdf8' : '#10b981'}
          />
          <StopMarker
            position={navTarget}
            color={tripPhase === 'to_dropoff' ? '#38bdf8' : '#fbbf24'}
            scale={9}
            label={tripPhase === 'to_dropoff' ? 'Drop-off' : 'Pickup'}
          />
        </>
      )}

      {!showRoute && pickup && (
        <StopMarker position={pickup} color="#fbbf24" scale={7} label="Pickup" />
      )}
      {!showRoute && dropoff && (
        <StopMarker position={dropoff} color="#38bdf8" scale={7} label="Drop-off" />
      )}

      {!showRoute &&
        isOnline &&
        availableOrders.map((order) => {
          const p = getPickupCoords(order);
          if (!p) return null;
          return (
            <Fragment key={order.id}>
              <StopMarker position={p} color="#0ea5e9" scale={6} label="Request" />
            </Fragment>
          );
        })}
    </Map>
  );
}
