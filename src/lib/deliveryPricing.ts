/** Distance-based delivery fee (₵ per km). */

export const DEFAULT_DELIVERY_PRICE_PER_KM = 4;

export function haversineDistanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  if (!lat1 || !lon1 || !lat2 || !lon2) return 0;
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}

export function deliveryFeeFromDistanceKm(
  distanceKm: number,
  pricePerKm: number,
  bounds?: { min?: number; max?: number | null }
): number {
  const rate = Number(pricePerKm) > 0 ? Number(pricePerKm) : DEFAULT_DELIVERY_PRICE_PER_KM;
  let fee = distanceKm * rate;
  if (bounds?.min != null && Number.isFinite(bounds.min)) {
    fee = Math.max(fee, bounds.min);
  }
  if (bounds?.max != null && Number.isFinite(bounds.max)) {
    fee = Math.min(fee, bounds.max);
  }
  return Math.round(fee * 100) / 100;
}

export type DeliveryZoneRow = {
  region: string;
  is_active?: boolean;
  min_price: number | string;
  max_price?: number | string | null;
};

/** Zone min/max override global caps when a region matches. */
export function deliveryFeeBoundsForRegion(
  region: string | undefined,
  zones: DeliveryZoneRow[],
  global: { min?: number | null; max?: number | null }
): { min?: number; max?: number | null } {
  const zone = zones.find((z) => z.region === region && z.is_active !== false);
  if (zone) {
    const zMin = Number(zone.min_price);
    const zMax = zone.max_price != null && zone.max_price !== '' ? Number(zone.max_price) : null;
    return {
      min: Number.isFinite(zMin) && zMin > 0 ? zMin : global.min ?? undefined,
      max: Number.isFinite(zMax) && zMax > 0 ? zMax : global.max ?? null,
    };
  }
  return {
    min: global.min ?? undefined,
    max: global.max ?? null,
  };
}
