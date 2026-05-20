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
import { OAuth2Client } from 'google-auth-library';
import webpush from 'web-push';
import crypto from 'crypto';

dotenv.config({ path: path.join(__dirname, '.env') });
dotenv.config({ path: path.join(__dirname, '..', '.env.local') });

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'bytzgo-72f1c';
const GOOGLE_WEB_CLIENT_ID =
  process.env.GOOGLE_WEB_CLIENT_ID?.trim() ||
  process.env.VITE_GOOGLE_CLIENT_ID?.trim() ||
  '568487483843-99c0bucqujokf2h1vtmno1ku0jea7b4f.apps.googleusercontent.com';
const googleOAuthClient = new OAuth2Client();
let firebaseAdminHasCredentials = false;

function googleTokenAudiences(): string[] {
  return [...new Set([FIREBASE_PROJECT_ID, GOOGLE_WEB_CLIENT_ID].filter(Boolean))];
}

async function verifyGoogleIdToken(idToken: string) {
  const audiences = googleTokenAudiences();

  if (firebaseAdminHasCredentials) {
    try {
      return await admin.auth().verifyIdToken(idToken);
    } catch {
      // Fall through to Google public cert verification.
    }
  }

  try {
    const ticket = await googleOAuthClient.verifyIdToken({ idToken, audience: audiences });
    const payload = ticket.getPayload();
    if (!payload?.email) throw new Error('Invalid Google token');
    return payload;
  } catch (err) {
    console.error('Google ID token verification failed:', err);
    throw new Error('Invalid Google token');
  }
}

try {
  const serviceAccountPath = path.join(__dirname, 'bytzgo-72f1c-firebase-adminsdk-fbsvc-51cd0be35b.json');
  if (fs.existsSync(serviceAccountPath)) {
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount)
    });
    firebaseAdminHasCredentials = true;
    console.log('Firebase Admin initialized successfully with service account certificate.');
  } else {
    admin.initializeApp({
      projectId: FIREBASE_PROJECT_ID
    });
    console.warn('Firebase Admin: no service account; Google ID tokens verified via public certs.');
  }
} catch (err) {
  console.error('Failed to initialize Firebase Admin:', err);
}

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

app.get('/api/health', (_req, res) => {
  res.json({ ok: true, service: 'bytzgo-api', client: 'flutter' });
});

app.get('/', (_req, res) => {
  res.json({
    name: 'BytzGo API',
    client: 'Flutter mobile app (Android/iOS)',
    health: '/api/health',
  });
});



// Multer config for in-memory processing (images stored in DB as Base64)
const upload = multer({ 
  storage: multer.memoryStorage(), 
  limits: { fileSize: 5 * 1024 * 1024 } // 5MB limit
});

const riderDocUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 3 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ok = /^image\/(jpeg|jpg|pjpeg)$/i.test(file.mimetype);
    cb(null, ok);
  },
});

const RIDER_DOC_TYPES = ['license', 'ghana_card', 'photo'] as const;
type RiderDocType = (typeof RIDER_DOC_TYPES)[number];

function isRiderDocType(value: string): value is RiderDocType {
  return (RIDER_DOC_TYPES as readonly string[]).includes(value);
}

const USER_PUBLIC_FIELDS =
  'id, name, email, role, balance, phone, cover_image, address, lat, lng, region, status, is_online';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('supabase.com') ? { rejectUnauthorized: false } : false
});

async function fetchRiderDocuments(userId: string) {
  const result = await pool.query(
    `SELECT doc_type, image_url, mime_type, review_status, rejection_reason, uploaded_at, reviewed_at
     FROM rider_documents WHERE user_id = $1 ORDER BY doc_type`,
    [userId]
  );
  return result.rows;
}

async function riderHasAllDocuments(userId: string): Promise<boolean> {
  const result = await pool.query(
    `SELECT COUNT(DISTINCT doc_type)::int AS n FROM rider_documents WHERE user_id = $1`,
    [userId]
  );
  return (result.rows[0]?.n ?? 0) >= RIDER_DOC_TYPES.length;
}

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

function haversineDistanceKm(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
  if (!lat1 || !lon1 || !lat2 || !lon2) return 0;
  const r = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) *
      Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(r * c * 1000) / 1000;
}

async function calculateDeliveryFeeFromCoords(
  pickupLat: number,
  pickupLng: number,
  destLat: number,
  destLng: number,
  pickupRegion?: string | null,
  destinationRegion?: string | null
): Promise<{ distance_km: number; delivery_fee: number; price_per_km: number; zone: string | null }> {
  const distance_km = haversineDistanceKm(pickupLat, pickupLng, destLat, destLng);
  const globalRate = Math.max(0.01, parseFloat((await getSetting('delivery_price_per_km')) || '4') || 4);

  let zone: any = null;
  if (destinationRegion) {
    const result = await pool.query(
      'SELECT * FROM delivery_zones WHERE region = $1 AND is_active = true LIMIT 1',
      [destinationRegion]
    );
    zone = result.rows[0];
  }
  if (!zone && pickupRegion) {
    const result = await pool.query(
      'SELECT * FROM delivery_zones WHERE region = $1 AND is_active = true LIMIT 1',
      [pickupRegion]
    );
    zone = result.rows[0];
  }

  if (!zone) {
    const price = Math.round(distance_km * globalRate * 100) / 100;
    return { distance_km, delivery_fee: price, price_per_km: globalRate, zone: null };
  }

  const rate = Number(zone.price_per_km) > 0 ? Number(zone.price_per_km) : globalRate;
  let price = distance_km * rate;
  price = Math.max(price, Number(zone.min_price));
  if (zone.max_price) price = Math.min(price, Number(zone.max_price));
  return {
    distance_km,
    delivery_fee: Math.round(price * 100) / 100,
    price_per_km: rate,
    zone: zone.name,
  };
}

async function getPaystackPublicKey(): Promise<string> {
  const fromDb = await getSetting('paystack_public_key');
  if (fromDb?.trim()) return fromDb.trim();
  return process.env.PAYSTACK_PUBLIC_KEY?.trim() || '';
}

async function getPaystackSecretKey(): Promise<string> {
  const fromDb = await getSetting('paystack_secret_key');
  if (fromDb?.trim()) return fromDb.trim();
  return process.env.PAYSTACK_SECRET_KEY?.trim() || '';
}

function paystackKeysMatch(publicKey: string, secretKey: string): boolean {
  const pubTest = publicKey.startsWith('pk_test_');
  const pubLive = publicKey.startsWith('pk_live_');
  const secTest = secretKey.startsWith('sk_test_');
  const secLive = secretKey.startsWith('sk_live_');
  if (pubTest && secTest) return true;
  if (pubLive && secLive) return true;
  return !pubTest && !pubLive && !secTest && !secLive;
}

async function verifyPaystackTransaction(reference: string) {
  const secretKey = await getPaystackSecretKey();
  if (!secretKey) {
    throw new Error('Paystack secret key is not configured. Add sk_test_ or sk_live_ in Admin or PAYSTACK_SECRET_KEY in backend/.env');
  }

  const publicKey = await getPaystackPublicKey();
  if (publicKey && !paystackKeysMatch(publicKey, secretKey)) {
    throw new Error('Paystack public and secret keys must both be test or both be live (pk_test_ with sk_test_, etc.)');
  }

  try {
    const response = await axios.get(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
      { headers: { Authorization: `Bearer ${secretKey}` } }
    );

    if (!response.data?.status) {
      throw new Error(response.data?.message || 'Paystack could not verify this payment');
    }

    const data = response.data.data;
    if (data.status !== 'success') {
      throw new Error(`Payment was not successful (status: ${data.status})`);
    }

    return {
      amountGhs: Number(data.amount) / 100,
      currency: data.currency as string,
      reference: data.reference as string,
    };
  } catch (err: unknown) {
    if (axios.isAxiosError(err) && err.response?.data?.message) {
      throw new Error(String(err.response.data.message));
    }
    throw err;
  }
}

function paystackPaymentEmail(user: { email?: string; phone?: string; id: string }): string {
  const email = user.email?.trim();
  if (email && email.includes('@')) return email;
  const digits = (user.phone || '').replace(/\D/g, '');
  if (digits.length >= 9) return `user${digits}@bytzgo.app`;
  return `user${String(user.id).replace(/-/g, '').slice(0, 12)}@bytzgo.app`;
}

async function initializePaystackTopup(amountGhs: number, user: { id: string; email?: string; phone?: string }) {
  const secretKey = await getPaystackSecretKey();
  if (!secretKey) {
    throw new Error('Paystack is not configured. Add keys in Admin → Settings.');
  }

  const publicKey = await getPaystackPublicKey();
  if (publicKey && !paystackKeysMatch(publicKey, secretKey)) {
    throw new Error('Paystack public and secret keys must both be test or both be live.');
  }

  const amount = Math.round(amountGhs * 100);
  if (!Number.isFinite(amount) || amount < 100) {
    throw new Error('Minimum top-up is ₵1');
  }

  const reference = `bytzgo_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
  const callbackBase =
    process.env.PAYSTACK_CALLBACK_URL?.trim() ||
    process.env.APP_URL?.trim() ||
    'https://bytzgo.net';
  const callbackUrl = `${callbackBase.replace(/\/$/, '')}/paystack/callback`;

  const response = await axios.post(
    'https://api.paystack.co/transaction/initialize',
    {
      email: paystackPaymentEmail(user),
      amount,
      currency: 'GHS',
      reference,
      callback_url: callbackUrl,
      channels: ['card', 'mobile_money', 'bank'],
      metadata: { type: 'wallet_topup', user_id: user.id },
    },
    { headers: { Authorization: `Bearer ${secretKey}` } }
  );

  if (!response.data?.status) {
    throw new Error(response.data?.message || 'Could not start Paystack checkout');
  }

  const data = response.data.data;
  if (!data?.authorization_url || !data?.reference) {
    throw new Error('Paystack did not return a checkout URL');
  }

  return {
    reference: data.reference as string,
    authorizationUrl: data.authorization_url as string,
    accessCode: data.access_code as string | undefined,
    amountGhs,
  };
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
        ALTER TABLE users ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT false;
        ALTER TABLE users ALTER COLUMN password DROP NOT NULL;
      EXCEPTION WHEN others THEN NULL;
      END $$;

      CREATE TABLE IF NOT EXISTS rider_documents (
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        doc_type TEXT NOT NULL CHECK (doc_type IN ('license', 'ghana_card', 'photo')),
        image_url TEXT NOT NULL,
        mime_type TEXT,
        review_status TEXT NOT NULL DEFAULT 'pending' CHECK (review_status IN ('pending', 'approved', 'rejected')),
        rejection_reason TEXT,
        reviewed_by UUID REFERENCES users(id),
        reviewed_at TIMESTAMP WITH TIME ZONE,
        uploaded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id, doc_type)
      );

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
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_fee DECIMAL(10,2) DEFAULT 0.00;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_code TEXT;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_code_created_at TIMESTAMP WITH TIME ZONE;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS arrived_at TIMESTAMP WITH TIME ZONE;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_payment_ack TEXT;
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

      CREATE UNIQUE INDEX IF NOT EXISTS wallet_transactions_topup_reference_idx
        ON wallet_transactions (reference)
        WHERE type = 'topup' AND reference IS NOT NULL;

      CREATE TABLE IF NOT EXISTS system_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS otps (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        phone TEXT NOT NULL,
        otp TEXT NOT NULL,
        purpose TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL
      );

      CREATE TABLE IF NOT EXISTS push_subscriptions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        user_id UUID REFERENCES users(id) ON DELETE CASCADE,
        endpoint TEXT NOT NULL UNIQUE,
        keys_p256dh TEXT NOT NULL,
        keys_auth TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS fcm_tokens (
        user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        token TEXT NOT NULL,
        platform TEXT NOT NULL DEFAULT 'android',
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (user_id, token)
      );

      CREATE UNIQUE INDEX IF NOT EXISTS idx_fcm_tokens_token ON fcm_tokens(token);

      CREATE TABLE IF NOT EXISTS order_messages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        sender_id UUID NOT NULL REFERENCES users(id),
        body TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_order_messages_order_id
        ON order_messages(order_id, created_at);

      CREATE TABLE IF NOT EXISTS order_dispatch_offers (
        order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
        rider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        wave INTEGER NOT NULL DEFAULT 1,
        status TEXT NOT NULL DEFAULT 'offered' CHECK (status IN ('offered', 'declined', 'expired', 'accepted')),
        offered_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
        PRIMARY KEY (order_id, rider_id)
      );

      DO $$ BEGIN
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS dispatch_wave INTEGER;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS offer_expires_at TIMESTAMP WITH TIME ZONE;
      EXCEPTION WHEN others THEN NULL;
      END $$;
    `);

    // Seed SMS gateway configurations
    await pool.query(`
      UPDATE users SET status = 'active', is_online = false
      WHERE role = 'rider' AND status = 'offline';
      UPDATE users SET is_online = true
      WHERE role = 'rider' AND status = 'active';
      UPDATE users SET is_online = false
      WHERE role = 'rider' AND status IN ('pending', 'disabled', 'rejected');
    `);

    await pool.query(`
      INSERT INTO system_settings (key, value)
      VALUES 
        ('sms_base_url', 'https://www.inteksms.top/api/v1'),
        ('sms_api_key', 'INTEK_0E3012.cb48045dfaa3384211cdcbf82516d36fff101a23da78f1dd'),
        ('sms_sender_id', 'bytzee')
      ON CONFLICT (key) DO NOTHING;
    `);

    if (process.env.PAYSTACK_PUBLIC_KEY?.trim()) {
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('paystack_public_key', $1)
         ON CONFLICT (key) DO NOTHING`,
        [process.env.PAYSTACK_PUBLIC_KEY.trim()]
      );
    }
    if (process.env.PAYSTACK_SECRET_KEY?.trim()) {
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('paystack_secret_key', $1)
         ON CONFLICT (key) DO NOTHING`,
        [process.env.PAYSTACK_SECRET_KEY.trim()]
      );
    }

    await pool.query(`
      INSERT INTO system_settings (key, value) VALUES ('delivery_price_per_km', '4')
      ON CONFLICT (key) DO NOTHING;
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

let vapidPublicKey = '';

async function ensureVapidKeys() {
  let publicKey = process.env.VAPID_PUBLIC_KEY;
  let privateKey = process.env.VAPID_PRIVATE_KEY;

  if (!publicKey || !privateKey) {
    const stored = await getSetting('vapid_keys');
    if (stored) {
      try {
        const parsed = JSON.parse(stored);
        publicKey = parsed.publicKey;
        privateKey = parsed.privateKey;
      } catch {
        /* ignore */
      }
    }
  }

  if (!publicKey || !privateKey) {
    const generated = webpush.generateVAPIDKeys();
    publicKey = generated.publicKey;
    privateKey = generated.privateKey;
    await pool.query(
      `INSERT INTO system_settings (key, value) VALUES ('vapid_keys', $1)
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
      [JSON.stringify({ publicKey, privateKey })]
    );
    console.log('[push] Generated VAPID keys (saved to system_settings). Set VAPID_PUBLIC_KEY / VAPID_PRIVATE_KEY in production.');
  }

  webpush.setVapidDetails(
    process.env.VAPID_SUBJECT || 'mailto:support@bytzgo.com',
    publicKey,
    privateKey
  );
  vapidPublicKey = publicKey;
}

function isOfferableOrder(order: any) {
  return order?.status === 'ready' && !order?.rider_id;
}

function generateDeliveryCode(): string {
  return crypto.randomInt(100000, 999999).toString();
}

const deliveryCodeAttempts = new Map<string, { attempts: number; lockedUntil: number }>();

const TRIP_CONTACT_STATUSES = new Set(['pending', 'preparing', 'ready', 'picked_up', 'arrived']);

function tripAllowsContact(order: any): boolean {
  return Boolean(order?.rider_id) && TRIP_CONTACT_STATUSES.has(order.status);
}

function formatOrderMessage(row: any, viewerId: string) {
  return {
    id: row.id,
    orderId: row.order_id,
    senderId: row.sender_id,
    senderName: row.sender_name || 'User',
    body: row.body,
    createdAt: row.created_at,
    isMine: row.sender_id === viewerId,
  };
}

async function assertOrderChatAccess(orderId: string, userId: string) {
  const orderRes = await pool.query(
    'SELECT id, customer_id, rider_id, status FROM orders WHERE id = $1',
    [orderId]
  );
  if (orderRes.rowCount === 0) {
    const err: any = new Error('Order not found');
    err.status = 404;
    throw err;
  }
  const order = orderRes.rows[0];
  if (order.customer_id !== userId && order.rider_id !== userId) {
    const err: any = new Error('Unauthorized');
    err.status = 403;
    throw err;
  }
  if (!tripAllowsContact(order)) {
    const err: any = new Error('Chat is only available during an active trip');
    err.status = 400;
    throw err;
  }
  return order;
}

function sanitizeOrderForRole(order: any, role: string, userId: string) {
  if (!order) return order;
  const o = { ...order };
  if (role !== 'customer' || o.customer_id !== userId) {
    delete o.delivery_code;
  }
  if (o.customer_name) o.customerName = o.customer_name;
  if (o.rider_name) o.riderName = o.rider_name;

  if (tripAllowsContact(o)) {
    if (role === 'customer' && o.customer_id === userId && o.rider_phone) {
      o.riderPhone = o.rider_phone;
    }
    if (role === 'rider' && o.rider_id === userId && o.customer_phone) {
      o.customerPhone = o.customer_phone;
    }
  }

  delete o.customer_phone;
  delete o.rider_phone;
  delete o.customer_name;
  delete o.rider_name;
  return o;
}

const ORDER_CONTACT_JOINS = `
  LEFT JOIN users cu ON cu.id = o.customer_id
  LEFT JOIN users ru ON ru.id = o.rider_id`;
const ORDER_CONTACT_SELECT = `
  cu.name AS customer_name, cu.phone AS customer_phone,
  ru.name AS rider_name, ru.phone AS rider_phone`;

function isCustomerPaymentReady(order: any): boolean {
  if (order.payment_status === 'paid') return true;
  return ['cash', 'wallet', 'paystack'].includes(order.customer_payment_ack);
}

async function loadOrderWithContacts(orderId: string) {
  const r = await pool.query(
    `SELECT o.*, ${ORDER_CONTACT_SELECT}
     FROM orders o
     ${ORDER_CONTACT_JOINS}
     WHERE o.id = $1`,
    [orderId]
  );
  return r.rows[0];
}

async function broadcastOrderUpdated(order: any) {
  let full = order;
  if (order?.id && order.customer_phone === undefined && order.rider_phone === undefined) {
    try {
      const loaded = await loadOrderWithContacts(order.id);
      if (loaded) full = loaded;
    } catch {
      /* keep original row */
    }
  }
  const publicPayload = { ...full, delivery_code: undefined };
  delete publicPayload.customer_phone;
  delete publicPayload.rider_phone;
  delete publicPayload.customerPhone;
  delete publicPayload.riderPhone;
  io.emit('order:updated', publicPayload);

  if (full.customer_id) {
    io.to(full.customer_id).emit(
      'order:updated',
      sanitizeOrderForRole(full, 'customer', full.customer_id)
    );
  }
  if (full.rider_id) {
    io.to(full.rider_id).emit(
      'order:updated',
      sanitizeOrderForRole(full, 'rider', full.rider_id)
    );
  }
  void notifyCustomerTripPush(full);
}

async function settleOrderPayment(order: any) {
  const total = parseFloat(order.total);
  const isPaidOnline = order.payment_status === 'paid';

  if (isPaidOnline) {
    if (order.vendor_id) {
      const vendorAmount = total * 0.8;
      const vRes = await pool.query(
        'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
        [vendorAmount, order.vendor_id]
      );
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [order.vendor_id, vendorAmount, 'payment', `Order #${order.id.slice(0, 8)} payment`]
      );
      io.to(order.vendor_id).emit('wallet:updated', { balance: parseFloat(vRes.rows[0].balance) });
    }
    if (order.rider_id) {
      const riderAmount =
        order.delivery_fee && Number(order.delivery_fee) > 0 ? Number(order.delivery_fee) : total * 0.1;
      const rRes = await pool.query(
        'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
        [riderAmount, order.rider_id]
      );
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [order.rider_id, riderAmount, 'payment', `Order #${order.id.slice(0, 8)} delivery fee`]
      );
      io.to(order.rider_id).emit('wallet:updated', { balance: parseFloat(rRes.rows[0].balance) });
    }
    const commissionAmount = total * 0.1;
    await pool.query(
      'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
      [null, commissionAmount, 'commission', `Order #${order.id.slice(0, 8)} platform fee`]
    );
  } else if (order.rider_id) {
    const platformFee = total * 0.1;
    const vendorShare = total * 0.8;
    const totalToDeduct = platformFee + vendorShare;

    const rRes = await pool.query(
      'UPDATE users SET balance = balance - $1 WHERE id = $2 RETURNING balance',
      [totalToDeduct, order.rider_id]
    );
    await pool.query(
      'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
      [order.rider_id, -totalToDeduct, 'payment', `COD Order #${order.id.slice(0, 8)} (Vendor + Platform share)`]
    );
    io.to(order.rider_id).emit('wallet:updated', { balance: parseFloat(rRes.rows[0].balance) });

    if (order.vendor_id) {
      const vRes = await pool.query(
        'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
        [vendorShare, order.vendor_id]
      );
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [order.vendor_id, vendorShare, 'payment', `COD Order #${order.id.slice(0, 8)} payment`]
      );
      io.to(order.vendor_id).emit('wallet:updated', { balance: parseFloat(vRes.rows[0].balance) });
    }

    await pool.query(
      'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
      [null, platformFee, 'commission', `COD Order #${order.id.slice(0, 8)} platform fee`]
    );
  }
}

const OFFER_TTL_SEC = 30;
const RIDERS_PER_WAVE = 5;
const MAX_DISPATCH_WAVES = 3;
const LOCATION_MAX_AGE_MIN = 15;

const dispatchWaveTimers = new Map<string, NodeJS.Timeout>();

function clearDispatchTimer(orderId: string) {
  const t = dispatchWaveTimers.get(orderId);
  if (t) {
    clearTimeout(t);
    dispatchWaveTimers.delete(orderId);
  }
}

function normalizeRegion(region?: string | null): string | null {
  if (!region || typeof region !== 'string') return null;
  const t = region.trim();
  return t.length ? t.toLowerCase() : null;
}

/** Active online riders; widens to all riders if regional filter matches nobody. */
async function getActiveRiderIds(region?: string | null): Promise<string[]> {
  const norm = normalizeRegion(region);
  if (norm) {
    const regional = await pool.query(
      `SELECT id FROM users
       WHERE role = 'rider' AND status = 'active' AND is_online = true
       AND (
         region IS NULL OR TRIM(region) = ''
         OR LOWER(TRIM(region)) = $1
       )`,
      [norm]
    );
    if (regional.rows.length > 0) {
      return regional.rows.map((r: { id: string }) => r.id);
    }
  }
  const all = await pool.query(
    `SELECT id FROM users WHERE role = 'rider' AND status = 'active' AND is_online = true`
  );
  return all.rows.map((r: { id: string }) => r.id);
}

async function seedRiderLocationFromProfile(riderId: string) {
  const u = await pool.query('SELECT lat, lng FROM users WHERE id = $1', [riderId]);
  const lat = parseFloat(u.rows[0]?.lat);
  const lng = parseFloat(u.rows[0]?.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) < 0.001) return;
  await pool.query(
    `INSERT INTO rider_locations (rider_id, lat, lng, updated_at)
     VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
     ON CONFLICT (rider_id) DO UPDATE SET lat = $2, lng = $3, updated_at = CURRENT_TIMESTAMP`,
    [riderId, lat, lng]
  );
}

async function getPickupPoint(order: any): Promise<{ lat: number; lng: number } | null> {
  if (order.pickup_lat != null && order.pickup_lng != null) {
    const lat = parseFloat(order.pickup_lat);
    const lng = parseFloat(order.pickup_lng);
    if (Math.abs(lat) > 0.001 && Math.abs(lng) > 0.001) return { lat, lng };
  }
  if (order.vendor_id) {
    const v = await pool.query('SELECT lat, lng FROM users WHERE id = $1', [order.vendor_id]);
    if (v.rows[0]?.lat != null && v.rows[0]?.lng != null) {
      return { lat: parseFloat(v.rows[0].lat), lng: parseFloat(v.rows[0].lng) };
    }
  }
  return null;
}

async function getOfferedRiderIds(orderId: string): Promise<string[]> {
  const r = await pool.query(
    `SELECT rider_id FROM order_dispatch_offers WHERE order_id = $1`,
    [orderId]
  );
  return r.rows.map((row: { rider_id: string }) => row.rider_id);
}

async function queryNearestActiveRiders(
  pickup: { lat: number; lng: number },
  region: string | null,
  excludeRiderIds: string[],
  limit: number,
  useRegionFilter: boolean
): Promise<string[]> {
  const norm = normalizeRegion(region);
  const regionClause = useRegionFilter && norm
    ? `AND (u.region IS NULL OR TRIM(u.region) = '' OR LOWER(TRIM(u.region)) = $6)`
    : '';
  const params: unknown[] = [
    pickup.lat,
    pickup.lng,
    excludeRiderIds.length ? excludeRiderIds : [],
    limit,
    LOCATION_MAX_AGE_MIN,
  ];
  if (useRegionFilter && norm) params.push(norm);

  const result = await pool.query(
    `SELECT u.id,
      (6371 * acos(
        LEAST(1, GREATEST(-1,
          cos(radians($1)) * cos(radians(rl.lat)) * cos(radians(rl.lng) - radians($2))
          + sin(radians($1)) * sin(radians(rl.lat))
        ))
      )) AS distance_km
     FROM users u
     INNER JOIN rider_locations rl ON rl.rider_id = u.id
     WHERE u.role = 'rider' AND u.status = 'active' AND u.is_online = true
     AND rl.updated_at > NOW() - INTERVAL '1 minute' * $5
     AND (COALESCE(array_length($3::uuid[], 1), 0) = 0 OR NOT (u.id = ANY($3::uuid[])))
     ${regionClause}
     ORDER BY distance_km ASC
     LIMIT $4`,
    params
  );
  return result.rows.map((row: { id: string }) => row.id);
}

async function getNearestActiveRiders(
  pickup: { lat: number; lng: number },
  region: string | null,
  excludeRiderIds: string[],
  limit: number
): Promise<string[]> {
  let ids = await queryNearestActiveRiders(pickup, region, excludeRiderIds, limit, true);
  if (ids.length === 0 && normalizeRegion(region)) {
    ids = await queryNearestActiveRiders(pickup, region, excludeRiderIds, limit, false);
  }
  return ids;
}

async function emitOffersToRiders(order: any, riderIds: string[], wave: number) {
  if (!riderIds.length) return 0;

  const expiresAt = new Date(Date.now() + OFFER_TTL_SEC * 1000);
  const orderPayload = { ...order };

  for (const riderId of riderIds) {
    await pool.query(
      `INSERT INTO order_dispatch_offers (order_id, rider_id, wave, status, offered_at, expires_at)
       VALUES ($1, $2, $3, 'offered', CURRENT_TIMESTAMP, $4)
       ON CONFLICT (order_id, rider_id) DO UPDATE SET
         wave = EXCLUDED.wave,
         status = 'offered',
         offered_at = CURRENT_TIMESTAMP,
         expires_at = EXCLUDED.expires_at`,
      [order.id, riderId, wave, expiresAt]
    );
    const payload = {
      ...orderPayload,
      expiresAt: expiresAt.toISOString(),
      dispatchWave: wave,
    };
    io.to(String(riderId)).emit('ride:incoming', payload);
  }

  console.info(
    `[dispatch] order ${order.id} wave ${wave}: notified ${riderIds.length} rider(s)`,
    riderIds
  );

  await sendPushToRiders(order, riderIds);
  await pool.query(
    `UPDATE orders SET dispatch_wave = $1, offer_expires_at = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3`,
    [wave, expiresAt, order.id]
  );

  clearDispatchTimer(order.id);
  const timer = setTimeout(() => {
    void handleWaveExpired(order.id, wave);
  }, OFFER_TTL_SEC * 1000 + 500);
  dispatchWaveTimers.set(order.id, timer);
  return riderIds.length;
}

async function handleWaveExpired(orderId: string, wave: number) {
  dispatchWaveTimers.delete(orderId);

  await pool.query(
    `UPDATE order_dispatch_offers SET status = 'expired'
     WHERE order_id = $1 AND wave = $2 AND status = 'offered'`,
    [orderId, wave]
  );

  const fresh = await pool.query('SELECT * FROM orders WHERE id = $1', [orderId]);
  const order = fresh.rows[0];
  if (!order || !isOfferableOrder(order)) return;

  const open = await pool.query(
    `SELECT COUNT(*)::int AS c FROM order_dispatch_offers WHERE order_id = $1 AND status = 'offered'`,
    [orderId]
  );
  if (open.rows[0].c > 0) return;

  await advanceDispatchWave(order, wave + 1);
}

async function advanceDispatchWave(order: any, wave: number) {
  if (!isOfferableOrder(order)) return;
  if (wave > MAX_DISPATCH_WAVES) return;

  const exclude = await getOfferedRiderIds(order.id);
  const pickup = await getPickupPoint(order);

  let riderIds: string[] = [];

  if (pickup) {
    riderIds = await getNearestActiveRiders(pickup, order.region, exclude, RIDERS_PER_WAVE);
  }

  if (riderIds.length === 0) {
    const fallback = (await getActiveRiderIds(order.region)).filter((id) => !exclude.includes(id));
    riderIds = fallback.slice(0, RIDERS_PER_WAVE);
  }

  if (riderIds.length === 0) {
    console.warn(`[dispatch] order ${order.id} wave ${wave}: no riders available to notify`);
    return;
  }

  await emitOffersToRiders(order, riderIds, wave);
}

async function startOrderDispatch(order: any) {
  if (!isOfferableOrder(order)) return;
  clearDispatchTimer(order.id);
  await pool.query(
    `UPDATE order_dispatch_offers SET status = 'expired'
     WHERE order_id = $1 AND status = 'offered'`,
    [order.id]
  );
  await advanceDispatchWave(order, 1);
}

async function recordRiderDecline(orderId: string, riderId: string) {
  await pool.query(
    `UPDATE order_dispatch_offers SET status = 'declined'
     WHERE order_id = $1 AND rider_id = $2`,
    [orderId, riderId]
  );

  const fresh = await pool.query('SELECT * FROM orders WHERE id = $1', [orderId]);
  const order = fresh.rows[0];
  if (!order || !isOfferableOrder(order)) return;

  const wave = order.dispatch_wave || 1;
  const open = await pool.query(
    `SELECT COUNT(*)::int AS c FROM order_dispatch_offers
     WHERE order_id = $1 AND wave = $2 AND status = 'offered'`,
    [orderId, wave]
  );

  if (open.rows[0].c === 0) {
    clearDispatchTimer(orderId);
    await advanceDispatchWave(order, wave + 1);
  }
}

async function notifyRideTaken(orderId: string, winnerRiderId: string) {
  clearDispatchTimer(orderId);

  const offers = await pool.query(
    `SELECT rider_id FROM order_dispatch_offers WHERE order_id = $1`,
    [orderId]
  );

  await pool.query(
    `UPDATE order_dispatch_offers SET status = CASE
       WHEN rider_id = $2 THEN 'accepted'
       ELSE 'expired'
     END
     WHERE order_id = $1`,
    [orderId, winnerRiderId]
  );

  for (const row of offers.rows) {
    if (row.rider_id !== winnerRiderId) {
      io.to(row.rider_id).emit('ride:taken', { orderId });
    }
  }
}

type PushAlert = {
  title: string;
  body: string;
  type: string;
  orderId?: string;
  channelId?: 'incoming_rides' | 'trip_updates';
  highPriority?: boolean;
};

async function sendPushToUserIds(userIds: string[], alert: PushAlert) {
  const ids = [...new Set(userIds.filter(Boolean))];
  if (!ids.length) return;

  const payload = JSON.stringify({
    type: alert.type,
    orderId: alert.orderId ?? '',
    title: alert.title,
    body: alert.body,
  });

  const channelId = alert.channelId ?? 'trip_updates';
  const high = alert.highPriority === true;

  if (vapidPublicKey) {
    const subs = await pool.query(
      `SELECT endpoint, keys_p256dh, keys_auth FROM push_subscriptions WHERE user_id = ANY($1::uuid[])`,
      [ids]
    );

    for (const sub of subs.rows) {
      try {
        await webpush.sendNotification(
          {
            endpoint: sub.endpoint,
            keys: { p256dh: sub.keys_p256dh, auth: sub.keys_auth },
          },
          payload,
          { urgency: high ? 'high' : 'normal', TTL: high ? 30 : 3600 }
        );
      } catch (err: any) {
        if (err.statusCode === 404 || err.statusCode === 410) {
          await pool.query('DELETE FROM push_subscriptions WHERE endpoint = $1', [sub.endpoint]);
        } else {
          console.warn('[push] web send failed:', err.statusCode || err.message);
        }
      }
    }
  }

  if (!firebaseAdminHasCredentials) return;

  try {
    const fcmRes = await pool.query(
      `SELECT token FROM fcm_tokens WHERE user_id = ANY($1::uuid[])`,
      [ids]
    );
    const tokens = fcmRes.rows.map((r: { token: string }) => r.token).filter(Boolean);
    if (!tokens.length) return;

    await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: alert.title,
        body: alert.body,
      },
      data: {
        type: alert.type,
        orderId: String(alert.orderId ?? ''),
      },
      android: {
        priority: high ? 'high' : 'normal',
        notification: {
          channelId,
          sound: 'default',
          priority: high ? ('high' as const) : ('default' as const),
        },
      },
      apns: {
        headers: { 'apns-priority': high ? '10' : '5' },
        payload: { aps: { sound: 'default', contentAvailable: true } },
      },
    });
  } catch (err) {
    console.warn('[push] FCM send failed:', err);
  }
}

async function sendPushToRiders(order: any, riderIds: string[]) {
  if (!riderIds.length) return;
  const pickup = order.pickup_address || order.pickup || 'Pickup';
  const dropoff = order.address || 'Drop-off';
  await sendPushToUserIds(riderIds, {
    title: 'New delivery job',
    body: `${pickup} → ${dropoff}`,
    type: 'incoming-ride',
    orderId: order.id,
    channelId: 'incoming_rides',
    highPriority: true,
  });
}

async function notifyCustomerTripPush(order: any) {
  if (!order?.customer_id) return;
  const status = String(order.status || '');
  let title = 'BytzGO';
  let body = '';
  if (order.rider_id && ['pending', 'ready', 'preparing'].includes(status)) {
    title = 'Biker on the way';
    body = 'Your biker is heading to the pickup point';
  } else if (status === 'picked_up') {
    title = 'On the way';
    body = 'Your biker is heading to your delivery address';
  } else if (status === 'arrived') {
    title = 'Biker arrived';
    body = 'Complete payment to get your delivery PIN';
  } else if (status === 'delivered') {
    title = 'Delivered';
    body = 'Your delivery is complete';
  } else {
    return;
  }
  await sendPushToUserIds([order.customer_id], {
    title,
    body,
    type: 'trip-update',
    orderId: order.id,
    channelId: 'trip_updates',
    highPriority: status === 'arrived',
  });
}

async function broadcastRideOfferToRiders(order: any) {
  try {
    if (!isOfferableOrder(order)) return;
    await startOrderDispatch(order);
  } catch (err) {
    console.error('[dispatch] start order dispatch failed:', err);
  }
}

ensureVapidKeys().catch((err) => console.error('[push] VAPID setup failed:', err));

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

const DEFAULT_SMS_API_KEY = 'INTEK_0E3012.cb48045dfaa3384211cdcbf82516d36fff101a23da78f1dd';

function formatGhanaPhone(phone: string): string {
  let formatted = phone.trim().replace(/\s+/g, '');
  if (formatted.startsWith('+')) formatted = formatted.slice(1);
  if (formatted.startsWith('0')) {
    return '233' + formatted.substring(1);
  }
  if (!formatted.startsWith('233') && /^\d{9}$/.test(formatted)) {
    return '233' + formatted;
  }
  return formatted;
}

/** All common Ghana formats for DB lookups (024…, 233…, 9 digits). */
function phoneLookupVariants(phone: string): string[] {
  const raw = phone.trim().replace(/\s+/g, '');
  const set = new Set<string>();
  if (!raw) return [];
  set.add(raw);
  if (raw.startsWith('+')) {
    const noPlus = raw.slice(1);
    set.add(noPlus);
    if (noPlus.startsWith('233')) set.add('0' + noPlus.slice(3));
  }
  if (raw.startsWith('0')) {
    set.add('233' + raw.slice(1));
  } else if (raw.startsWith('233')) {
    set.add('0' + raw.slice(3));
  } else if (/^\d{9}$/.test(raw)) {
    set.add('0' + raw);
    set.add('233' + raw);
  }
  set.add(formatGhanaPhone(raw));
  return [...set];
}

function isValidGhanaPhone(phone: string): boolean {
  const v = phoneLookupVariants(phone);
  return v.some((p) => /^233\d{9}$/.test(p) || /^0\d{9}$/.test(p));
}

async function getSmsConfig() {
  const envKey = process.env.SMS_API_KEY?.trim();
  const envBase = process.env.SMS_BASE_URL?.trim();
  const envSender = process.env.SMS_SENDER_ID?.trim();
  const dbKey = await getSetting('sms_api_key');
  const dbBase = await getSetting('sms_base_url');
  const dbSender = await getSetting('sms_sender_id');
  return {
    apiKey: envKey || dbKey || DEFAULT_SMS_API_KEY,
    baseUrl: envBase || dbBase || 'https://www.inteksms.top/api/v1',
    senderId: envSender || dbSender || 'bytzee',
    source: envKey ? 'env' : dbKey ? 'database' : 'default',
  };
}

function extractIntekError(data: any): string | null {
  if (!data || typeof data !== 'object') return null;
  if (data.ok === false) {
    const hint = data.hint ? ` ${data.hint}` : '';
    return (data.error || 'SMS gateway rejected the message') + hint;
  }
  const nested = data.data;
  if (nested && typeof nested === 'object') {
    if (nested.ok === false || nested.status === 'failed' || nested.status === 'rejected') {
      return nested.error || nested.message || 'SMS gateway reported delivery failure';
    }
  }
  if (data.success === false) {
    return data.message || data.error || 'SMS gateway rejected the message';
  }
  return null;
}

function isIntekSmsSuccess(data: any): boolean {
  if (!data || typeof data !== 'object') return false;
  if (data.ok === true) return true;
  if (data.success === true) return true;
  const status = data.data?.status || data.status;
  if (typeof status === 'string' && ['sent', 'queued', 'delivered', 'success'].includes(status.toLowerCase())) {
    return true;
  }
  return false;
}

// SMS via INTEK — POST /api/v1/messages/send
async function sendSMS(phone: string, message: string) {
  const { apiKey, baseUrl, senderId, source } = await getSmsConfig();

  const formattedPhone = formatGhanaPhone(phone);
  if (!/^233\d{9}$/.test(formattedPhone)) {
    throw new Error('Invalid Ghana phone number. Use format 024XXXXXXX.');
  }
  if (!apiKey || apiKey.length < 8) {
    throw new Error('SMS API key is not configured. Set SMS_API_KEY on the server or in Admin → Settings.');
  }

  const headers = {
    Authorization: `Bearer ${apiKey}`,
    apikey: apiKey,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
  const payload = {
    recipients: [formattedPhone],
    message,
    sender: senderId,
  };

  const url = `${baseUrl.replace(/\/$/, '')}/messages/send`;
  console.log(`[SMS] Sending to ${formattedPhone} via INTEK (${source}, sender=${senderId})...`);
  try {
    const response = await axios.post(url, payload, {
      headers,
      timeout: 20000,
    });
    console.log('[SMS] INTEK response:', JSON.stringify(response.data));
    const gatewayError = extractIntekError(response.data);
    if (gatewayError) {
      throw new Error(gatewayError);
    }
    if (!isIntekSmsSuccess(response.data)) {
      throw new Error(
        'SMS gateway returned an unexpected response. Check INTEK credits and your approved Sender ID.'
      );
    }
    return response.data;
  } catch (err: any) {
    const data = err.response?.data;
    const detail =
      extractIntekError(data) ||
      data?.error ||
      data?.message ||
      (typeof data === 'string' ? data : null) ||
      err.message ||
      'SMS delivery failed';
    console.error('[SMS] Failed:', data || err.message);
    if (err.response?.status === 401 || String(detail).toLowerCase().includes('unauthorized')) {
      throw new Error('Invalid SMS API key. Update SMS_API_KEY in Render/host env or Admin → Settings.');
    }
    throw new Error(detail);
  }
}

function generateOtp(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

/** Store OTP and send SMS; rolls back DB row if SMS fails. */
async function createAndSendOtp(
  phone: string,
  purpose: 'signup_verify' | 'forgot_password',
  buildMessage: (otp: string) => string
) {
  const variants = phoneLookupVariants(phone);
  const storePhone = formatGhanaPhone(phone);
  const otp = generateOtp();

  await pool.query('DELETE FROM otps WHERE phone = ANY($1) AND purpose = $2', [variants, purpose]);

  const insert = await pool.query(
    `INSERT INTO otps (phone, otp, purpose, expires_at)
     VALUES ($1, $2, $3, NOW() + INTERVAL '10 minutes')
     RETURNING id`,
    [storePhone, otp, purpose]
  );
  const otpId = insert.rows[0]?.id;

  const message = buildMessage(otp);
  if (process.env.SMS_LOG_OTP === 'true') {
    console.log(`[SMS_LOG_OTP] ${purpose} → ${storePhone}: ${otp}`);
  }

  try {
    await sendSMS(phone, message);
  } catch (smsErr: any) {
    if (otpId) {
      await pool.query('DELETE FROM otps WHERE id = $1', [otpId]);
    }
    throw new Error(smsErr.message || 'SMS delivery failed');
  }

  return { otpSent: true, phone: storePhone };
}

function phoneMatchSql(column: string, paramIndex: number): string {
  return `(
    ${column} = ANY($${paramIndex})
    OR regexp_replace(COALESCE(${column}, ''), '[^0-9]', '', 'g') = ANY(
      SELECT regexp_replace(v, '[^0-9]', '', 'g') FROM unnest($${paramIndex}::text[]) AS v
    )
  )`;
}

async function findValidOtp(phone: string, otp: string, purpose: string) {
  const normalized = formatGhanaPhone(phone);
  const variants = [...new Set([...phoneLookupVariants(phone), normalized])];
  const result = await pool.query(
    `SELECT id FROM otps
     WHERE ${phoneMatchSql('phone', 1)} AND otp = $2 AND purpose = $3 AND expires_at > NOW()
     ORDER BY created_at DESC LIMIT 1`,
    [variants, String(otp).trim(), purpose]
  );
  return result.rows[0]?.id as string | undefined;
}

async function findUserIdByPhone(phone: string): Promise<string | undefined> {
  const variants = phoneLookupVariants(phone);
  const result = await pool.query(
    `SELECT id FROM users WHERE ${phoneMatchSql('phone', 1)} LIMIT 1`,
    [variants]
  );
  return result.rows[0]?.id as string | undefined;
}

function isEmailLoginIdentifier(value: string): boolean {
  return value.includes('@');
}

async function findUserByLoginIdentifier(identifier: string) {
  const trimmed = identifier.trim();
  if (!trimmed) return undefined;
  if (isEmailLoginIdentifier(trimmed)) {
    const result = await pool.query(
      'SELECT * FROM users WHERE LOWER(email) = LOWER($1) LIMIT 1',
      [trimmed]
    );
    return result.rows[0];
  }
  if (!isValidGhanaPhone(trimmed)) return undefined;
  const variants = phoneLookupVariants(trimmed);
  const result = await pool.query(
    `SELECT * FROM users WHERE ${phoneMatchSql('phone', 1)} LIMIT 1`,
    [variants]
  );
  return result.rows[0];
}

// Auth Routes

// Send Sign-Up OTP Endpoint
app.post('/api/auth/send-signup-otp', async (req, res) => {
  const { phone, email } = req.body;
  if (!phone) {
    return res.status(400).json({ message: 'Phone number is required' });
  }
  if (!isValidGhanaPhone(phone)) {
    return res.status(400).json({ message: 'Enter a valid Ghana phone number (e.g. 0247904675).' });
  }

  try {
    const variants = phoneLookupVariants(phone);
    const checkUser = await pool.query(
      'SELECT id FROM users WHERE email = $1 OR phone = ANY($2)',
      [email, variants]
    );
    if (checkUser.rowCount && checkUser.rowCount > 0) {
      return res.status(400).json({ message: 'Email or phone number is already registered' });
    }

    await createAndSendOtp(
      phone,
      'signup_verify',
      (code) => `Your BytzGo verification code is: ${code}. Valid for 10 minutes.`
    );

    res.json({ success: true, message: 'Verification code sent by SMS' });
  } catch (err: any) {
    console.error('Error sending signup OTP:', err.response?.data || err.message);
    const msg = err.message || 'Failed to send verification code';
    const status = msg.includes('registered') ? 400 : msg.includes('Invalid') ? 400 : 502;
    res.status(status).json({ message: msg });
  }
});

// Send Forgot Password OTP Endpoint
app.post('/api/auth/send-forgot-otp', async (req, res) => {
  const { phone } = req.body;
  if (!phone) {
    return res.status(400).json({ message: 'Phone number is required' });
  }
  if (!isValidGhanaPhone(phone)) {
    return res.status(400).json({ message: 'Enter a valid Ghana phone number (e.g. 0247904675).' });
  }

  try {
    const userId = await findUserIdByPhone(phone);
    if (!userId) {
      return res.status(404).json({ message: 'Phone number is not registered' });
    }

    await createAndSendOtp(
      phone,
      'forgot_password',
      (code) => `Your BytzGo password reset code is: ${code}. Valid for 10 minutes.`
    );

    res.json({ success: true, message: 'Reset code sent by SMS' });
  } catch (err: any) {
    console.error('Error sending forgot password OTP:', err.response?.data || err.message);
    res.status(502).json({ message: err.message || 'Failed to send reset code via SMS' });
  }
});

// Resend OTP (signup or forgot password)
app.post('/api/auth/resend-otp', async (req, res) => {
  const { phone, purpose, email } = req.body;
  if (!phone || !purpose) {
    return res.status(400).json({ message: 'Phone and purpose are required' });
  }
  if (purpose !== 'signup_verify' && purpose !== 'forgot_password') {
    return res.status(400).json({ message: 'Invalid OTP purpose' });
  }
  if (!isValidGhanaPhone(phone)) {
    return res.status(400).json({ message: 'Enter a valid Ghana phone number (e.g. 0247904675).' });
  }

  try {
    if (purpose === 'signup_verify') {
      const variants = phoneLookupVariants(phone);
      const checkUser = await pool.query(
        'SELECT id FROM users WHERE email = $1 OR phone = ANY($2)',
        [email, variants]
      );
      if (checkUser.rowCount && checkUser.rowCount > 0) {
        return res.status(400).json({ message: 'Email or phone number is already registered' });
      }
      await createAndSendOtp(
        phone,
        'signup_verify',
        (code) => `Your BytzGo verification code is: ${code}. Valid for 10 minutes.`
      );
    } else {
      const userId = await findUserIdByPhone(phone);
      if (!userId) {
        return res.status(404).json({ message: 'Phone number is not registered' });
      }
      await createAndSendOtp(
        phone,
        'forgot_password',
        (code) => `Your BytzGo password reset code is: ${code}. Valid for 10 minutes.`
      );
    }
    res.json({ success: true, message: 'A new code was sent by SMS' });
  } catch (err: any) {
    console.error('Error resending OTP:', err.message);
    res.status(502).json({ message: err.message || 'Failed to resend SMS code' });
  }
});

// Verify OTP Endpoint
app.post('/api/auth/verify-otp', async (req, res) => {
  const { phone, otp, purpose } = req.body;
  if (!phone || !otp || !purpose) {
    return res.status(400).json({ message: 'Phone, OTP code, and purpose are required' });
  }

  try {
    const otpId = await findValidOtp(phone, String(otp).trim(), purpose);
    if (!otpId) {
      return res.status(400).json({ message: 'Invalid or expired OTP code' });
    }

    res.json({ success: true, message: 'OTP verified successfully' });
  } catch (err: any) {
    console.error('Error verifying OTP:', err);
    res.status(500).json({ message: 'Failed to verify OTP' });
  }
});

// Reset Password with OTP Endpoint
app.post('/api/auth/reset-password-otp', async (req, res) => {
  const { phone, otp, newPassword } = req.body;
  if (!phone || !otp || !newPassword) {
    return res.status(400).json({ message: 'Phone, OTP code, and new password are required' });
  }

  try {
    const otpId = await findValidOtp(phone, String(otp).trim(), 'forgot_password');
    if (!otpId) {
      return res.status(400).json({ message: 'Invalid or expired OTP code' });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    const lookups = phoneLookupVariants(phone);
    const userId = await findUserIdByPhone(phone);
    if (!userId) {
      return res.status(404).json({ message: 'User not found' });
    }

    const updateResult = await pool.query(
      'UPDATE users SET password = $1 WHERE id = $2 RETURNING id',
      [hashedPassword, userId]
    );

    if (updateResult.rowCount === 0) {
      return res.status(404).json({ message: 'User not found' });
    }

    await pool.query('DELETE FROM otps WHERE phone = ANY($1) AND purpose = $2', [
      phoneLookupVariants(phone),
      'forgot_password',
    ]);

    res.json({ success: true, message: 'Password reset successful' });
  } catch (err: any) {
    console.error('Error resetting password with OTP:', err);
    res.status(500).json({ message: 'Failed to reset password' });
  }
});

app.post('/api/auth/register', async (req, res) => {
  const { name, email, password, role, phone, adminInviteSecret, otp } = req.body;
  if (role === 'admin') {
    const expected = process.env.ADMIN_INVITE_SECRET;
    if (!expected || adminInviteSecret !== expected) {
      return res.status(403).json({ message: 'Admin registration is restricted. Contact platform owner.' });
    }
  }
  if (role === 'customer') {
    if (!phone) {
      return res.status(400).json({ message: 'Phone number is required' });
    }
    if (!isValidGhanaPhone(phone)) {
      return res.status(400).json({ message: 'Enter a valid Ghana phone number (e.g. 0247904675).' });
    }
    if (otp) {
      const otpId = await findValidOtp(phone, String(otp).trim(), 'signup_verify');
      if (!otpId) {
        return res.status(400).json({ message: 'Invalid or expired verification code' });
      }
    }
  }
  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    const userStatus = role === 'vendor' || role === 'rider' ? 'pending' : 'active';
    const storePhone = phone ? formatGhanaPhone(phone) : phone;
    const result = await pool.query(
      'INSERT INTO users (name, email, password, role, status, phone) VALUES ($1, $2, $3, $4, $5, $6) RETURNING id, name, email, role, balance, phone, status',
      [name, email, hashedPassword, role, userStatus, storePhone]
    );
    if (role === 'customer' && phone) {
      await pool.query('DELETE FROM otps WHERE phone = ANY($1) AND purpose = $2', [
        phoneLookupVariants(phone),
        'signup_verify',
      ]);
    }
    const user = result.rows[0];
    const token = jwt.sign(user, process.env.JWT_SECRET as string);
    res.json({ user, token });
  } catch (err) {
    console.error('Registration failed:', err);
    res.status(400).json({ message: 'Email or Phone number already exists' });
  }
});

app.post('/api/auth/login', async (req, res) => {
  const { email, phone, login, password } = req.body;
  const identifier = String(login ?? phone ?? email ?? '').trim();
  if (!identifier || !password) {
    return res.status(400).json({ message: 'Phone or email and password are required' });
  }
  if (!isEmailLoginIdentifier(identifier) && !isValidGhanaPhone(identifier)) {
    return res.status(400).json({
      message: 'Enter a valid email or Ghana phone number (e.g. 0247904675).',
    });
  }
  try {
    const user = await findUserByLoginIdentifier(identifier);
    if (!user?.password) {
      return res.status(401).json({ message: 'Invalid phone/email or password' });
    }
    if (await bcrypt.compare(password, user.password)) {
      const { password: _pw, ...userWithoutPassword } = user;
      const token = jwt.sign(userWithoutPassword, process.env.JWT_SECRET as string);
      res.json({ user: userWithoutPassword, token });
    } else {
      res.status(401).json({ message: 'Invalid phone/email or password' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Reset password with registered phone + email (no SMS)
app.post('/api/auth/reset-password', async (req, res) => {
  const { phone, email, newPassword } = req.body;
  if (!phone || !email || !newPassword) {
    return res.status(400).json({ message: 'Phone, email, and new password are required' });
  }
  if (String(newPassword).length < 6) {
    return res.status(400).json({ message: 'Password must be at least 6 characters' });
  }
  if (!isValidGhanaPhone(phone)) {
    return res.status(400).json({ message: 'Enter a valid Ghana phone number (e.g. 0247904675).' });
  }

  try {
    const userId = await findUserIdByPhone(phone);
    if (!userId) {
      return res.status(400).json({ message: 'Phone and email do not match our records' });
    }
    const userResult = await pool.query('SELECT id, email FROM users WHERE id = $1', [userId]);
    const user = userResult.rows[0];
    if (!user || String(user.email).toLowerCase() !== String(email).trim().toLowerCase()) {
      return res.status(400).json({ message: 'Phone and email do not match our records' });
    }

    const hashedPassword = await bcrypt.hash(newPassword, 10);
    await pool.query('UPDATE users SET password = $1 WHERE id = $2', [hashedPassword, userId]);
    res.json({ success: true, message: 'Password reset successful' });
  } catch (err: any) {
    console.error('Error resetting password:', err);
    res.status(500).json({ message: 'Failed to reset password' });
  }
});

// Google Auth
app.post('/api/auth/google', async (req, res) => {
  const { credential, role } = req.body;
  try {
    const payload = await verifyGoogleIdToken(credential);
    if (!payload || !payload.email) {
      return res.status(400).json({ message: 'Invalid Google token' });
    }

    const googleId = payload.sub || (payload as { user_id?: string }).user_id;
    const displayName = payload.name || payload.email.split('@')[0];
    
    // Check if user exists
    let result = await pool.query('SELECT * FROM users WHERE email = $1', [payload.email]);
    let user = result.rows[0];
    if (!user) {
      const newRole = role || 'customer';
      if (newRole === 'admin') {
        return res.status(403).json({ message: 'Admin accounts cannot be created via Google sign-in.' });
      }
      const userStatus = (newRole === 'vendor' || newRole === 'rider') ? 'pending' : 'active';
      result = await pool.query(
        'INSERT INTO users (name, email, google_id, role, status) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, email, role, balance, phone, status',
        [displayName, payload.email, googleId, newRole, userStatus]
      );
      user = result.rows[0];
    } else {
      // Update google_id if not set
      if (!user.google_id && googleId) {
        await pool.query('UPDATE users SET google_id = $1 WHERE id = $2', [googleId, user.id]);
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

// Supabase Auth
app.post('/api/auth/supabase', async (req, res) => {
  const { accessToken, role } = req.body;
  try {
    // Verify token with Supabase Auth API
    const supabaseUrl = process.env.SUPABASE_URL || 'https://ypmiurbtmfiyzmrygonh.supabase.co';
    const supabaseAnonKey = process.env.SUPABASE_ANON_KEY || '';
    
    const headers: any = {
      'Authorization': `Bearer ${accessToken}`
    };
    if (supabaseAnonKey) {
      headers['apikey'] = supabaseAnonKey;
    }

    const response = await axios.get(`${supabaseUrl}/auth/v1/user`, { headers });
    const payload = response.data;
    
    if (!payload || !payload.email) {
      return res.status(400).json({ message: 'Invalid Supabase token' });
    }

    const email = payload.email;
    const name = payload.user_metadata?.full_name || payload.email.split('@')[0];
    const googleId = payload.id; // Use Supabase user ID as google_id / external ID

    // Check if user exists in database
    let result = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
    let user = result.rows[0];
    if (!user) {
      const userStatus = role === 'vendor' || role === 'rider' ? 'pending' : 'active';
      result = await pool.query(
        'INSERT INTO users (name, email, google_id, role, status) VALUES ($1, $2, $3, $4, $5) RETURNING id, name, email, role, balance, phone, status',
        [name, email, googleId, role || 'customer', userStatus]
      );
      user = result.rows[0];
    } else {
      // Update google_id if not set
      if (!user.google_id) {
        await pool.query('UPDATE users SET google_id = $1 WHERE id = $2', [googleId, user.id]);
      }
      const { password, ...u } = user;
      user = u;
    }

    const token = jwt.sign({ id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance }, process.env.JWT_SECRET as string);
    res.json({ user, token });
  } catch (err: any) {
    console.error('Supabase auth error:', err.response?.data || err.message);
    res.status(500).json({ message: 'Supabase authentication failed' });
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
       RETURNING ${USER_PUBLIC_FIELDS}`,
      [email, phone, cover_image, address, lat, lng, region, req.user.id]
    );
    const user = result.rows[0];
    const token = jwt.sign({ id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance, status: user.status, is_online: user.is_online, region: user.region }, process.env.JWT_SECRET as string);
    res.json({ user, token });
  } catch (err: any) {
    console.error('Profile update error:', err);
    res.status(500).json({ message: 'Profile update failed' });
  }
});

// Status Update (vendors: account status; riders: online toggle via active/offline)
app.patch('/api/auth/status', authenticateToken, async (req: any, res) => {
  const { status } = req.body;
  try {
    const current = await pool.query(
      `SELECT ${USER_PUBLIC_FIELDS} FROM users WHERE id = $1`,
      [req.user.id]
    );
    const row = current.rows[0];
    if (!row) return res.status(404).json({ message: 'User not found' });

    if (row.role === 'rider') {
      if (row.status === 'pending') {
        return res.status(403).json({ message: 'Your account is pending admin approval. Upload your documents first.' });
      }
      if (row.status === 'rejected') {
        return res.status(403).json({ message: 'Your application was rejected. Update your documents and contact support.' });
      }
      if (row.status !== 'active') {
        return res.status(403).json({ message: 'Your account is not active.' });
      }
      if (status !== 'active' && status !== 'offline') {
        return res.status(400).json({ message: 'Riders can only go online or offline.' });
      }
      const isOnline = status === 'active';
      const hasDocs = await riderHasAllDocuments(req.user.id);
      if (isOnline && !hasDocs) {
        return res.status(403).json({ message: 'Upload your licence, Ghana card, and photo before going online.' });
      }
      const result = await pool.query(
        `UPDATE users SET is_online = $1 WHERE id = $2 RETURNING ${USER_PUBLIC_FIELDS}`,
        [isOnline, req.user.id]
      );
      const user = result.rows[0];
      if (isOnline) await seedRiderLocationFromProfile(user.id);
      const token = jwt.sign(
        { id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance, status: user.status, is_online: user.is_online, region: user.region },
        process.env.JWT_SECRET as string
      );
      res.json({ user, token });
      io.to(String(user.id)).emit('status:updated', { status: user.status, is_online: user.is_online });
      return;
    }

    const result = await pool.query(
      `UPDATE users SET status = $1 WHERE id = $2 RETURNING ${USER_PUBLIC_FIELDS}`,
      [status, req.user.id]
    );
    const user = result.rows[0];
    const token = jwt.sign(
      { id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance, status: user.status, is_online: user.is_online, region: user.region },
      process.env.JWT_SECRET as string
    );
    res.json({ user, token });
    io.to(String(user.id)).emit('status:updated', { status });
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

// Rider KYC documents (JPEG only)
app.get('/api/rider/documents', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') return res.sendStatus(403);
  try {
    const documents = await fetchRiderDocuments(req.user.id);
    const userRes = await pool.query(`SELECT status FROM users WHERE id = $1`, [req.user.id]);
    res.json({
      documents,
      status: userRes.rows[0]?.status,
      complete: documents.length >= RIDER_DOC_TYPES.length,
      ready_for_review: await riderHasAllDocuments(req.user.id),
    });
  } catch (err) {
    console.error('Fetch rider documents error:', err);
    res.status(500).json({ message: 'Failed to load documents' });
  }
});

app.post(
  '/api/rider/documents/:docType/upload',
  authenticateToken,
  riderDocUpload.single('image'),
  async (req: any, res) => {
    if (req.user.role !== 'rider') return res.sendStatus(403);
    const docType = req.params.docType;
    if (!isRiderDocType(docType)) {
      return res.status(400).json({ message: 'Invalid document type. Use license, ghana_card, or photo.' });
    }
    if (!req.file) {
      return res.status(400).json({ message: 'No JPEG image uploaded' });
    }
    try {
      const base64 = `data:${req.file.mimetype};base64,${req.file.buffer.toString('base64')}`;
      await pool.query(
        `INSERT INTO rider_documents (user_id, doc_type, image_url, mime_type, review_status, rejection_reason, reviewed_by, reviewed_at)
         VALUES ($1, $2, $3, $4, 'pending', NULL, NULL, NULL)
         ON CONFLICT (user_id, doc_type) DO UPDATE SET
           image_url = EXCLUDED.image_url,
           mime_type = EXCLUDED.mime_type,
           review_status = 'pending',
           rejection_reason = NULL,
           reviewed_by = NULL,
           reviewed_at = NULL,
           uploaded_at = CURRENT_TIMESTAMP`,
        [req.user.id, docType, base64, req.file.mimetype]
      );

      if (await riderHasAllDocuments(req.user.id)) {
        await pool.query(
          `UPDATE users SET status = 'pending', is_online = false
           WHERE id = $1 AND role = 'rider' AND status NOT IN ('disabled')`,
          [req.user.id]
        );
      }

      const documents = await fetchRiderDocuments(req.user.id);
      const userRes = await pool.query(`SELECT ${USER_PUBLIC_FIELDS} FROM users WHERE id = $1`, [req.user.id]);
      const user = userRes.rows[0];
      const token = jwt.sign(
        { id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance, status: user.status, is_online: user.is_online, region: user.region },
        process.env.JWT_SECRET as string
      );
      res.json({ url: base64, documents, user, token });
    } catch (err) {
      console.error('Rider document upload error:', err);
      res.status(500).json({ message: 'Document upload failed' });
    }
  }
);

app.post('/api/rider/documents/submit', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') return res.sendStatus(403);
  try {
    if (!(await riderHasAllDocuments(req.user.id))) {
      return res.status(400).json({ message: 'Upload licence, Ghana card, and profile photo first.' });
    }
    await pool.query(
      `UPDATE users SET status = 'pending', is_online = false WHERE id = $1 AND role = 'rider'`,
      [req.user.id]
    );
    await pool.query(
      `UPDATE rider_documents SET review_status = 'pending', rejection_reason = NULL, reviewed_by = NULL, reviewed_at = NULL
       WHERE user_id = $1`,
      [req.user.id]
    );
    const userRes = await pool.query(`SELECT ${USER_PUBLIC_FIELDS} FROM users WHERE id = $1`, [req.user.id]);
    const user = userRes.rows[0];
    const token = jwt.sign(
      { id: user.id, name: user.name, email: user.email, role: user.role, balance: user.balance, status: user.status, is_online: user.is_online, region: user.region },
      process.env.JWT_SECRET as string
    );
    res.json({ message: 'Submitted for admin review', user, token, documents: await fetchRiderDocuments(req.user.id) });
    io.to(String(req.user.id)).emit('status:updated', { status: 'pending', is_online: false });
  } catch (err) {
    console.error('Rider document submit error:', err);
    res.status(500).json({ message: 'Submit failed' });
  }
});

app.post('/api/wallet/topup/initialize', authenticateToken, async (req: any, res) => {
  const amountGhs = Number(req.body?.amount);
  if (!Number.isFinite(amountGhs) || amountGhs < 1) {
    return res.status(400).json({ message: 'Minimum top-up is ₵1' });
  }

  try {
    const userRes = await pool.query(
      'SELECT id, email, phone, status FROM users WHERE id = $1',
      [req.user.id]
    );
    const row = userRes.rows[0];
    if (!row || row.status === 'disabled') {
      return res.status(403).json({ message: 'Your account is disabled.' });
    }

    const checkout = await initializePaystackTopup(amountGhs, {
      id: row.id,
      email: row.email,
      phone: row.phone,
    });

    res.json({
      reference: checkout.reference,
      authorization_url: checkout.authorizationUrl,
      access_code: checkout.accessCode,
      amount: checkout.amountGhs,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Could not start payment';
    console.error('Paystack initialize error:', message);
    const status = message.includes('not configured') ? 503 : 400;
    res.status(status).json({ message });
  }
});

app.post('/api/wallet/topup', authenticateToken, async (req: any, res) => {
  const reference = typeof req.body?.reference === 'string' ? req.body.reference.trim() : '';
  if (!reference) {
    return res.status(400).json({ message: 'Payment reference is required' });
  }

  const client = await pool.connect();
  try {
    const userRes = await client.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
    const accountStatus = userRes.rows[0]?.status;
    if (accountStatus === 'disabled') {
      return res.status(403).json({ message: 'Your account is disabled.' });
    }

    const existing = await client.query(
      `SELECT amount FROM wallet_transactions WHERE type = 'topup' AND reference = $1 AND user_id = $2 LIMIT 1`,
      [reference, req.user.id]
    );
    if (existing.rowCount && existing.rowCount > 0) {
      const balanceRes = await client.query('SELECT balance FROM users WHERE id = $1', [req.user.id]);
      const balance = parseFloat(balanceRes.rows[0].balance);
      io.to(req.user.id).emit('wallet:updated', { balance });
      return res.json({ balance, alreadyProcessed: true });
    }

    const verified = await verifyPaystackTransaction(reference);
    if (verified.currency && verified.currency !== 'GHS') {
      return res.status(400).json({ message: `Unexpected currency: ${verified.currency}` });
    }

    await client.query('BEGIN');

    const result = await client.query(
      'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
      [verified.amountGhs, req.user.id]
    );

    await client.query(
      'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
      [req.user.id, verified.amountGhs, 'topup', reference]
    );

    await client.query('COMMIT');

    const balance = parseFloat(result.rows[0].balance);
    res.json({ balance });
    io.to(req.user.id).emit('wallet:updated', { balance });
  } catch (err: unknown) {
    await client.query('ROLLBACK').catch(() => {});
    const message = err instanceof Error ? err.message : 'Server error during verification';
    console.error('Wallet topup error:', message, err);
    const status =
      message.includes('secret key') || message.includes('public and secret') ? 503 : 400;
    res.status(status).json({ message });
  } finally {
    client.release();
  }
});

app.get('/api/config/pricing', async (_req, res) => {
  try {
    const raw = await getSetting('delivery_price_per_km');
    const pricePerKm = Math.max(0.01, parseFloat(raw || '4') || 4);
    res.json({ price_per_km: pricePerKm });
  } catch (err) {
    res.json({ price_per_km: 4 });
  }
});

/** Nearby online riders for customer map (lat/lng only — no PII). */
app.get('/api/riders/nearby', authenticateToken, async (req: any, res) => {
  try {
    const lat = parseFloat(String(req.query.lat ?? ''));
    const lng = parseFloat(String(req.query.lng ?? ''));
    const limit = Math.min(
      Math.max(1, parseInt(String(req.query.limit ?? '8'), 10) || 8),
      15
    );
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return res.status(400).json({ message: 'lat and lng are required' });
    }
    const region = req.user?.region ?? null;
    const riderIds = await getNearestActiveRiders({ lat, lng }, region, [], limit);
    if (!riderIds.length) {
      return res.json({ riders: [] });
    }
    const locs = await pool.query(
      `SELECT rl.lat, rl.lng
       FROM rider_locations rl
       WHERE rl.rider_id = ANY($1::uuid[])
         AND rl.updated_at > NOW() - INTERVAL '1 minute' * $2`,
      [riderIds, LOCATION_MAX_AGE_MIN]
    );
    const riders = locs.rows
      .map((row: { lat: string; lng: string }) => ({
        lat: parseFloat(row.lat),
        lng: parseFloat(row.lng),
      }))
      .filter((r: { lat: number; lng: number }) => Number.isFinite(r.lat) && Number.isFinite(r.lng));
    res.json({ riders });
  } catch (err) {
    console.error('[riders/nearby]', err);
    res.status(500).json({ message: 'Failed to load nearby riders' });
  }
});

app.get('/api/config/paystack', async (_req, res) => {
  try {
    const publicKey = await getPaystackPublicKey();
    res.json({ publicKey });
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch config' });
  }
});

function mapsApiKey(): string {
  return (
    process.env.VITE_GOOGLE_MAPS_API_KEY?.trim() ||
    process.env.GOOGLE_MAPS_API_KEY?.trim() ||
    ''
  );
}

const GEOCODE_PREFERRED_TYPES = [
  'street_address',
  'premise',
  'route',
  'establishment',
  'point_of_interest',
  'sublocality',
  'neighborhood',
  'locality',
  'administrative_area_level_2',
  'administrative_area_level_1',
];

function pickBestGeocodeAddress(results: { formatted_address?: string; types?: string[] }[]): string | null {
  if (!results?.length) return null;
  for (const type of GEOCODE_PREFERRED_TYPES) {
    const hit = results.find((r) => r.types?.includes(type));
    if (hit?.formatted_address) return hit.formatted_address;
  }
  const inGhana = results.find((r) => /ghana/i.test(r.formatted_address || ''));
  return (inGhana || results[0]).formatted_address || null;
}

app.get('/api/maps/autocomplete', authenticateToken, async (req: any, res) => {
  try {
    const input = String(req.query.input || '').trim();
    if (input.length < 2) return res.json({ predictions: [] });
    const key = mapsApiKey();
    if (!key) return res.status(503).json({ predictions: [], message: 'Maps not configured' });
    const url = new URL('https://maps.googleapis.com/maps/api/place/autocomplete/json');
    url.searchParams.set('input', input);
    url.searchParams.set('key', key);
    url.searchParams.set('components', 'country:gh');
    url.searchParams.set('location', '5.6037,-0.1870');
    url.searchParams.set('radius', '500000');
    const { data } = await axios.get(url.toString());
    if (data.status !== 'OK' && data.status !== 'ZERO_RESULTS') {
      return res.json({ predictions: [], message: data.error_message || data.status });
    }
    const predictions = (data.predictions || []).map((p: { place_id: string; description: string }) => ({
      placeId: p.place_id,
      description: p.description,
    }));
    res.json({ predictions });
  } catch (err) {
    console.error('Maps autocomplete error:', err);
    res.status(500).json({ predictions: [], message: 'Autocomplete failed' });
  }
});

app.get('/api/maps/place-details', authenticateToken, async (req: any, res) => {
  try {
    const placeId = String(req.query.place_id || '').trim();
    if (!placeId) return res.status(400).json({ message: 'place_id required' });
    const key = mapsApiKey();
    if (!key) return res.status(503).json({ message: 'Maps not configured' });
    const url = new URL('https://maps.googleapis.com/maps/api/place/details/json');
    url.searchParams.set('place_id', placeId);
    url.searchParams.set('fields', 'formatted_address,geometry,name');
    url.searchParams.set('key', key);
    const { data } = await axios.get(url.toString());
    if (data.status !== 'OK' || !data.result?.geometry?.location) {
      return res.status(400).json({ message: data.error_message || 'Place not found' });
    }
    const loc = data.result.geometry.location;
    res.json({
      address: data.result.formatted_address || data.result.name || '',
      lat: loc.lat,
      lng: loc.lng,
    });
  } catch (err) {
    console.error('Maps place details error:', err);
    res.status(500).json({ message: 'Place lookup failed' });
  }
});

function decodeGooglePolyline(encoded: string): { lat: number; lng: number }[] {
  const points: { lat: number; lng: number }[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let b: number;
    let shift = 0;
    let result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlat = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
    lat += dlat;
    shift = 0;
    result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20);
    const dlng = (result & 1) !== 0 ? ~(result >> 1) : result >> 1;
    lng += dlng;
    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return points;
}

app.get('/api/maps/directions', authenticateToken, async (req: any, res) => {
  try {
    const oLat = parseFloat(String(req.query.origin_lat ?? ''));
    const oLng = parseFloat(String(req.query.origin_lng ?? ''));
    const dLat = parseFloat(String(req.query.dest_lat ?? ''));
    const dLng = parseFloat(String(req.query.dest_lng ?? ''));
    if (![oLat, oLng, dLat, dLng].every(Number.isFinite)) {
      return res.status(400).json({ message: 'origin_lat, origin_lng, dest_lat, dest_lng required' });
    }
    const key = mapsApiKey();
    if (!key) return res.status(503).json({ message: 'Maps not configured' });
    const url = new URL('https://maps.googleapis.com/maps/api/directions/json');
    url.searchParams.set('origin', `${oLat},${oLng}`);
    url.searchParams.set('destination', `${dLat},${dLng}`);
    url.searchParams.set('mode', 'driving');
    url.searchParams.set('region', 'gh');
    url.searchParams.set('language', 'en');
    url.searchParams.set('key', key);
    const { data } = await axios.get(url.toString());
    if (data.status !== 'OK' || !data.routes?.length) {
      return res.status(404).json({ message: data.error_message || 'No route found' });
    }
    const leg = data.routes[0].legs?.[0];
    const durationSec = leg?.duration?.value ?? 0;
    const durationText = leg?.duration?.text ?? '';
    const distanceText = leg?.distance?.text ?? '';
    const encoded = data.routes[0].overview_polyline?.points ?? '';
    const points = encoded ? decodeGooglePolyline(encoded) : [];
    const etaMinutes = Math.max(1, Math.round(durationSec / 60));
    res.json({
      duration_seconds: durationSec,
      duration_text: durationText,
      distance_text: distanceText,
      eta_minutes: etaMinutes,
      points,
    });
  } catch (err) {
    console.error('Maps directions error:', err);
    res.status(500).json({ message: 'Directions failed' });
  }
});

app.get('/api/maps/reverse-geocode', authenticateToken, async (req: any, res) => {
  try {
    const lat = parseFloat(String(req.query.lat ?? ''));
    const lng = parseFloat(String(req.query.lng ?? ''));
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
      return res.status(400).json({ message: 'lat and lng required' });
    }
    const key = mapsApiKey();
    if (!key) return res.status(503).json({ message: 'Maps not configured' });
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('latlng', `${lat},${lng}`);
    url.searchParams.set('key', key);
    url.searchParams.set('region', 'gh');
    url.searchParams.set('language', 'en');
    const { data } = await axios.get(url.toString());
    if (data.status !== 'OK' || !data.results?.length) {
      return res.json({ address: null });
    }
    const address = pickBestGeocodeAddress(data.results);
    res.json({ address });
  } catch (err) {
    console.error('Maps reverse geocode error:', err);
    res.status(500).json({ message: 'Reverse geocode failed' });
  }
});

app.get('/api/config/maps-health', async (_req, res) => {
  const key = mapsApiKey();
  if (!key) {
    return res.json({ ok: false, message: 'No GOOGLE_MAPS_API_KEY in backend env', keyHint: '' });
  }
  const keyHint = `…${key.slice(-6)}`;
  try {
    const url = new URL('https://maps.googleapis.com/maps/api/geocode/json');
    url.searchParams.set('address', 'Accra, Ghana');
    url.searchParams.set('key', key);
    const response = await axios.get(url.toString());
    const data = response.data as { status?: string; error_message?: string };
    if (data.status === 'OK') {
      return res.json({ ok: true, keyHint });
    }
    return res.json({
      ok: false,
      keyHint,
      status: data.status,
      message: data.error_message || data.status || 'Unknown error',
    });
  } catch (err) {
    console.error('Maps health check error:', err);
    res.status(500).json({ ok: false, keyHint, message: 'Could not reach Google Maps API' });
  }
});

app.post('/api/wallet/withdraw', authenticateToken, async (req: any, res) => {
  const { amount, phone, network } = req.body;
  try {
    const userRes = await pool.query('SELECT status, balance FROM users WHERE id = $1', [req.user.id]);
    const userData = userRes.rows[0];
    
    if (userData?.status !== 'active') {
      return res.status(403).json({ message: 'Your account is pending approval.' });
    }
    
    // Check if user has enough balance
    if (parseFloat(userData.balance) < amount) {
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
    let query = 'SELECT id, name, email, phone, cover_image, address, lat, lng, region FROM users WHERE role = $1 AND status = \'active\'';
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
    const userRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
    if (userRes.rows[0]?.status !== 'active' && req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Your account is pending approval.' });
    }
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
    const userRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
    if (userRes.rows[0]?.status !== 'active' && req.user.role !== 'admin') {
      return res.status(403).json({ message: 'Your account is pending approval.' });
    }
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

app.delete('/api/products/:id', authenticateToken, async (req: any, res) => {
  const { id } = req.params;
  if (req.user.role !== 'vendor' && req.user.role !== 'admin') return res.sendStatus(403);
  try {
    const productRes = await pool.query('SELECT vendor_id FROM products WHERE id = $1', [id]);
    if (!productRes.rows[0]) return res.status(404).json({ message: 'Product not found' });
    if (req.user.role === 'vendor' && productRes.rows[0].vendor_id !== req.user.id) {
      return res.status(403).json({ message: 'Not authorized to delete this product' });
    }
    await pool.query('DELETE FROM products WHERE id = $1', [id]);
    res.json({ success: true, message: 'Product deleted' });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Admin User Management
app.get('/api/admin/users', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  try {
    const result = await pool.query(
      `SELECT id, name, email, role, balance, created_at, status, is_online, phone, region
       FROM users ORDER BY created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/admin/pending-riders', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  try {
    const result = await pool.query(
      `SELECT u.id, u.name, u.email, u.phone, u.region, u.status, u.is_online, u.created_at,
        COALESCE(
          json_agg(
            json_build_object(
              'doc_type', d.doc_type,
              'image_url', d.image_url,
              'review_status', d.review_status,
              'rejection_reason', d.rejection_reason,
              'uploaded_at', d.uploaded_at
            ) ORDER BY d.doc_type
          ) FILTER (WHERE d.doc_type IS NOT NULL),
          '[]'::json
        ) AS documents
       FROM users u
       LEFT JOIN rider_documents d ON d.user_id = u.id
       WHERE u.role = 'rider'
         AND (
           u.status IN ('pending', 'rejected')
           OR EXISTS (
             SELECT 1 FROM rider_documents rd
             WHERE rd.user_id = u.id AND rd.review_status = 'pending'
           )
         )
       GROUP BY u.id
       ORDER BY u.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Pending riders error:', err);
    res.status(500).json({ message: 'Failed to fetch pending riders' });
  }
});

app.patch('/api/admin/riders/:id/approve', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { id } = req.params;
  try {
    const check = await pool.query('SELECT id, role FROM users WHERE id = $1', [id]);
    if (!check.rows[0] || check.rows[0].role !== 'rider') {
      return res.status(404).json({ message: 'Rider not found' });
    }
    const result = await pool.query(
      `UPDATE users SET status = 'active', is_online = false WHERE id = $1
       RETURNING id, name, email, role, status, is_online, phone, region`,
      [id]
    );
    await pool.query(
      `UPDATE rider_documents SET review_status = 'approved', rejection_reason = NULL,
        reviewed_by = $2, reviewed_at = CURRENT_TIMESTAMP
       WHERE user_id = $1`,
      [id, req.user.id]
    );
    res.json(result.rows[0]);
    io.to(id).emit('status:updated', { status: 'active', is_online: false });
  } catch (err) {
    console.error('Approve rider error:', err);
    res.status(500).json({ message: 'Failed to approve rider' });
  }
});

app.patch('/api/admin/riders/:id/reject', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { id } = req.params;
  const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
  try {
    const check = await pool.query('SELECT id, role FROM users WHERE id = $1', [id]);
    if (!check.rows[0] || check.rows[0].role !== 'rider') {
      return res.status(404).json({ message: 'Rider not found' });
    }
    const result = await pool.query(
      `UPDATE users SET status = 'rejected', is_online = false WHERE id = $1
       RETURNING id, name, email, role, status, is_online, phone, region`,
      [id]
    );
    await pool.query(
      `UPDATE rider_documents SET review_status = 'rejected', rejection_reason = $2,
        reviewed_by = $3, reviewed_at = CURRENT_TIMESTAMP
       WHERE user_id = $1`,
      [id, reason || 'Application rejected', req.user.id]
    );
    res.json(result.rows[0]);
    io.to(id).emit('status:updated', { status: 'rejected', is_online: false, reason: reason || 'Application rejected' });
  } catch (err) {
    console.error('Reject rider error:', err);
    res.status(500).json({ message: 'Failed to reject rider' });
  }
});

/** Send a test SMS (admin diagnostics). */
app.post('/api/admin/sms-test', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const phone = typeof req.body?.phone === 'string' ? req.body.phone.trim() : '';
  if (!phone || !isValidGhanaPhone(phone)) {
    return res.status(400).json({ message: 'Enter a valid Ghana phone (e.g. 0247904675).' });
  }
  try {
    const cfg = await getSmsConfig();
    const data = await sendSMS(phone, 'BytzGo SMS test — your OTP gateway is working.');
    res.json({
      success: true,
      message: 'Test SMS accepted by gateway. Check the phone within 1–2 minutes.',
      phone: formatGhanaPhone(phone),
      sender: cfg.senderId,
      config_source: cfg.source,
      gateway: data,
    });
  } catch (err: any) {
    console.error('[admin/sms-test]', err.message);
    res.status(502).json({ message: err.message || 'SMS test failed' });
  }
});

/** Live fleet + ops counters for admin control tower. */
app.get('/api/admin/overview', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  try {
    const statsRes = await pool.query(`
      SELECT
        (SELECT COUNT(*)::int FROM users WHERE role = 'rider' AND is_online = true AND status = 'active') AS drivers_online,
        (SELECT COUNT(*)::int FROM users WHERE role = 'rider' AND status = 'active') AS drivers_approved,
        (SELECT COUNT(*)::int FROM users WHERE role = 'rider') AS drivers_total,
        (SELECT COUNT(*)::int FROM users WHERE role = 'rider' AND status IN ('pending', 'rejected')) AS drivers_pending,
        (SELECT COUNT(*)::int FROM orders WHERE status NOT IN ('delivered', 'cancelled')) AS active_orders,
        (SELECT COUNT(*)::int FROM orders WHERE created_at >= CURRENT_DATE) AS orders_today,
        (SELECT COUNT(*)::int FROM users WHERE role = 'vendor' AND status = 'active') AS vendors_active,
        (SELECT COUNT(*)::int FROM users WHERE role = 'customer') AS customers_total,
        (SELECT COALESCE(SUM(total), 0)::float FROM orders WHERE status = 'delivered') AS gross_revenue
    `);
    const ridersRes = await pool.query(`
      SELECT
        u.id,
        u.name,
        u.email,
        u.phone,
        u.region,
        u.status,
        u.is_online,
        rl.lat,
        rl.lng,
        rl.updated_at AS location_updated_at,
        (
          SELECT COUNT(*)::int FROM orders o
          WHERE o.rider_id = u.id AND o.status NOT IN ('delivered', 'cancelled')
        ) AS active_trips
      FROM users u
      LEFT JOIN rider_locations rl ON rl.rider_id = u.id
      WHERE u.role = 'rider'
      ORDER BY u.is_online DESC, rl.updated_at DESC NULLS LAST, u.name ASC
    `);
    const liveRiders = ridersRes.rows.map((row: any) => ({
      id: row.id,
      name: row.name,
      email: row.email,
      phone: row.phone,
      region: row.region,
      status: row.status,
      is_online: row.is_online === true,
      lat: row.lat != null ? parseFloat(row.lat) : null,
      lng: row.lng != null ? parseFloat(row.lng) : null,
      location_updated_at: row.location_updated_at,
      active_trips: row.active_trips ?? 0,
      has_location:
        row.lat != null &&
        row.lng != null &&
        Math.abs(parseFloat(row.lat)) > 0.001 &&
        Math.abs(parseFloat(row.lng)) > 0.001,
    }));
    res.json({
      stats: statsRes.rows[0],
      live_riders: liveRiders,
    });
  } catch (err) {
    console.error('[admin/overview]', err);
    res.status(500).json({ message: 'Failed to load admin overview' });
  }
});

app.patch('/api/admin/users/:id/status', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { status } = req.body;
  const { id } = req.params;
  try {
    const isRiderActivate = status === 'active';
    const result = await pool.query(
      `UPDATE users SET status = $1,
        is_online = CASE WHEN role = 'rider' AND $3 THEN false ELSE is_online END
       WHERE id = $2 RETURNING id, name, email, role, status, is_online`,
      [status, id, isRiderActivate]
    );
    if (result.rows[0]) {
      const row = result.rows[0];
      if (row.role === 'rider' && status === 'active') {
        await pool.query(
          `UPDATE rider_documents SET review_status = 'approved', rejection_reason = NULL,
            reviewed_by = $2, reviewed_at = CURRENT_TIMESTAMP WHERE user_id = $1`,
          [id, req.user.id]
        );
      }
      res.json(row);
      io.to(id).emit('status:updated', { status, is_online: row.is_online });
    } else {
      res.status(404).json({ message: 'User not found' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

// Order Routes
app.get('/api/orders', authenticateToken, async (req: any, res) => {
  try {
    let query = `SELECT o.*, ${ORDER_CONTACT_SELECT} FROM orders o ${ORDER_CONTACT_JOINS}`;
    const params: any[] = [];

    if (req.user.role === 'customer') {
      query += ' WHERE o.customer_id = $1';
      params.push(req.user.id);
    } else if (req.user.role === 'vendor') {
      query += ' WHERE o.vendor_id = $1';
      params.push(req.user.id);
    } else if (req.user.role === 'rider') {
      const userRes = await pool.query('SELECT status, is_online FROM users WHERE id = $1', [req.user.id]);
      const rider = userRes.rows[0];
      if (rider?.status !== 'active') {
        return res.json([]);
      }

      query = `
        SELECT o.*, odo.expires_at AS rider_offer_expires_at, odo.wave AS rider_offer_wave,
          ${ORDER_CONTACT_SELECT}
        FROM orders o
        ${ORDER_CONTACT_JOINS}
        LEFT JOIN order_dispatch_offers odo ON odo.order_id = o.id
          AND odo.rider_id = $1
          AND odo.status = 'offered'
          AND odo.expires_at > NOW()
        WHERE (
          o.rider_id = $1
        ) OR (
          o.status = 'ready'
          AND o.rider_id IS NULL
          AND odo.order_id IS NOT NULL
          AND $2 = true
        )
        ORDER BY o.created_at DESC`;
      params.push(req.user.id, rider?.is_online === true);
    }

    if (req.user.role !== 'rider') {
      query += ' ORDER BY o.created_at DESC';
    }

    const result = await pool.query(query, params);
    const rows = result.rows.map((o: any) => {
      const row = sanitizeOrderForRole(o, req.user.role, req.user.id);
      if (req.user.role === 'rider' && o.rider_offer_expires_at) {
        row.expiresAt = new Date(o.rider_offer_expires_at).toISOString();
        row.dispatchWave = o.rider_offer_wave;
      }
      return row;
    });
    res.json(rows);
  } catch (err) {
    console.error('Fetch orders error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/orders', authenticateToken, async (req: any, res) => {
  const {
    items,
    total,
    address,
    pickup,
    orderType,
    order_type,
    scheduledTime,
    scheduled_time,
    vendorId,
    lat,
    lng,
    pickup_lat,
    pickup_lng,
    region: providedRegion,
    payment_reference,
    payment_method,
    delivery_fee,
  } = req.body;
  
  let paymentStatus = 'pending';
  const finalPaymentMethod = payment_method || (payment_reference ? 'paystack' : 'pay_on_delivery');

  // Verify Paystack payment if reference provided
  if (payment_reference) {
    try {
      const verified = await verifyPaystackTransaction(payment_reference);
      if (Math.abs(verified.amountGhs - Number(total)) > 0.02) {
        return res.status(400).json({ message: 'Payment amount does not match order total' });
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
    } else if (finalOrderType === 'courier') {
      finalPickup = pickup || finalPickup;
      pickupLat = pickup_lat ?? pickupLat;
      pickupLng = pickup_lng ?? pickupLng;
    }

    // Fallback to customer's region if still not found
    if (!finalRegion) {
      const customerRes = await pool.query('SELECT region FROM users WHERE id = $1', [req.user.id]);
      finalRegion = customerRes.rows[0]?.region;
    }

    let finalDeliveryFee = Number(delivery_fee) || 0;
    if (
      pickupLat != null &&
      pickupLng != null &&
      lat != null &&
      lng != null &&
      Number(pickupLat) &&
      Number(pickupLng) &&
      Number(lat) &&
      Number(lng)
    ) {
      const quote = await calculateDeliveryFeeFromCoords(
        Number(pickupLat),
        Number(pickupLng),
        Number(lat),
        Number(lng),
        finalRegion,
        finalRegion
      );
      finalDeliveryFee = quote.delivery_fee;
      const itemsSubtotal = Array.isArray(items)
        ? items.reduce(
            (sum: number, it: any) =>
              sum + Number(it.price || 0) * Number(it.quantity || 1),
            0
          )
        : 0;
      const expectedTotal =
        finalOrderType === 'courier' && itemsSubtotal <= 0
          ? finalDeliveryFee
          : Math.round((itemsSubtotal + finalDeliveryFee) * 100) / 100;
      if (Math.abs(Number(total) - expectedTotal) > 1) {
        return res.status(400).json({
          message: 'Order total does not match items + delivery for route distance',
          distance_km: quote.distance_km,
          delivery_fee: finalDeliveryFee,
          expected_total: expectedTotal,
        });
      }
    }

    const initialStatus = (finalOrderType === 'courier') ? 'ready' : 'pending';
    const scheduled = scheduledTime || scheduled_time || null;

    const result = await pool.query(
      'INSERT INTO orders (customer_id, vendor_id, items, total, status, address, pickup_address, order_type, scheduled_time, lat, lng, pickup_lat, pickup_lng, region, payment_status, payment_method, delivery_fee) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17) RETURNING *',
      [req.user.id, vendorId, JSON.stringify(items), total, initialStatus, address || 'Customer Address', finalPickup || 'Pickup', finalOrderType, scheduled, lat, lng, pickupLat, pickupLng, finalRegion, paymentStatus, finalPaymentMethod, finalDeliveryFee]
    );
    const order = result.rows[0];
    res.json(order);
    io.emit('order:new', order); // Notify vendors/admin
    if (isOfferableOrder(order)) {
      void broadcastRideOfferToRiders(order);
    }
  } catch (err) {
    console.error('Order creation error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/orders/:id', authenticateToken, async (req: any, res) => {
  const { status, riderId } = req.body;
  const orderId = req.params.id;
  
  try {
    // Check if vendor/rider is active before allowing updates
    if (req.user.role === 'vendor' || req.user.role === 'rider') {
      const userRes = await pool.query('SELECT status, is_online FROM users WHERE id = $1', [req.user.id]);
      const account = userRes.rows[0];
      if (account?.status !== 'active') {
        const message =
          account?.status === 'pending'
            ? 'Your account is pending approval.'
            : account?.status === 'rejected'
              ? 'Your driver application was rejected.'
              : 'Your account is not active.';
        return res.status(403).json({ message });
      }
      if (req.user.role === 'rider') {
        const accepting = Boolean(riderId) || status === 'picked_up' || status === 'ready';
        if (accepting && !account?.is_online) {
          return res.status(403).json({ message: 'Go online to accept and update rides.' });
        }
      }
    }

    if (riderId && req.user.role === 'rider' && riderId !== req.user.id) {
      return res.status(403).json({ message: 'You can only accept rides for yourself.' });
    }

    if (req.user.role === 'rider' && (status === 'delivered' || status === 'arrived')) {
      return res.status(400).json({ message: 'Use the arrive or complete-delivery actions in the driver app.' });
    }
    if (req.user.role !== 'admin' && status === 'delivered') {
      return res.status(400).json({ message: 'Deliveries must be completed with the customer delivery PIN.' });
    }

    let result;
    if (status === 'picked_up') {
      const code = generateDeliveryCode();
      const params: any[] = [status, code];
      let q = `UPDATE orders SET status = $1, delivery_code = $2, delivery_code_created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $${params.length + 1}`;
      if (riderId) {
        params.splice(1, 0, riderId);
        q = `UPDATE orders SET status = $1, rider_id = $2, delivery_code = $3, delivery_code_created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $${params.length + 1} AND rider_id IS NULL`;
      }
      params.push(orderId);
      q += ' RETURNING *';
      result = await pool.query(q, params);
    } else {
      let updateQuery = 'UPDATE orders SET status = $1';
      const params: any[] = [status];

      if (riderId) {
        updateQuery += ', rider_id = $2';
        params.push(riderId);
      }

      updateQuery += `, updated_at = CURRENT_TIMESTAMP WHERE id = $${params.length + 1}`;
      if (riderId) {
        updateQuery += ' AND rider_id IS NULL';
      }
      updateQuery += ' RETURNING *';
      params.push(orderId);
      result = await pool.query(updateQuery, params);
    }

    const order = result.rows[0];

    if (!order && riderId) {
      return res.status(409).json({ message: 'This ride was already taken by another rider.' });
    }
    
    if (order) {
      res.json(sanitizeOrderForRole(order, req.user.role, req.user.id));
      broadcastOrderUpdated(order);
      if (riderId && order.rider_id) {
        await notifyRideTaken(order.id, order.rider_id);
      } else if (isOfferableOrder(order)) {
        broadcastRideOfferToRiders(order);
      }
      if (status === 'delivered' && req.user.role === 'admin') {
        await settleOrderPayment(order);
      }
    } else {
      res.status(404).json({ message: 'Order not found' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/orders/:id/decline', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') {
    return res.status(403).json({ message: 'Riders only' });
  }
  const orderId = req.params.id;
  try {
    const userRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
    if (userRes.rows[0]?.status !== 'active') {
      return res.status(403).json({ message: 'Go online to respond to ride offers.' });
    }
    await recordRiderDecline(orderId, req.user.id);
    res.json({ ok: true });
  } catch (err) {
    console.error('[dispatch] decline failed:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/orders/:id/arrive', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') return res.status(403).json({ message: 'Riders only' });
  const orderId = req.params.id;
  try {
    const userRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
    if (userRes.rows[0]?.status !== 'active') {
      return res.status(403).json({ message: 'Go online to update rides.' });
    }
    const orderRes = await pool.query('SELECT * FROM orders WHERE id = $1 AND rider_id = $2', [orderId, req.user.id]);
    if (!orderRes.rows[0]) return res.status(404).json({ message: 'Order not found' });
    const existing = orderRes.rows[0];
    if (existing.status !== 'picked_up') {
      return res.status(400).json({ message: 'Mark the order as picked up first.' });
    }
    const result = await pool.query(
      `UPDATE orders SET status = 'arrived', arrived_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`,
      [orderId]
    );
    const order = result.rows[0];
    broadcastOrderUpdated(order);
    res.json(sanitizeOrderForRole(order, 'rider', req.user.id));
  } catch (err) {
    console.error('Arrive error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/orders/:id/ack-cash', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'customer') return res.status(403).json({ message: 'Customers only' });
  const orderId = req.params.id;
  try {
    const orderRes = await pool.query('SELECT * FROM orders WHERE id = $1 AND customer_id = $2', [orderId, req.user.id]);
    if (!orderRes.rows[0]) return res.status(404).json({ message: 'Order not found' });
    const order = orderRes.rows[0];
    if (order.status !== 'arrived') {
      return res.status(400).json({ message: 'Confirm cash payment when your driver has arrived.' });
    }
    if (order.payment_status === 'paid') {
      return res.json(sanitizeOrderForRole(order, 'customer', req.user.id));
    }
    const result = await pool.query(
      `UPDATE orders SET customer_payment_ack = 'cash', updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`,
      [orderId]
    );
    const updated = result.rows[0];
    broadcastOrderUpdated(updated);
    res.json(sanitizeOrderForRole(updated, 'customer', req.user.id));
  } catch (err) {
    console.error('Ack cash error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/orders/:id/pay-at-delivery', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'customer') return res.status(403).json({ message: 'Customers only' });
  const { payment_method, payment_reference } = req.body;
  const orderId = req.params.id;
  try {
    const orderRes = await pool.query('SELECT * FROM orders WHERE id = $1 AND customer_id = $2', [orderId, req.user.id]);
    if (!orderRes.rows[0]) return res.status(404).json({ message: 'Order not found' });
    const order = orderRes.rows[0];
    if (order.status !== 'arrived') {
      return res.status(400).json({ message: 'Pay when your driver has arrived.' });
    }
    if (order.payment_status === 'paid') {
      return res.json(sanitizeOrderForRole(order, 'customer', req.user.id));
    }

    const total = parseFloat(order.total);

    if (payment_method === 'wallet') {
      const userRes = await pool.query('SELECT balance FROM users WHERE id = $1', [req.user.id]);
      if (parseFloat(userRes.rows[0].balance) < total) {
        return res.status(400).json({ message: 'Insufficient wallet balance' });
      }
      const balanceRes = await pool.query(
        'UPDATE users SET balance = balance - $1 WHERE id = $2 RETURNING balance',
        [total, req.user.id]
      );
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [req.user.id, total, 'payment', `Delivery payment #${orderId.slice(0, 8)}`]
      );
      io.to(req.user.id).emit('wallet:updated', { balance: parseFloat(balanceRes.rows[0].balance) });
    } else if (payment_reference) {
      const verified = await verifyPaystackTransaction(payment_reference);
      if (Math.abs(verified.amountGhs - total) > 0.02) {
        return res.status(400).json({ message: 'Payment amount does not match order total' });
      }
    } else {
      return res.status(400).json({ message: 'Invalid payment method' });
    }

    const ack = payment_method === 'wallet' ? 'wallet' : 'paystack';
    const method = payment_method === 'wallet' ? 'wallet' : 'paystack';
    const result = await pool.query(
      `UPDATE orders SET payment_status = 'paid', customer_payment_ack = $1, payment_method = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3 RETURNING *`,
      [ack, method, orderId]
    );
    const updated = result.rows[0];
    broadcastOrderUpdated(updated);
    res.json(sanitizeOrderForRole(updated, 'customer', req.user.id));
  } catch (err) {
    console.error('Pay at delivery error:', err);
    res.status(500).json({ message: err instanceof Error ? err.message : 'Payment failed' });
  }
});

app.post('/api/orders/:id/complete-delivery', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') return res.status(403).json({ message: 'Riders only' });
  const { code } = req.body;
  const orderId = req.params.id;

  if (!code || String(code).trim().length !== 6) {
    return res.status(400).json({ message: 'Invalid code' });
  }

  const lock = deliveryCodeAttempts.get(orderId);
  if (lock && lock.lockedUntil > Date.now()) {
    return res.status(429).json({ message: 'Too many attempts. Try again in 15 minutes.' });
  }

  try {
    const userRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
    if (userRes.rows[0]?.status !== 'active') {
      return res.status(403).json({ message: 'Go online to complete deliveries.' });
    }

    const orderRes = await pool.query('SELECT * FROM orders WHERE id = $1 AND rider_id = $2', [orderId, req.user.id]);
    if (!orderRes.rows[0]) return res.status(404).json({ message: 'Order not found' });
    const order = orderRes.rows[0];

    if (order.status !== 'arrived') {
      return res.status(400).json({ message: 'Mark arrived before completing delivery.' });
    }

    if (!isCustomerPaymentReady(order)) {
      return res.status(400).json({ message: 'Waiting for customer to confirm payment.' });
    }

    if (order.delivery_code !== String(code).trim()) {
      const attempts = (lock?.attempts || 0) + 1;
      if (attempts >= 5) {
        deliveryCodeAttempts.set(orderId, { attempts, lockedUntil: Date.now() + 15 * 60 * 1000 });
      } else {
        deliveryCodeAttempts.set(orderId, { attempts, lockedUntil: 0 });
      }
      return res.status(400).json({ message: 'Invalid code' });
    }

    deliveryCodeAttempts.delete(orderId);

    const result = await pool.query(
      `UPDATE orders SET status = 'delivered', updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`,
      [orderId]
    );
    const delivered = result.rows[0];
    await settleOrderPayment(delivered);
    broadcastOrderUpdated(delivered);
    res.json(sanitizeOrderForRole(delivered, 'rider', req.user.id));
  } catch (err) {
    console.error('Complete delivery error:', err);
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

const CUSTOMER_CANCELLABLE_STATUSES = ['pending', 'ready', 'preparing'];

app.post('/api/orders/:id/cancel', authenticateToken, async (req: any, res) => {
  const orderId = req.params.id;
  try {
    const orderRes = await pool.query('SELECT * FROM orders WHERE id = $1', [orderId]);
    if (orderRes.rowCount === 0) return res.status(404).json({ message: 'Order not found' });

    const order = orderRes.rows[0];
    if (order.customer_id !== req.user.id) {
      return res.status(403).json({ message: 'Unauthorized' });
    }
    if (!CUSTOMER_CANCELLABLE_STATUSES.includes(order.status)) {
      return res.status(400).json({
        message: 'This trip can no longer be cancelled (package already picked up or delivered).',
      });
    }

    const prevRiderId = order.rider_id;
    const updated = await pool.query(
      `UPDATE orders SET status = 'cancelled', rider_id = NULL, updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 RETURNING *`,
      [orderId]
    );
    const cancelled = updated.rows[0];

    if (cancelled.payment_status === 'paid') {
      const bRes = await pool.query(
        'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
        [cancelled.total, req.user.id]
      );
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [req.user.id, cancelled.total, 'topup', `Refund for cancelled order #${orderId.slice(-6)}`]
      );
      io.to(req.user.id).emit('wallet:updated', { balance: parseFloat(bRes.rows[0].balance) });
    }

    if (prevRiderId) {
      await notifyRideTaken(orderId, prevRiderId);
    }

    res.json(sanitizeOrderForRole(cancelled, req.user.role, req.user.id));
    broadcastOrderUpdated(cancelled);
  } catch (err) {
    console.error('Cancel order error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/orders/:id/messages', authenticateToken, async (req: any, res) => {
  const orderId = req.params.id;
  try {
    await assertOrderChatAccess(orderId, req.user.id);
    const result = await pool.query(
      `SELECT m.*, u.name AS sender_name
       FROM order_messages m
       JOIN users u ON u.id = m.sender_id
       WHERE m.order_id = $1
       ORDER BY m.created_at ASC
       LIMIT 200`,
      [orderId]
    );
    res.json(
      result.rows.map((row: any) => formatOrderMessage(row, req.user.id))
    );
  } catch (err: any) {
    const status = err.status || 500;
    res.status(status).json({ message: err.message || 'Server error' });
  }
});

app.post('/api/orders/:id/messages', authenticateToken, async (req: any, res) => {
  const orderId = req.params.id;
  const body = String(req.body?.body ?? req.body?.text ?? '').trim();
  if (!body) return res.status(400).json({ message: 'Message cannot be empty' });
  if (body.length > 1000) {
    return res.status(400).json({ message: 'Message is too long (max 1000 characters)' });
  }
  try {
    const order = await assertOrderChatAccess(orderId, req.user.id);
    const inserted = await pool.query(
      `INSERT INTO order_messages (order_id, sender_id, body)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [orderId, req.user.id, body]
    );
    const row = inserted.rows[0];
    const nameRes = await pool.query('SELECT name FROM users WHERE id = $1', [req.user.id]);
    row.sender_name = nameRes.rows[0]?.name;

    const payload = formatOrderMessage(row, req.user.id);
    if (order.customer_id) {
      io.to(order.customer_id).emit('order:message', {
        orderId,
        message: formatOrderMessage(row, order.customer_id),
      });
    }
    if (order.rider_id) {
      io.to(order.rider_id).emit('order:message', {
        orderId,
        message: formatOrderMessage(row, order.rider_id),
      });
    }

    const recipientId =
      req.user.id === order.customer_id ? order.rider_id : order.customer_id;
    if (recipientId) {
      const senderName = nameRes.rows[0]?.name || 'Someone';
      void sendPushToUserIds([recipientId], {
        title: `Message from $senderName`,
        body: body.length > 140 ? `${body.slice(0, 137)}…` : body,
        type: 'trip-message',
        orderId,
        channelId: 'trip_updates',
        highPriority: true,
      });
    }

    res.status(201).json(payload);
  } catch (err: any) {
    const status = err.status || 500;
    res.status(status).json({ message: err.message || 'Server error' });
  }
});

// Admin: Approve Product
app.patch('/api/admin/products/:id/approve', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  try {
    const result = await pool.query(
      'UPDATE products SET is_approved = true WHERE id = $1 RETURNING *',
      [req.params.id]
    );
    if (!result.rows[0]) return res.status(404).json({ message: 'Product not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ message: 'Failed to approve product' });
  }
});

app.patch('/api/admin/products/:id/reject', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  try {
    const result = await pool.query(
      'DELETE FROM products WHERE id = $1 AND is_approved = false RETURNING id',
      [req.params.id]
    );
    if (!result.rows[0]) return res.status(404).json({ message: 'Product not found or already approved' });
    res.json({ success: true, message: 'Product rejected and removed' });
  } catch (err) {
    res.status(500).json({ message: 'Failed to reject product' });
  }
});

app.get('/api/admin/settings', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  try {
    const pub = await getSetting('paystack_public_key');
    const sec = await getSetting('paystack_secret_key');
    const fee = await getSetting('platform_fee_percent');
    const pricePerKm = await getSetting('delivery_price_per_km');
    const maskSecret = (k: string) => {
      if (!k) return '';
      if (k.length <= 8) return '••••••••';
      return k.slice(0, 7) + '…' + k.slice(-4);
    };
    const smsKey = await getSetting('sms_api_key');
    const smsBase = await getSetting('sms_base_url');
    const smsSender = await getSetting('sms_sender_id');
    const effectiveSmsKey = process.env.SMS_API_KEY?.trim() || smsKey || '';
    res.json({
      paystack_public_key: pub || process.env.PAYSTACK_PUBLIC_KEY || '',
      paystack_secret_key: maskSecret(sec || process.env.PAYSTACK_SECRET_KEY || ''),
      paystack_secret_configured: !!(sec || process.env.PAYSTACK_SECRET_KEY),
      platform_fee_percent: fee || '10',
      delivery_price_per_km: pricePerKm || '4',
      sms_base_url: smsBase || process.env.SMS_BASE_URL || 'https://www.inteksms.top/api/v1',
      sms_api_key: maskSecret(effectiveSmsKey),
      sms_api_key_configured: effectiveSmsKey.length > 8,
      sms_sender_id: smsSender || process.env.SMS_SENDER_ID || 'bytzee',
      sms_config_source: process.env.SMS_API_KEY?.trim() ? 'env' : smsKey ? 'database' : 'default',
    });
  } catch (err) {
    res.status(500).json({ message: 'Failed to load settings' });
  }
});

app.patch('/api/admin/settings', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  const {
    paystack_public_key,
    paystack_secret_key,
    platform_fee_percent,
    delivery_price_per_km,
    sms_base_url,
    sms_api_key,
    sms_sender_id,
  } = req.body;
  try {
    if (paystack_public_key != null) {
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('paystack_public_key', $1)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [String(paystack_public_key).trim()]
      );
    }
    if (paystack_secret_key && !String(paystack_secret_key).includes('…')) {
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('paystack_secret_key', $1)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [String(paystack_secret_key).trim()]
      );
    }
    if (platform_fee_percent != null) {
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('platform_fee_percent', $1)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [String(platform_fee_percent)]
      );
    }
    if (delivery_price_per_km != null) {
      const rate = Math.max(0.01, parseFloat(String(delivery_price_per_km)) || 4);
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('delivery_price_per_km', $1)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [String(rate)]
      );
    }
    if (sms_base_url != null && String(sms_base_url).trim()) {
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('sms_base_url', $1)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [String(sms_base_url).trim()]
      );
    }
    if (sms_api_key && !String(sms_api_key).includes('…')) {
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('sms_api_key', $1)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [String(sms_api_key).trim()]
      );
    }
    if (sms_sender_id != null && String(sms_sender_id).trim()) {
      await pool.query(
        `INSERT INTO system_settings (key, value) VALUES ('sms_sender_id', $1)
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
        [String(sms_sender_id).trim()]
      );
    }
    res.json({ success: true, message: 'Settings updated' });
  } catch (err) {
    res.status(500).json({ message: 'Failed to update settings' });
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
    const globalRate = Math.max(0.01, parseFloat((await getSetting('delivery_price_per_km')) || '4') || 4);
    const km = distance_km || 0;

    if (!zone) {
      const price = Math.round(km * globalRate * 100) / 100;
      return res.json({ price, zone: null, fallback: true, price_per_km: globalRate });
    }

    const rate = Number(zone.price_per_km) > 0 ? Number(zone.price_per_km) : globalRate;
    let price = km * rate;
    price = Math.max(price, Number(zone.min_price));
    if (zone.max_price) price = Math.min(price, Number(zone.max_price));
    
    res.json({ price: Math.round(price * 100) / 100, zone: zone.name, fallback: false });
  } catch (err) {
    console.error('Price calculation error:', err);
    res.status(500).json({ message: 'Failed to calculate price' });
  }
});

// Delivery fee from coordinates (shop → customer route)
app.post('/api/delivery/calculate', authenticateToken, async (req: any, res) => {
  const {
    pickup_lat,
    pickup_lng,
    dest_lat,
    dest_lng,
    destination_lat,
    destination_lng,
    pickup_region,
    destination_region,
  } = req.body;
  const pLat = Number(pickup_lat);
  const pLng = Number(pickup_lng);
  const dLat = Number(dest_lat ?? destination_lat);
  const dLng = Number(dest_lng ?? destination_lng);
  if (!pLat || !pLng || !dLat || !dLng) {
    return res.status(400).json({ message: 'pickup and destination coordinates required' });
  }
  try {
    const quote = await calculateDeliveryFeeFromCoords(
      pLat,
      pLng,
      dLat,
      dLng,
      pickup_region,
      destination_region
    );
    res.json({
      ...quote,
      route: {
        legs: [
          {
            from: 'shop',
            to: 'customer',
            label: 'Shop → You',
            distance_km: quote.distance_km,
          },
        ],
      },
    });
  } catch (err) {
    console.error('Delivery calculate error:', err);
    res.status(500).json({ message: 'Failed to calculate delivery' });
  }
});

// FCM device tokens (mobile — alerts when app is closed)
app.post('/api/push/fcm-token', authenticateToken, async (req: any, res) => {
  const { token, platform } = req.body;
  if (!token || typeof token !== 'string') {
    return res.status(400).json({ message: 'token required' });
  }
  try {
    await pool.query(
      `INSERT INTO fcm_tokens (user_id, token, platform, updated_at)
       VALUES ($1, $2, $3, CURRENT_TIMESTAMP)
       ON CONFLICT (user_id, token) DO UPDATE SET platform = $3, updated_at = CURRENT_TIMESTAMP`,
      [req.user.id, token.trim(), platform || 'android']
    );
    res.json({ ok: true });
  } catch (err) {
    console.error('FCM token save error:', err);
    res.status(500).json({ message: 'Failed to save FCM token' });
  }
});

app.delete('/api/push/fcm-token', authenticateToken, async (req: any, res) => {
  const { token } = req.body;
  if (!token) return res.status(400).json({ message: 'token required' });
  try {
    await pool.query('DELETE FROM fcm_tokens WHERE user_id = $1 AND token = $2', [
      req.user.id,
      token,
    ]);
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: 'Failed to remove FCM token' });
  }
});

// Web Push (background ride alerts for riders)
app.get('/api/push/vapid-public-key', async (_req, res) => {
  if (!vapidPublicKey) {
    try {
      await ensureVapidKeys();
    } catch (err) {
      console.error('[push] VAPID key load failed:', err);
    }
  }
  res.json({ publicKey: vapidPublicKey });
});

app.post('/api/push/subscribe', authenticateToken, async (req: any, res) => {
  const { endpoint, keys } = req.body;
  if (!endpoint || !keys?.p256dh || !keys?.auth) {
    return res.status(400).json({ message: 'Invalid subscription' });
  }
  if (req.user.role !== 'rider') {
    return res.status(403).json({ message: 'Riders only' });
  }
  try {
    await pool.query(
      `INSERT INTO push_subscriptions (user_id, endpoint, keys_p256dh, keys_auth)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (endpoint) DO UPDATE SET user_id = $1, keys_p256dh = $3, keys_auth = $4`,
      [req.user.id, endpoint, keys.p256dh, keys.auth]
    );
    res.json({ ok: true });
  } catch (err) {
    console.error('Push subscribe error:', err);
    res.status(500).json({ message: 'Failed to save subscription' });
  }
});

app.delete('/api/push/subscribe', authenticateToken, async (req: any, res) => {
  const { endpoint } = req.body;
  if (!endpoint) return res.status(400).json({ message: 'endpoint required' });
  try {
    await pool.query(
      'DELETE FROM push_subscriptions WHERE endpoint = $1 AND user_id = $2',
      [endpoint, req.user.id]
    );
    res.json({ ok: true });
  } catch (err) {
    res.status(500).json({ message: 'Failed to remove subscription' });
  }
});

// Socket.io Connection
io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  socket.on('join', (userId) => {
    if (!userId) return;
    const room = String(userId).trim();
    socket.join(room);
    console.log(`User ${room} joined their room`);
  });

  socket.on('location:update', async ({ userId, lat, lng }) => {
    if (!userId || lat == null || lng == null) return;
    const riderId = String(userId).trim();
    try {
      await pool.query(
        'INSERT INTO rider_locations (rider_id, lat, lng, updated_at) VALUES ($1, $2, $3, CURRENT_TIMESTAMP) ON CONFLICT (rider_id) DO UPDATE SET lat = $2, lng = $3, updated_at = CURRENT_TIMESTAMP',
        [riderId, lat, lng]
      );
      io.emit('location:updated', { riderId, lat, lng });
    } catch (err) {
      console.error('Location update failed', err);
    }
  });

  socket.on('disconnect', () => {
    console.log('User disconnected');
  });
});

/** Production: serve Vite build so bytzgo.net serves web + /api (Flutter uses same host). */
function attachWebApp() {
  const shouldServe =
    process.env.SERVE_WEB === 'true' || process.env.NODE_ENV === 'production';
  if (!shouldServe) return;

  const distDir = path.join(__dirname, '..', 'dist');
  const indexHtml = path.join(distDir, 'index.html');
  if (!fs.existsSync(indexHtml)) {
    console.warn('BytzGo: dist/index.html missing — API-only mode');
    return;
  }

  console.log(`BytzGo: serving web app from ${distDir}`);
  app.use(express.static(distDir, { maxAge: '1h', index: false }));
  app.get('*', (req, res, next) => {
    if (req.path.startsWith('/api') || req.path.startsWith('/socket.io')) {
      return next();
    }
    res.sendFile(indexHtml);
  });
}

attachWebApp();

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '0.0.0.0';
httpServer.listen(PORT, HOST, () => {
  console.log(`Server running on http://${HOST}:${PORT}`);
});
