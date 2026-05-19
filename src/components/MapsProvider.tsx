import { createContext, useContext, useEffect, useState, type ReactNode } from 'react';
import { APIProvider } from '@vis.gl/react-google-maps';
import { getGoogleMapsApiKey, hasGoogleMapsKey, onGoogleMapsAuthFailure } from '../lib/googleMaps';

const MapsContext = createContext({ available: false });

export function useMapsAvailable(): boolean {
  return useContext(MapsContext).available;
}

export function MapsProvider({ children }: { children: ReactNode }) {
  const [authFailed, setAuthFailed] = useState(false);
  const available = hasGoogleMapsKey() && !authFailed;

  useEffect(() => onGoogleMapsAuthFailure(() => setAuthFailed(true)), []);

  if (!available) {
    return <MapsContext.Provider value={{ available: false }}>{children}</MapsContext.Provider>;
  }

  return (
    <MapsContext.Provider value={{ available: true }}>
      <APIProvider apiKey={getGoogleMapsApiKey()} region="GH" language="en">
        {children}
      </APIProvider>
    </MapsContext.Provider>
  );
}
