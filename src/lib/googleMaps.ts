/** Google Maps API key and auth-failure handling for BytzGo */

const authFailureListeners = new Set<() => void>();

if (typeof window !== 'undefined') {
  const w = window as Window & { gm_authFailure?: () => void };
  const previous = w.gm_authFailure;
  w.gm_authFailure = () => {
    authFailureListeners.forEach((fn) => fn());
    previous?.();
  };
}

export function getGoogleMapsApiKey(): string {
  return (
    import.meta.env.VITE_GOOGLE_MAPS_API_KEY ||
    import.meta.env.GOOGLE_MAPS_API_KEY ||
    (typeof process !== 'undefined' ? process.env.GOOGLE_MAPS_API_KEY : '') ||
    ''
  ).trim();
}

export function hasGoogleMapsKey(): boolean {
  const key = getGoogleMapsApiKey();
  return key.length >= 20 && key.startsWith('AIza');
}

export function getGoogleMapsKeyHint(): string {
  const key = getGoogleMapsApiKey();
  if (!key) return 'no key in .env.local';
  return `…${key.slice(-6)}`;
}

export function onGoogleMapsAuthFailure(callback: () => void): () => void {
  authFailureListeners.add(callback);
  return () => authFailureListeners.delete(callback);
}

/** One-shot check — catches billing disabled / key invalid before loading the map widget. */
export async function checkMapsApiHealth(): Promise<{ ok: boolean; message?: string }> {
  const key = getGoogleMapsApiKey();
  if (!hasGoogleMapsKey()) {
    return {
      ok: false,
      message: 'Add VITE_GOOGLE_MAPS_API_KEY to .env.local (must start with AIza…).',
    };
  }
  try {
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('address', 'Accra, Ghana');
    url.searchParams.set('key', key);
    const res = await fetch(url);
    const data = (await res.json()) as { status?: string; error_message?: string };
    if (data.status === 'OK') return { ok: true };
    return {
      ok: false,
      message:
        data.error_message ||
        (data.status === 'REQUEST_DENIED'
          ? 'Enable billing and Geocoding API on your Google Cloud project.'
          : `Google Maps API: ${data.status || 'error'}`),
    };
  } catch {
    return { ok: false, message: 'Could not reach Google Maps API.' };
  }
}
