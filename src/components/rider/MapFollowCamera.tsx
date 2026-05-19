import { useEffect } from 'react';
import { useMap } from '@vis.gl/react-google-maps';

/** Keeps the map centered on the rider during active navigation */
export function MapFollowCamera({
  position,
  enabled,
  zoom = 16,
}: {
  position: { lat: number; lng: number };
  enabled: boolean;
  zoom?: number;
}) {
  const map = useMap();

  useEffect(() => {
    if (!map || !enabled) return;
    map.panTo(position);
    const z = map.getZoom();
    if (z === undefined || z < 14) map.setZoom(zoom);
  }, [map, position.lat, position.lng, enabled, zoom]);

  return null;
}
