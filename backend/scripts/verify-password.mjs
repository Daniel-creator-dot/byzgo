import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });
dotenv.config({ path: path.join(__dirname, '..', '..', '.env.local') });

const email = process.argv[2];
const password = process.argv[3];
if (!email || !password) {
  console.error('Usage: node verify-password.mjs <email> <password>');
  process.exit(1);
}

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('supabase.com')
    ? { rejectUnauthorized: false }
    : false,
});

const r = await pool.query('SELECT password, role, name FROM users WHERE email = $1', [email]);
if (!r.rowCount) {
  console.log('NOT_FOUND');
  process.exit(1);
}
const ok = r.rows[0].password
  ? await bcrypt.compare(password, r.rows[0].password)
  : false;
console.log(JSON.stringify({ email, role: r.rows[0].role, name: r.rows[0].name, password_matches: ok }));
await pool.end();
process.exit(ok ? 0 : 2);
