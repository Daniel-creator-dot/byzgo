/**
 * Applies backend/supabase-storage.sql via DATABASE_URL (same as Supabase SQL Editor).
 * Usage: node --import tsx scripts/run-supabase-storage-sql.mjs  (from backend/)
 */
import { readFileSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';
import pg from 'pg';

const __dirname = dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: join(__dirname, '..', '.env') });

const url = process.env.DATABASE_URL?.trim();
if (!url) {
  console.error('DATABASE_URL is missing in backend/.env');
  process.exit(1);
}

const sqlPath = join(__dirname, '..', 'supabase-storage.sql');
const sql = readFileSync(sqlPath, 'utf8');

const ssl =
  process.env.PG_SSL === 'true' ||
  /supabase\.com|render\.com|neon\.tech/i.test(url)
    ? { rejectUnauthorized: false }
    : undefined;

const client = new pg.Client({ connectionString: url, ssl });
try {
  await client.connect();
  await client.query(sql);
  console.log('OK: supabase-storage.sql applied (bucket + policies).');
} catch (err) {
  console.error('Failed:', err.message);
  process.exit(1);
} finally {
  await client.end();
}
