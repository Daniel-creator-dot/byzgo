/**
 * After `vite build`, ensure dist/ serves the same APK as public/ (Render has no Flutter).
 * Run in build:render so /download/android never serves a stale dist copy.
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = path.join(root, 'public', 'bytzgo.apk');
const dest = path.join(root, 'dist', 'bytzgo.apk');
const versionSrc = path.join(root, 'public', 'android-version.json');
const versionDest = path.join(root, 'dist', 'android-version.json');

if (!fs.existsSync(src)) {
  console.warn('sync-apk: public/bytzgo.apk missing — skip');
  process.exit(0);
}

fs.mkdirSync(path.dirname(dest), { recursive: true });
fs.copyFileSync(src, dest);
const mb = (fs.statSync(dest).size / (1024 * 1024)).toFixed(1);
console.log(`sync-apk: copied public/bytzgo.apk (${mb} MB) -> dist/bytzgo.apk`);

if (fs.existsSync(versionSrc)) {
  fs.copyFileSync(versionSrc, versionDest);
}
