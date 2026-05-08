import axios from 'axios';

async function test() {
  try {
    const res = await axios.post('http://localhost:3000/api/auth/register', {
      name: 'Test User',
      email: 'test@example.com',
      password: 'password123',
      role: 'customer'
    });
    console.log('Registration Success:', res.data);
    
    const loginRes = await axios.post('http://localhost:3000/api/auth/login', {
      email: 'test@example.com',
      password: 'password123'
    });
    console.log('Login Success:', loginRes.data);
  } catch (err) {
    console.error('Test Failed:', err.response?.data || err.message);
  }
}

test();
