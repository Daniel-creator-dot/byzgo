/** Ghana defaults for BytzGo maps, search, and geolocation */

export const GHANA_CENTER = { lat: 5.6037, lng: -0.1870 }; // Accra

/** Southwest / northeast corners for Places bias */
export const GHANA_BOUNDS = {
  south: 4.62,
  west: -3.26,
  north: 11.18,
  east: 1.19,
};

export type LocationValue = { address: string; lat: number; lng: number };

export function isInGhanaBounds(lat: number, lng: number): boolean {
  return (
    lat >= GHANA_BOUNDS.south &&
    lat <= GHANA_BOUNDS.north &&
    lng >= GHANA_BOUNDS.west &&
    lng <= GHANA_BOUNDS.east
  );
}

import { getGoogleMapsApiKey } from './googleMaps';

export { getGoogleMapsApiKey };

const PREFERRED_GEOCODE_TYPES = [
  'street_address',
  'premise',
  'route',
  'establishment',
  'point_of_interest',
  'sublocality',
  'neighborhood',
  'locality',
  'administrative_area_level_2',
  'administrative_area_level_1',
];

type GeocodeResult = { formatted_address: string; types?: string[] };

function pickBestGeocodeResult(results: GeocodeResult[]): string | null {
  if (!results.length) return null;
  for (const type of PREFERRED_GEOCODE_TYPES) {
    const hit = results.find((r) => r.types?.includes(type));
    if (hit?.formatted_address) return hit.formatted_address;
  }
  const inGhana = results.find((r) => /ghana/i.test(r.formatted_address));
  return (inGhana || results[0]).formatted_address || null;
}

/** True when the string is only lat,lng (what we want to replace in the UI). */
export function looksLikeCoordinates(address: string): boolean {
  if (!address?.trim()) return false;
  return /^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$/.test(address.trim());
}

function reverseGeocodeWithMapsJs(lat: number, lng: number): Promise<string | null> {
  return new Promise((resolve) => {
    if (typeof google === 'undefined' || !google.maps?.Geocoder) {
      resolve(null);
      return;
    }
    const geocoder = new google.maps.Geocoder();
    geocoder.geocode({ location: { lat, lng } }, (results, status) => {
      if (status !== 'OK' || !results?.length) {
        resolve(null);
        return;
      }
      resolve(pickBestGeocodeResult(results as GeocodeResult[]));
    });
  });
}

export async function reverseGeocodeGhana(lat: number, lng: number): Promise<string | null> {
  const key = getGoogleMapsApiKey();
  if (!key) return reverseGeocodeWithMapsJs(lat, lng);
  try {
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('latlng', `${lat},${lng}`);
    url.searchParams.set('key', key);
    url.searchParams.set('region', 'gh');
    url.searchParams.set('language', 'en');
    const res = await fetch(url.toString());
    const data = await res.json();
    if (data.status === 'OK' && data.results?.length) {
      const label = pickBestGeocodeResult(data.results as GeocodeResult[]);
      if (label) return label;
    }
  } catch {
    /* try Maps JS below */
  }
  return reverseGeocodeWithMapsJs(lat, lng);
}

/** Human-readable label for a pin; never returns raw coordinates. */
export async function resolveAddressLabel(
  lat: number,
  lng: number,
  existing?: string
): Promise<string> {
  if (existing?.trim() && !looksLikeCoordinates(existing)) return existing.trim();
  const label = (await reverseGeocodeGhana(lat, lng)) || (await reverseGeocodeWithMapsJs(lat, lng));
  if (label) return label;
  return 'Current location';
}

/** Pickup: GPS first, then saved profile address. Works without Maps API for coords. */
export async function resolvePickupLocation(options: {
  userLat?: number;
  userLng?: number;
  userAddress?: string;
}): Promise<LocationValue | null> {
  const gps = await detectCurrentLocation();
  if (gps) return gps;

  const { userLat, userLng, userAddress } = options;
  if (userLat && userLng && Math.abs(userLat) > 0.001 && Math.abs(userLng) > 0.001) {
    const address = await resolveAddressLabel(userLat, userLng, userAddress);
    return { lat: userLat, lng: userLng, address };
  }
  return null;
}

export function hasValidCoords(loc: { lat?: number; lng?: number } | null | undefined): boolean {
  return Boolean(loc?.lat && loc?.lng && Math.abs(loc.lat) > 0.001 && Math.abs(loc.lng) > 0.001);
}

export function detectCurrentLocation(): Promise<LocationValue | null> {
  if (!('geolocation' in navigator)) return Promise.resolve(null);

  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const lat = pos.coords.latitude;
        const lng = pos.coords.longitude;
        const address = await resolveAddressLabel(lat, lng);
        resolve({ lat, lng, address });
      },
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    );
  });
}

/** Options for google.maps.places.Autocomplete (Ghana only) */
export function ghanaPlacesAutocompleteOptions(
  maps: typeof google.maps
): google.maps.places.AutocompleteOptions {
  const bounds = new maps.LatLngBounds(
    { lat: GHANA_BOUNDS.south, lng: GHANA_BOUNDS.west },
    { lat: GHANA_BOUNDS.north, lng: GHANA_BOUNDS.east }
  );
  return {
    fields: ['formatted_address', 'geometry', 'name'],
    componentRestrictions: { country: 'gh' },
    bounds,
    strictBounds: false,
  };
}
