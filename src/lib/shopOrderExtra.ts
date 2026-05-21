/** Payload fields for marketplace (vendor) orders — matches mobile + backend validation. */
export function buildShopOrderExtra(params: {
  user: {
    address?: string | null;
    lat?: number | null;
    lng?: number | null;
    region?: string | null;
  };
  vendor?: {
    address?: string | null;
    lat?: number | null;
    lng?: number | null;
  } | null;
  deliveryFee: number;
  extra?: Record<string, unknown>;
}): Record<string, unknown> {
  const { user, vendor, deliveryFee, extra = {} } = params;
  return {
    ...extra,
    order_type: 'food',
    delivery_fee: deliveryFee,
    address: (extra.address as string) || user.address || 'East Legon, Accra',
    lat: (extra.lat as number) ?? user.lat,
    lng: (extra.lng as number) ?? user.lng,
    region: (extra.region as string) || user.region,
    pickup: (extra.pickup as string) || vendor?.address,
    pickup_lat: (extra.pickup_lat as number) ?? vendor?.lat,
    pickup_lng: (extra.pickup_lng as number) ?? vendor?.lng,
  };
}
