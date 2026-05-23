import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const apkSrc = path.join(
  root,
  'mobile',
  'build',
  'app',
  'outputs',
  'flutter-apk',
  'app-release.apk'
);
const dest = path.join(root, 'public', 'bytzgo.apk');

if (!fs.existsSync(apkSrc)) {
  console.error('APK not found. Run: npm run flutter:build:apk');
  process.exit(1);
}

fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.copyFileSync(apkSrc, dest);
const mb = (fs.statSync(dest).size / (1024 * 1024)).toFixed(1);
console.log(`Copied APK (${mb} MB) -> public/bytzgo.apk`);
console.log('After deploy: https://www.bytzgo.net/download/android');
