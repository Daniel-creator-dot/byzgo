#!/usr/bin/env node
/**
 * Opens Firebase Cloud Messaging and prints APNs upload values.
 * Firebase has no public API for .p8 upload — use the console once.
 *
 * Usage:
 *   node backend/scripts/setup-firebase-ios-apns.mjs
 *   node backend/scripts/setup-firebase-ios-apns.mjs /path/to/AuthKey_XXX.p8
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { execSync } from 'child_process';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..');
const defaultP8 = path.join(root, '.secrets/AuthKey_D4H8DZA4V9.p8');

const p8Path = path.resolve(process.argv[2] || defaultP8);
const keyId = path.basename(p8Path).match(/AuthKey_([A-Z0-9]+)\.p8/i)?.[1] || 'D4H8DZA4V9';
const teamId = 'MHTN5HYAHW';
const firebaseUrl =
  'https://console.firebase.google.com/project/bytzgo-9bd89/settings/cloudmessaging';

if (!fs.existsSync(p8Path)) {
  console.error('Missing .p8 file:', p8Path);
  process.exit(1);
}

console.log('');
console.log('BytzGo — upload APNs key to Firebase (one-time)');
console.log('================================================');
console.log('');
console.log('  .p8 file: ', p8Path);
console.log('  Key ID:   ', keyId);
console.log('  Team ID:  ', teamId);
console.log('  Bundle:   com.bytzgo.bytzgoMobile');
console.log('');
console.log('In Firebase → Cloud Messaging → Apple app configuration:');
console.log('  1. Click Upload under APNs Authentication Key');
console.log('  2. Select the .p8 file');
console.log('  3. Key ID:', keyId);
console.log('  4. Team ID:', teamId);
console.log('  5. Save');
console.log('');

try {
  execSync(`open "${firebaseUrl}"`, { stdio: 'ignore' });
  execSync(`open -R "${p8Path}"`, { stdio: 'ignore' });
  console.log('Opened Firebase Console + Finder with your .p8 file.');
} catch {
  console.log('Open manually:', firebaseUrl);
}
