import axios from 'axios';

export interface RiderStats {
  tripsToday: number;
  tripsWeek: number;
  tripsMonth: number;
  earningsToday: number;
  earningsWeek: number;
  earningsMonth: number;
  avgRating: number | null;
  ratedTrips: number;
  offersReceived: number;
  offersAccepted: number;
  offersDeclined: number;
  acceptanceRate: number | null;
  activeTrips: number;
}

export interface WalletTransaction {
  id: string;
  amount: number;
  type: string;
  status?: string;
  reference?: string;
  createdAt?: string;
}

export async function fetchRiderStats(): Promise<RiderStats> {
  const res = await axios.get<RiderStats>('/api/rider/stats');
  return res.data;
}

export async function fetchWalletTransactions(limit = 40): Promise<WalletTransaction[]> {
  const res = await axios.get<WalletTransaction[]>('/api/wallet/transactions', {
    params: { limit },
  });
  return res.data ?? [];
}

export async function releaseRiderTrip(orderId: string, reason?: string): Promise<void> {
  await axios.post(`/api/orders/${orderId}/release`, reason ? { reason } : {});
}

export function orderDeliveryEarnings(order: { delivery_fee?: number; total: number }): number {
  const fee = (order as { delivery_fee?: number }).delivery_fee;
  return fee != null && fee > 0 ? fee : order.total;
}
