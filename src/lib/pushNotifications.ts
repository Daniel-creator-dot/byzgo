import axios from 'axios';

function urlBase64ToUint8Array(base64String: string) {
  const padding = '='.repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
  const raw = atob(base64);
  const output = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) output[i] = raw.charCodeAt(i);
  return output;
}

export async function registerServiceWorker(): Promise<ServiceWorkerRegistration | null> {
  if (!('serviceWorker' in navigator)) return null;
  try {
    return await navigator.serviceWorker.register('/sw.js', { scope: '/' });
  } catch (err) {
    console.warn('Service worker registration failed', err);
    return null;
  }
}

export async function requestNotificationPermission(): Promise<NotificationPermission> {
  if (!('Notification' in window)) return 'denied';
  if (Notification.permission === 'granted') return 'granted';
  if (Notification.permission === 'denied') return 'denied';
  return Notification.requestPermission();
}

/** Subscribe rider device for background ride push alerts. */
export async function subscribeRiderPush(): Promise<boolean> {
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    console.warn('Push notifications not supported in this browser');
    return false;
  }

  const permission = await requestNotificationPermission();
  if (permission !== 'granted') return false;

  await registerServiceWorker();
  const registration = await navigator.serviceWorker.ready;

  const { data } = await axios.get<{ publicKey: string }>('/api/push/vapid-public-key');
  if (!data.publicKey) throw new Error('Push not configured on server');

  let subscription = await registration.pushManager.getSubscription();
  if (!subscription) {
    subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(data.publicKey),
    });
  }

  const json = subscription.toJSON();
  await axios.post('/api/push/subscribe', {
    endpoint: json.endpoint,
    keys: json.keys,
  });

  return true;
}

export async function unsubscribeRiderPush(): Promise<void> {
  if (!('serviceWorker' in navigator)) return;
  try {
    const registration = await navigator.serviceWorker.ready;
    const subscription = await registration.pushManager.getSubscription();
    if (!subscription) return;
    const endpoint = subscription.endpoint;
    await axios.delete('/api/push/subscribe', { data: { endpoint } });
    await subscription.unsubscribe();
  } catch (err) {
    console.warn('Unsubscribe push failed', err);
  }
}

export type IncomingRideMessage = {
  type: 'incoming-ride';
  orderId?: string;
  action?: string;
};

export function onServiceWorkerRideMessage(
  handler: (msg: IncomingRideMessage) => void
): () => void {
  if (!('serviceWorker' in navigator)) return () => {};
  const listener = (event: MessageEvent) => {
    if (event.data?.type === 'incoming-ride') handler(event.data as IncomingRideMessage);
  };
  navigator.serviceWorker.addEventListener('message', listener);
  return () => navigator.serviceWorker.removeEventListener('message', listener);
}
