/**
 * Sync rider users.balance to spendable funds (excludes COD cash-in-pocket ledger).
 * Run once after COD wallet fix: node backend/scripts/sync-rider-spendable-balances.mjs
 */
import pg from 'pg';
import dotenv from 'dotenv';
import { fileURLToPath } from 'url';
import path from 'path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '../.env') });

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });

const COD_SQL = `(reference LIKE 'COD collected%' OR reference LIKE 'COD vendor share%')`;
const EXTERNAL_COMMISSION_SQL = `(reference LIKE 'MoMo/card commission%')`;

async function spendableForRider(client, riderId) {
  const countRes = await client.query(
    'SELECT COUNT(*)::int AS n FROM wallet_transactions WHERE user_id = $1',
    [riderId]
  );
  const hasLedger = parseInt(String(countRes.rows[0]?.n ?? 0), 10) > 0;

  if (hasLedger) {
    const ledgerRes = await client.query(
      `SELECT COALESCE(SUM(amount), 0)::float AS spendable
       FROM wallet_transactions
       WHERE user_id = $1
         AND NOT ${COD_SQL}
         AND NOT ${EXTERNAL_COMMISSION_SQL}`,
      [riderId]
    );
    return Math.max(0, Math.round(parseFloat(ledgerRes.rows[0]?.spendable ?? 0) * 100) / 100);
  }

  const balRes = await client.query('SELECT balance FROM users WHERE id = $1', [riderId]);
  const raw = parseFloat(balRes.rows[0]?.balance ?? 0);
  const codRes = await client.query(
    `SELECT COALESCE(SUM(amount), 0)::float AS cod_net
     FROM wallet_transactions WHERE user_id = $1 AND ${COD_SQL}`,
    [riderId]
  );
  const codNet = parseFloat(codRes.rows[0]?.cod_net ?? 0);
  return Math.max(0, Math.round((raw - codNet) * 100) / 100);
}

async function main() {
  const riders = await pool.query(`SELECT id, balance FROM users WHERE role = 'rider'`);
  let updated = 0;

  for (const rider of riders.rows) {
    const client = await pool.connect();
    try {
      const spendable = await spendableForRider(client, rider.id);
      const raw = parseFloat(rider.balance ?? 0);
      if (Math.abs(raw - spendable) < 0.01) continue;

      await client.query('UPDATE users SET balance = $1 WHERE id = $2', [spendable, rider.id]);
      updated += 1;
      console.log(`Rider ${rider.id}: ${raw.toFixed(2)} → ${spendable.toFixed(2)}`);
    } finally {
      client.release();
    }
  }

  console.log(`Done. Synced ${updated} rider balance(s).`);
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
