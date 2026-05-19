export type OrderStatus = 'pending' | 'preparing' | 'ready' | 'picked_up' | 'arrived' | 'delivered' | 'cancelled';

export interface Order {
  id: string;
  customer_id: string;
  customerName: string;
  items: Array<{ id: string; name: string; quantity: number; price: number }>;
  total: number;
  status: OrderStatus;
  createdAt: string;
  address: string;
  pickup?: string;
  orderType?: 'food' | 'courier';
  vendor_id: string;
  rider_id?: string;
  riderId?: string; // Legacy/Mapping
  vendorId?: string; // Legacy/Mapping
  lat?: number;
  lng?: number;
  rating?: number;
  rating_comment?: string;
  payment_status?: string;
  payment_method?: string;
  customer_payment_ack?: string;
  delivery_code?: string;
  delivery_code_created_at?: string;
  arrived_at?: string;
  scheduled_time?: string;
  pickup_lat?: number;
  pickup_lng?: number;
  created_at?: string;
  order_type?: string;
  delivery_fee?: number;
  /** ISO timestamp — active dispatch offer for this rider */
  expiresAt?: string;
  dispatchWave?: number;
}

export interface Rider {
  id: string;
  name: string;
  status: 'online' | 'offline' | 'delivering';
  lat: number;
  lng: number;
}

export type Role = 'customer' | 'vendor' | 'rider' | 'admin';
