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
const destPublic = path.join(root, 'public', 'bytzgo.apk');
const destDist = path.join(root, 'dist', 'bytzgo.apk');

if (!fs.existsSync(apkSrc)) {
  console.error('APK not found. Run: npm run flutter:build:apk');
  process.exit(1);
}

fs.mkdirSync(path.dirname(destPublic), { recursive: true });
fs.copyFileSync(apkSrc, destPublic);
const mb = (fs.statSync(destPublic).size / (1024 * 1024)).toFixed(1);
console.log(`Copied APK (${mb} MB) -> public/bytzgo.apk`);

// Keep dist/ in sync so Render deploy serves the same file (vite copies public earlier;
// this overwrites dist after a local flutter build).
if (fs.existsSync(path.join(root, 'dist'))) {
  fs.copyFileSync(apkSrc, destDist);
  console.log(`Copied APK (${mb} MB) -> dist/bytzgo.apk`);
}

// Write version marker for /download/android/version
const pubspec = fs.readFileSync(path.join(root, 'mobile', 'pubspec.yaml'), 'utf8');
const versionMatch = pubspec.match(/^version:\s*(.+)$/m);
const version = versionMatch ? versionMatch[1].trim() : 'unknown';
const versionJson = JSON.stringify(
  {
    version,
    updated_at: new Date().toISOString(),
    size_bytes: fs.statSync(destPublic).size,
    install_note:
      'Uninstall any older BytzGo app first, then install this APK. If Google sign-in fails, use phone or email login.',
  },
  null,
  2
);
fs.writeFileSync(path.join(root, 'public', 'android-version.json'), versionJson);
if (fs.existsSync(path.join(root, 'dist'))) {
  fs.writeFileSync(path.join(root, 'dist', 'android-version.json'), versionJson);
}

console.log(`Android APK version: ${version}`);
console.log('After deploy: https://www.bytzgo.net/download/android');
