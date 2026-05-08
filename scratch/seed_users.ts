import axios from 'axios';

async function seed() {
  const users = [
    { name: 'Admin User', email: 'admin@example.com', password: 'password123', role: 'admin' },
    { name: 'Vendor Shop', email: 'vendor@example.com', password: 'password123', role: 'vendor' },
    { name: 'Speedy Rider', email: 'rider@example.com', password: 'password123', role: 'rider' },
    { name: 'John Customer', email: 'test@example.com', password: 'password123', role: 'customer' }
  ];

  for (const user of users) {
    try {
      await axios.post('http://localhost:3000/api/auth/register', user);
      console.log(`User created: ${user.email} (${user.role})`);
    } catch (err) {
      console.log(`User exists: ${user.email}`);
    }
  }
}

seed();
