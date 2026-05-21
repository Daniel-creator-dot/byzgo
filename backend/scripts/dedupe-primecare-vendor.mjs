/**
 * Remove duplicate Primecare Pharmacy vendor accounts (keep one canonical shop).
 *
 *   npm run dedupe:primecare
 *
 * Keeps: vendor@bytzgo.net, or the vendor with the most products, or the oldest row.
 */
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import pg from 'pg';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..', '..');

dotenv.config({ path: path.join(__dirname, '..', '.env') });
dotenv.config({ path: path.join(root, '.env.local') });

const CANONICAL_EMAIL = 'vendor@bytzgo.net';

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

function isPrimeCareName(name) {
  const n = String(name || '').toLowerCase().replace(/\s+/g, '');
  return n.includes('primecare') || n.includes('primecarepharmacy');
}

async function listPrimeCareVendors() {
  const res = await pool.query(
    `SELECT u.id, u.name, u.email, u.created_at,
            (SELECT COUNT(*)::int FROM products p WHERE p.vendor_id = u.id) AS product_count
     FROM users u
     WHERE u.role = 'vendor'
       AND (
         LOWER(u.name) LIKE '%primecare%'
         OR LOWER(u.name) LIKE '%prime care%'
         OR LOWER(u.email) = LOWER($1)
       )
     ORDER BY
       (LOWER(u.email) = LOWER($1)) DESC,
       product_count DESC,
       u.created_at ASC`,
    [CANONICAL_EMAIL],
  );
  return res.rows;
}

async function deleteVendor(client, vendorId) {
  const activeRes = await client.query(
    `SELECT COUNT(*)::int AS n FROM orders
     WHERE vendor_id = $1 AND status NOT IN ('delivered', 'cancelled')`,
    [vendorId],
  );
  const activeOrders = activeRes.rows[0]?.n ?? 0;
  if (activeOrders > 0) {
    throw new Error(
      `Vendor ${vendorId} has ${activeOrders} active order(s) — finish or cancel them first`,
    );
  }
  await client.query('DELETE FROM products WHERE vendor_id = $1', [vendorId]);
  await client.query('UPDATE orders SET vendor_id = NULL WHERE vendor_id = $1', [vendorId]);
  await client.query('DELETE FROM wallet_transactions WHERE user_id = $1', [vendorId]);
  await client.query('DELETE FROM users WHERE id = $1 AND role = $2', [vendorId, 'vendor']);
}

async function main() {
  const rows = await listPrimeCareVendors();
  if (rows.length === 0) {
    console.log('No Primecare vendor rows found. Run: npm run seed:primecare');
    return;
  }
  if (rows.length === 1) {
    console.log(`Single Primecare vendor OK: ${rows[0].name} (${rows[0].email})`);
    return;
  }

  const keeper = rows[0];
  const duplicates = rows.slice(1);
  console.log(`Keeping: ${keeper.name} (${keeper.email}) — ${keeper.product_count} products`);
  console.log(`Removing ${duplicates.length} duplicate(s):`);
  for (const d of duplicates) {
    console.log(`  - ${d.name} (${d.email}) — ${d.product_count} products`);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const dup of duplicates) {
      // Do not merge product rows — both shops often share the same formulary (duplicates).
      await deleteVendor(client, dup.id);
      console.log(`  Deleted vendor ${dup.email}`);
    }
    await client.query('COMMIT');
    const countRes = await pool.query(
      'SELECT COUNT(*)::int AS n FROM products WHERE vendor_id = $1',
      [keeper.id],
    );
    console.log('');
    console.log(`Done. One Primecare shop: ${keeper.email} (${countRes.rows[0].n} products).`);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

main()
  .catch((err) => {
    console.error('Dedupe failed:', err.message);
    process.exit(1);
  })
  .finally(() => pool.end());
