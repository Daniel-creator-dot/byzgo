/* BytzGo service worker — background ride alerts for riders */

const RIDE_TAG_PREFIX = 'ride-';

function parsePushData(event) {
  try {
    return event.data ? event.data.json() : {};
  } catch {
    return { type: 'incoming-ride' };
  }
}

self.addEventListener('push', (event) => {
  const data = parsePushData(event);
  if (data.type !== 'incoming-ride') return;

  const earnings = data.delivery_fee ?? data.total ?? 0;
  const body = `₵${Number(earnings).toFixed(2)} · ${data.address || 'New pickup request'}`;
  const tag = `${RIDE_TAG_PREFIX}${data.orderId}`;

  event.waitUntil(
    self.registration.showNotification('BytzGo — Incoming ride', {
      body,
      icon: '/icon-192.png',
      badge: '/icon-192.png',
      tag,
      renotify: true,
      requireInteraction: true,
      silent: false,
      vibrate: [400, 200, 400, 200, 400, 200, 400],
      data,
      actions: [
        { action: 'accept', title: 'Accept ride' },
        { action: 'view', title: 'View' },
      ],
    })
  );
});

self.addEventListener('notificationclick', (event) => {
  const data = event.notification.data || {};
  event.notification.close();

  const orderId = data.orderId;
  const action = event.action || 'view';
  const url = new URL('/motor', self.location.origin);
  if (orderId) url.searchParams.set('offer', orderId);
  if (action === 'accept') url.searchParams.set('action', 'accept');

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      const origin = self.location.origin;
      const appClient = clientList.find((c) => c.url && c.url.startsWith(origin));
      if (appClient) {
        appClient.postMessage({ type: 'incoming-ride', orderId, action });
        return appClient.focus();
      }
      return clients.openWindow(url.toString());
    })
  );
});

self.addEventListener('install', (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
