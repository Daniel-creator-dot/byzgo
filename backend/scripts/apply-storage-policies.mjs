/**
 * Applies backend/supabase-storage-policies.sql via DATABASE_URL.
 * (ALTER TABLE on storage.objects requires Dashboard owner; policies work via pooler.)
 */
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';
import pg from 'pg';

const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, '../.env') });

const url = process.env.DATABASE_URL?.trim();
if (!url) {
  console.error('DATABASE_URL missing in backend/.env');
  process.exit(1);
}

const sql = readFileSync(join(__dirname, '../supabase-storage-policies.sql'), 'utf8');
const pool = new pg.Pool({
  connectionString: url,
  ssl: url.includes('supabase.com') ? { rejectUnauthorized: false } : false,
});

try {
  await pool.query(sql);
  console.log('OK — storage RLS policies applied for bucket:', process.env.SUPABASE_STORAGE_BUCKET || 'pictures');
} catch (err) {
  console.error('FAIL —', err.message);
  process.exit(1);
} finally {
  await pool.end();
}
