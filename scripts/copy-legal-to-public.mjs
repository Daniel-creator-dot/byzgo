import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const src = path.join(root, 'backend', 'legal');
const dest = path.join(root, 'public');

for (const name of ['privacy.html', 'terms.html', 'account-deletion.html']) {
  fs.copyFileSync(path.join(src, name), path.join(dest, name));
  console.log(`Copied ${name} -> public/`);
}
