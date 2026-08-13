import axios from 'axios';
import { Order } from '../types';

function customerOrderRiderId(order: Order): string | undefined {
  const id = order.rider_id || (order as Order & { riderId?: string }).riderId;
  return id?.trim() ? id : undefined;
}

export function isCustomerSearchingBiker(order: Order): boolean {
  if (['cancelled', 'delivered', 'scheduled'].includes(order.status)) return false;
  if (customerOrderRiderId(order)) return false;
  if (customerOrderHasShopPickup(order)) {
    return order.status === 'ready';
  }
  return ['pending', 'ready', 'preparing'].includes(order.status);
}

export function customerPharmacyAwaitingConfirm(order: Order): boolean {
  return (
    customerOrderHasShopPickup(order) &&
    !customerOrderRiderId(order) &&
    ['pending', 'preparing'].includes(order.status)
  );
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

function orderCreatedMs(order: Order): number {
  const raw =
    order.created_at ||
    (order as Order & { createdAt?: string }).createdAt ||
    '';
  const t = Date.parse(raw);
  return Number.isFinite(t) ? t : 0;
}

function isRecentUnratedDelivered(order: Order, hours = 6): boolean {
  if (order.status !== 'delivered') return false;
  const rating = (order as Order & { rating?: number }).rating ?? 0;
  if (rating >= 1) return false;
  return Date.now() - orderCreatedMs(order) < hours * 3_600_000;
}

/** Ride tab: just-finished trip until rated, else the newest in-progress trip. */
export function rideTabCourierTrip(orders: Order[], userId: string): Order | undefined {
  const mine = orders.filter((o) => o.customer_id === userId && isCourierTrip(o));
  const recentDelivered = mine
    .filter((o) => isRecentUnratedDelivered(o))
    .sort((a, b) => orderCreatedMs(b) - orderCreatedMs(a))[0];
  const active = mine
    .filter((o) => !['delivered', 'cancelled', 'scheduled'].includes(o.status))
    .sort((a, b) => orderCreatedMs(b) - orderCreatedMs(a))[0];
  if (recentDelivered && active) {
    return orderCreatedMs(active) > orderCreatedMs(recentDelivered) ? active : recentDelivered;
  }
  return recentDelivered ?? active;
}

const TRIP_STATUS_RANK: Record<string, number> = {
  cancelled: -2,
  pending: 0,
  preparing: 1,
  ready: 2,
  picked_up: 3,
  arrived: 4,
  delivered: 5,
};

/** Ignore stale socket payloads that would rewind a finished trip back to searching. */
export function mergeCustomerOrderUpdate(prev: Order, next: Order): Order {
  if (prev.status === 'cancelled' && next.status !== 'cancelled') return prev;
  const merged: Order = { ...prev, ...next };
  if (prev.status === 'delivered' && next.status !== 'cancelled' && next.status !== 'delivered') {
    return {
      ...merged,
      status: 'delivered',
      rider_id: customerOrderRiderId(next) || customerOrderRiderId(prev),
    };
  }
  const prevRank = TRIP_STATUS_RANK[prev.status] ?? 0;
  const nextRank = TRIP_STATUS_RANK[next.status] ?? 0;
  if (nextRank < prevRank && next.status !== 'cancelled') {
    return {
      ...merged,
      status: prev.status,
      rider_id: customerOrderRiderId(next) || customerOrderRiderId(prev),
    };
  }
  if (
    !customerOrderRiderId(next) &&
    customerOrderRiderId(prev) &&
    ['picked_up', 'arrived', 'delivered'].includes(next.status)
  ) {
    return { ...merged, rider_id: customerOrderRiderId(prev) };
  }
  return merged;
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
