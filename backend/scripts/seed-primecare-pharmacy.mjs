/**
 * Seed Primecare Pharmacy vendor + drug formulary stock (from PDF export).
 *
 *   npm run seed:primecare
 *
 * Parses JSON from scratch/primecare_formulary.json (generate via scripts/parse_drug_formulary.py).
 */
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..', '..');

dotenv.config({ path: path.join(__dirname, '..', '.env') });
dotenv.config({ path: path.join(root, '.env.local') });

const VENDOR = {
  name: 'Primecare Pharmacy',
  email: 'vendor@bytzgo.net',
  phone: '0244123456',
  password: 'Vendor@2026',
  shop_category: 'pharmacy',
  region: 'Greater Accra',
  address: 'Ring Road Central, Accra',
  lat: 5.5717,
  lng: -0.2107,
};

const FORMULARY_PATH = path.join(root, 'scratch', 'primecare_formulary.json');
const BATCH_SIZE = 40;

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

function productDescription(item) {
  const parts = [];
  if (item.generic?.trim()) parts.push(`Generic: ${item.generic.trim()}`);
  if (item.strength?.trim()) parts.push(`Strength: ${item.strength.trim()}`);
  if (item.form?.trim()) parts.push(`Form: ${item.form.trim()}`);
  if (item.pack) parts.push(`Pack: ${item.pack}`);
  parts.push(`In stock: ${item.stock_qty ?? 0}`);
  return parts.join(' · ').slice(0, 500);
}

function mapCategory(raw) {
  const c = String(raw || 'Pharmacy').trim();
  if (!c || c.length < 2) return 'Pharmacy';
  return c.slice(0, 80);
}

async function main() {
  if (!fs.existsSync(FORMULARY_PATH)) {
    console.error(`Missing ${FORMULARY_PATH}`);
    console.error('Run: python scripts/parse_drug_formulary.py');
    process.exit(1);
  }

  const formulary = JSON.parse(fs.readFileSync(FORMULARY_PATH, 'utf8'));
  if (!Array.isArray(formulary) || formulary.length === 0) {
    console.error('Formulary JSON is empty');
    process.exit(1);
  }

  const hashed = await bcrypt.hash(VENDOR.password, 10);

  const vendorRes = await pool.query(
    `INSERT INTO users (name, email, password, role, region, address, lat, lng, phone, status, shop_category, balance)
     VALUES ($1, $2, $3, 'vendor', $4, $5, $6, $7, $8, 'active', $9, 0)
     ON CONFLICT (email) DO UPDATE SET
       name = EXCLUDED.name,
       password = EXCLUDED.password,
       region = EXCLUDED.region,
       address = EXCLUDED.address,
       lat = EXCLUDED.lat,
       lng = EXCLUDED.lng,
       phone = EXCLUDED.phone,
       status = 'active',
       shop_category = EXCLUDED.shop_category
     RETURNING id, name, email, shop_category`,
    [
      VENDOR.name,
      VENDOR.email,
      hashed,
      VENDOR.region,
      VENDOR.address,
      VENDOR.lat,
      VENDOR.lng,
      VENDOR.phone,
      VENDOR.shop_category,
    ],
  );

  const vendorId = vendorRes.rows[0].id;
  console.log(`Vendor: ${vendorRes.rows[0].name} (${vendorRes.rows[0].email})`);
  console.log(`  Category: ${vendorRes.rows[0].shop_category}`);
  console.log(`  ID: ${vendorId}`);

  const del = await pool.query('DELETE FROM products WHERE vendor_id = $1', [vendorId]);
  console.log(`Cleared ${del.rowCount} existing products for this pharmacy`);

  let inserted = 0;
  for (let i = 0; i < formulary.length; i += BATCH_SIZE) {
    const batch = formulary.slice(i, i + BATCH_SIZE);
    const values = [];
    const params = [];
    let p = 1;

    for (const item of batch) {
      values.push(
        `($${p++}, $${p++}, $${p++}, $${p++}, $${p++}, true, true)`,
      );
      params.push(
        vendorId,
        item.name,
        productDescription(item),
        item.unit_price,
        mapCategory(item.category),
      );
    }

    await pool.query(
      `INSERT INTO products (vendor_id, name, description, price, category, is_available, is_approved)
       VALUES ${values.join(', ')}`,
      params,
    );
    inserted += batch.length;
    if (inserted % 200 === 0 || inserted === formulary.length) {
      console.log(`  … ${inserted}/${formulary.length} products`);
    }
  }

  const countRes = await pool.query(
    'SELECT COUNT(*)::int AS n FROM products WHERE vendor_id = $1',
    [vendorId],
  );

  console.log('');
  console.log(`Done — ${countRes.rows[0].n} medicines listed for Primecare Pharmacy.`);
  console.log('');
  console.log('Merchant login (vendor app / web):');
  console.log(`  Email:    ${VENDOR.email}`);
  console.log(`  Password: ${VENDOR.password}`);
  console.log('');
  console.log('Customers: open Pharmacy tab → Primecare Pharmacy');
}

main()
  .catch((err) => {
    console.error('Seed failed:', err.message);
    process.exit(1);
  })
  .finally(() => pool.end());
