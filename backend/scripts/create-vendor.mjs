/**
 * Create or update the default BytzGo vendor account.
 *
 *   npm run create:vendor
 *   npm run create:vendor -- vendor@bytzgo.net Vendor@2026 "Primecare Pharmacy"
 */
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });
dotenv.config({ path: path.join(__dirname, '..', '..', '.env.local') });

const email = (process.argv[2] || 'vendor@bytzgo.net').trim().toLowerCase();
const password = process.argv[3] || 'Vendor@2026';
const name = process.argv[4] || 'Primecare Pharmacy';

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set (backend/.env)');
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
    `INSERT INTO users (name, email, password, role, region, address, lat, lng, phone, status, shop_category, balance)
     VALUES ($1, $2, $3, 'vendor', 'Greater Accra', 'Ring Road Central, Accra', 5.5717, -0.2107, '0244123456', 'active', 'pharmacy', 0)
     ON CONFLICT (email) DO UPDATE SET
       name = EXCLUDED.name,
       password = EXCLUDED.password,
       role = 'vendor',
       status = 'active',
       shop_category = 'pharmacy',
       region = EXCLUDED.region,
       address = EXCLUDED.address,
       lat = EXCLUDED.lat,
       lng = EXCLUDED.lng
     RETURNING id, name, email, role, shop_category, status`,
    [name, email, hashed],
  );
  const user = result.rows[0];
  console.log('Vendor account ready:');
  console.log(`  Name:     ${user.name}`);
  console.log(`  Email:    ${user.email}`);
  console.log(`  Password: ${password}`);
  console.log(`  Role:     ${user.role}`);
  console.log(`  Shop:     ${user.shop_category}`);
  console.log(`  Status:   ${user.status}`);
  console.log(`  ID:       ${user.id}`);
} catch (err) {
  console.error('Failed:', err.message);
  process.exit(1);
} finally {
  await pool.end();
}
