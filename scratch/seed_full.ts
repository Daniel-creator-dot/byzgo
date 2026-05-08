import axios from 'axios';

async function seed() {
  console.log('Starting DB Seeding...');

  // 1. Create Vendors
  const vendors = [
    { name: 'KFC East Legon', email: 'kfc@example.com', password: 'password123', role: 'vendor' },
    { name: 'Starbites', email: 'starbites@example.com', password: 'password123', role: 'vendor' },
    { name: 'Pizzaman CEO', email: 'pizzaman@example.com', password: 'password123', role: 'vendor' },
    { name: 'Mama\'s Kitchen', email: 'mama@example.com', password: 'password123', role: 'vendor' }
  ];

  const vendorTokens: { [key: string]: string } = {};

  for (const v of vendors) {
    try {
      const res = await axios.post('http://localhost:3000/api/auth/register', v);
      vendorTokens[v.email] = res.data.token;
      console.log(`Created vendor: ${v.name}`);
    } catch (err: any) {
      if (err.response?.status === 400) {
         // Login instead if exists
         const loginRes = await axios.post('http://localhost:3000/api/auth/login', { email: v.email, password: v.password });
         vendorTokens[v.email] = loginRes.data.token;
         console.log(`Vendor already exists, logged in: ${v.name}`);
      } else {
         console.error(`Failed to create vendor ${v.name}:`, err.message);
      }
    }
  }

  // 2. Create Products for each vendor
  const vendorProducts = {
    'kfc@example.com': [
      { name: 'Zinger Burger Meal', description: 'Spicy chicken fillet, fries, and a drink', price: 85.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&q=80&w=400' },
      { name: 'Streetwise 3', description: '3 pieces of crunchy chicken with chips', price: 65.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1626082927389-6cd097cdc6ec?auto=format&fit=crop&q=80&w=400' },
      { name: 'Krushers Oreo', description: 'Ice cold blended treat', price: 35.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1572490122747-3968b75cc699?auto=format&fit=crop&q=80&w=400' }
    ],
    'starbites@example.com': [
      { name: 'Full English Breakfast', description: 'Eggs, bacon, sausages, beans, and toast', price: 120.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1533089860892-a7c6f0a88666?auto=format&fit=crop&q=80&w=400' },
      { name: 'Iced Caramel Macchiato', description: 'Espresso, milk, and caramel syrup over ice', price: 45.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1559525839-b184a4d698c7?auto=format&fit=crop&q=80&w=400' }
    ],
    'pizzaman@example.com': [
      { name: 'Meat Lovers Pizza (Large)', description: 'Loaded with beef, pepperoni, and sausage', price: 150.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&q=80&w=400' },
      { name: 'Chicken Supreme', description: 'Chicken chunks, bell peppers, and olives', price: 135.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&q=80&w=400' }
    ],
    'mama@example.com': [
      { name: 'Assorted Jollof Rice', description: 'Ghanaian jollof with beef, chicken, and sausage', price: 60.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1644793610931-1b03d526e061?auto=format&fit=crop&q=80&w=400' },
      { name: 'Fufu & Light Soup', description: 'Traditional fufu with goat meat light soup', price: 55.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1544145945-f904253db0ad?auto=format&fit=crop&q=80&w=400' }, // fallback image
      { name: 'Waakye Special', description: 'Waakye with spaghetti, gari, egg, and fish', price: 40.00, category: 'Food', image_url: 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?auto=format&fit=crop&q=80&w=400' } // fallback image
    ]
  };

  for (const [email, products] of Object.entries(vendorProducts)) {
    const token = vendorTokens[email];
    if (!token) continue;

    for (const p of products) {
      try {
        await axios.post('http://localhost:3000/api/products', p, {
          headers: { Authorization: `Bearer ${token}` }
        });
        console.log(`Added product ${p.name} for ${email}`);
      } catch (err: any) {
        console.error(`Failed to add product ${p.name}:`, err.message);
      }
    }
  }

  console.log('Seeding Complete!');
}

seed();
