import { Role } from '../types';

const SETUP_KEY = 'bytzgo_device_setup_v1';

export type DeviceSetupRecord = {
  completed: boolean;
  role: Role;
  installSkipped?: boolean;
};

export function isStandalonePwa(): boolean {
  return (
    window.matchMedia('(display-mode: standalone)').matches ||
    (window.navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

export function isIos(): boolean {
  return /iPad|iPhone|iPod/.test(navigator.userAgent) && !(window as Window & { MSStream?: unknown }).MSStream;
}

export function isAndroid(): boolean {
  return /Android/i.test(navigator.userAgent);
}

export function getStoredSetup(): DeviceSetupRecord | null {
  try {
    const raw = localStorage.getItem(SETUP_KEY);
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

export function markSetupComplete(role: Role, extra?: Partial<DeviceSetupRecord>) {
  const record: DeviceSetupRecord = {
    completed: true,
    role,
    installSkipped: extra?.installSkipped,
  };
  localStorage.setItem(SETUP_KEY, JSON.stringify(record));
}

export function clearSetupForRole() {
  localStorage.removeItem(SETUP_KEY);
}

/** Whether to show install + permissions onboarding for this role. */
export function needsDeviceSetup(role: Role): boolean {
  if (role === 'admin') return false;
  const stored = getStoredSetup();
  if (!stored || stored.role !== role || !stored.completed) return true;

  const needsLocation = role === 'rider' || role === 'customer';
  const needsNotifications = role === 'rider' || role === 'vendor' || role === 'customer';

  if (needsLocation && localStorage.getItem('bytzgo_location_ok') !== '1') return true;
  if (needsNotifications && Notification.permission === 'default') return true;

  return false;
}

export async function requestDeviceLocation(): Promise<GeolocationPosition | null> {
  if (!('geolocation' in navigator)) return null;
  return new Promise((resolve) => {
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        localStorage.setItem('bytzgo_location_ok', '1');
        resolve(pos);
      },
      () => resolve(null),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    );
  });
}

export async function queryPermissionState(
  name: 'geolocation' | 'notifications'
): Promise<PermissionState | 'unsupported'> {
  if (!navigator.permissions?.query) return 'unsupported';
  try {
    const result = await navigator.permissions.query({ name } as PermissionDescriptor);
    return result.state;
  } catch {
    return 'unsupported';
  }
}

export function roleNeedsLocation(role: Role): boolean {
  return role === 'rider' || role === 'customer';
}

export function roleNeedsNotifications(role: Role): boolean {
  return role === 'rider' || role === 'vendor' || role === 'customer';
}
