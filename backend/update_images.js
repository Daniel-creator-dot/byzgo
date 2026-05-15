const { Pool } = require('pg');

const pool = new Pool({
  connectionString: 'postgresql://postgres.ypmiurbtmfiyzmrygonh:Daniel%4024419000@aws-1-eu-central-1.pooler.supabase.com:5432/postgres',
  ssl: { rejectUnauthorized: false }
});

const imageMapping = {
  "Jollof Rice & Chicken": "https://images.unsplash.com/photo-1512058564366-18510be2db19?w=600&q=80",
  "Banku & Tilapia": "https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=600&q=80",
  "Waakye Special": "https://images.unsplash.com/photo-1543339308-43e59d6b73a6?w=600&q=80",
  "Kelewele & Peanuts": "https://images.unsplash.com/photo-1604908176997-125f25cc6f3d?w=600&q=80",
  "Fried Rice & Beef": "https://images.unsplash.com/photo-1603133872878-684f208fb84b?w=600&q=80",
  "Fufu & Light Soup": "https://images.unsplash.com/photo-1547592180-85f173990554?w=600&q=80",
  "Meat Pie": "https://images.unsplash.com/photo-1512485800893-b08ec1ea59b1?w=600&q=80",
  "Fresh Fruit Juice": "https://images.unsplash.com/photo-1600271886742-f049cd451bba?w=600&q=80"
};

async function main() {
  try {
    for (const [name, url] of Object.entries(imageMapping)) {
      await pool.query('UPDATE products SET image_url = $1 WHERE name = $2', [url, name]);
      console.log(`Updated ${name}`);
    }
    console.log("All products updated successfully.");
  } catch (e) {
    console.error("Error updating products:", e);
  } finally {
    await pool.end();
  }
}

main();
