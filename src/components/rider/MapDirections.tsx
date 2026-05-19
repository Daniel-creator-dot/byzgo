import { useEffect, useRef, useState } from 'react';
import { useMap, useMapsLibrary } from '@vis.gl/react-google-maps';

export function MapDirections({
  origin,
  destination,
  onETAUpdate,
}: {
  origin: google.maps.LatLngLiteral;
  destination: google.maps.LatLngLiteral;
  onETAUpdate?: (eta: string) => void;
}) {
  const map = useMap();
  const routesLib = useMapsLibrary('routes');
  const [directionsService, setDirectionsService] = useState<google.maps.DirectionsService | null>(null);
  const [directionsRenderer, setDirectionsRenderer] = useState<google.maps.DirectionsRenderer | null>(null);
  const lastOriginRef = useRef(origin);

  useEffect(() => {
    if (!routesLib || !map) return;
    setDirectionsService(new routesLib.DirectionsService());
    setDirectionsRenderer(
      new routesLib.DirectionsRenderer({
        map,
        suppressMarkers: true,
        polylineOptions: { strokeColor: '#10b981', strokeWeight: 6, strokeOpacity: 0.9 },
      })
    );
  }, [routesLib, map]);

  useEffect(() => {
    if (!directionsService || !directionsRenderer) return;
    const dist = Math.hypot(origin.lat - lastOriginRef.current.lat, origin.lng - lastOriginRef.current.lng);
    if (dist < 0.0001 && lastOriginRef.current.lat !== 0) return;

    directionsService
      .route({
        origin,
        destination,
        travelMode: google.maps.TravelMode.DRIVING,
      })
      .then((response) => {
        directionsRenderer.setDirections(response);
        const leg = response.routes[0]?.legs[0];
        if (onETAUpdate && leg?.duration) onETAUpdate(leg.duration.text);
        lastOriginRef.current = origin;
      })
      .catch(() => {});
  }, [directionsService, directionsRenderer, origin, destination, onETAUpdate]);

  return null;
}
