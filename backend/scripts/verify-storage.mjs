/**
 * Verify Supabase Storage bucket + service role (run from repo root).
 * Usage: node backend/scripts/verify-storage.mjs
 */
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '../.env') });
dotenv.config({ path: path.join(__dirname, '../../.env.local') });

const url = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const key = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
const bucket = (process.env.SUPABASE_STORAGE_BUCKET || 'pictures').trim();

if (!url || !key) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in backend/.env');
  process.exit(1);
}

const res = await fetch(`${url}/storage/v1/bucket/${bucket}`, {
  headers: { Authorization: `Bearer ${key}`, apikey: key },
});

if (res.ok) {
  const data = await res.json();
  console.log('OK — bucket reachable:', data.name || bucket);
  console.log('  public:', data.public);
  console.log('  file_size_limit:', data.file_size_limit);
  console.log('  allowed_mime_types:', data.allowed_mime_types?.join(', '));
  process.exit(0);
}

const text = await res.text();
console.error('FAIL —', res.status, text.slice(0, 300));
if (res.status === 404) {
  console.error(`Run backend/supabase-storage.sql in Supabase SQL Editor to create bucket "${bucket}".`);
}
process.exit(1);
