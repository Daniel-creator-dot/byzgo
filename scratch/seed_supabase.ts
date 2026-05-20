import { Pool } from 'pg';
import bcrypt from 'bcryptjs';

const pool = new Pool({
  connectionString: 'postgresql://postgres.ypmiurbtmfiyzmrygonh:Daniel%4024419000@aws-1-eu-central-1.pooler.supabase.com:5432/postgres',
  ssl: { rejectUnauthorized: false }
});

async function seed() {
  try {
    // First, list all tables
    const tablesResult = await pool.query(`
      SELECT table_name FROM information_schema.tables 
      WHERE table_schema = 'public' 
      ORDER BY table_name
    `);
    console.log('\n=== EXISTING TABLES ===');
    tablesResult.rows.forEach(r => console.log(' -', r.table_name));
    console.log(`Total: ${tablesResult.rows.length} tables\n`);

    // Hash passwords
    const defaultPassword = await bcrypt.hash('Test@1234', 10);
    const customerPassword = await bcrypt.hash('Customer@1234', 10);
    const vendorPassword = await bcrypt.hash('Vendor@2026', 10);

    // Seed users for each role
    const users = [
      { name: 'Kofi Mensah', email: 'customer@bytzgo.net', role: 'customer', region: 'Greater Accra', password: customerPassword },
      { name: 'Ama Serwaa', email: 'customer2@bytzgo.com', role: 'customer', region: 'Ashanti', password: defaultPassword },
      { name: 'Primecare Pharmacy', email: 'vendor@bytzgo.net', role: 'vendor', region: 'Greater Accra', address: 'Ring Road Central, Accra', lat: 5.5717, lng: -0.2107, password: vendorPassword, shop_category: 'pharmacy' },
      { name: 'Accra Eats Kitchen', email: 'vendor2@bytzgo.com', role: 'vendor', region: 'Greater Accra', address: 'East Legon, Accra', lat: 5.6350, lng: -0.1570, password: defaultPassword },
      { name: 'Yaw Speed', email: 'rider@bytzgo.com', role: 'rider', region: 'Greater Accra', password: defaultPassword },
      { name: 'Kwesi Flash', email: 'rider2@bytzgo.com', role: 'rider', region: 'Greater Accra', password: defaultPassword },
      { name: 'Admin BytzGo', email: 'admin@bytzgo.com', role: 'admin', region: 'Greater Accra', password: defaultPassword },
    ];

    console.log('=== SEEDING USERS ===');
    for (const u of users) {
      try {
        const shopCat = (u as any).shop_category || 'food';
        const result = await pool.query(
          `INSERT INTO users (name, email, password, role, region, address, lat, lng, balance, status, shop_category) 
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) 
           ON CONFLICT (email) DO UPDATE SET name = $1, password = $3, shop_category = $11
           RETURNING id, name, email, role`,
          [u.name, u.email, (u as any).password ?? defaultPassword, u.role, u.region || null, (u as any).address || null, (u as any).lat || null, (u as any).lng || null, 100.00, 'active', shopCat]
        );
        console.log(` ✅ ${result.rows[0].role.padEnd(8)} | ${result.rows[0].name} (${result.rows[0].email})`);
      } catch (err: any) {
        console.log(` ❌ Failed: ${u.email} - ${err.message}`);
      }
    }

    // Seed some products for vendors
    console.log('\n=== SEEDING PRODUCTS ===');
    const vendor2Result = await pool.query("SELECT id FROM users WHERE email = 'vendor2@bytzgo.com'");
    
    if (vendor2Result.rows[0]) {
      const vendor2Id = vendor2Result.rows[0].id;

      const products = [
        { vendor_id: vendor2Id, name: 'Fried Rice & Beef', description: 'Special fried rice with tender beef strips', price: 38.00, category: 'Food', is_approved: true },
        { vendor_id: vendor2Id, name: 'Fufu & Light Soup', description: 'Pounded fufu with goat meat light soup', price: 45.00, category: 'Food', is_approved: true },
        { vendor_id: vendor2Id, name: 'Meat Pie', description: 'Freshly baked meat pie', price: 12.00, category: 'Snacks', is_approved: true },
        { vendor_id: vendor2Id, name: 'Fresh Fruit Juice', description: 'Blended mango and pineapple juice', price: 10.00, category: 'Drinks', is_approved: true },
      ];

      for (const p of products) {
        try {
          await pool.query(
            `INSERT INTO products (vendor_id, name, description, price, category, is_approved) 
             VALUES ($1, $2, $3, $4, $5, $6)
             ON CONFLICT DO NOTHING`,
            [p.vendor_id, p.name, p.description, p.price, p.category, p.is_approved]
          );
          console.log(` ✅ ${p.name} - GH₵${p.price.toFixed(2)}`);
        } catch (err: any) {
          console.log(` ❌ Failed: ${p.name} - ${err.message}`);
        }
      }
    }

    // Seed a delivery zone
    console.log('\n=== SEEDING DELIVERY ZONES ===');
    try {
      await pool.query(
        `INSERT INTO delivery_zones (name, region, base_price, price_per_km, min_price, max_price, is_active) 
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         ON CONFLICT DO NOTHING`,
        ['Greater Accra Zone', 'Greater Accra', 10.00, 2.50, 8.00, 50.00, true]
      );
      console.log(' ✅ Greater Accra Zone');
    } catch (err: any) {
      console.log(` ❌ ${err.message}`);
    }

    // Final table counts
    console.log('\n=== TABLE COUNTS ===');
    const counts = ['users', 'products', 'orders', 'rider_locations', 'delivery_zones'];
    for (const table of counts) {
      try {
        const res = await pool.query(`SELECT COUNT(*) FROM ${table}`);
        console.log(` ${table}: ${res.rows[0].count} rows`);
      } catch {
        console.log(` ${table}: (table not found)`);
      }
    }

    console.log('\n=== LOGIN CREDENTIALS ===');
    console.log(' Customer:  customer@bytzgo.net / Customer@1234');
    console.log(' Other roles: Test@1234');
    console.log(' Customer2: customer2@bytzgo.com');
    console.log(' Vendor:    vendor@bytzgo.net / Vendor@2026 (Primecare Pharmacy — run npm run seed:primecare for stock)');
    console.log(' Vendor2:   vendor2@bytzgo.com');
    console.log(' Rider:     rider@bytzgo.com');
    console.log(' Rider2:    rider2@bytzgo.com');
    console.log(' Admin:     admin@bytzgo.com');

  } catch (err) {
    console.error('Seed failed:', err);
  } finally {
    await pool.end();
  }
}

seed();
