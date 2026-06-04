/**
 * Register Android app net.bytzgo.app in Firebase (bytzgo-9bd89) and refresh google-services.json.
 * Uses backend/firebase-service-account.json (gitignored) or FIREBASE_SERVICE_ACCOUNT_JSON.
 *
 * Usage: node backend/scripts/setup-firebase-android.mjs
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { GoogleAuth } from 'google-auth-library';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
/** Repo root (byzgo/), not backend/. */
const repoRoot = path.resolve(__dirname, '..', '..');
const PROJECT_ID = 'bytzgo-9bd89';
const PACKAGE = 'net.bytzgo.app';
/** Production Android app in Firebase (package net.bytzgo.app). */
const ANDROID_APP_RESOURCE =
  'projects/bytzgo-9bd89/androidApps/1:645977332644:android:c61f7624820fc1e2977f31';
const ANDROID_APP_ID = '1:645977332644:android:c61f7624820fc1e2977f31';
const RELEASE_SHA1 = 'B2A044C879A5975095AB9AC5B60A2FFFD7CDE3F2D';
const RELEASE_SHA256 =
  'E98F20D01DD45A6AE3D1380D7B3B016DE1783C903FF915834CBD329D9EFA009';
/** Extra debug keystore (CI / other dev machines). */
const DEBUG_SHA1_ALT = '844C315C994787502E212EC2715DF5DED74FCC50';
/** Default Android Studio debug keystore on this PC (emulator / flutter run). */
const DEBUG_SHA1_LOCAL = '95F4D85777F2D006C131C4644D047627E2AA737';
/** Committed mobile/android/bytzgo-sideload.jks — used for https://www.bytzgo.net/download/android APKs. */
const SIDELOAD_APK_SHA1 = 'ECE976BB77E687634422DBA1DD58052522FA450A';
const SIDELOAD_APK_SHA256 =
  '3EC2C1D9A850E52D6AC1E2E4DAC03DAA8A8DCE6160E523DDCDAB851B9EF41534';

const saPath = path.resolve(__dirname, '../firebase-service-account.json');
const gsOut = path.join(repoRoot, 'mobile/android/app/google-services.json');
const firebaseOptsOut = path.join(repoRoot, 'mobile/lib/firebase_options.dart');

const FIREBASE_SCOPES = [
  'https://www.googleapis.com/auth/firebase',
  'https://www.googleapis.com/auth/cloud-platform',
];

function findServiceAccount() {
  if (fs.existsSync(saPath)) return saPath;
  const dir = path.join(repoRoot, 'backend');
  const hit = fs.readdirSync(dir).find((f) => f.includes('firebase-adminsdk') && f.endsWith('.json'));
  if (hit) return path.join(dir, hit);
  throw new Error('No firebase service account JSON in backend/');
}

async function api(token, method, url, body) {
  const res = await fetch(url, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    throw new Error(`${method} ${url} -> ${res.status}: ${text.slice(0, 500)}`);
  }
  return json;
}

async function waitOperation(token, name) {
  for (let i = 0; i < 30; i++) {
    const op = await api(token, 'GET', `https://firebase.googleapis.com/v1beta1/${name}`);
    if (op.done) {
      if (op.error) throw new Error(JSON.stringify(op.error));
      return op.response;
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error('Firebase operation timed out');
}

async function listAndroidApps(token) {
  const parent = `projects/${PROJECT_ID}`;
  let pageToken;
  const apps = [];
  do {
    const q = pageToken ? `?pageToken=${encodeURIComponent(pageToken)}` : '';
    const res = await api(
      token,
      'GET',
      `https://firebase.googleapis.com/v1beta1/${parent}/androidApps${q}`,
    );
    apps.push(...(res.apps || []));
    pageToken = res.nextPageToken;
  } while (pageToken);
  return apps;
}

function shaFormats(hexUpper) {
  const h = hexUpper.replace(/:/g, '').toUpperCase();
  const colon = h.match(/.{1,2}/g)?.join(':') ?? h;
  return [...new Set([h, colon, h.toLowerCase(), colon.toLowerCase()])];
}

async function patchShaHashes(token, appName) {
  const hashes = [...new Set([RELEASE_SHA1, DEBUG_SHA1_ALT, DEBUG_SHA1_LOCAL, SIDELOAD_APK_SHA1])];
  const extra = process.env.ANDROID_EXTRA_SHA1?.trim().toUpperCase().replace(/:/g, '');
  const shaResults = [];
  if (extra) hashes.push(extra);
  for (const sha1 of hashes) {
    let added = false;
    for (const fmt of shaFormats(sha1)) {
      try {
        await api(token, 'POST', `https://firebase.googleapis.com/v1beta1/${appName}/sha`, {
          shaHash: fmt,
          certType: 'SHA_1',
        });
        shaResults.push({ sha1: fmt, status: 'added' });
        added = true;
        break;
      } catch (e) {
        if (e.message.includes('409') || e.message.includes('ALREADY_EXISTS')) {
          shaResults.push({ sha1: fmt, status: 'already_registered' });
          added = true;
          break;
        }
      }
    }
    if (!added) shaResults.push({ sha1, status: 'failed' });
  }
  const sha256Hashes = [...new Set([RELEASE_SHA256, SIDELOAD_APK_SHA256])];
  for (const sha256 of sha256Hashes) {
    let added = false;
    for (const fmt of shaFormats(sha256)) {
      try {
        await api(token, 'POST', `https://firebase.googleapis.com/v1beta1/${appName}/sha`, {
          shaHash: fmt,
          certType: 'SHA_256',
        });
        shaResults.push({ sha256: fmt, status: 'added' });
        added = true;
        break;
      } catch (e) {
        if (e.message.includes('409') || e.message.includes('ALREADY_EXISTS')) {
          shaResults.push({ sha256: fmt, status: 'already_registered' });
          added = true;
          break;
        }
      }
    }
    if (!added) shaResults.push({ sha256, status: 'failed' });
  }
  return shaResults;
}

function filterGoogleServicesForPackage(jsonText, packageName) {
  const data = JSON.parse(jsonText);
  let client = (data.client || []).find(
    (c) => c.client_info?.mobilesdk_app_id === ANDROID_APP_ID,
  );
  if (!client) {
    client = (data.client || []).find(
      (c) => c.client_info?.android_client_info?.package_name === packageName,
    );
  }
  if (!client) {
    throw new Error(`google-services.json has no client for ${packageName} / ${ANDROID_APP_ID}`);
  }
  client.client_info.android_client_info.package_name = packageName;
  for (const oauth of client.oauth_client || []) {
    if (oauth.android_info) {
      oauth.android_info.package_name = packageName;
    }
  }
  data.client = [client];
  return `${JSON.stringify(data, null, 2)}\n`;
}

async function downloadConfig(token, appName) {
  const config = await api(token, 'GET', `https://firebase.googleapis.com/v1beta1/${appName}/config`);
  if (!config.configFilename || !config.configFileContents) {
    throw new Error('No config in Firebase response');
  }
  return Buffer.from(config.configFileContents, 'base64').toString('utf8');
}

function updateFirebaseOptionsDart(googleServicesJson) {
  const data = JSON.parse(googleServicesJson);
  const client = data.client?.[0];
  if (!client) throw new Error('Invalid google-services.json');
  const appId = client.client_info?.mobilesdk_app_id;
  const apiKey = client.api_key?.[0]?.current_key;
  if (!appId || !apiKey) throw new Error('Missing appId or apiKey in google-services.json');

  const dart = `import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Firebase project **${PROJECT_ID}** — generated by setup-firebase-android.mjs
class DefaultFirebaseOptions {
  static const bool isConfigured = true;

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('Firebase is not supported on this platform.');
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: '${apiKey}',
    appId: '${appId}',
    messagingSenderId: '${data.project_info.project_number}',
    projectId: '${PROJECT_ID}',
    storageBucket: '${data.project_info.storage_bucket}',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyAzDpvnJJ6x4zThAMk95KD_ABCF8Eo9ixY',
    appId: '1:645977332644:ios:0b014667ec40000e977f31',
    messagingSenderId: '${data.project_info.project_number}',
    projectId: '${PROJECT_ID}',
    storageBucket: '${data.project_info.storage_bucket}',
    iosBundleId: 'com.example.bytzgo',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: '${apiKey}',
    appId: '${appId}',
    messagingSenderId: '${data.project_info.project_number}',
    projectId: '${PROJECT_ID}',
    storageBucket: '${data.project_info.storage_bucket}',
  );
}
`;
  fs.writeFileSync(firebaseOptsOut, dart);
}

async function resolveAccessToken({ credentials, keyFile } = {}) {
  if (credentials) {
    const auth = new GoogleAuth({ credentials, scopes: FIREBASE_SCOPES });
    const client = await auth.getClient();
    const res = await client.getAccessToken();
    return res.token;
  }
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (inline) {
    const auth = new GoogleAuth({
      credentials: JSON.parse(inline),
      scopes: FIREBASE_SCOPES,
    });
    const client = await auth.getClient();
    const res = await client.getAccessToken();
    return res.token;
  }
  const file = keyFile || findServiceAccount();
  if (!fs.existsSync(file)) {
    throw new Error(`Service account not found: ${file}`);
  }
  const auth = new GoogleAuth({ keyFile: file, scopes: FIREBASE_SCOPES });
  const client = await auth.getClient();
  const res = await client.getAccessToken();
  return res.token;
}

/**
 * Register SHA fingerprints and download google-services.json from Firebase.
 * @param {{ credentials?: object, keyFile?: string, writeFiles?: boolean }} options
 */
export async function syncFirebaseAndroid(options = {}) {
  const { credentials, keyFile, writeFiles = true } = options;
  const token = await resolveAccessToken({ credentials, keyFile });
  if (!token) throw new Error('No access token');

  const apps = await listAndroidApps(token);
  let app = apps.find((a) => a.name === ANDROID_APP_RESOURCE);
  if (!app) app = apps.find((a) => a.packageName === PACKAGE);
  if (!app) app = { name: ANDROID_APP_RESOURCE };

  const shaResults = await patchShaHashes(token, app.name);
  const gsRaw = await downloadConfig(token, app.name);
  const gsFiltered = filterGoogleServicesForPackage(gsRaw, PACKAGE);
  const hasSideload = gsFiltered.includes(SIDELOAD_APK_SHA1.toLowerCase());
  const hasRelease = gsFiltered.includes(RELEASE_SHA1.toLowerCase());

  let wroteFiles = false;
  if (writeFiles) {
    if (!hasRelease && fs.existsSync(gsOut)) {
      // keep existing oauth entries if Firebase download is incomplete
    } else {
      fs.writeFileSync(gsOut, gsFiltered);
      updateFirebaseOptionsDart(gsFiltered);
      wroteFiles = true;
    }
  }

  return {
    projectId: PROJECT_ID,
    packageName: PACKAGE,
    appResource: app.name,
    shaResults,
    hasSideloadSha1: hasSideload,
    hasReleaseSha1: hasRelease,
    googleServicesJson: gsFiltered,
    wroteFiles,
    androidApps: apps.map((a) => ({
      name: a.name,
      packageName: a.packageName,
      displayName: a.displayName,
    })),
  };
}

async function main() {
  let keyFile;
  try {
    keyFile = findServiceAccount();
    console.log('Using service account:', keyFile);
  } catch {
    if (!process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim()) throw new Error('No firebase service account');
    console.log('Using FIREBASE_SERVICE_ACCOUNT_JSON from environment');
  }
  const result = await syncFirebaseAndroid({ keyFile, writeFiles: true });
  console.log('SHA results:', JSON.stringify(result.shaResults, null, 2));
  console.log('Sideload SHA-1 in config:', result.hasSideloadSha1);
  if (result.wroteFiles) {
    console.log('Wrote', gsOut);
    console.log('Wrote', firebaseOptsOut);
  }
  console.log('\nDone. Rebuild APK: bash mobile/scripts/build_apk.sh');
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === path.resolve(process.argv[1]);
if (isMain) {
  main().catch((e) => {
    console.error(e.message || e);
    process.exit(1);
  });
}
