/**
 * Register Android app net.bytzgo.app in Firebase (bytzgo-9bd89) and refresh google-services.json.
 * Uses backend/firebase-service-account.json (gitignored).
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
/** Production Firebase Android app (release SHA-1 registered here). */
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
const FIREBASE_WEB_CLIENT_ID =
  '645977332644-4gjjf08268b3irafs4bh8b7guct1i1jb.apps.googleusercontent.com';

const saPath = path.resolve(__dirname, '../firebase-service-account.json');
const gsOut = path.join(repoRoot, 'mobile/android/app/google-services.json');
const firebaseOptsOut = path.join(repoRoot, 'mobile/lib/firebase_options.dart');

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
    const q = pageToken
      ? `?pageToken=${encodeURIComponent(pageToken)}`
      : '';
    const res = await api(
      token,
      'GET',
      `https://firebase.googleapis.com/v1beta1/${parent}/androidApps${q}`
    );
    apps.push(...(res.apps || []));
    pageToken = res.nextPageToken;
  } while (pageToken);
  return apps;
}

async function createAndroidApp(token) {
  const parent = `projects/${PROJECT_ID}`;
  const op = await api(token, 'POST', `https://firebase.googleapis.com/v1beta1/${parent}/androidApps`, {
    packageName: PACKAGE,
    displayName: 'BytzGo Android',
  });
  const created = await waitOperation(token, op.name);
  console.log('Created Android app:', created.name);
  return created;
}

async function patchShaHashes(token, appName) {
  const hashes = [...new Set([RELEASE_SHA1, DEBUG_SHA1_ALT, DEBUG_SHA1_LOCAL, SIDELOAD_APK_SHA1])];
  const extra = process.env.ANDROID_EXTRA_SHA1?.trim().toUpperCase().replace(/:/g, '');
  if (extra) hashes.push(extra);
  for (const sha1 of hashes) {
    let added = false;
    for (const fmt of shaFormats(sha1)) {
      try {
        await api(
          token,
          'POST',
          `https://firebase.googleapis.com/v1beta1/${appName}/sha`,
          { shaHash: fmt, certType: 'SHA_1' },
        );
        console.log('Added SHA-1:', fmt);
        added = true;
        break;
      } catch (e) {
        if (e.message.includes('409') || e.message.includes('ALREADY_EXISTS')) {
          console.log('SHA-1 already registered:', fmt);
          added = true;
          break;
        }
      }
    }
    if (!added) console.warn('Could not add SHA-1', sha1);
  }
  try {
    await api(
      token,
      'POST',
      `https://firebase.googleapis.com/v1beta1/${appName}/sha`,
      { shaHash: RELEASE_SHA256, certType: 'SHA_256' },
    );
    console.log('Added release SHA-256.');
  } catch (e) {
    console.warn('SHA-256:', e.message.slice(0, 200));
  }
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

function shaFormats(hexUpper) {
  const h = hexUpper.replace(/:/g, '').toUpperCase();
  const colon = h.match(/.{1,2}/g)?.join(':') ?? h;
  return [...new Set([h, colon, h.toLowerCase(), colon.toLowerCase()])];
}

async function downloadConfig(token, appName) {
  const config = await api(
    token,
    'GET',
    `https://firebase.googleapis.com/v1beta1/${appName}/config`
  );
  if (!config.configFilename || !config.configFileContents) {
    throw new Error('No config in Firebase response');
  }
  const contents = Buffer.from(config.configFileContents, 'base64').toString('utf8');
  return contents;
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
  console.log('Wrote', firebaseOptsOut);
}

async function main() {
  const keyFile = findServiceAccount();
  console.log('Using service account:', keyFile);
  if (!fs.existsSync(keyFile)) {
    throw new Error(`Service account not found: ${keyFile}`);
  }
  let token;
  try {
    const auth = new GoogleAuth({
      keyFile,
      scopes: [
        'https://www.googleapis.com/auth/firebase',
        'https://www.googleapis.com/auth/cloud-platform',
      ],
    });
    const client = await auth.getClient();
    const res = await client.getAccessToken();
    token = res.token;
  } catch (e) {
    throw new Error(`Google auth failed (${keyFile}): ${e.message}`);
  }
  if (!token) throw new Error('No access token');

  const apps = await listAndroidApps(token);
  console.log(
    'Existing Android apps:',
    apps.map((a) => `${a.packageName || a.displayName || '?'} (${a.name})`).join(', ') || '(none)'
  );

  let app = apps.find((a) => a.name === ANDROID_APP_RESOURCE);
  if (!app) {
    app = apps.find((a) => a.packageName === PACKAGE);
  }
  if (!app) {
    console.warn(
      `App ${ANDROID_APP_RESOURCE} not listed; using resource id directly (package ${PACKAGE}).`
    );
    app = { name: ANDROID_APP_RESOURCE };
  } else {
    console.log('Using Firebase app:', app.name);
  }

  await patchShaHashes(token, app.name);
  const gsRaw = await downloadConfig(token, app.name);
  const gsFiltered = filterGoogleServicesForPackage(gsRaw, PACKAGE);
  if (!gsFiltered.includes('b2a044c879a5975095ab9ac5b60a2ffd7cde3f2d')) {
    console.warn(
      'Downloaded config missing Play upload SHA-1 — keeping existing google-services.json oauth entries.',
    );
    if (fs.existsSync(gsOut)) {
      updateFirebaseOptionsDart(fs.readFileSync(gsOut, 'utf8'));
    } else {
      fs.writeFileSync(gsOut, gsFiltered);
      updateFirebaseOptionsDart(gsFiltered);
    }
  } else {
    fs.writeFileSync(gsOut, gsFiltered);
    console.log('Wrote', gsOut, `(package ${PACKAGE} only)`);
    updateFirebaseOptionsDart(gsFiltered);
  }
  console.log('\nDone. Rebuild AAB: npm run flutter:build:aab');
}

main().catch((e) => {
  console.error(e.message || e);
  process.exit(1);
});
