/**
 * DEPRECATED — do not run on production after COD wallet fix (May 2026).
 * Older COD deliveries debited vendor share without crediting cash first.
 * Running this now adds COD credits that inflate wallet balance incorrectly.
 * Use backend/scripts/repair-rider-spendable-balances.mjs instead if needed.
 */
import pg from 'pg';
import dotenv from 'dotenv';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '../.env') });

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

async function main() {
  const orders = await pool.query(`
    SELECT o.id, o.rider_id, o.vendor_id, o.total
    FROM orders o
    WHERE o.status = 'delivered'
      AND o.payment_status IS DISTINCT FROM 'paid'
      AND o.rider_id IS NOT NULL
  `);

  let fixed = 0;
  for (const o of orders.rows) {
    const shortId = String(o.id).slice(0, 8);
    const collectRef = `COD collected · Order #${shortId}`;
    const existing = await pool.query(
      `SELECT 1 FROM wallet_transactions WHERE user_id = $1 AND reference = $2 LIMIT 1`,
      [o.rider_id, collectRef]
    );
    if (existing.rowCount > 0) continue;

    const total = parseFloat(o.total);
    if (!Number.isFinite(total) || total <= 0) continue;
    const vendorShare =
      o.vendor_id && String(o.vendor_id).trim() ? Math.round(total * 0.8 * 100) / 100 : 0;

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      await client.query('UPDATE users SET balance = balance + $1 WHERE id = $2', [
        total,
        o.rider_id,
      ]);
      await client.query(
        `INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)`,
        [o.rider_id, total, 'payment', collectRef]
      );
      if (vendorShare > 0) {
        await client.query('UPDATE users SET balance = balance - $1 WHERE id = $2', [
          vendorShare,
          o.rider_id,
        ]);
        await client.query(
          `INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)`,
          [
            o.rider_id,
            -vendorShare,
            'payment',
            `COD vendor share · Order #${shortId} (repair)`,
          ]
        );
      }
      await client.query('COMMIT');
      fixed += 1;
      console.log(`Repaired rider ${o.rider_id} order ${shortId}`);
    } catch (err) {
      await client.query('ROLLBACK');
      console.error(`Failed order ${shortId}:`, err.message);
    } finally {
      client.release();
    }
  }

  console.log(`Done. Repaired ${fixed} order(s).`);
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
