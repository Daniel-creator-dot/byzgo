import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import dotenv from 'dotenv';
import { Pool } from 'pg';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import * as admin from 'firebase-admin';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import axios from 'axios';

dotenv.config();

admin.initializeApp({
  projectId: "bytzgo-72f1c"
});

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, {
  cors: {
    origin: '*',
    methods: ['GET', 'POST', 'PATCH']
  }
});

app.use(cors());
app.use(express.json());



// Multer config for in-memory processing (images stored in DB as Base64)
const upload = multer({ 
  storage: multer.memoryStorage(), 
  limits: { fileSize: 5 * 1024 * 1024 } // 5MB limit
});

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('supabase.com') ? { rejectUnauthorized: false } : false
});

// Helper to get system settings from DB
async function getSetting(key: string) {
  try {
    const result = await pool.query('SELECT value FROM system_settings WHERE key = $1', [key]);
    return result.rows[0]?.value;
  } catch (err) {
    console.error(`Error fetching setting ${key}:`, err);
    return null;
  }
}

// Database Initialization
const initDb = async () => {
  try {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS users (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        email TEXT UNIQUE NOT NULL,
        password TEXT,
        phone TEXT,
        google_id TEXT,
        cover_image TEXT,
        address TEXT,
        lat DOUBLE PRECISION,
        lng DOUBLE PRECISION,
        role TEXT NOT NULL CHECK (role IN ('customer', 'vendor', 'rider', 'admin')),
        balance DECIMAL(10,2) DEFAULT 0.00,
        status TEXT DEFAULT 'active',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Add columns if they don't exist (for existing databases)
      DO $$ BEGIN
        ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS cover_image TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';
        ALTER TABLE users ADD COLUMN IF NOT EXISTS region TEXT;
        ALTER TABLE users ALTER COLUMN password DROP NOT NULL;
      EXCEPTION WHEN others THEN NULL;
      END $$;

      CREATE TABLE IF NOT EXISTS products (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        vendor_id UUID REFERENCES users(id),
        name TEXT NOT NULL,
        description TEXT,
        price DECIMAL(10,2) NOT NULL,
        category TEXT,
        image_url TEXT,
        is_available BOOLEAN DEFAULT true,
        is_approved BOOLEAN DEFAULT false,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      DO $$ BEGIN
        ALTER TABLE products ADD COLUMN IF NOT EXISTS is_approved BOOLEAN DEFAULT false;
      EXCEPTION WHEN others THEN NULL;
      END $$;

      CREATE TABLE IF NOT EXISTS orders (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        customer_id UUID REFERENCES users(id),
        vendor_id UUID REFERENCES users(id),
        rider_id UUID REFERENCES users(id),
        items JSONB NOT NULL,
        total DECIMAL(10,2) NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        address TEXT NOT NULL,
        pickup_address TEXT,
        order_type TEXT DEFAULT 'food',
        scheduled_time TIMESTAMP WITH TIME ZONE,
        rating INTEGER,
        rating_comment TEXT,
        lat DOUBLE PRECISION,
        lng DOUBLE PRECISION,
        pickup_lat DOUBLE PRECISION,
        pickup_lng DOUBLE PRECISION,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      DO $$ BEGIN
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS rating INTEGER;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS rating_comment TEXT;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS lat DOUBLE PRECISION;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS lng DOUBLE PRECISION;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_lat DOUBLE PRECISION;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_lng DOUBLE PRECISION;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS region TEXT;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'pending';
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS payment_method TEXT;
      EXCEPTION WHEN others THEN NULL;
      END $$;

      CREATE TABLE IF NOT EXISTS rider_locations (
        rider_id UUID PRIMARY KEY REFERENCES users(id),
        lat DOUBLE PRECISION NOT NULL,
        lng DOUBLE PRECISION NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS delivery_zones (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        name TEXT NOT NULL,
        region TEXT NOT NULL,
        base_price DECIMAL(10,2) NOT NULL DEFAULT 10.00,
        price_per_km DECIMAL(10,2) NOT NULL DEFAULT 2.00,
        min_price DECIMAL(10,2) NOT NULL DEFAULT 5.00,
        max_price DECIMAL(10,2) DEFAULT NULL,
        is_active BOOLEAN DEFAULT true,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS wallet_transactions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id),
        amount DECIMAL(10,2) NOT NULL,
        type TEXT NOT NULL CHECK (type IN ('topup', 'withdrawal', 'commission', 'payment')),
        status TEXT DEFAULT 'success',
        reference TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Paystack keys are now managed via DB directly or Admin UI
    `);
    // Fix existing courier orders that were mislabeled as food
    await pool.query(`
      UPDATE orders 
      SET order_type = 'courier' 
      WHERE order_type = 'food' 
      AND items::text LIKE '%courier-1%'
    `);
    console.log('Database initialized successfully');
  } catch (err) {
    console.error('Database initialization failed:', err);
  }
};

initDb();

// Middleware
const authenticateToken = (req: any, res: any, next: any) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token) return res.sendStatus(401);

  jwt.verify(token, process.env.JWT_SECRET as string, async (err: any, user: any) => {
    if (err) return res.sendStatus(403);
    
    // Check if user is still active in DB
    try {
      const result = await pool.query('SELECT status FROM users WHERE id = $1', [user.id]);
      if (result.rowCount === 0 || result.rows[0].status === 'disabled') {
        return res.status(403).json({ error: 'Account disabled or not found' });
      }
      req.user = user;
      next();
    } catch (dbErr) {
      res.status(500).json({ error: 'Auth server error' });
    }
  });
};

// Auth Routes
app.post('/api/auth/register', async (req, res) => {
  const { name, email, password, role } = req.body;
  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    const result = await pool.query(
      'INSERT INTO users (name, email, password, role) VALUES ($1, $2, $3, $4) RETURNING id, name, email, role, balance',
      [name, email, hashedPassword, role]
    );
    const user = result.rows[0];
    const token = jwt.sign(user, process.env.JWT_SECRET as string);
    res.json({ user, token });
  } catch (err) {
    res.status(400).json({ message: 'Email already exists' });
  }
});

app.post('/api/auth/login', async (req, res) => {
  const { email, password } = req.body;
  try {
    const result = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
    const user = result.rows[0];
    if (user && user.password && await bcrypt.compare(password, user.password)) {
      const { password, ...userWithoutPassword } = user;
      const token = jwt.sign(userWithoutPassword, process.env.JWT_SECRET as string);
      res.json({ user: userWithoutPassword, token });
    } else {
      res.status(401).json({ message: 'Invalid credentials' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Google Auth
app.post('/api/auth/google', async (req, res) => {
  const { credential, role } = req.body;
  try {
    const decodedToken = await admin.auth().verifyIdToken(credential);
    const payload = decodedToken;
    if (!payload || !payload.email) {
      return res.status(400).json({ message: 'Invalid Google token' });
    }
    
    // Check if user exists
    let result = await pool.query('SELECT * FROM users WHERE email = $1', [payload.email]);
    let user = result.rows[0];
    
    if (!user) {
      // Register new user from Google
      result = await pool.query(
        'INSERT INTO users (name, email, google_id, role) VALUES ($1, $2, $3, $4) RETURNING id, name, email, role, balance, phone',
        [payload.name, payload.email, payload.sub, role || 'customer']
      );
      user = result.rows[0];
    } else {
      // Update google_id if not set
      if (!user.google_id) {
        await pool.query('UPDATE users SET google_id = $1 WHERE id = $2', [payload.sub, user.id]);
      }
      const { password, ...u } = user;
      user = u;
    }
    
    const token = jwt.sign({ id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance }, process.env.JWT_SECRET as string);
    res.json({ user, token });
  } catch (err: any) {
    console.error('Google auth error:', err);
    res.status(500).json({ message: 'Google authentication failed' });
  }
});

// Profile Update
app.patch('/api/auth/profile', authenticateToken, async (req: any, res) => {
  const { email, phone, cover_image, address, lat, lng, region } = req.body;
  try {
    const result = await pool.query(
      `UPDATE users SET 
        email = COALESCE($1, email), 
        phone = COALESCE($2, phone),
        cover_image = COALESCE($3, cover_image),
        address = COALESCE($4, address),
        lat = COALESCE($5, lat),
        lng = COALESCE($6, lng),
        region = COALESCE($7, region)
       WHERE id = $8 
       RETURNING id, name, email, role, balance, phone, cover_image, address, lat, lng, region, status`,
      [email, phone, cover_image, address, lat, lng, region, req.user.id]
    );
    const user = result.rows[0];
    const token = jwt.sign({ id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance, status: user.status, region: user.region }, process.env.JWT_SECRET as string);
    res.json({ user, token });
  } catch (err: any) {
    console.error('Profile update error:', err);
    res.status(500).json({ message: 'Profile update failed' });
  }
});

// Status Update
app.patch('/api/auth/status', authenticateToken, async (req: any, res) => {
  const { status } = req.body;
  try {
    const result = await pool.query(
      'UPDATE users SET status = $1 WHERE id = $2 RETURNING id, name, email, role, balance, phone, cover_image, address, lat, lng, status, region',
      [status, req.user.id]
    );
    const user = result.rows[0];
    const token = jwt.sign({ id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance, status: user.status, region: user.region }, process.env.JWT_SECRET as string);
    res.json({ user, token });
  } catch (err: any) {
    console.error('Status update error:', err);
    res.status(500).json({ message: 'Status update failed' });
  }
});


// Wallet Routes
app.get('/api/wallet', authenticateToken, async (req: any, res) => {
  try {
    const result = await pool.query('SELECT balance FROM users WHERE id = $1', [req.user.id]);
    res.json({ balance: parseFloat(result.rows[0].balance) });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// File Upload (returns Base64 Data URL to be stored in DB)
app.post('/api/upload', authenticateToken, upload.single('image'), (req: any, res) => {
  if (!req.file) return res.status(400).json({ message: 'No file uploaded' });
  const base64 = `data:${req.file.mimetype};base64,${req.file.buffer.toString('base64')}`;
  res.json({ url: base64 });
});

app.post('/api/wallet/topup', authenticateToken, async (req: any, res) => {
  const { reference } = req.body;
  try {
    const secretKey = await getSetting('paystack_secret_key');
    const response = await axios.get(`https://api.paystack.co/transaction/verify/${reference}`, {
      headers: {
        Authorization: `Bearer ${secretKey}`
      }
    });

    if (response.data.data.status === 'success') {
      const amount = response.data.data.amount / 100; // GHS
      const result = await pool.query(
        'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
        [amount, req.user.id]
      );

      // Log transaction
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [req.user.id, amount, 'topup', reference]
      );

      res.json({ balance: parseFloat(result.rows[0].balance) });
      io.to(req.user.id).emit('wallet:updated', { balance: parseFloat(result.rows[0].balance) });
    } else {
      res.status(400).json({ message: 'Payment verification failed' });
    }
  } catch (err) {
    console.error('Paystack verification error:', err);
    res.status(500).json({ message: 'Server error during verification' });
  }
});

app.get('/api/config/paystack', async (_req, res) => {
  try {
    const publicKey = await getSetting('paystack_public_key');
    res.json({ publicKey });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch config' });
  }
});

app.post('/api/wallet/withdraw', authenticateToken, async (req: any, res) => {
  const { amount, phone, network } = req.body; // In a real app, you'd integrate Mobile Money API
  try {
    // Check if user has enough balance
    const userRes = await pool.query('SELECT balance FROM users WHERE id = $1', [req.user.id]);
    if (parseFloat(userRes.rows[0].balance) < amount) {
      return res.status(400).json({ message: 'Insufficient balance' });
    }
    
    // Deduct balance
    const result = await pool.query(
      'UPDATE users SET balance = balance - $1 WHERE id = $2 RETURNING balance',
      [amount, req.user.id]
    );

    // Log transaction
    await pool.query(
      'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
      [req.user.id, amount, 'withdrawal', `Withdrawal to ${phone} (${network})`]
    );

    const newBalance = parseFloat(result.rows[0].balance);
    res.json({ balance: newBalance, message: 'Withdrawal successful' });
    io.to(req.user.id).emit('wallet:updated', { balance: newBalance });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// User & Vendor Routes
app.get('/api/vendors', async (req, res) => {
  const { region } = req.query;
  try {
    let query = 'SELECT id, name, email, phone, cover_image, address, lat, lng, region FROM users WHERE role = $1';
    const params: any[] = ['vendor'];
    
    if (region) {
      query += ' AND (region = $2 OR region IS NULL)';
      params.push(region);
    }
    
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/products', async (req, res) => {
  const { vendor_id } = req.query;
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];
  let user: any = null;
  if (token) {
    try { user = jwt.verify(token, process.env.JWT_SECRET as string); } catch(e) {}
  }

  try {
    let query = 'SELECT * FROM products WHERE is_available = true';
    let params = [];
    
    // Only show unapproved if requester is the vendor themselves or admin
    if (!user || (user.role !== 'admin' && user.id !== vendor_id)) {
       query += ' AND is_approved = true';
    }

    if (vendor_id) {
      query += ' AND vendor_id = $' + (params.length + 1);
      params.push(vendor_id);
    }
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/products', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'vendor' && req.user.role !== 'admin') return res.sendStatus(403);
  const { name, description, price, category, image_url } = req.body;
  try {
    const result = await pool.query(
      'INSERT INTO products (vendor_id, name, description, price, category, image_url) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
      [req.user.id, name, description, price, category, image_url]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/products/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'vendor' && req.user.role !== 'admin') return res.sendStatus(403);
  const { name, description, price, category, image_url, is_available } = req.body;
  const { id } = req.params;
  try {
    const result = await pool.query(
      `UPDATE products SET 
        name = COALESCE($1, name),
        description = COALESCE($2, description),
        price = COALESCE($3, price),
        category = COALESCE($4, category),
        image_url = COALESCE($5, image_url),
        is_available = COALESCE($6, is_available)
       WHERE id = $7 AND vendor_id = $8
       RETURNING *`,
      [name, description, price, category, image_url, is_available, id, req.user.id]
    );
    if (result.rows[0]) {
      res.json(result.rows[0]);
    } else {
      res.status(404).json({ message: 'Product not found or unauthorized' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Admin User Management
app.get('/api/admin/users', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  try {
    const result = await pool.query('SELECT id, name, email, role, balance, created_at FROM users');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Order Routes
app.get('/api/orders', authenticateToken, async (req: any, res) => {
  try {
    let query = 'SELECT * FROM orders';
    const params: any[] = [];

    if (req.user.role === 'customer') {
      query += ' WHERE customer_id = $1';
      params.push(req.user.id);
    } else if (req.user.role === 'vendor') {
      query += " WHERE vendor_id = $1"; 
      params.push(req.user.id);
    } else if (req.user.role === 'rider') {
      // Riders see orders that are ready and in their region, or orders they have already accepted
      const userRes = await pool.query('SELECT region FROM users WHERE id = $1', [req.user.id]);
      const userRegion = userRes.rows[0]?.region;
      
      query += " WHERE (status = 'ready' AND (region = $2 OR region IS NULL)) OR rider_id = $1";
      params.push(req.user.id);
      params.push(userRegion);
    }

    query += ' ORDER BY created_at DESC';
    const result = await pool.query(query, params);
    res.json(result.rows);
  } catch (err) {
    console.error('Fetch orders error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/orders', authenticateToken, async (req: any, res) => {
  const { items, total, address, pickup, orderType, order_type, scheduledTime, vendorId, lat, lng, region: providedRegion, payment_reference, payment_method } = req.body;
  
  let paymentStatus = 'pending';
  const finalPaymentMethod = payment_method || (payment_reference ? 'paystack' : 'pay_on_delivery');

  // Verify Paystack payment if reference provided
  if (payment_reference) {
    try {
      const secretKey = await getSetting('paystack_secret_key');
      const response = await axios.get(`https://api.paystack.co/transaction/verify/${payment_reference}`, {
        headers: { Authorization: `Bearer ${secretKey}` }
      });
      if (response.data.data.status !== 'success') {
        return res.status(400).json({ message: 'Payment verification failed' });
      }
      paymentStatus = 'paid';
      // Log the payment as a transaction
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [req.user.id, total, 'payment', `Order Payment (Ref: ${payment_reference})`]
      );
    } catch (err) {
      console.error('Order payment verification error:', err);
      return res.status(500).json({ message: 'Payment verification error' });
    }
  } else if (payment_method === 'wallet') {
    try {
      // Check balance
      const userRes = await pool.query('SELECT balance FROM users WHERE id = $1', [req.user.id]);
      if (parseFloat(userRes.rows[0].balance) < total) {
        return res.status(400).json({ message: 'Insufficient wallet balance' });
      }
      
      // Deduct balance
      const balanceRes = await pool.query('UPDATE users SET balance = balance - $1 WHERE id = $2 RETURNING balance', [total, req.user.id]);
      paymentStatus = 'paid';
      const newBalance = parseFloat(balanceRes.rows[0].balance);
      
      // Log transaction
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [req.user.id, total, 'payment', 'Wallet payment for order']
      );
      io.to(req.user.id).emit('wallet:updated', { balance: newBalance });
    } catch (err) {
      console.error('Wallet payment error:', err);
      return res.status(500).json({ message: 'Wallet payment failed' });
    }
  } else if (finalPaymentMethod === 'pay_on_delivery') {
    paymentStatus = 'cash_on_delivery';
  }

  const finalOrderType = orderType || order_type || 'food';
  try {
    let finalPickup = pickup;
    let pickupLat = null;
    let pickupLng = null;
    let finalRegion = providedRegion;
    
    // If it's a vendor order, fetch vendor's saved location and region
    if (vendorId && (finalOrderType === 'food')) {
      const vendorResult = await pool.query('SELECT address, lat, lng, region FROM users WHERE id = $1', [vendorId]);
      if (vendorResult.rows[0]) {
        finalPickup = vendorResult.rows[0].address || pickup;
        pickupLat = vendorResult.rows[0].lat;
        pickupLng = vendorResult.rows[0].lng;
        finalRegion = finalRegion || vendorResult.rows[0].region;
      }
    }

    // Fallback to customer's region if still not found
    if (!finalRegion) {
      const customerRes = await pool.query('SELECT region FROM users WHERE id = $1', [req.user.id]);
      finalRegion = customerRes.rows[0]?.region;
    }

    const result = await pool.query(
      'INSERT INTO orders (customer_id, vendor_id, items, total, address, pickup_address, order_type, scheduled_time, lat, lng, pickup_lat, pickup_lng, region, payment_status, payment_method) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) RETURNING *',
      [req.user.id, vendorId, JSON.stringify(items), total, address, finalPickup, finalOrderType, scheduledTime, lat, lng, pickupLat, pickupLng, finalRegion, paymentStatus, finalPaymentMethod]
    );
    const order = result.rows[0];
    res.json(order);
    io.emit('order:new', order); // Notify vendors/admin
  } catch (err) {
    console.error('Order creation error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/orders/:id', authenticateToken, async (req: any, res) => {
  const { status, riderId } = req.body;
  const orderId = req.params.id;
  try {
    let updateQuery = 'UPDATE orders SET status = $1';
    const params: any[] = [status];
    
    if (riderId) {
      updateQuery += ', rider_id = $2';
      params.push(riderId);
    }
    
    updateQuery += `, updated_at = CURRENT_TIMESTAMP WHERE id = $${params.length + 1} RETURNING *`;
    params.push(orderId);

    const result = await pool.query(updateQuery, params);
    const order = result.rows[0];
    
    if (order) {
      res.json(order);
      io.emit('order:updated', order);
      
      // Handle payment logic when delivered
      if (status === 'delivered') {
        const total = parseFloat(order.total);
        const isPaidOnline = order.payment_status === 'paid';

        if (isPaidOnline) {
          // ONLINE PAYMENT: Distribute shares to wallets
          if (order.vendor_id) {
            const vendorAmount = total * 0.8;
            const vRes = await pool.query('UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance', [vendorAmount, order.vendor_id]);
            await pool.query(
              'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
              [order.vendor_id, vendorAmount, 'payment', `Order #${order.id.slice(0, 8)} payment`]
            );
            io.to(order.vendor_id).emit('wallet:updated', { balance: parseFloat(vRes.rows[0].balance) });
          }
          if (order.rider_id) {
            const riderAmount = total * 0.1;
            const rRes = await pool.query('UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance', [riderAmount, order.rider_id]);
            await pool.query(
              'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
              [order.rider_id, riderAmount, 'payment', `Order #${order.id.slice(0, 8)} delivery fee`]
            );
            io.to(order.rider_id).emit('wallet:updated', { balance: parseFloat(rRes.rows[0].balance) });
          }
          
          // Log platform commission (remaining 10%)
          const commissionAmount = total * 0.1;
          await pool.query(
            'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
            [null, commissionAmount, 'commission', `Order #${order.id.slice(0, 8)} platform fee`]
          );
        } else {
          // CASH ON DELIVERY: Rider has the cash. Deduct what they owe others.
          if (order.rider_id) {
            const platformFee = total * 0.1;
            const vendorShare = total * 0.8;
            const totalToDeduct = platformFee + vendorShare;
            
            const rRes = await pool.query('UPDATE users SET balance = balance - $1 WHERE id = $2 RETURNING balance', [totalToDeduct, order.rider_id]);
            await pool.query(
              'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
              [order.rider_id, -totalToDeduct, 'payment', `COD Order #${order.id.slice(0, 8)} (Vendor + Platform share)`]
            );
            io.to(order.rider_id).emit('wallet:updated', { balance: parseFloat(rRes.rows[0].balance) });

            if (order.vendor_id) {
              const vRes = await pool.query('UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance', [vendorShare, order.vendor_id]);
              await pool.query(
                'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
                [order.vendor_id, vendorShare, 'payment', `COD Order #${order.id.slice(0, 8)} payment`]
              );
              io.to(order.vendor_id).emit('wallet:updated', { balance: parseFloat(vRes.rows[0].balance) });
            }
            
            // Log platform commission
            await pool.query(
              'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
              [null, platformFee, 'commission', `COD Order #${order.id.slice(0, 8)} platform fee`]
            );
          }
        }
      }
    } else {
      res.status(404).json({ message: 'Order not found' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/orders/:id/rate', authenticateToken, async (req: any, res: any) => {
  const { rating, comment } = req.body;
  const orderId = req.params.id;
  try {
    const result = await pool.query(
      'UPDATE orders SET rating = $1, rating_comment = $2 WHERE id = $3 AND customer_id = $4 RETURNING *',
      [rating, comment, orderId, req.user.id]
    );
    if (result.rows[0]) {
      res.json(result.rows[0]);
      io.emit('order:updated', result.rows[0]);
    } else {
      res.status(404).json({ message: 'Order not found or unauthorized' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// ===== Delivery Zones Routes =====

// Get all delivery zones
app.get('/api/delivery-zones', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM delivery_zones ORDER BY region, name');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Admin: Create delivery zone
// Rating Endpoint
app.post('/api/orders/:id/rate', authenticateToken, async (req: any, res) => {
  try {
    const { rating, comment } = req.body;
    const result = await pool.query(
      'UPDATE orders SET rating = $1, rating_comment = $2 WHERE id = $3 AND customer_id = $4 RETURNING *',
      [rating, comment, req.params.id, req.user.id]
    );
    if (result.rowCount === 0) return res.status(404).json({ error: 'Order not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to save rating' });
  }
});

app.post('/api/orders/:id/cancel', authenticateToken, async (req: any, res) => {
  const orderId = req.params.id;
  try {
    const orderRes = await pool.query('SELECT status, total, customer_id FROM orders WHERE id = $1', [orderId]);
    if (orderRes.rowCount === 0) return res.status(404).json({ message: 'Order not found' });
    
    const order = orderRes.rows[0];
    if (order.status !== 'pending') {
      return res.status(400).json({ message: 'Only pending orders can be cancelled' });
    }

    if (order.customer_id !== req.user.id) {
      return res.status(403).json({ message: 'Unauthorized' });
    }

    await pool.query('UPDATE orders SET status = $1 WHERE id = $2', ['cancelled', orderId]);
    
    // Only refund if the order was paid online
    if (order.payment_status === 'paid') {
      const bRes = await pool.query('UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance', [order.total, req.user.id]);
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [req.user.id, order.total, 'topup', `Refund for cancelled order #${orderId.slice(-6)}`]
      );
      io.to(req.user.id).emit('wallet:updated', { balance: parseFloat(bRes.rows[0].balance) });
    }

    res.json({ message: 'Order cancelled successfully' });
    io.emit('order:updated', { ...order, status: 'cancelled' });
  } catch (err) {
    console.error('Cancel order error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

// Admin: Toggle User Status
app.patch('/api/admin/users/:id/status', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'Unauthorized' });
  try {
    const { status } = req.body; // 'active' or 'disabled'
    const result = await pool.query(
      'UPDATE users SET status = $1 WHERE id = $2 RETURNING *',
      [status, req.params.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to update user status' });
  }
});

// Admin: Approve Product
app.patch('/api/admin/products/:id/approve', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'Unauthorized' });
  try {
    const result = await pool.query(
      'UPDATE products SET is_approved = true WHERE id = $1 RETURNING *',
      [req.params.id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: 'Failed to approve product' });
  }
});

// Admin: Revenue Flow
app.get('/api/admin/revenue', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'Unauthorized' });
  try {
    const stats = await pool.query(`
      SELECT 
        COUNT(*) as total_orders,
        SUM(total) as gross_revenue,
        SUM(CASE WHEN order_type = 'food' THEN total * 0.1 ELSE 5.00 END) as system_earnings
      FROM orders 
      WHERE status = 'delivered'
    `);
    
    const recentTransactions = await pool.query(`
      SELECT t.*, u.name as user_name, u.email as user_email
      FROM wallet_transactions t
      LEFT JOIN users u ON t.user_id = u.id
      ORDER BY t.created_at DESC
      LIMIT 50
    `);

    res.json({
      summary: stats.rows[0],
      transactions: recentTransactions.rows
    });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch revenue stats' });
  }
});

// Admin: Get Unapproved Products
app.get('/api/admin/pending-products', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ error: 'Unauthorized' });
  try {
    const result = await pool.query(`
      SELECT p.*, v.name as vendor_name 
      FROM products p 
      JOIN users v ON p.vendor_id = v.id 
      WHERE p.is_approved = false
    `);
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch pending products' });
  }
});

app.post('/api/delivery-zones', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { name, region, base_price, price_per_km, min_price, max_price } = req.body;
  try {
    const result = await pool.query(
      'INSERT INTO delivery_zones (name, region, base_price, price_per_km, min_price, max_price) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
      [name, region, base_price || 10, price_per_km || 2, min_price || 5, max_price || null]
    );
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Create zone error:', err);
    res.status(500).json({ message: 'Failed to create delivery zone' });
  }
});

// Admin: Update delivery zone
app.patch('/api/delivery-zones/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { name, region, base_price, price_per_km, min_price, max_price, is_active } = req.body;
  try {
    const result = await pool.query(
      `UPDATE delivery_zones SET 
        name = COALESCE($1, name),
        region = COALESCE($2, region),
        base_price = COALESCE($3, base_price),
        price_per_km = COALESCE($4, price_per_km),
        min_price = COALESCE($5, min_price),
        max_price = $6,
        is_active = COALESCE($7, is_active)
       WHERE id = $8 RETURNING *`,
      [name, region, base_price, price_per_km, min_price, max_price ?? null, is_active, req.params.id]
    );
    if (result.rows.length === 0) return res.status(404).json({ message: 'Zone not found' });
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Update zone error:', err);
    res.status(500).json({ message: 'Failed to update delivery zone' });
  }
});

// Admin: Delete delivery zone
app.delete('/api/delivery-zones/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  try {
    await pool.query('DELETE FROM delivery_zones WHERE id = $1', [req.params.id]);
    res.json({ message: 'Zone deleted' });
  } catch (err) {
    res.status(500).json({ message: 'Failed to delete zone' });
  }
});

// Calculate delivery price based on distance
app.post('/api/delivery-zones/calculate', async (req, res) => {
  const { pickup_region, destination_region, distance_km } = req.body;
  try {
    // Try to find a zone matching the region
    let zone = null;
    if (destination_region) {
      const result = await pool.query('SELECT * FROM delivery_zones WHERE region = $1 AND is_active = true LIMIT 1', [destination_region]);
      zone = result.rows[0];
    }
    if (!zone && pickup_region) {
      const result = await pool.query('SELECT * FROM delivery_zones WHERE region = $1 AND is_active = true LIMIT 1', [pickup_region]);
      zone = result.rows[0];
    }
    if (!zone) {
      // Fallback: use default pricing
      const price = Math.max(10, (distance_km || 5) * 2 + 10);
      return res.json({ price: Math.round(price * 100) / 100, zone: null, fallback: true });
    }
    
    let price = Number(zone.base_price) + (distance_km || 5) * Number(zone.price_per_km);
    price = Math.max(price, Number(zone.min_price));
    if (zone.max_price) price = Math.min(price, Number(zone.max_price));
    
    res.json({ price: Math.round(price * 100) / 100, zone: zone.name, fallback: false });
  } catch (err) {
    console.error('Price calculation error:', err);
    res.status(500).json({ message: 'Failed to calculate price' });
  }
});

// Socket.io Connection
io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  socket.on('join', (userId) => {
    socket.join(userId);
    console.log(`User ${userId} joined their room`);
  });

  socket.on('location:update', async ({ userId, lat, lng }) => {
    try {
      await pool.query(
        'INSERT INTO rider_locations (rider_id, lat, lng, updated_at) VALUES ($1, $2, $3, CURRENT_TIMESTAMP) ON CONFLICT (rider_id) DO UPDATE SET lat = $2, lng = $3, updated_at = CURRENT_TIMESTAMP',
        [userId, lat, lng]
      );
      io.emit('location:updated', { riderId: userId, lat, lng });
    } catch (err) {
      console.error('Location update failed', err);
    }
  });

  socket.on('disconnect', () => {
    console.log('User disconnected');
  });
});

const PORT = process.env.PORT || 3000;
httpServer.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
