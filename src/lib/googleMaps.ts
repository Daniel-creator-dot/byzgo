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

export function onGoogleMapsAuthFailure(callback: () => void): () => void {
  authFailureListeners.add(callback);
  return () => authFailureListeners.delete(callback);
}
