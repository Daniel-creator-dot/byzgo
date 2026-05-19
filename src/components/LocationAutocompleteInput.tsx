import { useEffect, useRef, useState, type ComponentType } from 'react';
import { useMapsLibrary } from '@vis.gl/react-google-maps';
import { LocateFixed } from 'lucide-react';
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';
import { detectCurrentLocation, ghanaPlacesAutocompleteOptions } from '../lib/ghanaLocation';
import { useMapsAvailable } from './MapsProvider';
import { LoadingIndicator } from './UI';

function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

export function LocationAutocompleteInput({
  placeholder,
  icon: Icon,
  value,
  onChange,
  onMapClick,
  showUseMyLocation = true,
  showMapButton = true,
  onLocationError,
  variant = 'default',
  hideIcon = false,
  autoDetectOnMount = false,
}: {
  placeholder: string;
  icon: ComponentType<{ size?: number; className?: string }>;
  value: string;
  onChange: (val: { address: string; lat: number; lng: number }) => void;
  onMapClick: () => void;
  showUseMyLocation?: boolean;
  showMapButton?: boolean;
  onLocationError?: (message: string) => void;
  variant?: 'default' | 'dark';
  hideIcon?: boolean;
  autoDetectOnMount?: boolean;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  const mapsAvailable = useMapsAvailable();
  const places = useMapsLibrary('places');
  const onChangeRef = useRef(onChange);
  const autoDetectRan = useRef(false);
  const [locating, setLocating] = useState(false);

  useEffect(() => {
    onChangeRef.current = onChange;
  }, [onChange]);

  useEffect(() => {
    if (!mapsAvailable || !places || !inputRef.current || typeof google === 'undefined') return;
    const autocomplete = new places.Autocomplete(
      inputRef.current,
      ghanaPlacesAutocompleteOptions(google.maps)
    );

    const listener = autocomplete.addListener('place_changed', () => {
      const place = autocomplete.getPlace();
      if (place.geometry?.location) {
        onChangeRef.current({
          address: place.formatted_address || place.name || '',
          lat: place.geometry.location.lat(),
          lng: place.geometry.location.lng(),
        });
      }
    });

    return () => {
      if (listener) google.maps.event.removeListener(listener);
    };
  }, [mapsAvailable, places]);

  const handleUseMyLocation = async () => {
    setLocating(true);
    const loc = await detectCurrentLocation();
    setLocating(false);
    if (loc) onChangeRef.current(loc);
    else onLocationError?.('Could not get your location. Allow location access in your browser.');
  };

  useEffect(() => {
    if (!autoDetectOnMount || autoDetectRan.current) return;
    if (value?.trim()) return;
    autoDetectRan.current = true;
    void handleUseMyLocation();
  }, [autoDetectOnMount, value]);

  const inputPadLeft = hideIcon ? 'pl-3' : 'pl-12';

  return (
    <div className="relative flex items-center w-full">
      {!hideIcon && (
        <Icon size={18} className={cn('absolute left-4 z-10', variant === 'dark' ? 'text-slate-500' : 'text-slate-300')} />
      )}
      <input
        ref={inputRef}
        required
        type="text"
        placeholder={placeholder}
        className={cn(
          'w-full font-bold text-sm focus:outline-none transition-all rounded-2xl',
          variant === 'dark'
            ? 'bg-transparent border-0 py-3 text-white placeholder:text-slate-500 focus:ring-0'
            : 'bg-slate-50 border border-slate-100 py-4 focus:border-brand-blue',
          inputPadLeft,
          showUseMyLocation && showMapButton ? 'pr-28' : showUseMyLocation || showMapButton ? 'pr-20' : 'pr-4'
        )}
        value={value}
        onChange={(e) => onChange({ address: e.target.value, lat: 0, lng: 0 })}
      />
      {showUseMyLocation && (
        <button
          type="button"
          title="Use my location"
          disabled={locating}
          onClick={handleUseMyLocation}
          className={cn(
            'absolute z-10 p-2 rounded-xl transition-all disabled:opacity-50',
            variant === 'dark'
              ? 'bg-slate-800 text-brand-green hover:bg-slate-700'
              : 'bg-slate-100 text-brand-blue hover:bg-brand-blue/10',
            showMapButton ? 'right-14' : 'right-2'
          )}
        >
          {locating ? <LoadingIndicator size="sm" /> : <LocateFixed size={16} />}
        </button>
      )}
      {showMapButton && (
        <button
          type="button"
          onClick={onMapClick}
          className="absolute right-2 z-10 text-[10px] font-black uppercase tracking-widest bg-brand-blue text-white px-3 py-2 rounded-xl"
        >
          Map
        </button>
      )}
      {mapsAvailable && !places && (
        <p className="absolute -bottom-5 left-0 right-0 text-[9px] text-amber-400 font-bold">
          Loading address search…
        </p>
      )}
    </div>
  );
}
