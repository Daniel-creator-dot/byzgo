import './loadEnv';
import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
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
import {
  ALLOWED_UPLOAD_MIME,
  getStorageConfig,
  isMediaError,
  isSupabaseStorageConfigured,
  parseUploadFolder,
  persistUploadedImage,
  probeStorage,
  normalizeImageRefForDb,
  resolveImageUrlForClient,
  resolveUploadFileName,
  checkUploadRateLimit,
  type PictureFolder,
} from './media';

const FIREBASE_PROJECT_ID = process.env.FIREBASE_PROJECT_ID || 'bytzgo-9bd89';
/** Web OAuth client from Firebase `google-services.json` (type 3). */
const FIREBASE_WEB_CLIENT_ID =
  '645977332644-4gjjf08268b3irafs4bh8b7guct1i1jb.apps.googleusercontent.com';
const GOOGLE_WEB_CLIENT_ID =
  process.env.GOOGLE_WEB_CLIENT_ID?.trim() ||
  process.env.VITE_GOOGLE_CLIENT_ID?.trim() ||
  FIREBASE_WEB_CLIENT_ID;
/** Legacy web client (old Cloud project); keep during env migration. */
const LEGACY_GOOGLE_WEB_CLIENT_ID =
  '568487483843-99c0bucqujokf2h1vtmno1ku0jea7b4f.apps.googleusercontent.com';
const googleOAuthClient = new OAuth2Client();
let firebaseAdminHasCredentials = false;

function googleTokenAudiences(): string[] {
  return [
    ...new Set(
      [GOOGLE_WEB_CLIENT_ID, FIREBASE_WEB_CLIENT_ID, LEGACY_GOOGLE_WEB_CLIENT_ID].filter(Boolean),
    ),
  ];
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

function resolveFirebaseServiceAccountPath(): string | null {
  const fromEnv = process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim();
  if (fromEnv && fs.existsSync(fromEnv)) return fromEnv;
  const candidates = [
    path.join(__dirname, 'firebase-service-account.json'),
    path.join(__dirname, 'bytzgo-9bd89-firebase-adminsdk.json'),
    path.join(__dirname, 'bytzgo-72f1c-firebase-adminsdk-fbsvc-51cd0be35b.json'),
  ];
  for (const p of candidates) {
    if (fs.existsSync(p)) return p;
  }
  try {
    const files = fs.readdirSync(__dirname).filter(
      (f) => f.includes('firebase-adminsdk') && f.endsWith('.json')
    );
    if (files[0]) return path.join(__dirname, files[0]);
  } catch (_) {}
  return null;
}

function loadFirebaseServiceAccount(): Record<string, unknown> | null {
  const inline = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (inline) {
    try {
      return JSON.parse(inline) as Record<string, unknown>;
    } catch (e) {
      console.error('Firebase Admin: FIREBASE_SERVICE_ACCOUNT_JSON is not valid JSON', e);
    }
  }
  const serviceAccountPath = resolveFirebaseServiceAccountPath();
  if (!serviceAccountPath) return null;
  return JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8')) as Record<string, unknown>;
}

try {
  const serviceAccount = loadFirebaseServiceAccount();
  if (serviceAccount) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount as admin.ServiceAccount),
      projectId: (serviceAccount.project_id as string) || FIREBASE_PROJECT_ID,
    });
    firebaseAdminHasCredentials = true;
    console.log(
      `Firebase Admin initialized (project ${(serviceAccount.project_id as string) || FIREBASE_PROJECT_ID}, FCM enabled).`
    );
  } else {
    admin.initializeApp({
      projectId: FIREBASE_PROJECT_ID,
    });
    console.warn(
      'Firebase Admin: no service account — set FIREBASE_SERVICE_ACCOUNT_JSON on Render or add backend/firebase-service-account.json (see docs/FIREBASE_PUSH.md).'
    );
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
// Product photos are stored as data URLs in JSON — need headroom beyond default 100kb.
app.use(express.json({ limit: '12mb' }));
app.use(express.urlencoded({ extended: true, limit: '12mb' }));

app.get('/api/health', async (_req, res) => {
  const storage = getStorageConfig();
  let storageProbe: { ok: boolean; message?: string } = { ok: false, message: 'not configured' };
  if (storage.configured) {
    storageProbe = await probeStorage();
  }
  res.json({
    ok: true,
    service: process.env.RENDER_SERVICE_NAME || 'byzgoback',
    client: 'flutter',
    fcm: firebaseAdminHasCredentials,
    media: {
      storage: storage.configured ? 'supabase' : 'inline_fallback',
      bucket: storage.bucket,
      publicBaseUrl: storage.publicBaseUrl,
      storageOk: storageProbe.ok,
      storageMessage: storageProbe.message,
    },
  });
});

app.get('/', (_req, res) => {
  res.json({
    name: 'BytzGo API',
    client: 'Flutter mobile app (Android/iOS)',
    health: '/api/health',
  });
});



const imageMimeFilter: multer.Options['fileFilter'] = (_req, file, cb) => {
  const mime = (file.mimetype || '').toLowerCase().split(';')[0].trim();
  cb(null, ALLOWED_UPLOAD_MIME.has(mime));
};

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: imageMimeFilter,
});

const riderDocUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 4 * 1024 * 1024 },
  fileFilter: imageMimeFilter,
});

const RIDER_DOC_TYPES = ['license', 'ghana_card', 'photo'] as const;
type RiderDocType = (typeof RIDER_DOC_TYPES)[number];

function isRiderDocType(value: string): value is RiderDocType {
  return (RIDER_DOC_TYPES as readonly string[]).includes(value);
}

const USER_PUBLIC_FIELDS =
  'id, name, email, role, balance, phone, cover_image, avatar_url, address, lat, lng, region, status, is_online, shop_category';

/** Minimal JWT — large payloads (e.g. base64 in token) trigger HTTP 431 on Render/nginx. */
function signAuthToken(user: { id: string | number; role?: string }): string {
  return jwt.sign(
    { id: user.id, role: user.role },
    process.env.JWT_SECRET as string,
    { expiresIn: '30d' }
  );
}

/** Resolve stored image refs to loadable URLs for clients (Supabase CDN, data URLs, or legacy object keys). */
async function userForAuthResponse(row: Record<string, unknown> | null | undefined) {
  if (!row) return row;
  const u = { ...row } as Record<string, unknown>;
  delete u.password;
  if (typeof u.avatar_url === 'string' && u.avatar_url.trim()) {
    u.avatar_url = await resolveImageUrlForClient(u.avatar_url);
    if (u.avatar_url) u.has_avatar = true;
  }
  if (typeof u.cover_image === 'string' && u.cover_image.trim()) {
    u.cover_image = await resolveImageUrlForClient(u.cover_image);
    if (u.cover_image) u.has_cover_image = true;
  }
  return u;
}

const SHOP_CATEGORIES = ['pharmacy', 'food', 'restaurant', 'fashion', 'groceries'] as const;
const SHOP_OPEN_STATUSES = ['open', 'busy', 'closed'] as const;
type ShopOpenStatus = (typeof SHOP_OPEN_STATUSES)[number];

function normalizeShopOpenStatus(value: unknown): ShopOpenStatus | null {
  if (value == null || value === '') return null;
  const s = String(value).trim().toLowerCase();
  if ((SHOP_OPEN_STATUSES as readonly string[]).includes(s)) return s as ShopOpenStatus;
  return null;
}

const SHOP_STORY_TTL_HOURS = 24;

function shopStoryIsActive(row: Record<string, unknown>): boolean {
  const raw = row.shop_story_image;
  if (!raw || !String(raw).trim()) return false;
  const exp = row.shop_story_expires_at;
  if (!exp) return true;
  return new Date(String(exp)).getTime() > Date.now();
}

async function vendorPromoPayload(row: Record<string, unknown>) {
  const storyResolved = await resolveImageUrlForClient(
    typeof row.shop_story_image === 'string' ? row.shop_story_image : null
  );
  const active = Boolean(storyResolved && shopStoryIsActive(row));
  return {
    vendorId: row.id,
    id: row.id,
    name: row.name,
    shop_category: row.shop_category,
    shop_open_status: row.shop_open_status ?? 'open',
    shop_status_message: row.shop_status_message ?? null,
    shop_discount_label: row.shop_discount_label ?? null,
    shop_discount_percent:
      row.shop_discount_percent != null ? Number(row.shop_discount_percent) : null,
    shop_promo_updated_at: row.shop_promo_updated_at ?? null,
    shop_story_image: active ? storyResolved : null,
    shop_story_posted_at: row.shop_story_posted_at ?? null,
    shop_story_expires_at: row.shop_story_expires_at ?? null,
    has_active_story: active,
  };
}

async function emitVendorPromo(row: Record<string, unknown>) {
  io.emit('vendor:promo', await vendorPromoPayload(row));
}

async function vendorRowForClient(row: Record<string, unknown>) {
  const cover = await resolveImageUrlForClient(
    typeof row.cover_image === 'string' ? row.cover_image : null
  );
  const promo = await vendorPromoPayload(row);
  return {
    ...row,
    cover_image: cover,
    ...promo,
  };
}

const PRIMECARE_CANONICAL_EMAIL = 'vendor@bytzgo.net';

function isPrimeCareVendorRow(row: { name?: string; email?: string }): boolean {
  const n = String(row.name || '').toLowerCase().replace(/\s+/g, '');
  if (n.includes('primecare')) return true;
  return String(row.email || '').toLowerCase() === PRIMECARE_CANONICAL_EMAIL;
}

/** One Primecare Pharmacy in shop lists (DB may have duplicate vendor rows from re-seeding). */
function dedupeVendorList<T extends { id: string; name?: string; email?: string }>(rows: T[]): T[] {
  const primecare = rows.filter(isPrimeCareVendorRow);
  const rest = rows.filter((r) => !isPrimeCareVendorRow(r));
  if (primecare.length <= 1) return rows;
  const keeper =
    primecare.find((r) => String(r.email || '').toLowerCase() === PRIMECARE_CANONICAL_EMAIL) ||
    primecare[0];
  return [...rest, keeper];
}

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL?.includes('supabase.com') ? { rejectUnauthorized: false } : false
});

async function fetchRiderDocuments(userId: string, options?: { adminReview?: boolean }) {
  const result = await pool.query(
    `SELECT doc_type, image_url, mime_type, review_status, rejection_reason, uploaded_at, reviewed_at
     FROM rider_documents WHERE user_id = $1 ORDER BY doc_type`,
    [userId]
  );
  const rows = result.rows as Array<Record<string, unknown>>;
  return Promise.all(
    rows.map(async (row) => ({
      ...row,
      image_url: await resolveImageUrlForClient(String(row.image_url ?? ''), {
        adminReview: options?.adminReview,
      }),
    }))
  );
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

async function setSetting(key: string, value: string) {
  await pool.query(
    `INSERT INTO system_settings (key, value) VALUES ($1, $2)
     ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value`,
    [key, String(value)]
  );
}

/** One active zone per region — removes duplicate rows that break pricing. */
async function reconcileDeliveryZones() {
  try {
    const dupes = await pool.query(`
      DELETE FROM delivery_zones z
      USING delivery_zones keep
      WHERE z.region = keep.region
        AND z.is_active = true
        AND keep.is_active = true
        AND z.created_at > keep.created_at
      RETURNING z.id, z.region
    `);
    if (dupes.rowCount && dupes.rowCount > 0) {
      console.log(`[zones] Removed ${dupes.rowCount} duplicate active delivery zone(s)`);
    }
  } catch (err) {
    console.warn('[zones] reconcileDeliveryZones failed:', err);
  }
}

/** Ghana (GMT) — no DST */
function ghanaMinutesNow(): number {
  const now = new Date();
  return now.getUTCHours() * 60 + now.getUTCMinutes();
}

function parseTimeToMinutes(t: string): number | null {
  const m = /^(\d{1,2}):(\d{2})$/.exec(String(t).trim());
  if (!m) return null;
  const h = Number(m[1]);
  const min = Number(m[2]);
  if (h < 0 || h > 23 || min < 0 || min > 59) return null;
  return h * 60 + min;
}

function isMinutesInWindow(now: number, start: number, end: number): boolean {
  if (start === end) return false;
  if (start < end) return now >= start && now < end;
  return now >= start || now < end;
}

async function buildPublicPricingPayload() {
  const raw = await getSetting('delivery_price_per_km');
  const baseRate = Math.max(0.01, parseFloat(raw || '4') || 4);
  const surge = await getSurgePricingState();
  const pricePerKm = surge.surge_active
    ? Math.round(baseRate * surge.multiplier * 100) / 100
    : baseRate;
  return {
    price_per_km: pricePerKm,
    base_price_per_km: baseRate,
    surge_enabled: surge.enabled,
    surge_multiplier: surge.multiplier,
    surge_start_time: surge.start_time,
    surge_end_time: surge.end_time,
    surge_active: surge.surge_active,
    ghana_time: surge.ghana_time,
  };
}

function broadcastPricingUpdated() {
  void buildPublicPricingPayload()
    .then((payload) => {
      io.emit('pricing:updated', payload);
    })
    .catch((err) => console.error('broadcastPricingUpdated failed:', err));
}

async function getSurgePricingState() {
  const enabled = (await getSetting('surge_enabled')) === 'true';
  const multiplier = Math.max(
    1,
    parseFloat((await getSetting('surge_multiplier')) || '1.25') || 1.25
  );
  const startStr = (await getSetting('surge_start_time')) || '17:00';
  const endStr = (await getSetting('surge_end_time')) || '21:00';
  const start = parseTimeToMinutes(startStr) ?? 17 * 60;
  const end = parseTimeToMinutes(endStr) ?? 21 * 60;
  const now = ghanaMinutesNow();
  const surge_active = enabled && isMinutesInWindow(now, start, end);
  return {
    enabled,
    multiplier,
    start_time: startStr,
    end_time: endStr,
    surge_active,
    ghana_time: `${String(Math.floor(now / 60)).padStart(2, '0')}:${String(now % 60).padStart(2, '0')}`,
  };
}

async function applySurgeToFee(baseFee: number) {
  const surge = await getSurgePricingState();
  if (!surge.surge_active) {
    return { fee: Math.round(baseFee * 100) / 100, surge };
  }
  return {
    fee: Math.round(baseFee * surge.multiplier * 100) / 100,
    surge,
  };
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
): Promise<{
  distance_km: number;
  delivery_fee: number;
  price_per_km: number;
  zone: string | null;
  base_delivery_fee: number;
  surge_active: boolean;
  surge_multiplier: number;
}> {
  const distance_km = haversineDistanceKm(pickupLat, pickupLng, destLat, destLng);
  const globalRate = Math.max(0.01, parseFloat((await getSetting('delivery_price_per_km')) || '4') || 4);

  let zone: any = null;
  if (destinationRegion) {
    const result = await pool.query(
      'SELECT * FROM delivery_zones WHERE region = $1 AND is_active = true ORDER BY created_at ASC LIMIT 1',
      [destinationRegion]
    );
    zone = result.rows[0];
  }
  if (!zone && pickupRegion) {
    const result = await pool.query(
      'SELECT * FROM delivery_zones WHERE region = $1 AND is_active = true ORDER BY created_at ASC LIMIT 1',
      [pickupRegion]
    );
    zone = result.rows[0];
  }

  if (!zone) {
    const base = Math.round(distance_km * globalRate * 100) / 100;
    const { fee, surge } = await applySurgeToFee(base);
    const effectiveRate = surge.surge_active
      ? Math.round(globalRate * surge.multiplier * 100) / 100
      : globalRate;
    return {
      distance_km,
      delivery_fee: fee,
      price_per_km: effectiveRate,
      zone: null,
      base_delivery_fee: base,
      fee_from_distance_km: base,
      zone_min_price: null,
      zone_max_price: null,
      surge_active: surge.surge_active,
      surge_multiplier: surge.multiplier,
    };
  }

  // Admin "price per km" is global; zones only apply min/max caps (same as web/mobile UI).
  let base = distance_km * globalRate;
  const zoneMin = Number(zone.min_price);
  if (Number.isFinite(zoneMin) && zoneMin > 0) {
    base = Math.max(base, zoneMin);
  }
  if (zone.max_price) base = Math.min(base, Number(zone.max_price));
  base = Math.round(base * 100) / 100;
  const { fee, surge } = await applySurgeToFee(base);
  const effectiveRate = surge.surge_active
    ? Math.round(globalRate * surge.multiplier * 100) / 100
    : globalRate;
  const feeFromDistance = Math.round(distance_km * globalRate * 100) / 100;
  return {
    distance_km,
    delivery_fee: fee,
    price_per_km: effectiveRate,
    zone: zone.name,
    base_delivery_fee: base,
    fee_from_distance_km: feeFromDistance,
    zone_min_price: Number.isFinite(zoneMin) ? zoneMin : null,
    zone_max_price: zone.max_price != null ? Number(zone.max_price) : null,
    surge_active: surge.surge_active,
    surge_multiplier: surge.multiplier,
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
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_category TEXT DEFAULT 'food';
        ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar_url TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_open_status TEXT DEFAULT 'open';
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_status_message TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_discount_label TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_discount_percent DECIMAL(5,2);
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_promo_updated_at TIMESTAMP WITH TIME ZONE;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_story_image TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_story_posted_at TIMESTAMP WITH TIME ZONE;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS shop_story_expires_at TIMESTAMP WITH TIME ZONE;
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
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS pulse_guide_lat DOUBLE PRECISION;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS pulse_guide_lng DOUBLE PRECISION;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS pulse_guide_at TIMESTAMP WITH TIME ZONE;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS pulse_guide_phase TEXT;
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

      CREATE TABLE IF NOT EXISTS support_tickets (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        display_id TEXT NOT NULL UNIQUE,
        created_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        created_by_role TEXT NOT NULL CHECK (created_by_role IN ('customer', 'vendor', 'rider', 'admin')),
        category TEXT NOT NULL CHECK (category IN ('order', 'payment', 'account', 'delivery', 'shop', 'other')),
        subject TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'pending', 'resolved', 'closed')),
        related_order_id UUID REFERENCES orders(id) ON DELETE SET NULL,
        assigned_admin_id UUID REFERENCES users(id) ON DELETE SET NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_support_tickets_created_by
        ON support_tickets(created_by, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_support_tickets_status
        ON support_tickets(status, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_support_tickets_assigned
        ON support_tickets(assigned_admin_id, updated_at DESC);

      CREATE TABLE IF NOT EXISTS support_messages (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
        sender_id UUID NOT NULL REFERENCES users(id),
        body TEXT NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_support_messages_ticket_id
        ON support_messages(ticket_id, created_at);

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
      INSERT INTO system_settings (key, value) VALUES ('surge_enabled', 'false')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('surge_multiplier', '1.5')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('surge_start_time', '17:00')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('surge_end_time', '21:00')
      ON CONFLICT (key) DO NOTHING;
    `);
    // Fix existing courier orders that were mislabeled as food
    await pool.query(`
      UPDATE orders 
      SET order_type = 'courier' 
      WHERE order_type = 'food' 
      AND items::text LIKE '%courier-1%'
    `);
    await reconcileDeliveryZones();
    console.log('Database initialized successfully');
    const mediaCfg = getStorageConfig();
    if (mediaCfg.configured) {
      const probe = await probeStorage();
      if (probe.ok) {
        console.log(`[media] Supabase bucket "${mediaCfg.bucket}" ready (WebP/JPEG pipeline, CDN URLs)`);
      } else {
        console.warn(`[media] Storage misconfigured: ${probe.message}`);
      }
    } else {
      console.warn(
        '[media] SUPABASE_SERVICE_ROLE_KEY not set — using inline base64 fallback (run backend/supabase-storage.sql)'
      );
    }
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
  if (order?.rider_id) return false;
  if (order?.status === 'ready') return true;
  // Marketplace shop orders (seeded vendors) start ready; legacy food may be pending until vendor marks ready.
  if (
    order?.status === 'pending' &&
    order?.vendor_id &&
    (order?.order_type === 'food' || order?.order_type === 'courier')
  ) {
    return true;
  }
  return false;
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

const SUPPORT_CATEGORIES = new Set(['order', 'payment', 'account', 'delivery', 'shop', 'other']);
const SUPPORT_STATUSES = new Set(['open', 'pending', 'resolved', 'closed']);

function generateSupportDisplayId(): string {
  return `SUP-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
}

function formatSupportMessage(row: any, viewerId: string) {
  return {
    id: row.id,
    ticketId: row.ticket_id,
    senderId: row.sender_id,
    senderName: row.sender_name || 'User',
    senderRole: row.sender_role || null,
    body: row.body,
    createdAt: row.created_at,
    isMine: row.sender_id === viewerId,
  };
}

function formatSupportTicket(row: any) {
  return {
    id: row.id,
    displayId: row.display_id,
    category: row.category,
    subject: row.subject,
    status: row.status,
    createdBy: row.created_by,
    createdByRole: row.created_by_role,
    creatorName: row.creator_name || null,
    creatorEmail: row.creator_email || null,
    relatedOrderId: row.related_order_id || null,
    assignedAdminId: row.assigned_admin_id || null,
    assignedAdminName: row.assigned_admin_name || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    lastMessageAt: row.last_message_at || row.updated_at,
    lastMessagePreview: row.last_message_preview || null,
    messageCount: row.message_count != null ? Number(row.message_count) : undefined,
  };
}

async function fetchSupportTicketRow(ticketId: string) {
  const result = await pool.query(
    `SELECT t.*,
            u.name AS creator_name,
            u.email AS creator_email,
            a.name AS assigned_admin_name,
            (SELECT MAX(m.created_at) FROM support_messages m WHERE m.ticket_id = t.id) AS last_message_at,
            (SELECT m.body FROM support_messages m WHERE m.ticket_id = t.id ORDER BY m.created_at DESC LIMIT 1) AS last_message_preview,
            (SELECT COUNT(*)::int FROM support_messages m WHERE m.ticket_id = t.id) AS message_count
     FROM support_tickets t
     JOIN users u ON u.id = t.created_by
     LEFT JOIN users a ON a.id = t.assigned_admin_id
     WHERE t.id = $1`,
    [ticketId]
  );
  return result.rows[0] || null;
}

async function assertSupportTicketAccess(ticketId: string, userId: string, role: string) {
  const row = await fetchSupportTicketRow(ticketId);
  if (!row) {
    const err: any = new Error('Ticket not found');
    err.status = 404;
    throw err;
  }
  if (role === 'admin') return row;
  if (row.created_by !== userId) {
    const err: any = new Error('Unauthorized');
    err.status = 403;
    throw err;
  }
  return row;
}

async function emitSupportMessage(ticket: any, messageRow: any, senderId: string) {
  const nameRes = await pool.query(
    'SELECT name, role FROM users WHERE id = $1',
    [senderId]
  );
  messageRow.sender_name = nameRes.rows[0]?.name;
  messageRow.sender_role = nameRes.rows[0]?.role;

  const notifyIds = new Set<string>();
  if (ticket.created_by) notifyIds.add(String(ticket.created_by));
  if (ticket.assigned_admin_id) notifyIds.add(String(ticket.assigned_admin_id));
  notifyIds.delete(String(senderId));

  for (const uid of notifyIds) {
    io.to(uid).emit('ticket:message', {
      ticketId: ticket.id,
      message: formatSupportMessage(messageRow, uid),
    });
  }

  if (notifyIds.size > 0) {
    const senderName = nameRes.rows[0]?.name || 'Support';
    const body = String(messageRow.body || '');
    void sendPushToUserIds([...notifyIds], {
      title: `Support · ${ticket.display_id}`,
      body: `${senderName}: ${body.length > 120 ? `${body.slice(0, 117)}…` : body}`,
      type: 'support-message',
      ticketId: ticket.id,
      channelId: 'support_updates',
      highPriority: true,
    });
  }
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

async function sanitizeOrderForRole(order: any, role: string, userId: string) {
  if (!order) return order;
  const o = { ...order };
  const isBooker = o.customer_id === userId;
  const canSeeDeliveryCode = isBooker && (role === 'customer' || role === 'vendor');
  if (!canSeeDeliveryCode) {
    delete o.delivery_code;
  }
  if (o.customer_name) o.customerName = o.customer_name;
  if (o.rider_name) o.riderName = o.rider_name;
  if (o.vendor_name) o.vendorName = o.vendor_name;

  if (tripAllowsContact(o)) {
    if (isBooker && (role === 'customer' || role === 'vendor') && o.rider_phone) {
      o.riderPhone = o.rider_phone;
    }
    if (role === 'rider' && o.rider_id === userId && o.customer_phone) {
      o.customerPhone = o.customer_phone;
    }
  }

  if (role === 'rider' && o.rider_id === userId) {
    if (o.customer_avatar_url) {
      o.customerAvatarUrl = await resolveImageUrlForClient(o.customer_avatar_url);
    }
    if (o.customer_avg_rating != null) {
      o.customerAvgRating = parseFloat(String(o.customer_avg_rating));
    }
  }
  if (isBooker && (role === 'customer' || role === 'vendor') && o.rider_avatar_url) {
    o.riderAvatarUrl = await resolveImageUrlForClient(o.rider_avatar_url);
  }

  delete o.customer_phone;
  delete o.rider_phone;
  delete o.customer_name;
  delete o.rider_name;
  delete o.customer_avatar_url;
  delete o.customer_avg_rating;
  delete o.rider_avatar_url;
  attachPulseGuideFields(o);
  delete o.pulse_guide_lat;
  delete o.pulse_guide_lng;
  delete o.pulse_guide_at;
  delete o.pulse_guide_phase;
  return o;
}

const ORDER_CONTACT_JOINS = `
  LEFT JOIN users cu ON cu.id = o.customer_id
  LEFT JOIN users ru ON ru.id = o.rider_id
  LEFT JOIN users vu ON vu.id = o.vendor_id`;
const ORDER_CONTACT_SELECT = `
  cu.name AS customer_name, cu.phone AS customer_phone,
  cu.avatar_url AS customer_avatar_url,
  (SELECT ROUND(AVG(o2.rating)::numeric, 1) FROM orders o2
   WHERE o2.customer_id = cu.id AND o2.rating IS NOT NULL AND o2.rating > 0) AS customer_avg_rating,
  ru.name AS rider_name, ru.phone AS rider_phone,
  ru.avatar_url AS rider_avatar_url,
  vu.name AS vendor_name`;

function isCustomerPaymentReady(order: any): boolean {
  if (order.payment_status === 'paid') return true;
  const ack = String(order.customer_payment_ack || '').toLowerCase();
  return ack === 'cash' || ack === 'wallet' || ack === 'paystack';
}

const PULSE_GUIDE_TTL_MS = 8 * 60 * 1000;

function pulseGuidePhaseForStatus(status: string): 'pickup' | 'dropoff' | null {
  if (['picked_up', 'arrived'].includes(status)) return 'dropoff';
  if (['pending', 'ready', 'preparing'].includes(status)) return 'pickup';
  return null;
}

function isPulseGuideActive(row: any): boolean {
  if (row?.pulse_guide_lat == null || row?.pulse_guide_lng == null || !row?.pulse_guide_at) {
    return false;
  }
  const at = new Date(row.pulse_guide_at).getTime();
  return Number.isFinite(at) && Date.now() - at < PULSE_GUIDE_TTL_MS;
}

function attachPulseGuideFields(o: any) {
  if (!o) return o;
  if (o.pulse_guide_lat != null && o.pulse_guide_lng != null) {
    o.pulseGuideLat = parseFloat(String(o.pulse_guide_lat));
    o.pulseGuideLng = parseFloat(String(o.pulse_guide_lng));
    o.pulseGuideAt = o.pulse_guide_at;
    o.pulseGuidePhase = o.pulse_guide_phase;
    o.pulseGuideActive = isPulseGuideActive(o);
  }
  return o;
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
      await sanitizeOrderForRole(full, 'customer', full.customer_id)
    );
  }
  if (full.rider_id) {
    io.to(full.rider_id).emit(
      'order:updated',
      await sanitizeOrderForRole(full, 'rider', full.rider_id)
    );
  }
  if (full.vendor_id) {
    io.to(full.vendor_id).emit(
      'order:updated',
      await sanitizeOrderForRole(full, 'vendor', full.vendor_id)
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

const OFFER_TTL_SEC = 25;
/** Bolt-style: ping one nearest rider at a time. */
const RIDERS_PER_WAVE = 1;
/** Max sequential offers before giving up (each step = next nearest rider). */
const MAX_DISPATCH_WAVES = 15;
const LOCATION_MAX_AGE_MIN = 15;
/** Expanding pickup radius (km) as dispatch steps progress. */
const DISPATCH_RADIUS_KM_TIERS = [4, 8, 15] as const;
const NEARBY_RIDERS_MAX_KM = 6;

function dispatchRadiusKm(wave: number): number {
  if (wave <= 5) return DISPATCH_RADIUS_KM_TIERS[0];
  if (wave <= 10) return DISPATCH_RADIUS_KM_TIERS[1];
  return DISPATCH_RADIUS_KM_TIERS[2];
}

type NearbyRider = { id: string; distanceKm: number };

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
  maxRadiusKm: number,
  useRegionFilter: boolean
): Promise<NearbyRider[]> {
  const norm = normalizeRegion(region);
  const regionClause = useRegionFilter && norm
    ? `AND (u.region IS NULL OR TRIM(u.region) = '' OR LOWER(TRIM(u.region)) = $7)`
    : '';
  const params: unknown[] = [
    pickup.lat,
    pickup.lng,
    excludeRiderIds.length ? excludeRiderIds : [],
    limit,
    LOCATION_MAX_AGE_MIN,
    maxRadiusKm,
  ];
  if (useRegionFilter && norm) params.push(norm);

  const result = await pool.query(
    `SELECT id, distance_km FROM (
      SELECT u.id,
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
       AND NOT EXISTS (
         SELECT 1 FROM orders busy
         WHERE busy.rider_id = u.id
         AND busy.status IN ('ready', 'picked_up', 'arrived')
       )
       ${regionClause}
     ) ranked
     WHERE distance_km <= $6
     ORDER BY distance_km ASC
     LIMIT $4`,
    params
  );
  return result.rows.map((row: { id: string; distance_km: string }) => ({
    id: row.id,
    distanceKm: parseFloat(row.distance_km),
  }));
}

async function getNearestActiveRiders(
  pickup: { lat: number; lng: number },
  region: string | null,
  excludeRiderIds: string[],
  limit: number,
  maxRadiusKm: number = DISPATCH_RADIUS_KM_TIERS[0]
): Promise<NearbyRider[]> {
  let riders = await queryNearestActiveRiders(
    pickup,
    region,
    excludeRiderIds,
    limit,
    maxRadiusKm,
    true
  );
  if (riders.length === 0 && normalizeRegion(region)) {
    riders = await queryNearestActiveRiders(
      pickup,
      region,
      excludeRiderIds,
      limit,
      maxRadiusKm,
      false
    );
  }
  return riders;
}

async function emitOffersToRiders(order: any, candidates: NearbyRider[], wave: number) {
  const eligibleIds = await filterIncomingRideRecipientIds(
    candidates.map((c) => c.id),
    order?.customer_id ?? null
  );
  const eligible = candidates.filter((c) => eligibleIds.includes(c.id));
  if (!eligible.length) return 0;

  const expiresAt = new Date(Date.now() + OFFER_TTL_SEC * 1000);
  const orderPayload = { ...order };

  for (const { id: riderId, distanceKm } of eligible) {
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
    const dist =
      Number.isFinite(distanceKm) && distanceKm >= 0
        ? Math.round(distanceKm * 10) / 10
        : null;
    const payload = {
      ...orderPayload,
      expiresAt: expiresAt.toISOString(),
      dispatchWave: wave,
      offerDistanceKm: dist,
      pickupDistanceKm: dist,
    };
    io.to(String(riderId)).emit('ride:incoming', payload);
  }

  const next = eligible[0];
  console.info(
    `[dispatch] order ${order.id} step ${wave}: offered to ${next.id.slice(0, 8)}… (${next.distanceKm.toFixed(1)} km)`,
  );

  await sendPushToRiders(order, eligible);
  await pool.query(
    `UPDATE orders SET dispatch_wave = $1, offer_expires_at = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3`,
    [wave, expiresAt, order.id]
  );

  clearDispatchTimer(order.id);
  const timer = setTimeout(() => {
    void handleWaveExpired(order.id, wave);
  }, OFFER_TTL_SEC * 1000 + 500);
  dispatchWaveTimers.set(order.id, timer);
  return eligible.length;
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
  const radiusKm = dispatchRadiusKm(wave);

  let candidates: NearbyRider[] = [];

  if (pickup) {
    candidates = await getNearestActiveRiders(
      pickup,
      order.region,
      exclude,
      RIDERS_PER_WAVE,
      radiusKm
    );
  } else {
    const fallback = (await getActiveRiderIds(order.region)).filter(
      (id) => !exclude.includes(id)
    );
    candidates = fallback
      .slice(0, RIDERS_PER_WAVE)
      .map((id) => ({ id, distanceKm: 0 }));
  }

  if (candidates.length === 0) {
    if (wave < MAX_DISPATCH_WAVES) {
      console.warn(
        `[dispatch] order ${order.id} step ${wave}: no riders within ${radiusKm}km — widening search`
      );
      await advanceDispatchWave(order, wave + 1);
    } else {
      console.warn(
        `[dispatch] order ${order.id}: no nearby riders accepted after ${MAX_DISPATCH_WAVES} attempts`
      );
    }
    return;
  }

  await emitOffersToRiders(order, candidates, wave);
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
    // Sequential Bolt flow: try next nearest rider after decline.
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

/** Customer cancelled before a rider accepted — dismiss incoming UI for offered riders. */
async function notifyRideCancelled(orderId: string) {
  clearDispatchTimer(orderId);
  const offers = await pool.query(
    `SELECT DISTINCT rider_id FROM order_dispatch_offers WHERE order_id = $1`,
    [orderId]
  );
  for (const row of offers.rows) {
    if (row.rider_id) {
      io.to(row.rider_id).emit('ride:taken', { orderId, reason: 'cancelled' });
    }
  }
}

type PushAlert = {
  title: string;
  body: string;
  type: string;
  orderId?: string;
  ticketId?: string;
  channelId?: 'incoming_rides_alarm' | 'trip_updates' | 'support_updates';
  highPriority?: boolean;
};

/** Only active riders receive incoming-job pushes; never the ordering customer. */
async function filterIncomingRideRecipientIds(
  userIds: string[],
  excludeCustomerId?: string | null
): Promise<string[]> {
  const unique = [...new Set(userIds.filter(Boolean))];
  if (!unique.length) return [];
  const res = await pool.query(
    `SELECT id FROM users
     WHERE id = ANY($1::uuid[]) AND role = 'rider' AND status = 'active' AND is_online = true`,
    [unique]
  );
  let ids = res.rows.map((r: { id: string }) => r.id);
  if (excludeCustomerId) {
    ids = ids.filter((id) => id !== excludeCustomerId);
  }
  return ids;
}

async function sendPushToUserIds(userIds: string[], alert: PushAlert) {
  let ids = [...new Set(userIds.filter(Boolean))];
  if (!ids.length) return;
  if (alert.type === 'incoming-ride') {
    ids = await filterIncomingRideRecipientIds(ids);
    if (!ids.length) return;
  }

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

    const incomingRide = high && alert.type === 'incoming-ride';
    await admin.messaging().sendEachForMulticast({
      tokens,
      // Incoming jobs: data-only on Android so Flutter shows one local alarm (no system + local duplicate).
      ...(incomingRide
        ? {}
        : {
            notification: {
              title: alert.title,
              body: alert.body,
            },
          }),
      data: {
        type: alert.type,
        orderId: String(alert.orderId ?? ''),
        title: alert.title,
        body: alert.body,
        ...(incomingRide ? { audience: 'rider' } : {}),
      },
      android: {
        priority: high ? 'high' : 'normal',
        ttl: high ? 30 * 1000 : 3600 * 1000,
        ...(incomingRide
          ? {}
          : {
              notification: {
                channelId,
                sound: 'default',
                priority: high ? ('max' as const) : ('default' as const),
                visibility: 'public',
                defaultVibrateTimings: true,
                ...(high && alert.orderId ? { tag: `ride-${alert.orderId}` } : {}),
              },
            }),
      },
      apns: {
        headers: {
          'apns-priority': high ? '10' : '5',
          'apns-push-type': 'alert',
        },
        payload: {
          aps: {
            alert: { title: alert.title, body: alert.body },
            sound: 'default',
            contentAvailable: true,
          },
        },
      },
    });
  } catch (err) {
    console.warn('[push] FCM send failed:', err);
  }
}

async function sendPushToRiders(order: any, riders: NearbyRider[]) {
  const eligibleIds = await filterIncomingRideRecipientIds(
    riders.map((r) => r.id),
    order?.customer_id ?? null
  );
  const eligible = riders.filter((r) => eligibleIds.includes(r.id));
  if (!eligible.length) return;
  const pickup = order.pickup_address || order.pickup || 'Pickup';
  const dropoff = order.address || 'Drop-off';
  for (const { id, distanceKm } of eligible) {
    const distLabel =
      Number.isFinite(distanceKm) && distanceKm > 0 && distanceKm < 500
        ? `${distanceKm.toFixed(1)} km to pickup · `
        : '';
    await sendPushToUserIds([id], {
      title: 'New delivery job',
      body: `${distLabel}${pickup} → ${dropoff}`,
      type: 'incoming-ride',
      orderId: order.id,
      channelId: 'incoming_rides_alarm',
      highPriority: true,
    });
  }
}

function shopLabelForOrder(order: any): string {
  const name = String(order.vendor_name || order.vendorName || '').trim();
  if (name) return name;
  const pickup = String(order.pickup_address || order.pickup || '').trim();
  if (pickup) return pickup.length > 48 ? `${pickup.slice(0, 45)}…` : pickup;
  return 'the shop';
}

function isShopCourierOrder(order: any): boolean {
  return Boolean(order?.vendor_id);
}

async function notifyCustomerTripPush(order: any) {
  if (!order?.customer_id) return;
  const status = String(order.status || '');
  const shopTrip = isShopCourierOrder(order);
  const shopLabel = shopTrip ? shopLabelForOrder(order) : '';
  let title = 'BytzGO';
  let body = '';
  if (order.rider_id && ['pending', 'ready', 'preparing'].includes(status)) {
    if (shopTrip) {
      title = 'Rider heading to shop';
      body = `Your rider is going to ${shopLabel} to pick up your order`;
    } else {
      title = 'Biker on the way';
      body = 'Your biker is heading to the pickup point';
    }
  } else if (status === 'picked_up') {
    if (shopTrip) {
      title = 'Picked up from shop';
      body = `Collected at ${shopLabel} — on the way to you`;
    } else {
      title = 'On the way';
      body = 'Your biker is heading to your delivery address';
    }
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
  if (token.length > 2048) {
    return res.status(431).json({
      message: 'Session token is too large. Sign out and sign in again to refresh your session.',
    });
  }

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
    const token = signAuthToken(user);
    res.json({ user: await userForAuthResponse(user), token });
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
      const token = signAuthToken(userWithoutPassword);
      res.json({ user: await userForAuthResponse(userWithoutPassword), token });
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
    
    const token = signAuthToken(user);
    res.json({ user: await userForAuthResponse(user), token });
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

    const token = signAuthToken(user);
    res.json({ user: await userForAuthResponse(user), token });
  } catch (err: any) {
    console.error('Supabase auth error:', err.response?.data || err.message);
    res.status(500).json({ message: 'Supabase authentication failed' });
  }
});

/** Google Play: account deletion (in-app + https://www.bytzgo.net/account-deletion). */
app.delete('/api/auth/account', authenticateToken, async (req: any, res) => {
  const userId = req.user.id as string;
  const client = await pool.connect();
  try {
    const userRes = await client.query(
      `SELECT id, name, email, role FROM users WHERE id = $1`,
      [userId]
    );
    const row = userRes.rows[0];
    if (!row) return res.status(404).json({ message: 'Account not found' });
    if (row.role === 'admin') {
      return res.status(403).json({ message: 'Admin accounts cannot be self-deleted. Contact support.' });
    }

    const activeRes = await client.query(
      `SELECT COUNT(*)::int AS n FROM orders
       WHERE status NOT IN ('delivered', 'cancelled')
         AND (customer_id = $1 OR rider_id = $1 OR vendor_id = $1)`,
      [userId]
    );
    const activeOrders = activeRes.rows[0]?.n ?? 0;
    if (activeOrders > 0) {
      return res.status(409).json({
        message: `Cannot delete: ${activeOrders} active order(s). Finish or cancel them first.`,
        active_orders: activeOrders,
      });
    }

    await client.query('BEGIN');
    if (row.role === 'vendor') {
      await client.query('DELETE FROM products WHERE vendor_id = $1', [userId]);
      await client.query('UPDATE orders SET vendor_id = NULL WHERE vendor_id = $1', [userId]);
    }
    if (row.role === 'rider') {
      await client.query('DELETE FROM rider_locations WHERE rider_id = $1', [userId]);
      await client.query('UPDATE orders SET rider_id = NULL WHERE rider_id = $1', [userId]);
    }
    if (row.role === 'customer') {
      await client.query('UPDATE orders SET customer_id = NULL WHERE customer_id = $1', [userId]);
    }
    await client.query('DELETE FROM order_messages WHERE sender_id = $1', [userId]);
    await client.query('DELETE FROM support_messages WHERE sender_id = $1', [userId]);
    await client.query('DELETE FROM support_tickets WHERE created_by = $1', [userId]);
    await client.query('DELETE FROM order_dispatch_offers WHERE rider_id = $1', [userId]);
    await client.query('DELETE FROM wallet_transactions WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM fcm_tokens WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM push_subscriptions WHERE user_id = $1', [userId]);
    await client.query('DELETE FROM users WHERE id = $1', [userId]);
    await client.query('COMMIT');

    io.to(String(userId)).emit('status:updated', { status: 'deleted' });
    res.json({ success: true, message: 'Account deleted' });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Account deletion error:', err);
    res.status(500).json({ message: 'Failed to delete account' });
  } finally {
    client.release();
  }
});

// Refresh session (slim JWT + profile without re-login)
app.get('/api/auth/me', authenticateToken, async (req: any, res) => {
  try {
    const result = await pool.query(`SELECT ${USER_PUBLIC_FIELDS} FROM users WHERE id = $1`, [
      req.user.id,
    ]);
    const row = result.rows[0];
    if (!row) return res.status(404).json({ message: 'User not found' });
    const user = await userForAuthResponse(row);
    const token = signAuthToken(row);
    res.json({ user, token });
  } catch (err) {
    console.error('Auth me error:', err);
    res.status(500).json({ message: 'Failed to load profile' });
  }
});

// Profile Update
app.patch('/api/auth/profile', authenticateToken, async (req: any, res) => {
  const { email, phone, cover_image, avatar_url, address, lat, lng, region, shop_category } = req.body;
  const dbCover = normalizeImageRefForDb(cover_image);
  const dbAvatar = normalizeImageRefForDb(avatar_url);
  let normalizedCategory: string | null = null;
  if (shop_category != null && String(shop_category).trim()) {
    const c = String(shop_category).trim().toLowerCase();
    if (!(SHOP_CATEGORIES as readonly string[]).includes(c)) {
      return res.status(400).json({
        message: `shop_category must be one of: ${SHOP_CATEGORIES.join(', ')}`,
      });
    }
    normalizedCategory = c;
  }
  try {
    const result = await pool.query(
      `UPDATE users SET 
        email = COALESCE($1, email), 
        phone = COALESCE($2, phone),
        cover_image = COALESCE($3, cover_image),
        avatar_url = COALESCE($4, avatar_url),
        address = COALESCE($5, address),
        lat = COALESCE($6, lat),
        lng = COALESCE($7, lng),
        region = COALESCE($8, region),
        shop_category = COALESCE($9, shop_category)
       WHERE id = $10 
       RETURNING ${USER_PUBLIC_FIELDS}`,
      [
        email,
        phone,
        dbCover === undefined ? cover_image : dbCover,
        dbAvatar === undefined ? avatar_url : dbAvatar,
        address,
        lat,
        lng,
        region,
        normalizedCategory,
        req.user.id,
      ]
    );
    const user = await userForAuthResponse(result.rows[0]);
    const token = signAuthToken(result.rows[0]);
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
      const token = signAuthToken(user);
      res.json({ user: await userForAuthResponse(user), token });
      io.to(String(user.id)).emit('status:updated', { status: user.status, is_online: user.is_online });
      return;
    }

    const result = await pool.query(
      `UPDATE users SET status = $1 WHERE id = $2 RETURNING ${USER_PUBLIC_FIELDS}`,
      [status, req.user.id]
    );
    const user = result.rows[0];
    const token = signAuthToken(user);
    res.json({ user: await userForAuthResponse(user), token });
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

app.get('/api/wallet/transactions', authenticateToken, async (req: any, res) => {
  const limit = Math.min(Math.max(parseInt(String(req.query.limit || '50'), 10) || 50, 1), 100);
  try {
    const result = await pool.query(
      `SELECT id, amount, type, status, reference, created_at
       FROM wallet_transactions
       WHERE user_id = $1
       ORDER BY created_at DESC
       LIMIT $2`,
      [req.user.id, limit]
    );
    res.json(
      result.rows.map((row: Record<string, unknown>) => ({
        id: row.id,
        amount: parseFloat(String(row.amount)),
        type: row.type,
        status: row.status,
        reference: row.reference,
        createdAt: row.created_at,
      }))
    );
  } catch (err) {
    console.error('Wallet transactions error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/rider/stats', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') {
    return res.status(403).json({ message: 'Riders only' });
  }
  const riderId = req.user.id;
  try {
    const tripsRes = await pool.query(
      `SELECT
         COUNT(*) FILTER (
           WHERE status = 'delivered'
             AND created_at >= date_trunc('day', CURRENT_TIMESTAMP)
         )::int AS trips_today,
         COUNT(*) FILTER (
           WHERE status = 'delivered'
             AND created_at >= date_trunc('week', CURRENT_TIMESTAMP)
         )::int AS trips_week,
         COUNT(*) FILTER (
           WHERE status = 'delivered'
             AND created_at >= date_trunc('month', CURRENT_TIMESTAMP)
         )::int AS trips_month,
         COALESCE(SUM(
           CASE WHEN status = 'delivered'
             AND created_at >= date_trunc('day', CURRENT_TIMESTAMP)
           THEN COALESCE(delivery_fee, total) ELSE 0 END
         ), 0)::float AS earnings_today,
         COALESCE(SUM(
           CASE WHEN status = 'delivered'
             AND created_at >= date_trunc('week', CURRENT_TIMESTAMP)
           THEN COALESCE(delivery_fee, total) ELSE 0 END
         ), 0)::float AS earnings_week,
         COALESCE(SUM(
           CASE WHEN status = 'delivered'
             AND created_at >= date_trunc('month', CURRENT_TIMESTAMP)
           THEN COALESCE(delivery_fee, total) ELSE 0 END
         ), 0)::float AS earnings_month,
         AVG(rating) FILTER (WHERE rating IS NOT NULL AND rating > 0)::float AS avg_rating,
         COUNT(*) FILTER (WHERE rating IS NOT NULL AND rating > 0)::int AS rated_trips
       FROM orders
       WHERE rider_id = $1`,
      [riderId]
    );

    const offersRes = await pool.query(
      `SELECT
         COUNT(*)::int AS offers_received,
         COUNT(*) FILTER (WHERE status = 'accepted')::int AS offers_accepted,
         COUNT(*) FILTER (WHERE status = 'declined')::int AS offers_declined
       FROM order_dispatch_offers
       WHERE rider_id = $1
         AND created_at >= CURRENT_TIMESTAMP - INTERVAL '30 days'`,
      [riderId]
    );

    const trips = tripsRes.rows[0] || {};
    const offers = offersRes.rows[0] || {};
    const offersReceived = offers.offers_received ?? 0;
    const offersAccepted = offers.offers_accepted ?? 0;
    const acceptanceRate =
      offersReceived > 0 ? Math.round((offersAccepted / offersReceived) * 1000) / 1000 : null;

    const activeRes = await pool.query(
      `SELECT COUNT(*)::int AS active_trips
       FROM orders
       WHERE rider_id = $1 AND status IN ('ready', 'picked_up', 'arrived')`,
      [riderId]
    );

    res.json({
      tripsToday: trips.trips_today ?? 0,
      tripsWeek: trips.trips_week ?? 0,
      tripsMonth: trips.trips_month ?? 0,
      earningsToday: trips.earnings_today ?? 0,
      earningsWeek: trips.earnings_week ?? 0,
      earningsMonth: trips.earnings_month ?? 0,
      avgRating: trips.avg_rating != null ? parseFloat(trips.avg_rating) : null,
      ratedTrips: trips.rated_trips ?? 0,
      offersReceived,
      offersAccepted,
      offersDeclined: offers.offers_declined ?? 0,
      acceptanceRate,
      activeTrips: activeRes.rows[0]?.active_trips ?? 0,
    });
  } catch (err) {
    console.error('Rider stats error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

function handleMediaUploadError(res: express.Response, err: unknown) {
  if (isMediaError(err)) {
    return res.status(err.statusCode).json({ message: err.message, code: err.code });
  }
  console.error('Media upload error:', err);
  return res.status(500).json({ message: 'Image upload failed' });
}

// File upload — validated pipeline → Supabase Storage (or compressed inline fallback)
app.post('/api/upload', authenticateToken, upload.single('image'), async (req: any, res) => {
  try {
    if (!req.file) return res.status(400).json({ message: 'No file uploaded' });
    checkUploadRateLimit(String(req.user.id));

    const role = req.user.role as string;
    let folder = parseUploadFolder(req.body?.folder, 'products');
    if (folder === 'products' && role !== 'vendor' && role !== 'admin') {
      folder = 'avatars';
    }
    if (folder === 'rider-documents') {
      return res.status(403).json({ message: 'Use rider document upload for KYC photos.' });
    }

    const fileName = resolveUploadFileName(folder);
    const result = await persistUploadedImage({
      folder,
      userId: String(req.user.id),
      fileName,
      buffer: req.file.buffer,
      mime: req.file.mimetype,
    });

    res.json({
      url: result.url,
      objectKey: result.objectKey,
      storage: result.storage,
      contentType: result.contentType,
      width: result.width,
      height: result.height,
    });
  } catch (err) {
    return handleMediaUploadError(res, err);
  }
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
      return res.status(400).json({ message: 'No image uploaded' });
    }
    try {
      checkUploadRateLimit(String(req.user.id));
      const imageResult = await persistUploadedImage({
        folder: 'rider-documents',
        userId: String(req.user.id),
        fileName: resolveUploadFileName('rider-documents', docType),
        buffer: req.file.buffer,
        mime: req.file.mimetype,
      });
      const imageRef = imageResult.url;
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
        [req.user.id, docType, imageRef, imageResult.contentType]
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
      const token = signAuthToken(user);
      res.json({
        url: await resolveImageUrlForClient(imageRef),
        storage: imageResult.storage,
        documents,
        user: await userForAuthResponse(user),
        token,
      });
    } catch (err) {
      return handleMediaUploadError(res, err);
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
    const token = signAuthToken(user);
    res.json({
      message: 'Submitted for admin review',
      user: await userForAuthResponse(user),
      token,
      documents: await fetchRiderDocuments(req.user.id),
    });
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
  res.set('Cache-Control', 'no-store, no-cache, must-revalidate');
  try {
    res.json(await buildPublicPricingPayload());
  } catch (err) {
    res.json({
      price_per_km: 4,
      base_price_per_km: 4,
      surge_enabled: false,
      surge_multiplier: 1.5,
      surge_start_time: '17:00',
      surge_end_time: '21:00',
      surge_active: false,
    });
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
    const nearby = await getNearestActiveRiders(
      { lat, lng },
      region,
      [],
      limit,
      NEARBY_RIDERS_MAX_KM
    );
    if (!nearby.length) {
      return res.json({ riders: [] });
    }
    const riderIds = nearby.map((r) => r.id);
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
  const usable = results.filter(
    (r) => r.formatted_address && !r.types?.includes('plus_code')
  );
  const pool = usable.length ? usable : results;
  for (const type of GEOCODE_PREFERRED_TYPES) {
    const hit = pool.find((r) => r.types?.includes(type));
    if (hit?.formatted_address) return hit.formatted_address;
  }
  const inGhana = pool.find((r) => /ghana/i.test(r.formatted_address || ''));
  return (inGhana || pool[0]).formatted_address || null;
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
    let query =
      `SELECT id, name, email, phone, cover_image, address, lat, lng, region, shop_category,
              shop_open_status, shop_status_message, shop_discount_label, shop_discount_percent,
              shop_promo_updated_at, shop_story_image, shop_story_posted_at, shop_story_expires_at
       FROM users WHERE role = $1 AND status = 'active'`;
    const params: any[] = ['vendor'];
    const { category } = req.query;
    
    if (region) {
      query += ' AND (region = $2 OR region IS NULL)';
      params.push(region);
    }
    if (category && typeof category === 'string') {
      query += ` AND LOWER(COALESCE(shop_category, 'food')) = LOWER($${params.length + 1})`;
      params.push(category.trim());
    }
    
    const result = await pool.query(query, params);
    const vendors = await Promise.all(
      dedupeVendorList(result.rows).map((v: Record<string, unknown>) => vendorRowForClient(v))
    );
    res.json(vendors);
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
  const { name, description, price, category, image_url, vendor_id: bodyVendorId } = req.body;
  try {
    let vendorId = req.user.id;
    if (req.user.role === 'admin') {
      const target = bodyVendorId ?? req.user.id;
      const vCheck = await pool.query(
        `SELECT id, status FROM users WHERE id = $1 AND role = 'vendor'`,
        [target]
      );
      if (!vCheck.rows[0]) {
        return res.status(400).json({ message: 'Invalid vendor_id' });
      }
      vendorId = vCheck.rows[0].id;
    } else {
      const userRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
      const st = userRes.rows[0]?.status;
      if (st === 'rejected' || st === 'disabled') {
        return res.status(403).json({ message: 'Your store account cannot add menu items.' });
      }
    }
    const result = await pool.query(
      'INSERT INTO products (vendor_id, name, description, price, category, image_url) VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
      [vendorId, name, description, price, category, image_url]
    );
    const product = result.rows[0];
    io.emit('product:updated', {
      vendorId,
      product: {
        id: product.id,
        vendor_id: product.vendor_id,
        name: product.name,
        price: product.price,
        is_available: product.is_available,
      },
    });
    res.json(product);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.patch('/api/products/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'vendor' && req.user.role !== 'admin') return res.sendStatus(403);
  const { name, description, price, category, image_url, is_available } = req.body;
  const { id } = req.params;
  try {
    const productRes = await pool.query('SELECT vendor_id FROM products WHERE id = $1', [id]);
    if (!productRes.rows[0]) {
      return res.status(404).json({ message: 'Product not found' });
    }
    const ownerVendorId = productRes.rows[0].vendor_id;
    if (req.user.role === 'vendor') {
      if (ownerVendorId !== req.user.id) {
        return res.status(403).json({ message: 'Not authorized to edit this product' });
      }
      const userRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
      const st = userRes.rows[0]?.status;
      if (st === 'rejected' || st === 'disabled') {
        return res.status(403).json({ message: 'Your store account cannot edit menu items.' });
      }
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
      [name, description, price, category, image_url, is_available, id, ownerVendorId]
    );
    if (result.rows[0]) {
      const product = result.rows[0];
      io.emit('product:updated', {
        vendorId: ownerVendorId,
        product: {
          id: product.id,
          vendor_id: product.vendor_id,
          name: product.name,
          price: product.price,
          is_available: product.is_available,
        },
      });
      res.json(product);
    } else {
      res.status(404).json({ message: 'Product not found or unauthorized' });
    }
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/vendor/shop-promo', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'vendor') return res.sendStatus(403);
  try {
    const result = await pool.query(
      `SELECT id, name, shop_category, shop_open_status, shop_status_message,
              shop_discount_label, shop_discount_percent, shop_promo_updated_at,
              shop_story_image, shop_story_posted_at, shop_story_expires_at
       FROM users WHERE id = $1 AND role = 'vendor'`,
      [req.user.id]
    );
    if (!result.rows[0]) return res.status(404).json({ message: 'Vendor not found' });
    res.json(await vendorPromoPayload(result.rows[0]));
  } catch (err) {
    console.error('Vendor shop-promo read error:', err);
    res.status(500).json({ message: 'Failed to load shop status' });
  }
});

app.patch('/api/vendor/shop-promo', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'vendor') return res.sendStatus(403);
  const {
    shop_open_status,
    shop_status_message,
    shop_discount_label,
    shop_discount_percent,
    shop_story_image,
    clear_shop_story,
  } = req.body ?? {};

  const openStatus = normalizeShopOpenStatus(shop_open_status);
  if (shop_open_status != null && shop_open_status !== '' && !openStatus) {
    return res.status(400).json({
      message: `shop_open_status must be one of: ${SHOP_OPEN_STATUSES.join(', ')}`,
    });
  }

  const statusMessage =
    shop_status_message === undefined
      ? undefined
      : shop_status_message == null
        ? null
        : String(shop_status_message).trim().slice(0, 160) || null;

  const discountLabel =
    shop_discount_label === undefined
      ? undefined
      : shop_discount_label == null
        ? null
        : String(shop_discount_label).trim().slice(0, 80) || null;

  let discountPercent: number | null | undefined = undefined;
  if (shop_discount_percent !== undefined) {
    if (shop_discount_percent == null || shop_discount_percent === '') {
      discountPercent = null;
    } else {
      const n = Number(shop_discount_percent);
      if (!Number.isFinite(n) || n < 0 || n > 100) {
        return res.status(400).json({ message: 'shop_discount_percent must be between 0 and 100' });
      }
      discountPercent = Math.round(n * 100) / 100;
    }
  }

  try {
    const acct = await pool.query(`SELECT status FROM users WHERE id = $1 AND role = 'vendor'`, [
      req.user.id,
    ]);
    if (!acct.rows[0]) return res.status(404).json({ message: 'Vendor not found' });
    if (acct.rows[0].status !== 'active') {
      return res.status(403).json({ message: 'Your store must be active before posting status to customers.' });
    }

    const sets: string[] = [];
    const params: unknown[] = [];
    if (openStatus) {
      params.push(openStatus);
      sets.push(`shop_open_status = $${params.length}`);
    }
    if (shop_status_message !== undefined) {
      params.push(statusMessage);
      sets.push(`shop_status_message = $${params.length}`);
    }
    if (shop_discount_label !== undefined) {
      params.push(discountLabel);
      sets.push(`shop_discount_label = $${params.length}`);
    }
    if (shop_discount_percent !== undefined) {
      params.push(discountPercent);
      sets.push(`shop_discount_percent = $${params.length}`);
    }
    if (clear_shop_story === true || shop_story_image === null) {
      params.push(null);
      sets.push(`shop_story_image = $${params.length}`);
      sets.push('shop_story_posted_at = NULL');
      sets.push('shop_story_expires_at = NULL');
    } else if (shop_story_image !== undefined) {
      const storyRef = normalizeImageRefForDb(shop_story_image);
      params.push(storyRef);
      sets.push(`shop_story_image = $${params.length}`);
      if (storyRef) {
        sets.push('shop_story_posted_at = CURRENT_TIMESTAMP');
        sets.push(
          `shop_story_expires_at = CURRENT_TIMESTAMP + interval '${SHOP_STORY_TTL_HOURS} hours'`
        );
      } else {
        sets.push('shop_story_posted_at = NULL');
        sets.push('shop_story_expires_at = NULL');
      }
    }
    if (sets.length === 0) {
      return res.status(400).json({ message: 'No shop status fields to update' });
    }
    sets.push('shop_promo_updated_at = CURRENT_TIMESTAMP');
    params.push(req.user.id);
    const result = await pool.query(
      `UPDATE users SET ${sets.join(', ')}
       WHERE id = $${params.length} AND role = 'vendor'
       RETURNING id, name, shop_category, shop_open_status, shop_status_message,
                 shop_discount_label, shop_discount_percent, shop_promo_updated_at,
                 shop_story_image, shop_story_posted_at, shop_story_expires_at`,
      params
    );
    const row = result.rows[0];
    const payload = await vendorPromoPayload(row);
    await emitVendorPromo(row);
    res.json(payload);
  } catch (err) {
    console.error('Vendor shop-promo update error:', err);
    res.status(500).json({ message: 'Failed to update shop status' });
  }
});

app.get('/api/vendor/dashboard', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'vendor') return res.status(403).json({ message: 'Vendors only' });
  try {
    const vendorId = req.user.id;
    const [statsRes, productsRes, recentRes] = await Promise.all([
      pool.query(
        `SELECT
          (SELECT COUNT(*)::int FROM orders
           WHERE (vendor_id = $1 OR (customer_id = $1 AND order_type = 'courier'))
             AND status NOT IN ('delivered', 'cancelled')) AS active_orders,
          (SELECT COUNT(*)::int FROM products WHERE vendor_id = $1 AND is_available = true AND is_approved = true) AS in_stock,
          (SELECT COUNT(*)::int FROM products WHERE vendor_id = $1 AND is_available = false) AS out_of_stock,
          (SELECT COUNT(*)::int FROM products WHERE vendor_id = $1 AND is_approved = false) AS pending_approval,
          (SELECT COALESCE(SUM(total), 0)::float FROM orders WHERE vendor_id = $1 AND status = 'delivered' AND created_at > NOW() - INTERVAL '7 days') AS revenue_7d`,
        [vendorId]
      ),
      pool.query(
        `SELECT id, name, price, category, is_available, is_approved, image_url
         FROM products WHERE vendor_id = $1 ORDER BY is_available DESC, name ASC LIMIT 80`,
        [vendorId]
      ),
      pool.query(
        `SELECT id, status, total, items, created_at, customer_id, order_type, pickup_address, address
         FROM orders
         WHERE vendor_id = $1 OR (customer_id = $1 AND order_type = 'courier')
         ORDER BY created_at DESC LIMIT 12`,
        [vendorId]
      ),
    ]);
    res.json({
      stats: statsRes.rows[0],
      products: productsRes.rows,
      recentOrders: recentRes.rows,
    });
  } catch (err) {
    console.error('Vendor dashboard error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/** Vendor menu — search & paginate (supports large pharmacies). */
app.get('/api/vendor/products', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'vendor') return res.status(403).json({ message: 'Vendors only' });
  try {
    const vendorId = req.user.id;
    const q = String(req.query.q || '').trim();
    const limit = Math.min(Math.max(parseInt(String(req.query.limit || '200'), 10) || 200, 1), 500);
    const offset = Math.max(parseInt(String(req.query.offset || '0'), 10) || 0, 0);
    const params: any[] = [vendorId];
    let sql = `SELECT id, vendor_id, name, description, price, category, image_url, is_available, is_approved, created_at
               FROM products WHERE vendor_id = $1`;
    if (q.length >= 2) {
      params.push(`%${q}%`);
      sql += ` AND (name ILIKE $${params.length} OR category ILIKE $${params.length} OR COALESCE(description,'') ILIKE $${params.length})`;
    }
    sql += ` ORDER BY is_available DESC, name ASC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);
    const result = await pool.query(sql, params);
    res.json(result.rows);
  } catch (err) {
    console.error('Vendor products list error:', err);
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

// Admin vendor accounts (create stores for merchants)
app.get('/api/admin/vendors', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  try {
    const result = await pool.query(
      `SELECT u.id, u.name, u.email, u.phone, u.status, u.shop_category, u.address, u.region,
              u.created_at,
              (SELECT COUNT(*)::int FROM products p WHERE p.vendor_id = u.id) AS product_count,
              (SELECT COUNT(*)::int FROM products p WHERE p.vendor_id = u.id AND p.is_approved = false) AS pending_products,
              (SELECT COUNT(*)::int FROM orders o WHERE o.vendor_id = u.id
                 AND o.status NOT IN ('delivered', 'cancelled')) AS active_orders
       FROM users u
       WHERE u.role = 'vendor'
       ORDER BY u.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Admin vendors list error:', err);
    res.status(500).json({ message: 'Failed to load vendors' });
  }
});

app.post('/api/admin/vendors', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const {
    name,
    email,
    password,
    phone,
    shop_category,
    address,
    lat,
    lng,
    region,
    activate,
  } = req.body;
  if (!name || !email || !password) {
    return res.status(400).json({ message: 'Name, email, and password are required' });
  }
  if (String(password).length < 6) {
    return res.status(400).json({ message: 'Password must be at least 6 characters' });
  }
  let shopCat = 'food';
  if (shop_category != null && String(shop_category).trim()) {
    const c = String(shop_category).trim().toLowerCase();
    if (!(SHOP_CATEGORIES as readonly string[]).includes(c)) {
      return res.status(400).json({
        message: `shop_category must be one of: ${SHOP_CATEGORIES.join(', ')}`,
      });
    }
    shopCat = c;
  }
  let storePhone: string | null = null;
  if (phone) {
    if (!isValidGhanaPhone(phone)) {
      return res.status(400).json({ message: 'Enter a valid Ghana phone (e.g. 0247904675).' });
    }
    storePhone = formatGhanaPhone(phone);
  }
  const status = activate === false ? 'pending' : 'active';
  try {
    const hashedPassword = await bcrypt.hash(String(password), 10);
    const result = await pool.query(
      `INSERT INTO users (name, email, password, role, status, phone, shop_category, address, lat, lng, region)
       VALUES ($1, $2, $3, 'vendor', $4, $5, $6, $7, $8, $9, $10)
       RETURNING id, name, email, role, balance, phone, status, shop_category, address, lat, lng, region, created_at`,
      [
        String(name).trim(),
        String(email).trim().toLowerCase(),
        hashedPassword,
        status,
        storePhone,
        shopCat,
        address ?? null,
        lat ?? null,
        lng ?? null,
        region ?? null,
      ]
    );
    const user = result.rows[0];
    res.status(201).json({
      user,
      message:
        status === 'active'
          ? 'Store account created. The merchant can log in on the app with email or phone and upload menu items.'
          : 'Store account created (pending). Approve the account before they can add menu items.',
    });
  } catch (err: any) {
    console.error('Admin create vendor error:', err);
    if (err?.code === '23505') {
      return res.status(400).json({ message: 'Email or phone already registered' });
    }
    res.status(500).json({ message: 'Failed to create vendor account' });
  }
});

/** Permanently remove a vendor account (products deleted; orders keep history with vendor cleared). */
app.delete('/api/admin/vendors/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { id } = req.params;
  const client = await pool.connect();
  try {
    const vendorRes = await client.query(
      `SELECT id, name, email, role FROM users WHERE id = $1`,
      [id]
    );
    const vendor = vendorRes.rows[0];
    if (!vendor) {
      return res.status(404).json({ message: 'Account not found' });
    }
    if (vendor.role !== 'vendor') {
      return res.status(400).json({ message: 'Only vendor accounts can be deleted here' });
    }
    const activeRes = await client.query(
      `SELECT COUNT(*)::int AS n FROM orders
       WHERE vendor_id = $1 AND status NOT IN ('delivered', 'cancelled')`,
      [id]
    );
    const activeOrders = activeRes.rows[0]?.n ?? 0;
    if (activeOrders > 0) {
      return res.status(409).json({
        message: `Cannot delete: ${activeOrders} active order(s). Wait until delivered/cancelled or disable the account instead.`,
        active_orders: activeOrders,
      });
    }

    await client.query('BEGIN');
    await client.query('DELETE FROM products WHERE vendor_id = $1', [id]);
    await client.query('UPDATE orders SET vendor_id = NULL WHERE vendor_id = $1', [id]);
    await client.query('DELETE FROM wallet_transactions WHERE user_id = $1', [id]);
    await client.query('DELETE FROM users WHERE id = $1 AND role = $2', [id, 'vendor']);
    await client.query('COMMIT');

    io.to(id).emit('status:updated', { status: 'deleted' });
    res.json({
      success: true,
      message: `Vendor "${vendor.name}" (${vendor.email}) deleted`,
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Admin delete vendor error:', err);
    res.status(500).json({ message: 'Failed to delete vendor account' });
  } finally {
    client.release();
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
    const rows = result.rows as Array<{ documents?: Array<{ image_url?: string }> }>;
    const withUrls = await Promise.all(
      rows.map(async (row) => {
        const docs = Array.isArray(row.documents) ? row.documents : [];
        const documents = await Promise.all(
          docs.map(async (d) => ({
            ...d,
            image_url: await resolveImageUrlForClient(String(d.image_url ?? ''), {
              adminReview: true,
            }),
          }))
        );
        return { ...row, documents };
      })
    );
    res.json(withUrls);
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
      query +=
        ' WHERE o.vendor_id = $1 OR (o.customer_id = $1 AND o.order_type = \'courier\')';
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
    const rows = await Promise.all(
      result.rows.map(async (o: any) => {
        const row = await sanitizeOrderForRole(o, req.user.role, req.user.id);
        if (req.user.role === 'rider' && o.rider_offer_expires_at) {
          row.expiresAt = new Date(o.rider_offer_expires_at).toISOString();
          row.dispatchWave = o.rider_offer_wave;
        }
        return row;
      })
    );
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
      if (
        req.user.role === 'vendor' &&
        (!pickupLat || !pickupLng || !String(finalPickup || '').trim())
      ) {
        const vendorResult = await pool.query(
          'SELECT address, lat, lng, region FROM users WHERE id = $1',
          [req.user.id]
        );
        const v = vendorResult.rows[0];
        if (v?.lat != null && v?.lng != null) {
          finalPickup = v.address || finalPickup || 'Store pickup';
          pickupLat = v.lat;
          pickupLng = v.lng;
          finalRegion = finalRegion || v.region;
        }
      }
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
      let quotePickupLat = Number(pickupLat);
      let quotePickupLng = Number(pickupLng);
      if (
        vendorId &&
        pickup_lat != null &&
        pickup_lng != null &&
        Number(pickup_lat) &&
        Number(pickup_lng)
      ) {
        quotePickupLat = Number(pickup_lat);
        quotePickupLng = Number(pickup_lng);
      }
      const quote = await calculateDeliveryFeeFromCoords(
        quotePickupLat,
        quotePickupLng,
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
      const isVendorShopOrder =
        Boolean(vendorId) &&
        itemsSubtotal > 0.5 &&
        Array.isArray(items) &&
        items.some((it: any) => Number(it.price || 0) > 0);
      // Pure courier: total = delivery only. Shop/vendor carts: items + delivery.
      const expectedTotal =
        finalOrderType === 'courier' && !isVendorShopOrder
          ? finalDeliveryFee
          : Math.round((itemsSubtotal + finalDeliveryFee) * 100) / 100;
      if (Math.abs(Number(total) - expectedTotal) > 1.5) {
        return res.status(400).json({
          message: 'Order total does not match items + delivery for route distance',
          distance_km: quote.distance_km,
          delivery_fee: finalDeliveryFee,
          expected_total: expectedTotal,
        });
      }
    }

    const initialStatus =
      finalOrderType === 'courier' || (vendorId && finalOrderType === 'food')
        ? 'ready'
        : 'pending';
    const scheduled = scheduledTime || scheduled_time || null;

    const result = await pool.query(
      'INSERT INTO orders (customer_id, vendor_id, items, total, status, address, pickup_address, order_type, scheduled_time, lat, lng, pickup_lat, pickup_lng, region, payment_status, payment_method, delivery_fee) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17) RETURNING *',
      [req.user.id, vendorId, JSON.stringify(items), total, initialStatus, address || 'Customer Address', finalPickup || 'Pickup', finalOrderType, scheduled, lat, lng, pickupLat, pickupLng, finalRegion, paymentStatus, finalPaymentMethod, finalDeliveryFee]
    );
    const order = result.rows[0];
    res.json(order);
    io.emit('order:new', order); // Notify vendors/admin
    if (order.customer_id) {
      io.to(String(order.customer_id)).emit('order:new', order);
    }
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
      res.json(await sanitizeOrderForRole(order, req.user.role, req.user.id));
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

/** Driver releases an accepted trip before pickup — order returns to dispatch queue. */
app.post('/api/orders/:id/release', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') {
    return res.status(403).json({ message: 'Riders only' });
  }
  const orderId = req.params.id;
  const reason = String(req.body?.reason || 'Driver released trip').trim().slice(0, 200);
  try {
    const userRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
    if (userRes.rows[0]?.status !== 'active') {
      return res.status(403).json({ message: 'Go online to manage rides.' });
    }

    const orderRes = await pool.query(
      'SELECT * FROM orders WHERE id = $1 AND rider_id = $2',
      [orderId, req.user.id]
    );
    const order = orderRes.rows[0];
    if (!order) {
      return res.status(404).json({ message: 'Order not found or not assigned to you.' });
    }
    if (order.status !== 'ready') {
      return res.status(400).json({
        message: 'You can only release a trip before pickup. Contact support if you cannot complete an active delivery.',
      });
    }

    const updated = await pool.query(
      `UPDATE orders
       SET rider_id = NULL, updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 AND rider_id = $2 AND status = 'ready'
       RETURNING *`,
      [orderId, req.user.id]
    );
    if (!updated.rows[0]) {
      return res.status(409).json({ message: 'Trip could not be released.' });
    }

    const released = updated.rows[0];
    await pool.query(
      `UPDATE order_dispatch_offers SET status = 'declined'
       WHERE order_id = $1 AND rider_id = $2 AND status = 'accepted'`,
      [orderId, req.user.id]
    );

    broadcastOrderUpdated(released);
    if (isOfferableOrder(released)) {
      await broadcastRideOfferToRiders(released);
    }

    res.json({
      ok: true,
      message: 'Trip released — it will be offered to other drivers.',
      reason,
      order: await sanitizeOrderForRole(released, 'rider', req.user.id),
    });
  } catch (err) {
    console.error('Rider release trip error:', err);
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
    res.json(await sanitizeOrderForRole(order, 'rider', req.user.id));
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
      return res.json(await sanitizeOrderForRole(order, 'customer', req.user.id));
    }
    const result = await pool.query(
      `UPDATE orders SET customer_payment_ack = 'cash', updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`,
      [orderId]
    );
    const updated = result.rows[0];
    broadcastOrderUpdated(updated);
    res.json(await sanitizeOrderForRole(updated, 'customer', req.user.id));
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
      return res.json(await sanitizeOrderForRole(order, 'customer', req.user.id));
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
    res.json(await sanitizeOrderForRole(updated, 'customer', req.user.id));
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
    try {
      await settleOrderPayment(delivered);
    } catch (settleErr) {
      console.error('[complete-delivery] settlement failed (order still delivered):', settleErr);
    }
    broadcastOrderUpdated(delivered);
    res.json(await sanitizeOrderForRole(delivered, 'rider', req.user.id));
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

function orderRefundAmount(order: { total: unknown; payment_status?: string }): number {
  return parseFloat(String(order.total ?? 0));
}

async function customerPrepaidForOrder(
  client: { query: typeof pool.query },
  customerId: string,
  orderId: string
): Promise<number> {
  const tail = orderId.slice(-6);
  const short = orderId.slice(0, 8);
  const r = await client.query(
    `SELECT COALESCE(SUM(amount), 0)::float AS paid
     FROM wallet_transactions
     WHERE user_id = $1 AND type = 'payment'
       AND (reference ILIKE $2 OR reference ILIKE $3 OR reference ILIKE $4)`,
    [customerId, `%${orderId}%`, `%${tail}%`, `%${short}%`]
  );
  return parseFloat(r.rows[0]?.paid ?? 0);
}

app.post('/api/orders/:id/cancel', authenticateToken, async (req: any, res) => {
  const orderId = req.params.id;
  const client = await pool.connect();
  try {
    const orderRes = await client.query('SELECT * FROM orders WHERE id = $1', [orderId]);
    if (orderRes.rowCount === 0) {
      client.release();
      return res.status(404).json({ message: 'Order not found' });
    }

    const order = orderRes.rows[0];
    if (order.customer_id !== req.user.id) {
      client.release();
      return res.status(403).json({ message: 'Unauthorized' });
    }
    if (!CUSTOMER_CANCELLABLE_STATUSES.includes(order.status)) {
      client.release();
      return res.status(400).json({
        message: 'This trip can no longer be cancelled (package already picked up or delivered).',
      });
    }

    const prevRiderId = order.rider_id;
    const refundAmount = orderRefundAmount(order);
    let refundCredited = false;
    let walletBalance: number | undefined;

    await client.query('BEGIN');

    const updated = await client.query(
      `UPDATE orders SET status = 'cancelled', rider_id = NULL, updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 RETURNING *`,
      [orderId]
    );
    const cancelled = updated.rows[0];

    const shouldRefund =
      cancelled.payment_status === 'paid' ||
      (await customerPrepaidForOrder(client, req.user.id, orderId)) > 0.01;

    if (shouldRefund && refundAmount > 0) {
      const existingRefund = await client.query(
        `SELECT id FROM wallet_transactions
         WHERE user_id = $1 AND type = 'topup' AND reference = $2 LIMIT 1`,
        [req.user.id, `Refund for cancelled order #${orderId.slice(-6)}`]
      );
      if (existingRefund.rowCount === 0) {
        const bRes = await client.query(
          'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
          [refundAmount, req.user.id]
        );
        await client.query(
          'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
          [
            req.user.id,
            refundAmount,
            'topup',
            `Refund for cancelled order #${orderId.slice(-6)}`,
          ]
        );
        walletBalance = parseFloat(bRes.rows[0].balance);
        refundCredited = true;
      }
    }

    await client.query('COMMIT');
    client.release();

    if (refundCredited && walletBalance != null) {
      io.to(req.user.id).emit('wallet:updated', { balance: walletBalance });
    }

    if (prevRiderId) {
      await notifyRideTaken(orderId, prevRiderId);
    } else {
      await notifyRideCancelled(orderId);
    }

    clearDispatchTimer(orderId);
    await pool.query(
      `UPDATE order_dispatch_offers SET status = 'expired'
       WHERE order_id = $1 AND status = 'offered'`,
      [orderId]
    );

    const payload = await sanitizeOrderForRole(cancelled, req.user.role, req.user.id);
    res.json({
      ...payload,
      refundCredited,
      refundAmount: refundCredited ? refundAmount : 0,
      walletBalance,
      refundMessage: refundCredited
        ? `${refundAmount.toFixed(2)} GHS added to your BytzGo wallet`
        : cancelled.payment_status === 'cash_on_delivery'
          ? 'No payment was taken — nothing to refund'
          : 'Order cancelled (no prepaid amount to refund)',
    });
    broadcastOrderUpdated(cancelled);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    client.release();
    console.error('Cancel order error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/** Pulse Guide™ — customer flashes live GPS so rider finds them without phone calls. */
app.post('/api/orders/:id/pulse-guide', authenticateToken, async (req: any, res) => {
  const orderId = req.params.id;
  const lat = Number(req.body?.lat);
  const lng = Number(req.body?.lng);
  let phase = String(req.body?.phase || '').trim().toLowerCase();

  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    return res.status(400).json({ message: 'Valid lat and lng are required' });
  }

  try {
    const orderRes = await pool.query(
      `SELECT o.*, ${ORDER_CONTACT_SELECT}
       FROM orders o ${ORDER_CONTACT_JOINS} WHERE o.id = $1`,
      [orderId]
    );
    const order = orderRes.rows[0];
    if (!order) return res.status(404).json({ message: 'Order not found' });
    if (order.customer_id !== req.user.id) {
      return res.status(403).json({ message: 'Only the customer can activate Pulse Guide' });
    }
    if (!order.rider_id) {
      return res.status(400).json({ message: 'Wait until a biker accepts your trip' });
    }

    const allowedPhase = pulseGuidePhaseForStatus(order.status);
    if (!allowedPhase) {
      return res.status(400).json({ message: 'Pulse Guide is not available for this trip stage' });
    }
    if (phase !== 'pickup' && phase !== 'dropoff') phase = allowedPhase;
    if (phase !== allowedPhase) {
      return res.status(400).json({
        message: phase === 'pickup' ? 'Use drop-off pulse for this stage' : 'Use pickup pulse for this stage',
      });
    }

    const updated = await pool.query(
      `UPDATE orders SET
         pulse_guide_lat = $1,
         pulse_guide_lng = $2,
         pulse_guide_at = CURRENT_TIMESTAMP,
         pulse_guide_phase = $3,
         updated_at = CURRENT_TIMESTAMP
       WHERE id = $4
       RETURNING *`,
      [lat, lng, phase, orderId]
    );
    const full = await loadOrderWithContacts(orderId);

    const pulsePayload = {
      orderId,
      lat,
      lng,
      phase,
      at: full?.pulse_guide_at,
      active: true,
    };
    io.to(String(order.rider_id)).emit('pulse:guide', pulsePayload);
    io.to(String(order.customer_id)).emit('pulse:guide', pulsePayload);

    const phaseLabel = phase === 'pickup' ? 'pickup' : 'drop-off';
    void sendPushToUserIds([order.rider_id], {
      title: 'Pulse Guide active',
      body: `Customer is flashing live ${phaseLabel} location on your map — follow the pulse`,
      type: 'pulse-guide',
      orderId,
      highPriority: true,
    });

    broadcastOrderUpdated(full);
    res.json(await sanitizeOrderForRole(full, 'customer', req.user.id));
  } catch (err: any) {
    console.error('Pulse Guide error:', err);
    res.status(500).json({ message: 'Could not activate Pulse Guide' });
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

// --- Support tickets (customer / vendor / rider / admin) ---

app.post('/api/support/tickets', authenticateToken, async (req: any, res) => {
  const category = String(req.body?.category ?? '').trim().toLowerCase();
  const subject = String(req.body?.subject ?? '').trim();
  const description = String(req.body?.description ?? req.body?.body ?? '').trim();
  const relatedOrderId = req.body?.relatedOrderId ?? req.body?.related_order_id ?? null;

  if (!SUPPORT_CATEGORIES.has(category)) {
    return res.status(400).json({ message: 'Invalid category' });
  }
  if (!subject) return res.status(400).json({ message: 'Subject is required' });
  if (subject.length > 200) {
    return res.status(400).json({ message: 'Subject is too long (max 200 characters)' });
  }
  if (!description) {
    return res.status(400).json({ message: 'Please describe your issue' });
  }
  if (description.length > 2000) {
    return res.status(400).json({ message: 'Description is too long (max 2000 characters)' });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    let displayId = generateSupportDisplayId();
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        const inserted = await client.query(
          `INSERT INTO support_tickets
             (display_id, created_by, created_by_role, category, subject, status, related_order_id)
           VALUES ($1, $2, $3, $4, $5, 'open', $6)
           RETURNING *`,
          [displayId, req.user.id, req.user.role, category, subject, relatedOrderId || null]
        );
        const ticket = inserted.rows[0];
        const msgRes = await client.query(
          `INSERT INTO support_messages (ticket_id, sender_id, body)
           VALUES ($1, $2, $3)
           RETURNING *`,
          [ticket.id, req.user.id, description]
        );
        await client.query('COMMIT');
        const row = await fetchSupportTicketRow(ticket.id);
        const msgRow = msgRes.rows[0];
        const nameRes = await pool.query('SELECT name, role FROM users WHERE id = $1', [
          req.user.id,
        ]);
        msgRow.sender_name = nameRes.rows[0]?.name;
        msgRow.sender_role = nameRes.rows[0]?.role;
        const ticketPayload = formatSupportTicket(row);
        const adminRes = await pool.query(
          "SELECT id FROM users WHERE role = 'admin' AND status = 'active'"
        );
        const adminIds = adminRes.rows.map((r: any) => String(r.id));
        for (const adminId of adminIds) {
          io.to(adminId).emit('ticket:new', { ticket: ticketPayload });
        }
        if (adminIds.length > 0) {
          void sendPushToUserIds(adminIds, {
            title: `New support case · ${ticketPayload.displayId}`,
            body: `${nameRes.rows[0]?.name || 'User'}: ${subject}`,
            type: 'support-ticket',
            ticketId: ticketPayload.id,
            channelId: 'support_updates',
            highPriority: true,
          });
        }
        return res.status(201).json({
          ticket: ticketPayload,
          message: formatSupportMessage(msgRow, req.user.id),
        });
      } catch (err: any) {
        if (err?.code === '23505' && attempt < 4) {
          displayId = generateSupportDisplayId();
          continue;
        }
        throw err;
      }
    }
    throw new Error('Could not create ticket');
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Create support ticket error:', err);
    res.status(500).json({ message: 'Could not create support ticket' });
  } finally {
    client.release();
  }
});

app.get('/api/support/tickets', authenticateToken, async (req: any, res) => {
  try {
    const result = await pool.query(
      `SELECT t.*,
              u.name AS creator_name,
              u.email AS creator_email,
              a.name AS assigned_admin_name,
              (SELECT MAX(m.created_at) FROM support_messages m WHERE m.ticket_id = t.id) AS last_message_at,
              (SELECT m.body FROM support_messages m WHERE m.ticket_id = t.id ORDER BY m.created_at DESC LIMIT 1) AS last_message_preview,
              (SELECT COUNT(*)::int FROM support_messages m WHERE m.ticket_id = t.id) AS message_count
       FROM support_tickets t
       JOIN users u ON u.id = t.created_by
       LEFT JOIN users a ON a.id = t.assigned_admin_id
       WHERE t.created_by = $1
       ORDER BY COALESCE(
         (SELECT MAX(m.created_at) FROM support_messages m WHERE m.ticket_id = t.id),
         t.updated_at
       ) DESC
       LIMIT 100`,
      [req.user.id]
    );
    res.json(result.rows.map((row: any) => formatSupportTicket(row)));
  } catch (err) {
    console.error('List support tickets error:', err);
    res.status(500).json({ message: 'Could not load tickets' });
  }
});

app.get('/api/support/tickets/:id', authenticateToken, async (req: any, res) => {
  try {
    const ticket = await assertSupportTicketAccess(
      req.params.id,
      req.user.id,
      req.user.role
    );
    res.json(formatSupportTicket(ticket));
  } catch (err: any) {
    const status = err.status || 500;
    res.status(status).json({ message: err.message || 'Server error' });
  }
});

app.get('/api/support/tickets/:id/messages', authenticateToken, async (req: any, res) => {
  try {
    await assertSupportTicketAccess(req.params.id, req.user.id, req.user.role);
    const result = await pool.query(
      `SELECT m.*, u.name AS sender_name, u.role AS sender_role
       FROM support_messages m
       JOIN users u ON u.id = m.sender_id
       WHERE m.ticket_id = $1
       ORDER BY m.created_at ASC
       LIMIT 300`,
      [req.params.id]
    );
    res.json(result.rows.map((row: any) => formatSupportMessage(row, req.user.id)));
  } catch (err: any) {
    const status = err.status || 500;
    res.status(status).json({ message: err.message || 'Server error' });
  }
});

app.post('/api/support/tickets/:id/messages', authenticateToken, async (req: any, res) => {
  const body = String(req.body?.body ?? req.body?.text ?? '').trim();
  if (!body) return res.status(400).json({ message: 'Message cannot be empty' });
  if (body.length > 2000) {
    return res.status(400).json({ message: 'Message is too long (max 2000 characters)' });
  }
  try {
    const ticket = await assertSupportTicketAccess(
      req.params.id,
      req.user.id,
      req.user.role
    );
    if (ticket.status === 'closed') {
      return res.status(400).json({ message: 'This ticket is closed' });
    }

    const inserted = await pool.query(
      `INSERT INTO support_messages (ticket_id, sender_id, body)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [req.params.id, req.user.id, body]
    );
    const row = inserted.rows[0];

    let newStatus = ticket.status;
    let assignedAdminId = ticket.assigned_admin_id;
    if (req.user.role === 'admin') {
      if (!assignedAdminId) assignedAdminId = req.user.id;
      if (ticket.status === 'open' || ticket.status === 'pending') newStatus = 'pending';
    } else if (ticket.status === 'pending') {
      newStatus = 'open';
    }

    await pool.query(
      `UPDATE support_tickets
       SET status = $2,
           assigned_admin_id = COALESCE($3, assigned_admin_id),
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [req.params.id, newStatus, assignedAdminId]
    );

    const freshTicket = await fetchSupportTicketRow(req.params.id);
    const nameRes = await pool.query('SELECT name, role FROM users WHERE id = $1', [req.user.id]);
    row.sender_name = nameRes.rows[0]?.name;
    row.sender_role = nameRes.rows[0]?.role;
    await emitSupportMessage(freshTicket || ticket, row, req.user.id);
    res.status(201).json(formatSupportMessage(row, req.user.id));
  } catch (err: any) {
    const status = err.status || 500;
    res.status(status).json({ message: err.message || 'Server error' });
  }
});

app.get('/api/admin/support/tickets', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  const status = String(req.query.status ?? '').trim().toLowerCase();
  const category = String(req.query.category ?? '').trim().toLowerCase();
  const role = String(req.query.role ?? '').trim().toLowerCase();

  const clauses: string[] = [];
  const params: any[] = [];
  if (status && SUPPORT_STATUSES.has(status)) {
    params.push(status);
    clauses.push(`t.status = $${params.length}`);
  }
  if (category && SUPPORT_CATEGORIES.has(category)) {
    params.push(category);
    clauses.push(`t.category = $${params.length}`);
  }
  if (role && ['customer', 'vendor', 'rider', 'admin'].includes(role)) {
    params.push(role);
    clauses.push(`t.created_by_role = $${params.length}`);
  }
  const where = clauses.length ? `WHERE ${clauses.join(' AND ')}` : '';

  try {
    const result = await pool.query(
      `SELECT t.*,
              u.name AS creator_name,
              u.email AS creator_email,
              a.name AS assigned_admin_name,
              (SELECT MAX(m.created_at) FROM support_messages m WHERE m.ticket_id = t.id) AS last_message_at,
              (SELECT m.body FROM support_messages m WHERE m.ticket_id = t.id ORDER BY m.created_at DESC LIMIT 1) AS last_message_preview,
              (SELECT COUNT(*)::int FROM support_messages m WHERE m.ticket_id = t.id) AS message_count
       FROM support_tickets t
       JOIN users u ON u.id = t.created_by
       LEFT JOIN users a ON a.id = t.assigned_admin_id
       ${where}
       ORDER BY
         CASE t.status WHEN 'open' THEN 0 WHEN 'pending' THEN 1 WHEN 'resolved' THEN 2 ELSE 3 END,
         COALESCE(
           (SELECT MAX(m.created_at) FROM support_messages m WHERE m.ticket_id = t.id),
           t.updated_at
         ) DESC
       LIMIT 200`,
      params
    );
    res.json(result.rows.map((row: any) => formatSupportTicket(row)));
  } catch (err) {
    console.error('Admin list support tickets error:', err);
    res.status(500).json({ message: 'Could not load support inbox' });
  }
});

app.patch('/api/admin/support/tickets/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  const status = req.body?.status != null ? String(req.body.status).trim().toLowerCase() : null;
  const assignSelf = req.body?.assign === true || req.body?.assignSelf === true;

  if (status && !SUPPORT_STATUSES.has(status)) {
    return res.status(400).json({ message: 'Invalid status' });
  }
  if (!status && !assignSelf) {
    return res.status(400).json({ message: 'Nothing to update' });
  }

  try {
    const existing = await fetchSupportTicketRow(req.params.id);
    if (!existing) return res.status(404).json({ message: 'Ticket not found' });

    const nextStatus = status || existing.status;
    const assignedAdminId = assignSelf ? req.user.id : existing.assigned_admin_id;

    await pool.query(
      `UPDATE support_tickets
       SET status = $2,
           assigned_admin_id = $3,
           updated_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [req.params.id, nextStatus, assignedAdminId]
    );

    const row = await fetchSupportTicketRow(req.params.id);
    res.json(formatSupportTicket(row));
  } catch (err) {
    console.error('Admin update support ticket error:', err);
    res.status(500).json({ message: 'Could not update ticket' });
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
    const surge = await getSurgePricingState();
    res.json({
      paystack_public_key: pub || process.env.PAYSTACK_PUBLIC_KEY || '',
      paystack_secret_key: maskSecret(sec || process.env.PAYSTACK_SECRET_KEY || ''),
      paystack_secret_configured: !!(sec || process.env.PAYSTACK_SECRET_KEY),
      platform_fee_percent: fee || '10',
      delivery_price_per_km: pricePerKm || '4',
      surge_enabled: surge.enabled ? 'true' : 'false',
      surge_multiplier: String(surge.multiplier),
      surge_start_time: surge.start_time,
      surge_end_time: surge.end_time,
      surge_active_now: surge.surge_active,
      ghana_time: surge.ghana_time,
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
    surge_enabled,
    surge_multiplier,
    surge_start_time,
    surge_end_time,
    sms_base_url,
    sms_api_key,
    sms_sender_id,
  } = req.body;
  const pricingTouched =
    delivery_price_per_km != null ||
    surge_enabled != null ||
    surge_multiplier != null ||
    surge_start_time != null ||
    surge_end_time != null;
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
      await setSetting('delivery_price_per_km', String(rate));
      await pool.query(
        `UPDATE delivery_zones SET price_per_km = $1 WHERE is_active = true`,
        [rate]
      );
    }
    if (surge_enabled != null) {
      const on =
        surge_enabled === true ||
        surge_enabled === 'true' ||
        surge_enabled === 1 ||
        surge_enabled === '1';
      await setSetting('surge_enabled', on ? 'true' : 'false');
    }
    if (surge_multiplier != null) {
      const mult = Math.max(1, parseFloat(String(surge_multiplier)) || 1.25);
      await setSetting('surge_multiplier', String(mult));
    }
    if (surge_start_time != null && String(surge_start_time).trim()) {
      const mins = parseTimeToMinutes(String(surge_start_time));
      if (mins == null) {
        return res.status(400).json({ message: 'surge_start_time must be HH:MM (e.g. 17:00)' });
      }
      await setSetting('surge_start_time', String(surge_start_time).trim());
    }
    if (surge_end_time != null && String(surge_end_time).trim()) {
      const mins = parseTimeToMinutes(String(surge_end_time));
      if (mins == null) {
        return res.status(400).json({ message: 'surge_end_time must be HH:MM (e.g. 21:00)' });
      }
      await setSetting('surge_end_time', String(surge_end_time).trim());
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
    if (pricingTouched) broadcastPricingUpdated();
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
    broadcastPricingUpdated();
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
    broadcastPricingUpdated();
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
    broadcastPricingUpdated();
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
      const result = await pool.query(
        'SELECT * FROM delivery_zones WHERE region = $1 AND is_active = true ORDER BY created_at ASC LIMIT 1',
        [destination_region]
      );
      zone = result.rows[0];
    }
    if (!zone && pickup_region) {
      const result = await pool.query(
        'SELECT * FROM delivery_zones WHERE region = $1 AND is_active = true ORDER BY created_at ASC LIMIT 1',
        [pickup_region]
      );
      zone = result.rows[0];
    }
    const globalRate = Math.max(0.01, parseFloat((await getSetting('delivery_price_per_km')) || '4') || 4);
    const km = distance_km || 0;

    if (!zone) {
      const price = Math.round(km * globalRate * 100) / 100;
      return res.json({ price, zone: null, fallback: true, price_per_km: globalRate });
    }

    let price = km * globalRate;
    const zoneMin = Number(zone.min_price);
    if (Number.isFinite(zoneMin) && zoneMin > 0) {
      price = Math.max(price, zoneMin);
    }
    if (zone.max_price) price = Math.min(price, Number(zone.max_price));

    res.json({
      price: Math.round(price * 100) / 100,
      zone: zone.name,
      fallback: false,
      price_per_km: globalRate,
    });
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
       ON CONFLICT (token) DO UPDATE SET
         user_id = EXCLUDED.user_id,
         platform = EXCLUDED.platform,
         updated_at = CURRENT_TIMESTAMP`,
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
      const payload = { riderId, lat, lng };
      io.to(riderId).emit('location:updated', payload);
      const watching = await pool.query(
        `SELECT DISTINCT customer_id FROM orders
         WHERE rider_id = $1 AND status IN ('ready', 'picked_up', 'arrived')`,
        [riderId]
      );
      for (const row of watching.rows) {
        if (row.customer_id) {
          io.to(String(row.customer_id)).emit('location:updated', payload);
        }
      }
    } catch (err) {
      console.error('Location update failed', err);
    }
  });

  socket.on('disconnect', () => {
    console.log('User disconnected');
  });
});

/** Legal pages for Google Play (privacy policy URL, account deletion). */
const legalDir = path.join(__dirname, 'legal');
function serveLegalPage(slug: string) {
  return (_req: express.Request, res: express.Response) => {
    const file = path.join(legalDir, `${slug}.html`);
    if (!fs.existsSync(file)) {
      return res.status(404).type('text/plain').send('Page not found');
    }
    res.set('Cache-Control', 'no-store');
    res.type('html').sendFile(file);
  };
}
const LEGAL_PATHS = new Set(['/privacy', '/terms', '/account-deletion', '/privacy-policy']);
app.get('/privacy', serveLegalPage('privacy'));
app.get('/privacy-policy', (_req, res) => res.redirect(301, '/privacy'));
app.get('/terms', serveLegalPage('terms'));
app.get('/account-deletion', serveLegalPage('account-deletion'));

/** Direct APK install for testers / before Play listing (file copied by scripts/copy-apk-to-public.mjs). */
app.get('/download/android', (_req, res) => {
  const candidates = [
    path.join(__dirname, '..', 'dist', 'bytzgo.apk'),
    path.join(__dirname, '..', 'public', 'bytzgo.apk'),
  ];
  const apk = candidates.find((p) => fs.existsSync(p));
  if (!apk) {
    return res.status(404).type('text/plain').send('APK not published yet. Check back after the next release.');
  }
  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', 'attachment; filename="BytzGo.apk"');
  res.sendFile(apk);
});

/** Production: serve Vite build — admin portal only on web (mobile app for everyone else). */
function attachWebApp() {
  const shouldServe =
    process.env.SERVE_WEB === 'true' || process.env.NODE_ENV === 'production';
  if (!shouldServe) return;

  const distDir = path.join(__dirname, '..', 'dist');
  const indexHtml = path.join(distDir, 'index.html');
  const landingHtml = path.join(__dirname, 'public-admin-landing.html');
  if (!fs.existsSync(indexHtml)) {
    console.warn('BytzGo: dist/index.html missing — API-only mode');
    return;
  }

  const adminOnly = process.env.SERVE_ADMIN_WEB_ONLY !== 'false';
  console.log(
    `BytzGo: serving web from ${distDir} (${adminOnly ? 'admin /admin only' : 'full SPA'})`
  );

  app.use(express.static(distDir, { maxAge: '1h', index: false }));

  const isAdminPath = (p: string) => p === '/admin' || p.startsWith('/admin/');
  const isAssetPath = (p: string) =>
    p.startsWith('/assets/') ||
    p.startsWith('/branding/') ||
    /\.(js|css|png|jpg|jpeg|gif|webp|svg|ico|woff2?|ttf|map|webmanifest|json|apk)$/i.test(p);

  app.get('/', (_req, res) => {
    if (fs.existsSync(landingHtml)) {
      res.set('Cache-Control', 'no-store');
      return res.type('html').sendFile(landingHtml);
    }
    res.redirect(302, '/admin');
  });

  app.get('*', (req, res, next) => {
    if (
      req.path.startsWith('/api') ||
      req.path.startsWith('/socket.io') ||
      LEGAL_PATHS.has(req.path)
    ) {
      return next();
    }
    if (isAssetPath(req.path)) {
      return next();
    }
    if (adminOnly && !isAdminPath(req.path)) {
      if (fs.existsSync(landingHtml)) {
        res.set('Cache-Control', 'no-store');
        return res.type('html').sendFile(landingHtml);
      }
      return res.status(403).type('text/html').send(
        '<h1>BytzGo</h1><p>Web access is for administrators only. Use the mobile app, or go to <a href="/admin">/admin</a>.</p>'
      );
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
