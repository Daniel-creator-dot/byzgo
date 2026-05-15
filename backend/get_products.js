const { Pool } = require('pg');

const pool = new Pool({
  connectionString: 'postgresql://postgres.ypmiurbtmfiyzmrygonh:Daniel%4024419000@aws-1-eu-central-1.pooler.supabase.com:5432/postgres',
  ssl: { rejectUnauthorized: false }
});

async function main() {
  try {
    const res = await pool.query('SELECT id, name, category, image_url FROM products');
    console.log(JSON.stringify(res.rows, null, 2));
  } catch (e) {
    console.error(e);
  } finally {
    await pool.end();
  }
}

main();
