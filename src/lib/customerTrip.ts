import axios from 'axios';
import { Order } from '../types';

export function isCustomerSearchingBiker(order: Order): boolean {
  if (order.rider_id) return false;
  return ['pending', 'ready', 'preparing'].includes(order.status);
}

export function isActiveCustomerTrip(order: Order): boolean {
  if (['delivered', 'cancelled'].includes(order.status)) return false;
  const type = (order as Order & { order_type?: string }).order_type;
  return type === 'courier' || Boolean(order.vendor_id);
}

function isCourierTrip(order: Order): boolean {
  const type =
    (order as Order & { order_type?: string }).order_type ??
    (order as Order & { orderType?: string }).orderType;
  return type === 'courier' || Boolean(order.vendor_id?.trim());
}

/** Ride tab: in-progress trip, or just-delivered until the customer rates. */
export function rideTabCourierTrip(orders: Order[], userId: string): Order | undefined {
  const mine = orders.filter((o) => o.customer_id === userId && isCourierTrip(o));
  const active = mine.find((o) => !['delivered', 'cancelled'].includes(o.status));
  if (active) return active;
  const unratedDelivered = mine.filter(
    (o) => o.status === 'delivered' && !((o as Order & { rating?: number }).rating ?? 0)
  );
  if (unratedDelivered.length === 0) return undefined;
  return unratedDelivered.sort(
    (a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  )[0];
}

export function customerOrderHasShopPickup(order: Order): boolean {
  return Boolean(order.vendor_id?.trim());
}

export function customerEtaLabel(order: Order, searching = false): string {
  if (searching || isCustomerSearchingBiker(order)) return 'est. pickup';
  if (order.status === 'picked_up') return 'to you';
  if (order.status === 'arrived') return 'arrived';
  if (
    customerOrderHasShopPickup(order) &&
    ['ready', 'preparing', 'pending'].includes(order.status)
  ) {
    return 'to shop';
  }
  return 'to pickup';
}

export async function fetchNearbyRiders(
  lat: number,
  lng: number,
  limit = 8
): Promise<{ id: string; lat: number; lng: number; distance_km?: number }[]> {
  const res = await axios.get<{ riders: { id: string; lat: number; lng: number; distance_km?: number }[] }>(
    '/api/riders/nearby',
    { params: { lat, lng, limit } }
  );
  return res.data?.riders ?? [];
}

export async function fetchRiderLocation(
  riderId: string
): Promise<{ lat: number; lng: number } | null> {
  try {
    const res = await axios.get<{ lat: number | null; lng: number | null }>(
      `/api/riders/${riderId}/location`
    );
    const { lat, lng } = res.data;
    if (lat == null || lng == null || !Number.isFinite(lat) || !Number.isFinite(lng)) {
      return null;
    }
    return { lat, lng };
  } catch {
    return null;
  }
}

export type DirectionsEta = {
  eta: string;
  eta_minutes: number;
  duration_text: string;
  expires_at: number;
};

export function etaExpiresAtFromMinutes(minutes: number, fromMs = Date.now()): number {
  const mins = Math.max(1, Math.round(minutes));
  return fromMs + mins * 60_000;
}

/** Bolt-style MM:SS countdown from an expiry timestamp. */
export function formatEtaCountdown(expiresAtMs: number | null, fallbackMinutes?: number): string {
  if (expiresAtMs != null) {
    const sec = Math.max(0, Math.floor((expiresAtMs - Date.now()) / 1000));
    if (sec <= 0) return '0:01';
    if (sec >= 3600) {
      const h = Math.floor(sec / 3600);
      const m = Math.floor((sec % 3600) / 60);
      return `${h}:${m.toString().padStart(2, '0')}`;
    }
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  }
  if (fallbackMinutes != null && fallbackMinutes > 0) {
    return `${fallbackMinutes}`;
  }
  return '—';
}

export async function fetchDirectionsEta(
  origin: { lat: number; lng: number },
  dest: { lat: number; lng: number }
): Promise<DirectionsEta | null> {
  try {
    const res = await axios.get<{
      eta_minutes?: number;
      duration_text?: string;
    }>('/api/maps/directions', {
      params: {
        origin_lat: origin.lat,
        origin_lng: origin.lng,
        dest_lat: dest.lat,
        dest_lng: dest.lng,
      },
    });
    const mins = res.data?.eta_minutes ?? 1;
    const text = res.data?.duration_text?.trim() || `${mins} min`;
    return {
      eta: text.startsWith('Arriving') ? text : `Arriving in ${text}`,
      eta_minutes: mins,
      duration_text: text,
      expires_at: etaExpiresAtFromMinutes(mins),
    };
  } catch {
    return null;
  }
}
