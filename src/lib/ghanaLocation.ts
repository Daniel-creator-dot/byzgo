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

export function getGoogleMapsApiKey(): string {
  return import.meta.env.VITE_GOOGLE_MAPS_API_KEY || import.meta.env.GOOGLE_MAPS_API_KEY || '';
}

export async function reverseGeocodeGhana(lat: number, lng: number): Promise<string | null> {
  const key = getGoogleMapsApiKey();
  if (!key) return null;
  try {
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('latlng', `${lat},${lng}`);
    url.searchParams.set('key', key);
    url.searchParams.set('region', 'gh');
    url.searchParams.set('language', 'en');
    const res = await fetch(url.toString());
    const data = await res.json();
    const results = data.results as Array<{ formatted_address: string }> | undefined;
    if (!results?.length) return null;
    const inGhana = results.find((r) =>
      /ghana/i.test(r.formatted_address)
    );
    return (inGhana || results[0]).formatted_address;
  } catch {
    return null;
  }
}

export function detectCurrentLocation(): Promise<LocationValue | null> {
  if (!('geolocation' in navigator)) return Promise.resolve(null);

  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      async (pos) => {
        const lat = pos.coords.latitude;
        const lng = pos.coords.longitude;
        const address =
          (await reverseGeocodeGhana(lat, lng)) ||
          `${lat.toFixed(5)}, ${lng.toFixed(5)}`;
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
