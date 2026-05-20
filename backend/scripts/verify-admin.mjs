import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const email = process.argv[2] || 'admin@bytzgo.net';
const password = process.argv[3] || 'Admin@2026';

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('supabase.com')
    ? { rejectUnauthorized: false }
    : false,
});

try {
  const r = await pool.query(
    `SELECT id, name, email, role, status, password IS NOT NULL AS has_password
     FROM users WHERE email = $1`,
    [email],
  );
  if (r.rowCount === 0) {
    console.log('NOT_FOUND');
    process.exit(1);
  }
  const u = r.rows[0];
  const passRes = await pool.query('SELECT password FROM users WHERE id = $1', [u.id]);
  const hash = passRes.rows[0]?.password;
  const passwordOk = hash ? await bcrypt.compare(password, hash) : false;
  console.log(
    JSON.stringify(
      {
        email: u.email,
        name: u.name,
        role: u.role,
        status: u.status,
        has_password: u.has_password,
        password_matches: passwordOk,
      },
      null,
      2,
    ),
  );
  process.exit(passwordOk && u.role === 'admin' && u.status === 'active' ? 0 : 2);
} finally {
  await pool.end();
}
