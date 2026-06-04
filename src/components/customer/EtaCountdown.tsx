import { useEffect, useState } from 'react';
import { formatEtaCountdown } from '../../lib/customerTrip';

/** Live MM:SS ETA display (tabular) — mirrors mobile BoltEtaPill. */
export function EtaCountdown({
  expiresAtMs,
  fallbackMinutes,
  className = 'text-lg font-black text-brand-green font-mono leading-tight tabular-nums',
}: {
  expiresAtMs: number | null;
  fallbackMinutes?: number;
  className?: string;
}) {
  const [, tick] = useState(0);

  useEffect(() => {
    if (expiresAtMs == null) return;
    const id = setInterval(() => tick((n) => n + 1), 1000);
    return () => clearInterval(id);
  }, [expiresAtMs]);

  return <p className={className}>{formatEtaCountdown(expiresAtMs, fallbackMinutes)}</p>;
}
