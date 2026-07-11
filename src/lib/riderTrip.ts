import type { Order } from '../types';

export type TripPhase = 'to_pickup' | 'to_dropoff';

export type LatLng = { lat: number; lng: number };

export type TripStop = LatLng & { label: string };

export function getDropoffCoords(order: Order): TripStop | null {
  if (order.lat && order.lng && hasValidCoords(order.lat, order.lng)) {
    return { lat: order.lat, lng: order.lng, label: order.address || 'Drop-off' };
  }
  if (order.address?.trim()) {
    return { lat: 0, lng: 0, label: order.address.trim() };
  }
  return null;
}

export function getPickupCoordsForOrder(
  order: Order,
  vendors: { id: string; lat?: number; lng?: number; name?: string; address?: string }[]
): TripStop | null {
  const isCourier = (order as Order & { order_type?: string }).order_type === 'courier';
  if (isCourier && order.pickup_lat && order.pickup_lng) {
    const label =
      (order as Order & { pickup_address?: string }).pickup_address || 'Pickup';
    return { lat: order.pickup_lat, lng: order.pickup_lng, label };
  }
  const vendor = vendors.find((v) => v.id === order.vendor_id);
  if (vendor?.lat && vendor?.lng && hasValidCoords(vendor.lat, vendor.lng)) {
    return { lat: vendor.lat, lng: vendor.lng, label: vendor.name || vendor.address || 'Vendor' };
  }
  if (vendor?.address?.trim()) {
    return { lat: 0, lng: 0, label: `${vendor.name ? `${vendor.name}, ` : ''}${vendor.address.trim()}` };
  }
  if (vendor?.name) {
    return { lat: 0, lng: 0, label: vendor.name };
  }
  return null;
}

export function getTripPhase(order: Order): TripPhase {
  return order.status === 'picked_up' ? 'to_dropoff' : 'to_pickup';
}

export function getNavigationTarget(
  order: Order,
  vendors: { id: string; lat?: number; lng?: number; name?: string; address?: string }[]
): TripStop | null {
  if (order.status === 'picked_up') {
    return getDropoffCoords(order);
  }
  return getPickupCoordsForOrder(order, vendors);
}

export function hasValidCoords(lat: number, lng: number): boolean {
  return Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) > 0.001 && Math.abs(lng) > 0.001;
}

/** Matches backend/mobile dispatch: open jobs riders can accept. */
export function isOfferableToRider(order: Order): boolean {
  const riderId =
    order.rider_id ?? (order as Order & { riderId?: string }).riderId ?? null;
  if (riderId) return false;
  if (order.status === 'ready') return true;
  return false;
}

export function isActiveDispatchOffer(order: Order, now = Date.now()): boolean {
  if (!order.expiresAt) return true;
  const t = new Date(order.expiresAt).getTime();
  return Number.isFinite(t) && t > now;
}

export function googleMapsNavUrl(
  destLat: number,
  destLng: number,
  origin?: LatLng | null
): string {
  const params = new URLSearchParams({
    api: '1',
    destination: `${destLat},${destLng}`,
    travelmode: 'driving',
  });
  if (origin && hasValidCoords(origin.lat, origin.lng)) {
    params.set('origin', `${origin.lat},${origin.lng}`);
  }
  return `https://www.google.com/maps/dir/?${params.toString()}`;
}

export function googleMapsSearchUrl(query: string): string {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}`;
}

/** Open Google Maps (app on phone, new tab on desktop) for turn-by-turn navigation. */
export function openTurnByTurnNavigation(
  target: TripStop,
  origin?: LatLng | null
): void {
  const url = hasValidCoords(target.lat, target.lng)
    ? googleMapsNavUrl(target.lat, target.lng, origin)
    : googleMapsSearchUrl(target.label);

  const link = document.createElement('a');
  link.href = url;
  link.target = '_blank';
  link.rel = 'noopener noreferrer';
  document.body.appendChild(link);
  link.click();
  link.remove();
}
