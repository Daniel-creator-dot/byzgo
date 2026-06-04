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

export function customerEtaLabel(order: Order, searching = false): string {
  if (searching || isCustomerSearchingBiker(order)) return 'est. pickup';
  if (order.status === 'picked_up') return 'to you';
  if (order.status === 'arrived') return 'arrived';
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

export async function fetchDirectionsEta(
  origin: { lat: number; lng: number },
  dest: { lat: number; lng: number }
): Promise<{ eta: string; eta_minutes: number; duration_text: string } | null> {
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
    };
  } catch {
    return null;
  }
}
