/**
 * Allow Google Sign-In on sideload APKs by adding package + SHA-1 to the
 * Firebase Android API key (from google-services.json) in Google Cloud.
 *
 * Usage: node backend/scripts/configure-google-signin-apikey.mjs
 * Requires backend/firebase-service-account.json or FIREBASE_SERVICE_ACCOUNT_JSON.
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { GoogleAuth } from 'google-auth-library';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..', '..');
const PROJECT = 'bytzgo-9bd89';
const PACKAGE = 'net.bytzgo.app';
/** Firebase Android API key in mobile/android/app/google-services.json */
const FIREBASE_API_KEY_HINT = '2iTtiY';

const ANDROID_APPS = [
  { packageName: PACKAGE, sha1Fingerprint: 'ECE976BB77E687634422DBA1DD58052522FA450A' },
  { packageName: PACKAGE, sha1Fingerprint: 'B2A044C879A5975095AB9AC5B60A2FFD7CDE3F2D' },
  { packageName: PACKAGE, sha1Fingerprint: '844C315C994787502E212EC2715DF5DED74FCC50' },
  { packageName: PACKAGE, sha1Fingerprint: '95F4D85777F2D006C1311C4644D047627E2AA737' },
];

function findServiceAccount() {
  const saPath = path.join(repoRoot, 'backend', 'firebase-service-account.json');
  if (fs.existsSync(saPath)) return saPath;
  const dir = path.join(repoRoot, 'backend');
  const hit = fs.readdirSync(dir).find((f) => f.includes('firebase-adminsdk') && f.endsWith('.json'));
  if (hit) return path.join(dir, hit);
  return null;
}

async function getToken() {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  const scopes = ['https://www.googleapis.com/auth/cloud-platform'];
  if (inline) {
    const auth = new GoogleAuth({ credentials: JSON.parse(inline), scopes });
    const client = await auth.getClient();
    return (await client.getAccessToken()).token;
  }
  const keyFile = findServiceAccount();
  if (!keyFile) throw new Error('No Firebase service account');
  const auth = new GoogleAuth({ keyFile, scopes });
  const client = await auth.getClient();
  return (await client.getAccessToken()).token;
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
    throw new Error(`${res.status} ${url}: ${data.error?.message || text.slice(0, 300)}`);
  }
  return data;
}

async function listKeys(token) {
  const url = `https://apikeys.googleapis.com/v2/projects/${PROJECT}/locations/global/keys`;
  const data = await apiFetch(url, token);
  return data.keys || [];
}

async function getKeyDetails(token, name) {
  return apiFetch(`https://apikeys.googleapis.com/v2/${name}`, token);
}

async function patchAndroidRestrictions(token, keyResource, existing) {
  const restrictions = { ...(existing.restrictions || {}) };
  restrictions.androidKeyRestrictions = { allowedApplications: ANDROID_APPS };
  // Do not set browser/http restrictions — they block native Google Sign-In.
  delete restrictions.browserKeyRestrictions;
  const body = { restrictions };
  const url = `https://apikeys.googleapis.com/v2/${keyResource}?updateMask=restrictions`;
  return apiFetch(url, token, { method: 'PATCH', body: JSON.stringify(body) });
}

async function enableService(token, service) {
  const url = `https://serviceusage.googleapis.com/v1/projects/${PROJECT}/services/${service}:enable`;
  try {
    await apiFetch(url, token, { method: 'POST', body: '{}' });
  } catch (e) {
    if (e.status === 409 || /already enabled/i.test(String(e.message))) return;
    throw e;
  }
}

export async function configureGoogleSignInApiKey() {
  const token = await getToken();
  if (!token) throw new Error('No access token');

  await enableService(token, 'apikeys.googleapis.com');
  await enableService(token, 'serviceusage.googleapis.com');

  const keys = await listKeys(token);
  let target =
    keys.find((k) => /android/i.test(k.displayName || '') && /firebase|auto/i.test(k.displayName || '')) ||
    keys.find((k) => /android/i.test(k.displayName || '')) ||
    keys[0];

  for (const k of keys) {
    try {
      const detail = await getKeyDetails(token, k.name);
      const keyString = detail.keyString || '';
      if (keyString.includes(FIREBASE_API_KEY_HINT) || (detail.displayName || '').includes('Android')) {
        target = detail;
        break;
      }
    } catch {
      /* continue */
    }
  }

  if (!target?.name) {
    throw new Error('No API key found in Google Cloud — patch Firebase Android key manually');
  }

  const detail = target.restrictions ? target : await getKeyDetails(token, target.name);
  await patchAndroidRestrictions(token, detail.name, detail);
  return {
    keyName: detail.displayName || detail.name,
    androidApps: ANDROID_APPS,
  };
}

async function main() {
  const result = await configureGoogleSignInApiKey();
  console.log('Patched API key:', result.keyName);
  console.log('Android apps:', result.androidApps);
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}
