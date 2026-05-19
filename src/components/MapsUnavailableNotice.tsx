import { AlertCircle, ExternalLink } from 'lucide-react';

export function MapsUnavailableNotice({
  message,
  compact = false,
}: {
  message?: string;
  compact?: boolean;
}) {
  const detail =
    message ||
    'Enable billing and Maps APIs on your Google Cloud project, then restart the app.';

  return (
    <div
      className={`rounded-xl border border-amber-500/40 bg-amber-500/10 text-left ${
        compact ? 'p-3' : 'p-4'
      }`}
    >
      <div className="flex gap-2 items-start">
        <AlertCircle size={compact ? 16 : 20} className="text-amber-400 shrink-0 mt-0.5" />
        <div className="min-w-0">
          <p
            className={`font-black text-amber-200 ${compact ? 'text-[10px]' : 'text-xs'} uppercase tracking-widest`}
          >
            Maps &amp; search unavailable
          </p>
          <p className={`text-amber-100/90 mt-1 leading-snug ${compact ? 'text-[10px]' : 'text-xs'}`}>
            {detail}
          </p>
          <ol
            className={`mt-2 space-y-1 text-slate-300 list-decimal list-inside ${compact ? 'text-[10px]' : 'text-[11px]'}`}
          >
            <li>
              Open{' '}
              <a
                href="https://console.cloud.google.com/google/maps-apis"
                target="_blank"
                rel="noreferrer"
                className="text-brand-blue underline inline-flex items-center gap-0.5"
              >
                Google Maps Platform <ExternalLink size={10} />
              </a>
            </li>
            <li>Enable billing on the project linked to your API key</li>
            <li>
              Enable: <strong>Maps JavaScript API</strong>, <strong>Places API</strong>,{' '}
              <strong>Geocoding API</strong>, <strong>Directions API</strong>
            </li>
            <li>
              Under API key restrictions, allow <code className="text-amber-200">http://localhost:5173/*</code>
            </li>
            <li>
              Set <code className="text-amber-200">VITE_GOOGLE_MAPS_API_KEY</code> in{' '}
              <code className="text-amber-200">.env.local</code> and restart{' '}
              <code className="text-amber-200">npm run dev</code>
            </li>
          </ol>
        </div>
      </div>
    </div>
  );
}
