export type OrderStatus = 'pending' | 'preparing' | 'ready' | 'picked_up' | 'delivered' | 'cancelled';

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
  scheduled_time?: string;
  pickup_lat?: number;
  pickup_lng?: number;
}

export interface Rider {
  id: string;
  name: string;
  status: 'online' | 'offline' | 'delivering';
  lat: number;
  lng: number;
}

export type Role = 'customer' | 'vendor' | 'rider' | 'admin';
