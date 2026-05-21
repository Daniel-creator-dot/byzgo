/**
 * Add debug + release SHA-1 to the Maps API key (Android apps) in Google Cloud.
 * Uses backend/firebase-service-account.json (needs API Keys Admin or Editor).
 *
 * Usage: node mobile/scripts/configure-maps-android-key.mjs
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { GoogleAuth } from 'google-auth-library';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.join(__dirname, '..', '..');
const saPath = path.join(repoRoot, 'backend', 'firebase-service-account.json');
const PROJECT = 'bytzgo-9bd89';
const PACKAGE = 'net.bytzgo.app';

const ANDROID_APPS = [
  { packageName: PACKAGE, sha1Fingerprint: '95F4D85777F2D006C1311C4644D047627E2AA737' }, // debug
  { packageName: PACKAGE, sha1Fingerprint: 'B2A044C879A5975095AB9AC5B60A2FFD7CDE3F2D' }, // release upload
];

const API_TARGETS = [
  { service: 'maps-android-backend.googleapis.com' },
  { service: 'maps-ios-backend.googleapis.com' },
  { service: 'directions-backend.googleapis.com' },
  { service: 'distance-matrix-backend.googleapis.com' },
  { service: 'geocoding-backend.googleapis.com' },
  { service: 'places-backend.googleapis.com' },
  { service: 'places.googleapis.com' },
];

function readMapsKeyHint() {
  const envLocal = path.join(repoRoot, '.env.local');
  const defines = path.join(repoRoot, 'mobile', 'dart_defines.json');
  for (const f of [envLocal, defines]) {
    if (!fs.existsSync(f)) continue;
    const text = fs.readFileSync(f, 'utf8');
    const m = text.match(/GOOGLE_MAPS_API_KEY["\s:=]+([A-Za-z0-9_-]{20,})/);
    if (m) return m[1];
  }
  return '';
}

async function apiFetch(url, token, opts = {}) {
  const res = await fetch(url, {
    ...opts,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
      ...(opts.headers || {}),
    },
  });
  const text = await res.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { raw: text };
  }
  if (!res.ok) {
    const err = new Error(`${res.status} ${url}: ${data.error?.message || text.slice(0, 200)}`);
    err.status = res.status;
    err.data = data;
    throw err;
  }
  return data;
}

async function enableMapsApis(token) {
  const services = [
    'maps-android-backend.googleapis.com',
    'geocoding-backend.googleapis.com',
    'places-backend.googleapis.com',
    'directions-backend.googleapis.com',
  ];
  for (const svc of services) {
    const url = `https://serviceusage.googleapis.com/v1/projects/${PROJECT}/services/${svc}:enable`;
    try {
      await apiFetch(url, token, { method: 'POST', body: '{}' });
      console.log(`Enabled ${svc}`);
    } catch (e) {
      if (e.status === 409 || /already enabled/i.test(String(e.message))) {
        console.log(`Already enabled: ${svc}`);
      } else {
        console.warn(`Could not enable ${svc}:`, e.message);
      }
    }
  }
}

async function findMapsKey(token, keySuffix) {
  const url = `https://apikeys.googleapis.com/v2/projects/${PROJECT}/locations/global/keys`;
  const data = await apiFetch(url, token);
  const keys = data.keys || [];
  for (const k of keys) {
    const name = k.name || '';
    const display = k.displayName || '';
    if (keySuffix && (k.keyString?.includes(keySuffix) || display.includes(keySuffix))) {
      return k;
    }
  }
  // Fallback: key whose restrictions mention maps or first Browser key with geocoding
  const mapsKey = keys.find(
    (k) =>
      k.restrictions?.apiTargets?.some((t) =>
        String(t.service || '').includes('maps-android')
      ) || /maps/i.test(k.displayName || '')
  );
  return mapsKey || keys[0] || null;
}

async function patchKey(token, keyResource) {
  const body = {
    restrictions: {
      androidKeyRestrictions: { allowedApplications: ANDROID_APPS },
      apiTargets: API_TARGETS,
    },
  };
  const url = `https://apikeys.googleapis.com/v2/${keyResource}?updateMask=restrictions`;
  return apiFetch(url, token, { method: 'PATCH', body: JSON.stringify(body) });
}

async function main() {
  if (!fs.existsSync(saPath)) {
    console.error('Missing', saPath);
    process.exit(1);
  }
  const hint = readMapsKeyHint();
  const suffix = hint ? hint.slice(-6) : '';
  const auth = new GoogleAuth({
    keyFile: saPath,
    scopes: ['https://www.googleapis.com/auth/cloud-platform'],
  });
  const client = await auth.getClient();
  const { token } = await client.getAccessToken();
  if (!token) throw new Error('No access token');

  console.log('Project:', PROJECT, '| Maps key hint:', suffix ? `…${suffix}` : '(unknown)');
  await enableMapsApis(token);

  const key = await findMapsKey(token, suffix);
  if (!key?.name) {
    console.error(
      'Could not find API key in Cloud Console. Add SHA-1 manually — see docs/GOOGLE_CLOUD_PLAY_SHA.md'
    );
    process.exit(1);
  }
  console.log('Patching key:', key.displayName || key.name);
  await patchKey(token, key.name);
  console.log('OK — Android restrictions set for debug + release SHA-1 on', PACKAGE);
}

main().catch((e) => {
  console.error(e.message || e);
  console.error('\nManual fix: docs/GOOGLE_CLOUD_PLAY_SHA.md (Maps API key → Android apps)');
  process.exit(1);
});
