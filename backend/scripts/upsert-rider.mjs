import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });
dotenv.config({ path: path.join(__dirname, '..', '..', '.env.local') });

const email = 'rider@bytzgo.net';
const password = 'Rider@2026';
const name = 'BytzGo Rider';

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set (backend/.env or .env.local)');
  process.exit(1);
}

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL.includes('supabase.com')
    ? { rejectUnauthorized: false }
    : false,
});

try {
  const hashed = await bcrypt.hash(password, 10);
  const result = await pool.query(
    `INSERT INTO users (name, email, password, role, status, region, balance)
     VALUES ($1, $2, $3, 'rider', 'active', 'Greater Accra', 0)
     ON CONFLICT (email) DO UPDATE SET
       name = EXCLUDED.name,
       password = EXCLUDED.password,
       role = 'rider',
       status = 'active'
     RETURNING id, name, email, role, status`,
    [name, email, hashed],
  );
  const user = result.rows[0];
  console.log('Rider account ready:');
  console.log(`  Email:    ${user.email}`);
  console.log(`  Password: ${password}`);
  console.log(`  Role:     ${user.role}`);
  console.log(`  Status:   ${user.status}`);
  console.log(`  ID:       ${user.id}`);
} catch (err) {
  console.error('Failed:', err.message);
  process.exit(1);
} finally {
  await pool.end();
}
