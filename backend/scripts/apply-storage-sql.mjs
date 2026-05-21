/**
 * Upsert storage.buckets via DATABASE_URL.
 * Policies: run backend/supabase-storage-policies.sql in Supabase SQL Editor.
 */
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '../.env') });
dotenv.config({ path: path.join(__dirname, '../../.env.local') });

const url = process.env.DATABASE_URL;
const bucket = process.env.SUPABASE_STORAGE_BUCKET || 'pictures';
if (!url) {
  console.error('DATABASE_URL missing in backend/.env');
  process.exit(1);
}

const pool = new pg.Pool({
  connectionString: url,
  ssl: url.includes('supabase.com') ? { rejectUnauthorized: false } : false,
});

const bucketSql = `
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ($1, $1, true, 5242880, ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;
`;

try {
  await pool.query(bucketSql, [bucket]);
  const check = await pool.query(
    `SELECT id, public, file_size_limit FROM storage.buckets WHERE id = $1`,
    [bucket]
  );
  console.log('OK — bucket ready:', check.rows[0]);
  console.log('');
  console.log('Next: Supabase Dashboard → SQL Editor → paste and run:');
  console.log('  backend/supabase-storage-policies.sql');
  console.log('');
  console.log('Then add to backend/.env and Render (byzgo-api / byzgoback):');
  console.log('  SUPABASE_SERVICE_ROLE_KEY=<service_role from Settings → API>');
} catch (err) {
  console.error('FAIL —', err.message);
  process.exit(1);
} finally {
  await pool.end();
}
