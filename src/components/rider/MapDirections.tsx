import { useEffect, useRef, useState } from 'react';
import { useMap, useMapsLibrary } from '@vis.gl/react-google-maps';

export type RouteSummary = {
  eta: string;
  distance: string;
};

export function MapDirections({
  origin,
  destination,
  onRouteUpdate,
  strokeColor = '#10b981',
}: {
  origin: google.maps.LatLngLiteral;
  destination: google.maps.LatLngLiteral;
  onRouteUpdate?: (summary: RouteSummary) => void;
  strokeColor?: string;
}) {
  const map = useMap();
  const routesLib = useMapsLibrary('routes');
  const [directionsService, setDirectionsService] = useState<google.maps.DirectionsService | null>(null);
  const [directionsRenderer, setDirectionsRenderer] = useState<google.maps.DirectionsRenderer | null>(null);
  const lastOriginRef = useRef(origin);
  const lastFetchRef = useRef(0);

  useEffect(() => {
    if (!routesLib || !map) return;
    const renderer = new routesLib.DirectionsRenderer({
      map,
      suppressMarkers: true,
      preserveViewport: true,
      polylineOptions: {
        strokeColor,
        strokeWeight: 7,
        strokeOpacity: 0.95,
        zIndex: 50,
      },
    });
    setDirectionsService(new routesLib.DirectionsService());
    setDirectionsRenderer(renderer);
    return () => renderer.setMap(null);
  }, [routesLib, map, strokeColor]);

  useEffect(() => {
    if (!directionsService || !directionsRenderer || !map) return;

    const distMoved = Math.hypot(
      origin.lat - lastOriginRef.current.lat,
      origin.lng - lastOriginRef.current.lng
    );
    const now = Date.now();
    const shouldRefresh =
      distMoved > 0.00025 || now - lastFetchRef.current > 20000 || lastOriginRef.current.lat === 0;

    if (!shouldRefresh) return;

    directionsService
      .route({
        origin,
        destination,
        travelMode: google.maps.TravelMode.DRIVING,
        region: 'GH',
      })
      .then((response) => {
        directionsRenderer.setDirections(response);
        const leg = response.routes[0]?.legs[0];
        if (leg?.duration && leg?.distance) {
          onRouteUpdate?.({
            eta: leg.duration.text,
            distance: leg.distance.text,
          });
        }
        const bounds = response.routes[0]?.bounds;
        if (bounds && distMoved > 0.001) {
          map.fitBounds(bounds, { top: 100, right: 48, bottom: 280, left: 48 });
        }
        lastOriginRef.current = origin;
        lastFetchRef.current = now;
      })
      .catch(() => {});
  }, [directionsService, directionsRenderer, map, origin, destination, onRouteUpdate]);

  return null;
}
