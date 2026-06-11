#!/usr/bin/env node
/**
 * Diagnose Firebase → iOS (APNs) push for rider job alerts.
 *
 * Usage:
 *   node backend/scripts/diagnose-fcm-ios.mjs
 *   node backend/scripts/diagnose-fcm-ios.mjs <FCM_DEVICE_TOKEN>
 *
 * Get a rider FCM token from production:
 *   curl -s https://www.bytzgo.net/api/push/status -H "Authorization: Bearer RIDER_JWT"
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import admin from 'firebase-admin';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
const saPath = path.join(root, 'firebase-service-account.json');

function loadServiceAccount() {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (inline) return JSON.parse(inline);
  if (fs.existsSync(saPath)) {
    return JSON.parse(fs.readFileSync(saPath, 'utf8'));
  }
  return null;
}

const sa = loadServiceAccount();
if (!sa) {
  console.error('❌ No Firebase service account. Add backend/firebase-service-account.json');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(sa),
  projectId: sa.project_id || 'bytzgo-9bd89',
});

const token = process.argv[2]?.trim();

console.log('Firebase project:', sa.project_id);
console.log('FCM API: OK (service account loaded)');
console.log('');

if (!token) {
  console.log('No device token passed. To test lock-screen ring on a real iPhone:');
  console.log('');
  console.log('1. Install BytzGo 1.0.46+ on iPhone');
  console.log('2. Rider → Go Online → allow notifications');
  console.log('3. curl https://www.bytzgo.net/api/push/status -H "Authorization: Bearer RIDER_JWT"');
  console.log('4. Lock phone, then:');
  console.log('   node backend/scripts/diagnose-fcm-ios.mjs <FCM_TOKEN_FROM_DB_OR_STATUS>');
  console.log('');
  console.log('Or use API test (rider must be online):');
  console.log('   curl -X POST https://www.bytzgo.net/api/push/test-incoming-ride -H "Authorization: Bearer RIDER_JWT"');
  console.log('');
  console.log('⚠️  If send fails with messaging/third-party-auth-error → upload APNs .p8 to Firebase Console');
  process.exit(0);
}

const message = {
  token,
  data: {
    type: 'incoming-ride',
    orderId: 'diagnose-test',
    title: 'Test delivery job',
    body: 'Lock-screen ring test — tap to open BytzGo',
    audience: 'rider',
  },
  apns: {
    headers: {
      'apns-priority': '10',
      'apns-push-type': 'alert',
    },
    payload: {
      aps: {
        alert: { title: 'Test delivery job', body: 'Lock-screen ring test — tap to open BytzGo' },
        sound: 'default',
        badge: 1,
        'interruption-level': 'time-sensitive',
      },
    },
  },
};

try {
  const id = await admin.messaging().send(message);
  console.log('✅ FCM accepted message:', id);
  console.log('   Lock the iPhone now — expect banner + sound within ~5s.');
} catch (err) {
  const code = err?.code || err?.errorInfo?.code || 'unknown';
  const msg = err?.message || String(err);
  console.error('❌ FCM send failed:', code);
  console.error('   ', msg);
  if (code === 'messaging/third-party-auth-error') {
    console.error('');
    console.error('→ Fix: Firebase Console → bytzgo-9bd89 → Cloud Messaging');
    console.error('  Upload Apple APNs Auth Key (.p8), Key ID, Team MHTN5HYAHW');
    console.error('  See docs/FIREBASE_IOS.md');
  } else if (code === 'messaging/registration-token-not-registered') {
    console.error('→ Token expired. Rider: reopen app, Go Online, retry.');
  } else if (code === 'messaging/invalid-argument') {
    console.error('→ Token format invalid. Copy full FCM token from /api/push/status.');
  }
  process.exit(1);
}
