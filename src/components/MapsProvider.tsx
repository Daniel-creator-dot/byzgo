import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from 'react';
import { APIProvider } from '@vis.gl/react-google-maps';
import {
  checkMapsApiHealth,
  getGoogleMapsApiKey,
  getGoogleMapsKeyHint,
  hasGoogleMapsKey,
  onGoogleMapsAuthFailure,
} from '../lib/googleMaps';
import { MapsUnavailableNotice } from './MapsUnavailableNotice';

type MapsContextValue = {
  available: boolean;
  mapsWarning?: string;
  keyHint: string;
  recheckMaps: () => void;
  checking: boolean;
};

const MapsContext = createContext<MapsContextValue>({
  available: false,
  keyHint: '',
  recheckMaps: () => {},
  checking: false,
});

export function useMapsAvailable(): boolean {
  return useContext(MapsContext).available;
}

export function useMapsStatus(): MapsContextValue {
  return useContext(MapsContext);
}

const MAP_LIBRARIES: ('places' | 'routes')[] = ['places', 'routes'];

export function MapsProvider({ children }: { children: ReactNode }) {
  const [authFailed, setAuthFailed] = useState(false);
  const [health, setHealth] = useState<{ ok: boolean; message?: string } | null>(null);
  const [checking, setChecking] = useState(false);

  const recheckMaps = useCallback(() => {
    if (!hasGoogleMapsKey()) {
      setHealth({ ok: false, message: 'Google Maps API key is missing from .env.local' });
      return;
    }
    setChecking(true);
    checkMapsApiHealth()
      .then(setHealth)
      .finally(() => setChecking(false));
  }, []);

  useEffect(() => onGoogleMapsAuthFailure(() => setAuthFailed(true)), []);

  useEffect(() => {
    recheckMaps();
  }, [recheckMaps]);

  const keyHint = getGoogleMapsKeyHint();
  const mapsWarning =
    health && !health.ok
      ? `${health.message || 'Maps API check failed'} (key ${keyHint})`
      : authFailed
        ? `Google Maps rejected key ${keyHint}. Check billing and HTTP referrer http://localhost:5173/*`
        : undefined;

  // Load the JS map when we have a key — REST geocode check can fail even if Maps JS works
  const available = hasGoogleMapsKey() && !authFailed;

  const ctx: MapsContextValue = { available, mapsWarning, keyHint, recheckMaps, checking };

  if (!available) {
    return (
      <MapsContext.Provider value={ctx}>
        {children}
      </MapsContext.Provider>
    );
  }

  return (
    <MapsContext.Provider value={ctx}>
      <APIProvider
        apiKey={getGoogleMapsApiKey()}
        region="GH"
        language="en"
        libraries={MAP_LIBRARIES}
      >
        {children}
      </APIProvider>
    </MapsContext.Provider>
  );
}

export function MapsHealthBanner({ compact }: { compact?: boolean }) {
  const { mapsWarning, recheckMaps, checking, keyHint } = useMapsStatus();
  if (!mapsWarning) return null;
  return (
    <div className="space-y-2">
      <MapsUnavailableNotice
        message={`${mapsWarning}. In Google Cloud → Credentials, open the key ending in ${keyHint} and confirm billing + APIs are on that same project.`}
        compact={compact}
      />
      <button
        type="button"
        onClick={recheckMaps}
        disabled={checking}
        className="w-full py-2 rounded-xl bg-slate-800 border border-slate-700 text-[10px] font-black uppercase tracking-widest text-slate-300 hover:text-white disabled:opacity-50"
      >
        {checking ? 'Checking…' : 'Retry maps check'}
      </button>
    </div>
  );
}
