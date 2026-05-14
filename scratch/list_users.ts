import { Pool } from 'pg';
import dotenv from 'dotenv';
import path from 'path';

import { fileURLToPath } from 'url';
const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

async function checkData() {
  try {
    const tables = ['users', 'products', 'orders', 'rider_locations', 'delivery_zones'];
    console.log('Row counts in tables:');
    for (const table of tables) {
      const result = await pool.query(`SELECT COUNT(*) FROM ${table}`);
      console.log(`${table.padEnd(20)}: ${result.rows[0].count} rows`);
    }
  } catch (err) {
    console.error('Error querying database:', err);
  } finally {
    await pool.end();
  }
}

checkData();
