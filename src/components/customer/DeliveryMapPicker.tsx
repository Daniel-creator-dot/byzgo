import type { Dispatch, SetStateAction } from 'react';
import { Map, Marker } from '@vis.gl/react-google-maps';
import { GHANA_CENTER, resolveAddressLabel } from '../../lib/ghanaLocation';
import { CLEAN_MAP_STYLE } from '../../lib/mapStyles';
import { useMapsAvailable, useMapsStatus } from '../MapsProvider';
import { MapsUnavailableNotice } from '../MapsUnavailableNotice';
import type { CourierFormState } from './CustomerDeliveryHome';

export function DeliveryMapPicker({
  mapMode,
  courierForm,
  setCourierForm,
}: {
  mapMode: 'pickup' | 'destination';
  courierForm: CourierFormState;
  setCourierForm: Dispatch<SetStateAction<CourierFormState>>;
}) {
  const mapsAvailable = useMapsAvailable();
  const { mapsWarning } = useMapsStatus();

  if (!mapsAvailable) {
    return (
      <div className="min-h-[13rem] rounded-xl border border-slate-700 overflow-hidden">
        <MapsUnavailableNotice message={mapsWarning} compact />
        <p className="text-[10px] text-slate-500 text-center px-3 pb-3">
          You can still type addresses or use the GPS button on the fields above.
        </p>
      </div>
    );
  }

  return (
    <div className="h-52 rounded-xl overflow-hidden relative">
      <Map
        defaultCenter={
          courierForm.pickup
            ? { lat: courierForm.pickup.lat, lng: courierForm.pickup.lng }
            : GHANA_CENTER
        }
        defaultZoom={15}
        gestureHandling="greedy"
        disableDefaultUI
        styles={CLEAN_MAP_STYLE}
        onClick={async (e) => {
          if (!e.detail.latLng) return;
          const lat = e.detail.latLng.lat;
          const lng = e.detail.latLng.lng;
          const address = await resolveAddressLabel(lat, lng);
          const loc = { lat, lng, address };
          if (mapMode === 'pickup') setCourierForm((prev) => ({ ...prev, pickup: loc }));
          else setCourierForm((prev) => ({ ...prev, destination: loc }));
        }}
      >
        {courierForm.pickup && (
          <Marker position={{ lat: courierForm.pickup.lat, lng: courierForm.pickup.lng }} />
        )}
        {courierForm.destination && (
          <Marker position={{ lat: courierForm.destination.lat, lng: courierForm.destination.lng }} />
        )}
      </Map>
    </div>
  );
}
