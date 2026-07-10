import './loadEnv';
import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import compression from 'compression';
import helmet from 'helmet';
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

/** Android OAuth clients from google-services.json (ID token aud may be Android or Web). */
const GOOGLE_ANDROID_CLIENT_IDS = [
  '645977332644-rv482i78e7hln0u3dh475dn4g0rgoa2l.apps.googleusercontent.com',
  '645977332644-lmndn49qajhkqjqa18demn4aqh4le5m9.apps.googleusercontent.com',
];

function googleTokenAudiences(): string[] {
  return [
    ...new Set(
      [
        GOOGLE_WEB_CLIENT_ID,
        FIREBASE_WEB_CLIENT_ID,
        LEGACY_GOOGLE_WEB_CLIENT_ID,
        ...GOOGLE_ANDROID_CLIENT_IDS,
      ].filter(Boolean),
    ),
  ];
}

async function verifyGoogleIdToken(idToken: string) {
  const audiences = googleTokenAudiences();

  try {
    const ticket = await googleOAuthClient.verifyIdToken({ idToken, audience: audiences });
    const payload = ticket.getPayload();
    if (!payload?.email) throw new Error('Invalid Google token');
    return payload;
  } catch (err) {
    console.error('Google ID token verification failed:', err);
    throw err;
  }
}

const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const APPLE_AUDIENCE = 'com.bytzgo.bytzgoMobile';
type AppleJwk = { kid?: string; kty?: string; n?: string; e?: string; alg?: string; use?: string };

let appleJwksCache: { keys: AppleJwk[]; fetchedAt: number } | null = null;

async function getAppleJwks(): Promise<AppleJwk[]> {
  if (appleJwksCache && Date.now() - appleJwksCache.fetchedAt < 3_600_000) {
    return appleJwksCache.keys;
  }
  const res = await axios.get<{ keys: AppleJwk[] }>(APPLE_JWKS_URL);
  appleJwksCache = { keys: res.data.keys, fetchedAt: Date.now() };
  return appleJwksCache.keys;
}

async function verifyAppleIdToken(idToken: string): Promise<jwt.JwtPayload> {
  const decoded = jwt.decode(idToken, { complete: true });
  if (!decoded || typeof decoded === 'string' || !decoded.header?.kid) {
    throw new Error('Invalid Apple token');
  }
  const keys = await getAppleJwks();
  const jwk = keys.find((k) => k.kid === decoded.header.kid);
  if (!jwk) throw new Error('Apple signing key not found');
  const pubKey = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  const payload = jwt.verify(idToken, pubKey, {
    algorithms: ['RS256'],
    issuer: 'https://appleid.apple.com',
    audience: APPLE_AUDIENCE,
  });
  if (typeof payload === 'string' || !payload.sub) {
    throw new Error('Invalid Apple token payload');
  }
  return payload;
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

/** Google Sign-In API — off by default; set GOOGLE_SIGN_IN_ENABLED=true to re-enable. */
const GOOGLE_SIGN_IN_ENABLED = process.env.GOOGLE_SIGN_IN_ENABLED === 'true';

const corsAllowedOrigins = (process.env.CORS_ORIGINS || process.env.APP_URL || '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);

const io = new Server(httpServer, {
  cors: {
    origin: corsAllowedOrigins.length ? corsAllowedOrigins : '*',
    methods: ['GET', 'POST', 'PATCH'],
  },
});

app.use(
  helmet({
    crossOriginResourcePolicy: { policy: 'cross-origin' },
    contentSecurityPolicy: false,
  })
);
if (corsAllowedOrigins.length) {
  app.use(
    cors({
      origin(origin, cb) {
        if (!origin || corsAllowedOrigins.includes(origin)) {
          cb(null, true);
        } else {
          cb(new Error('Not allowed by CORS'));
        }
      },
    })
  );
} else {
  app.use(cors());
}
app.use(compression());
// Product photos are stored as data URLs in JSON — need headroom beyond default 100kb.
app.use(express.json({ limit: '12mb' }));
app.use(express.urlencoded({ extended: true, limit: '12mb' }));

app.get('/api/health', async (req, res) => {
  const deep = req.query.deep === '1';
  let dbOk = true;
  try {
    await pool.query('SELECT 1');
  } catch {
    dbOk = false;
  }

  const storage = getStorageConfig();
  if (!deep) {
    return res.json({
      ok: dbOk,
      service: process.env.RENDER_SERVICE_NAME || 'byzgoback',
      client: 'flutter',
      fast: true,
      fcm: firebaseAdminHasCredentials,
      firebaseProject: FIREBASE_PROJECT_ID,
      database: {
        ...dbConnectionDiagnostics(),
        poolMax: (pool as any).options?.max ?? null,
      },
      media: {
        storage: storage.configured ? 'supabase' : 'inline_fallback',
        bucket: storage.bucket,
        publicBaseUrl: storage.publicBaseUrl,
      },
    });
  }

  let storageProbe: { ok: boolean; message?: string } = { ok: false, message: 'not configured' };
  if (storage.configured) {
    storageProbe = await probeStorage();
  }
  res.json({
    ok: dbOk,
    service: process.env.RENDER_SERVICE_NAME || 'byzgoback',
    client: 'flutter',
    fcm: firebaseAdminHasCredentials,
    firebaseProject: FIREBASE_PROJECT_ID,
    database: {
      ...dbConnectionDiagnostics(),
      poolMax: (pool as any).options?.max ?? null,
    },
    push: {
      iosRequiresApnsKeyInFirebase: true,
      testEndpoint: '/api/push/test-incoming-ride',
      statusEndpoint: '/api/push/status',
    },
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
  'id, name, email, role, balance, phone, cover_image, avatar_url, address, lat, lng, region, status, is_online, shop_category, rider_vehicle_type';

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
  if (u.role === 'rider' && u.id) {
    u.balance = await getRiderSpendableBalance(String(u.id));
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

const VEHICLE_STATUSES = ['active', 'maintenance', 'retired'] as const;
const VEHICLE_TYPES = ['motorcycle', 'bicycle', 'car', 'van', 'keke'] as const;

/** Customer-facing ride tiers (Nigeria/India-style okada + keke + package). */
const RIDE_SERVICE_TYPES = ['package', 'okada', 'keke'] as const;
type RideServiceType = (typeof RIDE_SERVICE_TYPES)[number];

const RIDER_VEHICLE_TYPES = ['motorcycle', 'keke', 'bicycle'] as const;

const RIDE_SERVICE_META: Record<
  RideServiceType,
  { rateKey: string; minKey: string; defaultRate: number; defaultMin: number; label: string; maxPassengers: number }
> = {
  package: {
    rateKey: 'delivery_price_per_km',
    minKey: 'delivery_min_fee',
    defaultRate: 4,
    defaultMin: 5,
    label: 'Package',
    maxPassengers: 0,
  },
  okada: {
    rateKey: 'okada_price_per_km',
    minKey: 'okada_min_fee',
    defaultRate: 3.5,
    defaultMin: 6,
    label: 'Okada',
    maxPassengers: 2,
  },
  keke: {
    rateKey: 'keke_price_per_km',
    minKey: 'keke_min_fee',
    defaultRate: 2.5,
    defaultMin: 5,
    label: 'Keke',
    maxPassengers: 4,
  },
};

function normalizeRideServiceType(value: unknown): RideServiceType {
  const s = String(value ?? 'package').trim().toLowerCase();
  if (s === 'courier' || s === 'delivery' || s === 'package') return 'package';
  if (s === 'okada' || s === 'bike' || s === 'motorbike' || s === 'ride') return 'okada';
  if (s === 'keke' || s === 'tricycle' || s === 'napep' || s === 'auto' || s === 'rickshaw') {
    return 'keke';
  }
  return (RIDE_SERVICE_TYPES as readonly string[]).includes(s) ? (s as RideServiceType) : 'package';
}

function normalizeRiderVehicleType(value: unknown): string {
  const s = String(value ?? 'motorcycle').trim().toLowerCase();
  if (s === 'okada' || s === 'motorbike') return 'motorcycle';
  if (s === 'keke' || s === 'tricycle' || s === 'napep' || s === 'auto') return 'keke';
  if ((RIDER_VEHICLE_TYPES as readonly string[]).includes(s)) return s;
  return 'motorcycle';
}

/** Which online riders can take a given service (Gokada-style matching). */
function riderServesService(riderVehicle: string | null | undefined, service: RideServiceType): boolean {
  const v = normalizeRiderVehicleType(riderVehicle);
  if (service === 'package') return v === 'motorcycle' || v === 'bicycle';
  if (service === 'okada') return v === 'motorcycle';
  if (service === 'keke') return v === 'keke';
  return false;
}

function rideServiceSqlFilter(service: RideServiceType): string {
  if (service === 'okada') {
    return `AND COALESCE(u.rider_vehicle_type, 'motorcycle') IN ('motorcycle')`;
  }
  if (service === 'keke') {
    return `AND COALESCE(u.rider_vehicle_type, 'motorcycle') = 'keke'`;
  }
  return `AND COALESCE(u.rider_vehicle_type, 'motorcycle') IN ('motorcycle', 'bicycle')`;
}

async function getRideServiceRate(service: RideServiceType): Promise<number> {
  const meta = RIDE_SERVICE_META[service];
  const raw = await getSetting(meta.rateKey);
  const parsed = parseFloat(raw || '');
  return Math.max(0.01, Number.isFinite(parsed) && parsed > 0 ? parsed : meta.defaultRate);
}

async function getRideServiceMinFee(service: RideServiceType): Promise<number> {
  const meta = RIDE_SERVICE_META[service];
  const raw = await getSetting(meta.minKey);
  const parsed = parseFloat(raw || '');
  return Math.max(0, Number.isFinite(parsed) && parsed >= 0 ? parsed : meta.defaultMin);
}

type RidePromotionRow = {
  id: string;
  name: string;
  code: string | null;
  service_types: string;
  customer_discount_percent: number;
  customer_discount_fixed: number;
  rider_bonus_amount: number;
  target_region: string | null;
  enabled: boolean;
  starts_at: string | null;
  ends_at: string | null;
  redemption_count: number;
  max_redemptions: number | null;
  announced_at?: string | null;
};

let ridePromotionsSchemaReady = false;

async function ensureRidePromotionsSchema() {
  if (ridePromotionsSchemaReady) return;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS ride_promotions (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      name VARCHAR(120) NOT NULL,
      code VARCHAR(40),
      service_types TEXT NOT NULL DEFAULT 'okada,keke,package',
      customer_discount_percent DECIMAL(5,2) NOT NULL DEFAULT 0,
      customer_discount_fixed DECIMAL(10,2) NOT NULL DEFAULT 0,
      rider_bonus_amount DECIMAL(10,2) NOT NULL DEFAULT 0,
      target_region VARCHAR(120),
      enabled BOOLEAN NOT NULL DEFAULT true,
      starts_at TIMESTAMPTZ,
      ends_at TIMESTAMPTZ,
      redemption_count INT NOT NULL DEFAULT 0,
      max_redemptions INT,
      created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    ALTER TABLE orders ADD COLUMN IF NOT EXISTS promotion_id UUID;
    ALTER TABLE orders ADD COLUMN IF NOT EXISTS promotion_discount DECIMAL(10,2) NOT NULL DEFAULT 0;
    ALTER TABLE orders ADD COLUMN IF NOT EXISTS rider_bonus_amount DECIMAL(10,2) NOT NULL DEFAULT 0;
    ALTER TABLE ride_promotions ADD COLUMN IF NOT EXISTS announced_at TIMESTAMPTZ;
  `);
  ridePromotionsSchemaReady = true;
}

function promotionCoversService(promo: RidePromotionRow, service: RideServiceType): boolean {
  const types = String(promo.service_types || '')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
  return types.length === 0 || types.includes(service);
}

function promotionCoversRegion(promo: RidePromotionRow, region?: string | null): boolean {
  const target = String(promo.target_region || '').trim();
  if (!target) return true;
  return String(region || '').trim().toLowerCase() === target.toLowerCase();
}

function promotionIsActiveNow(promo: RidePromotionRow, now = new Date()): boolean {
  if (!promo.enabled) return false;
  if (promo.max_redemptions != null && promo.redemption_count >= promo.max_redemptions) return false;
  if (promo.starts_at) {
    const start = new Date(promo.starts_at);
    if (!Number.isNaN(start.getTime()) && now < start) return false;
  }
  if (promo.ends_at) {
    const end = new Date(promo.ends_at);
    if (!Number.isNaN(end.getTime()) && now > end) return false;
  }
  return true;
}

async function findActiveRidePromotion(options: {
  service: RideServiceType;
  region?: string | null;
  code?: string | null;
}): Promise<RidePromotionRow | null> {
  await ensureRidePromotionsSchema();
  const code = String(options.code || '').trim().toUpperCase();
  if (code) {
    const byCode = await pool.query(
      `SELECT * FROM ride_promotions WHERE UPPER(COALESCE(code, '')) = $1 LIMIT 1`,
      [code]
    );
    const promo = byCode.rows[0] as RidePromotionRow | undefined;
    if (
      promo &&
      promotionIsActiveNow(promo) &&
      promotionCoversService(promo, options.service) &&
      promotionCoversRegion(promo, options.region)
    ) {
      return promo;
    }
    return null;
  }
  const result = await pool.query(
    `SELECT * FROM ride_promotions WHERE enabled = true ORDER BY updated_at DESC LIMIT 50`
  );
  for (const row of result.rows as RidePromotionRow[]) {
    if (
      promotionIsActiveNow(row) &&
      promotionCoversService(row, options.service) &&
      promotionCoversRegion(row, options.region)
    ) {
      return row;
    }
  }
  return null;
}

function applyPromotionToFee(fee: number, promo: RidePromotionRow): { fee: number; discount: number } {
  let next = fee;
  const pct = Math.max(0, Math.min(100, Number(promo.customer_discount_percent) || 0));
  const fixed = Math.max(0, Number(promo.customer_discount_fixed) || 0);
  if (pct > 0) next = next * (1 - pct / 100);
  if (fixed > 0) next = Math.max(0, next - fixed);
  next = Math.round(next * 100) / 100;
  return { fee: next, discount: Math.round((fee - next) * 100) / 100 };
}

function ridePromotionForClient(promo: RidePromotionRow | null) {
  if (!promo) return null;
  return {
    id: promo.id,
    name: promo.name,
    code: promo.code,
    service_types: promo.service_types,
    customer_discount_percent: Number(promo.customer_discount_percent) || 0,
    customer_discount_fixed: Number(promo.customer_discount_fixed) || 0,
    rider_bonus_amount: Number(promo.rider_bonus_amount) || 0,
    target_region: promo.target_region,
    enabled: promo.enabled,
    starts_at: promo.starts_at,
    ends_at: promo.ends_at,
    redemption_count: promo.redemption_count,
    max_redemptions: promo.max_redemptions,
    announced_at: promo.announced_at ?? null,
  };
}

function normalizeVehicleStatus(value: unknown): string | null {
  if (value == null || value === '') return null;
  const s = String(value).trim().toLowerCase();
  return (VEHICLE_STATUSES as readonly string[]).includes(s) ? s : null;
}

function normalizeVehicleType(value: unknown): string | null {
  if (value == null || value === '') return null;
  const s = String(value).trim().toLowerCase();
  return (VEHICLE_TYPES as readonly string[]).includes(s) ? s : null;
}

function vehicleRowForClient(row: Record<string, unknown>) {
  return {
    id: row.id,
    owner_id: row.owner_id,
    plate_number: row.plate_number,
    make: row.make ?? null,
    model: row.model ?? null,
    year: row.year != null ? Number(row.year) : null,
    color: row.color ?? null,
    vehicle_type: row.vehicle_type ?? 'motorcycle',
    status: row.status ?? 'active',
    assigned_rider_id: row.assigned_rider_id ?? null,
    assigned_rider_name: row.assigned_rider_name ?? null,
    assigned_rider_phone: row.assigned_rider_phone ?? null,
    notes: row.notes ?? null,
    created_at: row.created_at,
    updated_at: row.updated_at,
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

/** Transaction pooler (6543) needs pgbouncer=true so node-pg avoids prepared statements. */
function normalizeDatabaseUrl(raw: string | undefined): string {
  if (!raw?.trim()) return '';
  const url = raw.trim();
  try {
    const parsed = new URL(url.replace(/^postgresql:\/\//i, 'postgres://'));
    const port = parsed.port || '5432';
    if (port === '6543' && !parsed.searchParams.has('pgbouncer')) {
      parsed.searchParams.set('pgbouncer', 'true');
      return parsed.toString().replace(/^postgres:\/\//i, 'postgresql://');
    }
  } catch {
    /* keep original */
  }
  return url;
}

function resolveDbSsl(): false | { rejectUnauthorized: boolean } {
  const url = process.env.DATABASE_URL || '';
  if (process.env.PG_SSL === 'false') return false;
  if (process.env.PG_SSL === 'true' || url.includes('supabase.com')) {
    return { rejectUnauthorized: false };
  }
  return false;
}

function assertProductionConfig() {
  if (process.env.NODE_ENV !== 'production') return;
  const missing: string[] = [];
  if (!process.env.JWT_SECRET?.trim()) missing.push('JWT_SECRET');
  if (!process.env.DATABASE_URL?.trim()) missing.push('DATABASE_URL');
  if (missing.length) {
    console.error(`FATAL: missing required production env: ${missing.join(', ')}`);
    process.exit(1);
  }
  if ((process.env.JWT_SECRET?.length ?? 0) < 24) {
    console.warn('[config] JWT_SECRET is short — use a long random value in production');
  }
}

const pool = new Pool({
  connectionString: normalizeDatabaseUrl(process.env.DATABASE_URL),
  ssl: resolveDbSsl(),
  max: Math.min(20, Math.max(2, Number(process.env.PG_POOL_MAX) || 10)),
  idleTimeoutMillis: Number(process.env.PG_IDLE_TIMEOUT_MS) || 30_000,
  connectionTimeoutMillis: Number(process.env.PG_CONNECT_TIMEOUT_MS) || 10_000,
});

pool.on('error', (err) => {
  console.error('[pg] unexpected pool error:', err.message);
});

function dbConnectionDiagnostics(): {
  pooler: boolean;
  port: string | null;
  supabaseRegion: string | null;
  renderRegion: string | null;
  regionAligned: boolean | null;
  useTransactionPooler: boolean;
} {
  const raw = process.env.DATABASE_URL || '';
  let host = '';
  let port = '';
  try {
    const u = new URL(raw.replace(/^postgresql:\/\//, 'postgres://'));
    host = u.hostname;
    port = u.port || '5432';
  } catch {
    return {
      pooler: false,
      port: null,
      supabaseRegion: null,
      renderRegion: process.env.RENDER_REGION || null,
      regionAligned: null,
      useTransactionPooler: false,
    };
  }
  const pooler = host.includes('pooler.supabase.com');
  const supabaseRegion = host.match(/aws-\d+-([a-z]+-[a-z]+-\d+)/)?.[1] ?? null;
  const renderRegion = process.env.RENDER_REGION || null;
  let regionAligned: boolean | null = null;
  if (renderRegion && supabaseRegion) {
    const renderIsUs = ['oregon', 'ohio', 'virginia'].includes(renderRegion);
    const renderIsEu = renderRegion === 'frankfurt';
    const dbIsUs = supabaseRegion.startsWith('us-');
    const dbIsEu = supabaseRegion.startsWith('eu-');
    regionAligned = (renderIsUs && dbIsUs) || (renderIsEu && dbIsEu);
  }
  return {
    pooler,
    port,
    supabaseRegion,
    renderRegion,
    regionAligned,
    useTransactionPooler: pooler && port === '6543',
  };
}

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

// Helper to get system settings from DB (60s in-memory cache)
const SETTING_CACHE_MS = 60_000;
const settingCache = new Map<string, { value: string | null; expires: number }>();

async function getSettings(keys: string[]): Promise<Record<string, string | null>> {
  const result: Record<string, string | null> = {};
  const missing: string[] = [];
  const now = Date.now();
  for (const key of keys) {
    const cached = settingCache.get(key);
    if (cached && now < cached.expires) {
      result[key] = cached.value;
    } else {
      missing.push(key);
    }
  }
  if (missing.length) {
    try {
      const q = await pool.query(
        'SELECT key, value FROM system_settings WHERE key = ANY($1)',
        [missing]
      );
      const found = new Set<string>();
      for (const row of q.rows) {
        result[row.key] = row.value;
        settingCache.set(row.key, { value: row.value, expires: now + SETTING_CACHE_MS });
        found.add(row.key);
      }
      for (const key of missing) {
        if (!found.has(key)) {
          result[key] = null;
          settingCache.set(key, { value: null, expires: now + SETTING_CACHE_MS });
        }
      }
    } catch (err) {
      console.error('Error fetching settings batch:', err);
      for (const key of missing) result[key] = null;
    }
  }
  return result;
}

async function getSetting(key: string) {
  const cached = settingCache.get(key);
  if (cached && Date.now() < cached.expires) return cached.value;
  try {
    const result = await pool.query('SELECT value FROM system_settings WHERE key = $1', [key]);
    const value = result.rows[0]?.value ?? null;
    settingCache.set(key, { value, expires: Date.now() + SETTING_CACHE_MS });
    return value;
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
  settingCache.delete(key);
}

function parseOptionalPositiveAmount(raw: string | null | undefined): number | null {
  if (raw == null || String(raw).trim() === '') return null;
  const n = parseFloat(String(raw));
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) / 100 : null;
}

async function getGlobalDeliveryBounds(): Promise<{ min: number | null; max: number | null }> {
  const minRaw = await getSetting('delivery_min_fee');
  const maxRaw = await getSetting('delivery_max_fee');
  return {
    min: parseOptionalPositiveAmount(minRaw),
    max: parseOptionalPositiveAmount(maxRaw),
  };
}

function applyDeliveryFeeCaps(
  feeFromDistance: number,
  zone: { min_price?: unknown; max_price?: unknown } | null,
  globalBounds: { min: number | null; max: number | null }
): number {
  let fee = feeFromDistance;
  const minCap =
    zone && Number.isFinite(Number(zone.min_price)) && Number(zone.min_price) > 0
      ? Number(zone.min_price)
      : globalBounds.min;
  const maxCap =
    zone?.max_price != null && Number.isFinite(Number(zone.max_price))
      ? Number(zone.max_price)
      : globalBounds.max;
  if (minCap != null) fee = Math.max(fee, minCap);
  if (maxCap != null) fee = Math.min(fee, maxCap);
  return Math.round(fee * 100) / 100;
}

function moneyRound(n: number): number {
  return Math.round(n * 100) / 100;
}

/** Physical cash collected on delivery — audit only, not spendable wallet money. */
const COD_WALLET_REFERENCE_SQL = `(reference LIKE 'COD collected%' OR reference LIKE 'COD vendor share%')`;

/** Paystack/MoMo commission lines are audit-only; they do not change spendable wallet funds. */
const EXTERNAL_COMMISSION_REFERENCE_SQL = `(reference LIKE 'MoMo/card commission%')`;

type DbClient = { query: typeof pool.query };

function isCodLedgerReference(reference: unknown): boolean {
  const ref = String(reference ?? '');
  return ref.startsWith('COD collected') || ref.startsWith('COD vendor share');
}

/** Net COD ledger entries still on file (historical deliveries credited balance incorrectly). */
async function getRiderCodLedgerNet(riderId: string, client: DbClient = pool): Promise<number> {
  const r = await client.query(
    `SELECT COALESCE(SUM(amount), 0)::float AS cod_net
     FROM wallet_transactions
     WHERE user_id = $1 AND ${COD_WALLET_REFERENCE_SQL}`,
    [riderId]
  );
  return moneyRound(parseFloat(String(r.rows[0]?.cod_net ?? 0)));
}

/** Rider wallet funds that can pay commission or be withdrawn (excludes COD cash in pocket). */
async function getRiderSpendableBalance(riderId: string, client: DbClient = pool): Promise<number> {
  const countRes = await client.query(
    'SELECT COUNT(*)::int AS n FROM wallet_transactions WHERE user_id = $1',
    [riderId]
  );
  const hasLedger = parseInt(String(countRes.rows[0]?.n ?? 0), 10) > 0;

  if (hasLedger) {
    const ledgerRes = await client.query(
      `SELECT COALESCE(SUM(amount), 0)::float AS spendable
       FROM wallet_transactions
       WHERE user_id = $1
         AND NOT ${COD_WALLET_REFERENCE_SQL}
         AND NOT ${EXTERNAL_COMMISSION_REFERENCE_SQL}`,
      [riderId]
    );
    return moneyRound(Math.max(0, parseFloat(String(ledgerRes.rows[0]?.spendable ?? 0))));
  }

  // Fallback for legacy accounts with balance but no transaction rows yet
  const balRes = await client.query('SELECT balance FROM users WHERE id = $1', [riderId]);
  const raw = parseFloat(String(balRes.rows[0]?.balance ?? 0));
  const codNet = await getRiderCodLedgerNet(riderId, client);
  return moneyRound(Math.max(0, raw - codNet));
}

async function emitWalletUpdated(userId: string, role?: string, client: DbClient = pool) {
  const balance =
    role === 'rider' ? await getRiderSpendableBalance(userId, client) : await (async () => {
      const r = await client.query('SELECT balance FROM users WHERE id = $1', [userId]);
      return parseFloat(String(r.rows[0]?.balance ?? 0));
    })();
  io.to(userId).emit('wallet:updated', { balance });
}

/** Ghana calendar date (GMT, no DST). */
function ghanaDateOnly(d = new Date()): string {
  return d.toISOString().slice(0, 10);
}

/** Commission for trips on `dateStr` is due by 08:00 Ghana time the next day. */
function commissionDueAt(dateStr: string): Date {
  const d = new Date(`${dateStr}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() + 1);
  d.setUTCHours(8, 0, 0, 0);
  return d;
}

async function getCommissionSettings() {
  const totalPercent = Math.max(
    0,
    parseFloat((await getSetting('commission_percent')) || '10') || 10
  );
  const insurancePercent = Math.max(
    0,
    parseFloat((await getSetting('commission_insurance_percent')) || '3') || 3
  );
  const platformPercent = Math.max(
    0,
    parseFloat((await getSetting('commission_platform_percent')) || '7') || 7
  );
  return { totalPercent, insurancePercent, platformPercent };
}

async function refreshRiderSettlementStatus(riderId?: string) {
  if (riderId) {
    await pool.query(
      `UPDATE rider_daily_settlements SET
        status = CASE
          WHEN amount_paid >= commission_total - 0.01 THEN 'paid'
          WHEN due_at < NOW() THEN 'overdue'
          ELSE 'open'
        END,
        updated_at = CURRENT_TIMESTAMP
       WHERE rider_id = $1 AND status != 'paid'`,
      [riderId]
    );
    return;
  }
  await pool.query(
    `UPDATE rider_daily_settlements SET
      status = CASE
        WHEN amount_paid >= commission_total - 0.01 THEN 'paid'
        WHEN due_at < NOW() THEN 'overdue'
        ELSE 'open'
      END,
      updated_at = CURRENT_TIMESTAMP
     WHERE status != 'paid'`
  );
}

async function riderHasOverdueCommission(riderId: string): Promise<boolean> {
  await refreshRiderSettlementStatus(riderId);
  const r = await pool.query(
    `SELECT 1 FROM rider_daily_settlements
     WHERE rider_id = $1
       AND commission_total > amount_paid + 0.01
       AND due_at < NOW()
     LIMIT 1`,
    [riderId]
  );
  return r.rows.length > 0;
}

async function recordTripCommission(order: any) {
  if (!order?.rider_id) return;
  try {
    await recordTripCommissionInner(order);
  } catch (err) {
    console.error('[recordTripCommission] failed (delivery still complete):', err);
  }
}

async function recordTripCommissionInner(order: any) {
  const settings = await getCommissionSettings();
  const total = parseFloat(order.total);
  if (!Number.isFinite(total) || total <= 0) return;

  const commissionTotal = moneyRound((total * settings.totalPercent) / 100);
  const insuranceAmount = moneyRound((total * settings.insurancePercent) / 100);
  const platformAmount = moneyRound((total * settings.platformPercent) / 100);
  const settlementDate = ghanaDateOnly();
  const dueAt = commissionDueAt(settlementDate);
  const isCod = order.payment_status !== 'paid';

  await pool.query(
    `INSERT INTO order_commissions (
      order_id, rider_id, order_total, commission_total, insurance_amount, platform_amount, settlement_date
    ) VALUES ($1, $2, $3, $4, $5, $6, $7)
    ON CONFLICT (order_id) DO NOTHING`,
    [
      order.id,
      order.rider_id,
      total,
      commissionTotal,
      insuranceAmount,
      platformAmount,
      settlementDate,
    ]
  );

  if (insuranceAmount > 0) {
    await pool.query(
      `INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)`,
      [
        null,
        insuranceAmount,
        'commission',
        `Insurance pool · Order #${order.id.slice(0, 8)} (${settings.insurancePercent}%)`,
      ]
    );
  }
  if (platformAmount > 0) {
    await pool.query(
      `INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)`,
      [
        null,
        platformAmount,
        'commission',
        `BytzGo · Order #${order.id.slice(0, 8)} (${settings.platformPercent}%)`,
      ]
    );
  }

  if (isCod && commissionTotal > 0) {
    await pool.query(
      `INSERT INTO rider_daily_settlements (
        rider_id, settlement_date, commission_total, insurance_total, platform_total, due_at, status
      ) VALUES ($1, $2, $3, $4, $5, $6, 'open')
      ON CONFLICT (rider_id, settlement_date) DO UPDATE SET
        commission_total = rider_daily_settlements.commission_total + EXCLUDED.commission_total,
        insurance_total = rider_daily_settlements.insurance_total + EXCLUDED.insurance_total,
        platform_total = rider_daily_settlements.platform_total + EXCLUDED.platform_total,
        due_at = EXCLUDED.due_at,
        updated_at = CURRENT_TIMESTAMP`,
      [
        order.rider_id,
        settlementDate,
        commissionTotal,
        insuranceAmount,
        platformAmount,
        dueAt,
      ]
    );
  }
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
  const globalBounds = await getGlobalDeliveryBounds();
  const surge = await getSurgePricingState();
  const pricePerKm = surge.surge_active
    ? Math.round(baseRate * surge.multiplier * 100) / 100
    : baseRate;
  const zonesResult = await pool.query(
    `SELECT id, name, region, min_price, max_price, is_active
     FROM delivery_zones
     ORDER BY region, name`
  );
  const zones = zonesResult.rows.map((z) => ({
    id: z.id,
    name: z.name,
    region: z.region,
    min_price: Number(z.min_price),
    max_price: z.max_price != null ? Number(z.max_price) : null,
    is_active: z.is_active !== false,
  }));
  return {
    price_per_km: pricePerKm,
    base_price_per_km: baseRate,
    min_fee: globalBounds.min,
    max_fee: globalBounds.max,
    zones,
    surge_enabled: surge.enabled,
    surge_multiplier: surge.multiplier,
    surge_start_time: surge.start_time,
    surge_end_time: surge.end_time,
    surge_active: surge.surge_active,
    ghana_time: surge.ghana_time,
    ride_services: await Promise.all(
      RIDE_SERVICE_TYPES.map(async (id) => ({
        id,
        label: RIDE_SERVICE_META[id].label,
        price_per_km: await getRideServiceRate(id),
        min_fee: await getRideServiceMinFee(id),
        max_passengers: RIDE_SERVICE_META[id].maxPassengers,
      }))
    ),
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
  const s = await getSettings([
    'surge_enabled',
    'surge_multiplier',
    'surge_start_time',
    'surge_end_time',
  ]);
  const enabled = s.surge_enabled === 'true';
  const multiplier = Math.max(1, parseFloat(s.surge_multiplier || '1.25') || 1.25);
  const startStr = s.surge_start_time || '17:00';
  const endStr = s.surge_end_time || '21:00';
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
  destinationRegion?: string | null,
  serviceType: RideServiceType = 'package',
  options?: { promo_code?: string | null; region?: string | null }
): Promise<{
  distance_km: number;
  delivery_fee: number;
  price_per_km: number;
  zone: string | null;
  base_delivery_fee: number;
  surge_active: boolean;
  surge_multiplier: number;
  service_type: RideServiceType;
  promotion_id: string | null;
  promotion_discount: number;
  rider_bonus_amount: number;
  promotion: ReturnType<typeof ridePromotionForClient>;
}> {
  const distance_km = haversineDistanceKm(pickupLat, pickupLng, destLat, destLng);
  const globalRate = await getRideServiceRate(serviceType);
  const serviceMin = await getRideServiceMinFee(serviceType);
  const globalBounds = await getGlobalDeliveryBounds();
  const effectiveBounds = {
    min: Math.max(globalBounds.min, serviceMin),
    max: globalBounds.max,
  };

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

  const feeFromDistance = Math.round(distance_km * globalRate * 100) / 100;
  const base = applyDeliveryFeeCaps(feeFromDistance, zone, effectiveBounds);
  const { fee, surge } = await applySurgeToFee(base);
  const effectiveRate = surge.surge_active
    ? Math.round(globalRate * surge.multiplier * 100) / 100
    : globalRate;
  const zoneMin =
    zone && Number.isFinite(Number(zone.min_price)) && Number(zone.min_price) > 0
      ? Math.max(Number(zone.min_price), serviceMin)
      : effectiveBounds.min;
  const zoneMax =
    zone?.max_price != null && Number.isFinite(Number(zone.max_price))
      ? Number(zone.max_price)
      : globalBounds.max;

  const region = options?.region ?? destinationRegion ?? pickupRegion ?? null;
  const promo = await findActiveRidePromotion({
    service: serviceType,
    region,
    code: options?.promo_code,
  });
  const discounted = promo ? applyPromotionToFee(fee, promo) : { fee, discount: 0 };

  return {
    distance_km,
    delivery_fee: discounted.fee,
    price_per_km: effectiveRate,
    zone: zone?.name ?? null,
    base_delivery_fee: base,
    fee_from_distance_km: feeFromDistance,
    zone_min_price: zoneMin,
    zone_max_price: zoneMax,
    surge_active: surge.surge_active,
    surge_multiplier: surge.multiplier,
    service_type: serviceType,
    promotion_id: promo?.id ?? null,
    promotion_discount: discounted.discount,
    rider_bonus_amount: promo ? Number(promo.rider_bonus_amount) || 0 : 0,
    promotion: ridePromotionForClient(promo),
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
    throw new Error('Mobile Money and card payments are not configured. Contact support.');
  }

  const publicKey = await getPaystackPublicKey();
  if (publicKey && !paystackKeysMatch(publicKey, secretKey)) {
    throw new Error('Payment configuration error. Contact support.');
  }

  try {
    const response = await axios.get(
      `https://api.paystack.co/transaction/verify/${encodeURIComponent(reference)}`,
      { headers: { Authorization: `Bearer ${secretKey}` } }
    );

    if (!response.data?.status) {
      throw new Error(response.data?.message || 'Could not verify this payment');
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

async function initializePaystackPayment(
  amountGhs: number,
  user: { id: string; email?: string; phone?: string },
  metadata: Record<string, unknown>
) {
  const secretKey = await getPaystackSecretKey();
  if (!secretKey) {
    throw new Error('Mobile Money and card payments are not available. Contact support.');
  }

  const publicKey = await getPaystackPublicKey();
  if (publicKey && !paystackKeysMatch(publicKey, secretKey)) {
    throw new Error('Payment configuration error. Contact support.');
  }

  const amount = Math.round(amountGhs * 100);
  if (!Number.isFinite(amount) || amount < 100) {
    throw new Error('Minimum payment is ₵1');
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
      metadata: { user_id: user.id, ...metadata },
    },
    { headers: { Authorization: `Bearer ${secretKey}` } }
  );

  if (!response.data?.status) {
    throw new Error(response.data?.message || 'Could not start payment');
  }

  const data = response.data.data;
  if (!data?.authorization_url || !data?.reference) {
    throw new Error('Could not start payment. Try again.');
  }

  return {
    reference: data.reference as string,
    authorizationUrl: data.authorization_url as string,
    accessCode: data.access_code as string | undefined,
    amountGhs,
  };
}

async function initializePaystackTopup(amountGhs: number, user: { id: string; email?: string; phone?: string }) {
  return initializePaystackPayment(amountGhs, user, { type: 'wallet_topup' });
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
        apple_id TEXT,
        cover_image TEXT,
        address TEXT,
        lat DOUBLE PRECISION,
        lng DOUBLE PRECISION,
        role TEXT NOT NULL CHECK (role IN ('customer', 'vendor', 'rider', 'admin', 'owner')),
        balance DECIMAL(10,2) DEFAULT 0.00,
        status TEXT DEFAULT 'active',
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      -- Add columns if they don't exist (for existing databases)
      DO $$ BEGIN
        ALTER TABLE users ADD COLUMN IF NOT EXISTS phone TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS google_id TEXT;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_id TEXT;
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

      CREATE TABLE IF NOT EXISTS order_commissions (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        order_id UUID NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
        rider_id UUID NOT NULL REFERENCES users(id),
        order_total DECIMAL(10,2) NOT NULL,
        commission_total DECIMAL(10,2) NOT NULL,
        insurance_amount DECIMAL(10,2) NOT NULL,
        platform_amount DECIMAL(10,2) NOT NULL,
        settlement_date DATE NOT NULL,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE TABLE IF NOT EXISTS rider_daily_settlements (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        rider_id UUID NOT NULL REFERENCES users(id),
        settlement_date DATE NOT NULL,
        commission_total DECIMAL(10,2) NOT NULL DEFAULT 0,
        insurance_total DECIMAL(10,2) NOT NULL DEFAULT 0,
        platform_total DECIMAL(10,2) NOT NULL DEFAULT 0,
        amount_paid DECIMAL(10,2) NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'open',
        due_at TIMESTAMP WITH TIME ZONE NOT NULL,
        paid_at TIMESTAMP WITH TIME ZONE,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(rider_id, settlement_date)
      );

      CREATE INDEX IF NOT EXISTS rider_daily_settlements_rider_due_idx
        ON rider_daily_settlements (rider_id, due_at);

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
        created_by_role TEXT NOT NULL CHECK (created_by_role IN ('customer', 'vendor', 'rider', 'admin', 'owner')),
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

      CREATE INDEX IF NOT EXISTS idx_dispatch_offers_order_status
        ON order_dispatch_offers (order_id, status, expires_at);

      CREATE INDEX IF NOT EXISTS idx_users_rider_online
        ON users (id)
        WHERE role = 'rider' AND status = 'active' AND is_online = true;

      CREATE INDEX IF NOT EXISTS idx_rider_locations_updated
        ON rider_locations (updated_at DESC);

      DO $$ BEGIN
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS dispatch_wave INTEGER;
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS offer_expires_at TIMESTAMP WITH TIME ZONE;
      EXCEPTION WHEN others THEN NULL;
      END $$;

      CREATE TABLE IF NOT EXISTS vehicles (
        id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        owner_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
        plate_number TEXT NOT NULL,
        make TEXT,
        model TEXT,
        year INTEGER,
        color TEXT,
        vehicle_type TEXT NOT NULL DEFAULT 'motorcycle',
        status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'maintenance', 'retired')),
        assigned_rider_id UUID REFERENCES users(id) ON DELETE SET NULL,
        notes TEXT,
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        UNIQUE (owner_id, plate_number)
      );

      CREATE INDEX IF NOT EXISTS idx_vehicles_owner_id ON vehicles(owner_id, updated_at DESC);
      CREATE INDEX IF NOT EXISTS idx_vehicles_assigned_rider ON vehicles(assigned_rider_id)
        WHERE assigned_rider_id IS NOT NULL;
    `);

    await pool.query(`
      DO $$ BEGIN
        ALTER TABLE users DROP CONSTRAINT IF EXISTS users_role_check;
        ALTER TABLE users ADD CONSTRAINT users_role_check
          CHECK (role IN ('customer', 'vendor', 'rider', 'admin', 'owner'));
      EXCEPTION WHEN others THEN NULL;
      END $$;
      DO $$ BEGIN
        ALTER TABLE support_tickets DROP CONSTRAINT IF EXISTS support_tickets_created_by_role_check;
        ALTER TABLE support_tickets ADD CONSTRAINT support_tickets_created_by_role_check
          CHECK (created_by_role IN ('customer', 'vendor', 'rider', 'admin', 'owner'));
      EXCEPTION WHEN others THEN NULL;
      END $$;
    `);

    await pool.query(`
      DO $$ BEGIN
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS service_type TEXT NOT NULL DEFAULT 'package';
        ALTER TABLE orders ADD COLUMN IF NOT EXISTS passenger_count INTEGER NOT NULL DEFAULT 1;
        ALTER TABLE users ADD COLUMN IF NOT EXISTS rider_vehicle_type TEXT DEFAULT 'motorcycle';
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
      INSERT INTO system_settings (key, value) VALUES ('delivery_min_fee', '')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('delivery_max_fee', '')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('commission_percent', '10')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('commission_insurance_percent', '3')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('commission_platform_percent', '7')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('surge_enabled', 'false')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('surge_multiplier', '1.5')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('surge_start_time', '17:00')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('surge_end_time', '21:00')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('okada_price_per_km', '3.5')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('okada_min_fee', '6')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('keke_price_per_km', '2.5')
      ON CONFLICT (key) DO NOTHING;
      INSERT INTO system_settings (key, value) VALUES ('keke_min_fee', '5')
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

if (process.env.NODE_ENV !== 'production') {
  initDb();
} else {
  console.log('Skipping initDb DDL in production (run migrations separately).');
}

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
  if (order?.status === 'scheduled') return false;
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

function parseScheduledTimeInput(raw: unknown): Date | null {
  if (raw == null || raw === '') return null;
  const d = new Date(String(raw));
  return Number.isNaN(d.getTime()) ? null : d;
}

function isFutureScheduled(scheduled: Date | null): boolean {
  if (!scheduled) return false;
  return scheduled.getTime() > Date.now() + 10 * 60 * 1000;
}

async function ensureDeliveryCode(orderId: string): Promise<string> {
  const existing = await pool.query('SELECT delivery_code FROM orders WHERE id = $1', [orderId]);
  const code = existing.rows[0]?.delivery_code;
  if (code) return String(code);
  const generated = generateDeliveryCode();
  await pool.query(
    `UPDATE orders SET delivery_code = $1, delivery_code_created_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $2`,
    [generated, orderId]
  );
  return generated;
}

async function activateDueScheduledOrders() {
  const due = await pool.query(
    `UPDATE orders SET status = 'ready', updated_at = CURRENT_TIMESTAMP
     WHERE status = 'scheduled' AND scheduled_time IS NOT NULL AND scheduled_time <= NOW()
     RETURNING *`
  );
  for (const order of due.rows) {
    broadcastOrderUpdated(order);
    if (isOfferableOrder(order)) void broadcastRideOfferToRiders(order);
  }
}

/** Close trips stuck at arrival (missing PIN / rider never completed). */
async function repairStaleTripsForCustomer(customerId: string) {
  const stale = await pool.query(
    `UPDATE orders SET status = 'delivered', updated_at = CURRENT_TIMESTAMP
     WHERE customer_id = $1
       AND status = 'arrived'
       AND updated_at < NOW() - INTERVAL '6 hours'
       AND (payment_status = 'paid' OR customer_payment_ack IS NOT NULL)
     RETURNING *`,
    [customerId]
  );
  for (const order of stale.rows) {
    try {
      await settleOrderPayment(order);
    } catch (e) {
      console.error('[repairStaleTrips] settlement failed:', order.id, e);
    }
    broadcastOrderUpdated(order);
  }
  await pool.query(
    `UPDATE orders SET status = 'cancelled', rider_id = NULL, updated_at = CURRENT_TIMESTAMP
     WHERE customer_id = $1
       AND status IN ('ready', 'pending', 'preparing')
       AND rider_id IS NULL
       AND created_at < NOW() - INTERVAL '3 days'`,
    [customerId]
  );
}

const deliveryCodeAttempts = new Map<string, { attempts: number; lockedUntil: number }>();

const TRIP_CONTACT_STATUSES = new Set(['pending', 'preparing', 'ready', 'picked_up', 'arrived']);

function tripAllowsContact(order: any): boolean {
  return Boolean(order?.rider_id) && TRIP_CONTACT_STATUSES.has(order.status);
}

/** Human-friendly name for chat, push, and UI (hides email stubs and broken placeholders). */
function displayUserName(
  raw: string | null | undefined,
  opts?: { role?: string | null; fallback?: string }
): string {
  const fallback = opts?.fallback ?? 'BytzGo user';
  let name = String(raw ?? '').trim();
  const role = opts?.role ?? null;

  const looksPlaceholder =
    !name ||
    /\$/.test(name) ||
    /^(user|sender|test|guest)(\d+)?$/i.test(name) ||
    /^user[a-f0-9]{6,}$/i.test(name);

  if (looksPlaceholder) {
    if (role === 'rider') return 'Your biker';
    if (role === 'customer') return 'Customer';
    if (role === 'admin') return 'BytzGo Support';
    if (role === 'vendor') return 'Shop partner';
    return fallback;
  }

  if (name.includes('@')) {
    name = name
      .split('@')[0]
      .replace(/[._-]+/g, ' ')
      .trim();
    if (!name || /^(user|sender)(\d+)?$/i.test(name)) {
      if (role === 'rider') return 'Your biker';
      if (role === 'customer') return 'Customer';
      return fallback;
    }
  }

  return name
    .split(/\s+/)
    .filter(Boolean)
    .map((w) => w.charAt(0).toUpperCase() + w.slice(1))
    .join(' ');
}

function formatOrderMessage(row: any, viewerId: string) {
  return {
    id: row.id,
    orderId: row.order_id,
    senderId: row.sender_id,
    senderName: displayUserName(row.sender_name, {
      role: row.sender_role,
      fallback: 'Trip contact',
    }),
    senderRole: row.sender_role || null,
    body: row.body,
    createdAt: row.created_at,
    isMine: row.sender_id === viewerId,
  };
}

const SUPPORT_CATEGORIES = new Set(['order', 'payment', 'account', 'delivery', 'shop', 'other']);
const SUPPORT_STATUSES = new Set(['open', 'pending', 'resolved', 'closed']);

function generateSupportDisplayId(): string {
  return `BYTZGO-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
}

/** User-facing case reference (legacy SUP-* rows are normalized). */
function formatSupportDisplayLabel(raw: string | null | undefined): string {
  const id = String(raw ?? '').trim();
  if (/^bytzgo(\s|#)/i.test(id)) return id.replace(/^bytzgo/i, 'BytzGo');
  const code = id.replace(/^(SUP|BYTZGO)-/i, '');
  return code ? `BytzGo #${code}` : 'BytzGo Support';
}

function formatSupportMessage(row: any, viewerId: string) {
  return {
    id: row.id,
    ticketId: row.ticket_id,
    senderId: row.sender_id,
    senderName: displayUserName(row.sender_name, {
      role: row.sender_role,
      fallback: 'BytzGo Support',
    }),
    senderRole: row.sender_role || null,
    body: row.body,
    createdAt: row.created_at,
    isMine: row.sender_id === viewerId,
  };
}

function formatSupportTicket(row: any) {
  return {
    id: row.id,
    displayId: formatSupportDisplayLabel(row.display_id),
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

function buildSupportReplySmsBody(displayIdRaw: string, messageBody: string): string {
  const ref = formatSupportDisplayLabel(displayIdRaw);
  const snippet = String(messageBody || '')
    .replace(/\s+/g, ' ')
    .trim();
  const max = 120;
  const text =
    snippet.length > max ? `${snippet.slice(0, Math.max(0, max - 1))}…` : snippet;
  return `BytzGo Support (${ref}): ${text || 'New reply'} — open Help & support in the app.`;
}

/** Text the ticket creator when BytzGo support (admin) replies. Best-effort; never throws. */
async function notifySupportClientSms(
  ticket: any,
  messageBody: string
): Promise<void> {
  if (process.env.SUPPORT_REPLY_SMS === 'false') return;
  const creatorId = ticket?.created_by;
  if (!creatorId) return;

  try {
    const userRes = await pool.query('SELECT phone FROM users WHERE id = $1', [creatorId]);
    const phone = userRes.rows[0]?.phone;
    if (!phone || !String(phone).trim()) {
      console.warn(`[support-sms] No phone on file for user ${creatorId}`);
      return;
    }
    if (!isValidGhanaPhone(phone)) {
      console.warn(`[support-sms] Invalid phone for user ${creatorId}`);
      return;
    }
    const smsBody = buildSupportReplySmsBody(ticket.display_id, messageBody);
    await sendSMS(phone, smsBody);
    console.info(`[support-sms] Sent reply SMS for ticket ${ticket.id}`);
  } catch (err: any) {
    console.warn('[support-sms] Failed:', err?.message || err);
  }
}

async function emitSupportMessage(ticket: any, messageRow: any, senderId: string) {
  const nameRes = await pool.query(
    'SELECT name, role FROM users WHERE id = $1',
    [senderId]
  );
  messageRow.sender_name = nameRes.rows[0]?.name;
  messageRow.sender_role = nameRes.rows[0]?.role;
  const senderRole = nameRes.rows[0]?.role;

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

  const body = String(messageRow.body || '');
  const senderName = displayUserName(nameRes.rows[0]?.name, {
    role: senderRole,
    fallback: 'BytzGo Support',
  });

  if (notifyIds.size > 0) {
    void sendPushToUserIds([...notifyIds], {
      title: `BytzGo Support · ${formatSupportDisplayLabel(ticket.display_id)}`,
      body: `${senderName}: ${body.length > 120 ? `${body.slice(0, 117)}…` : body}`,
      type: 'support-message',
      ticketId: ticket.id,
      channelId: 'support_updates',
      highPriority: true,
    });
  }

  if (
    senderRole === 'admin' &&
    ticket.created_by &&
    String(ticket.created_by) !== String(senderId)
  ) {
    void notifySupportClientSms(ticket, body);
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

type DriverTier = 'gold' | 'silver' | 'bronze' | 'new';

/**
 * Uber Eats / Bolt Food-style driver tier. The more stars a driver keeps
 * (across enough rated trips), the higher they climb toward Gold.
 */
function driverTier(avg: number | null, count: number): DriverTier {
  if (avg == null || !Number.isFinite(avg) || count < 3) return 'new';
  if (avg >= 4.8 && count >= 20) return 'gold';
  if (avg >= 4.5 && count >= 8) return 'silver';
  if (avg >= 4.0) return 'bronze';
  return 'new';
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

  // Driver rating + gold tier — visible to whoever can see the assigned rider.
  if (o.rider_id) {
    const avg = o.rider_avg_rating != null ? parseFloat(String(o.rider_avg_rating)) : null;
    const cnt = o.rider_rating_count != null ? parseInt(String(o.rider_rating_count), 10) || 0 : 0;
    o.riderAvgRating = avg;
    o.riderRatingCount = cnt;
    o.riderTier = driverTier(avg, cnt);
  }

  delete o.customer_phone;
  delete o.rider_phone;
  delete o.customer_name;
  delete o.rider_name;
  delete o.customer_avatar_url;
  delete o.customer_avg_rating;
  delete o.rider_avatar_url;
  delete o.rider_avg_rating;
  delete o.rider_rating_count;
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
  (SELECT ROUND(AVG(o3.rating)::numeric, 1) FROM orders o3
   WHERE o3.rider_id = ru.id AND o3.rating IS NOT NULL AND o3.rating > 0) AS rider_avg_rating,
  (SELECT COUNT(*)::int FROM orders o4
   WHERE o4.rider_id = ru.id AND o4.rating IS NOT NULL AND o4.rating > 0) AS rider_rating_count,
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
  const settings = await getCommissionSettings();
  const vendorSharePct = 0.8;

  if (isPaidOnline) {
    if (order.vendor_id) {
      const vendorAmount = moneyRound(total * vendorSharePct);
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
        order.delivery_fee && Number(order.delivery_fee) > 0
          ? Number(order.delivery_fee)
          : moneyRound((total * settings.totalPercent) / 100);
      const bonus = Number(order.rider_bonus_amount) || 0;
      const totalRiderCredit = moneyRound(riderAmount + bonus);
      const rRes = await pool.query(
        'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
        [totalRiderCredit, order.rider_id]
      );
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [order.rider_id, riderAmount, 'payment', `Order #${order.id.slice(0, 8)} delivery fee`]
      );
      if (bonus > 0) {
        await pool.query(
          'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
          [order.rider_id, bonus, 'bonus', `Promo bonus · Order #${order.id.slice(0, 8)}`]
        );
      }
      await emitWalletUpdated(order.rider_id, 'rider');
    }
    await recordTripCommission(order);
  } else if (order.rider_id) {
    const totalCollected = moneyRound(total);
    const vendorShare =
      order.vendor_id && String(order.vendor_id).trim()
        ? moneyRound(total * vendorSharePct)
        : 0;
    const shortId = order.id.slice(0, 8);
    const collectRef = `COD collected · Order #${shortId}`;

    const existing = await pool.query(
      `SELECT 1 FROM wallet_transactions WHERE user_id = $1 AND reference = $2 LIMIT 1`,
      [order.rider_id, collectRef]
    );
    if (!existing.rowCount) {
      // Audit trail only — cash stays with the rider; do not credit users.balance.
      await pool.query(
        'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
        [order.rider_id, totalCollected, 'payment', collectRef]
      );

      if (vendorShare > 0) {
        await pool.query(
          'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
          [
            order.rider_id,
            -vendorShare,
            'payment',
            `COD vendor share · Order #${shortId}`,
          ]
        );

        const vRes = await pool.query(
          'UPDATE users SET balance = balance + $1 WHERE id = $2 RETURNING balance',
          [vendorShare, order.vendor_id]
        );
        await pool.query(
          'INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)',
          [order.vendor_id, vendorShare, 'payment', `COD Order #${shortId} payment`]
        );
        io.to(order.vendor_id).emit('wallet:updated', {
          balance: parseFloat(vRes.rows[0].balance),
        });
      }
    }

    await recordTripCommission(order);
  }
}

/** Seconds a rider can accept after push/socket (aligned with app UI countdown). */
const OFFER_TTL_SEC = Math.min(
  120,
  Math.max(15, Number(process.env.DISPATCH_OFFER_TTL_SEC) || 30)
);
/** Offer 2 nearest riders on early waves for faster matching. */
function ridersPerWave(wave: number): number {
  return wave <= 3 ? 2 : 1;
}
/** Max sequential offers before giving up (each step = next nearest rider). */
const MAX_DISPATCH_WAVES = 15;
/** Max age for rider GPS row; profile lat/lng still used when socket GPS is stale. */
const LOCATION_MAX_AGE_MIN = 45;
/** Expanding pickup radius (km) as dispatch steps progress. */
const DISPATCH_RADIUS_KM_TIERS = [6, 12, 25] as const;
const NEARBY_RIDERS_MAX_KM = 6;
/** Start offering any online rider after this wave if nobody nearby. */
const EARLY_GLOBAL_FALLBACK_WAVE = 2;

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
async function getActiveRiderIds(
  region?: string | null,
  serviceType: RideServiceType = 'package'
): Promise<string[]> {
  const serviceFilter = rideServiceSqlFilter(serviceType);
  const norm = normalizeRegion(region);
  if (norm) {
    const regional = await pool.query(
      `SELECT id FROM users
       WHERE role = 'rider' AND status = 'active' AND is_online = true
       ${serviceFilter}
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
    `SELECT id FROM users WHERE role = 'rider' AND status = 'active' AND is_online = true ${serviceFilter}`
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

async function getAvailableOnlineRiders(
  riderIds: string[],
  limit: number
): Promise<NearbyRider[]> {
  if (!riderIds.length || limit <= 0) return [];
  const res = await pool.query(
    `SELECT u.id FROM users u
     WHERE u.id = ANY($1::uuid[])
     AND NOT EXISTS (
       SELECT 1 FROM orders busy
       WHERE busy.rider_id = u.id
       AND busy.status IN ('ready', 'picked_up', 'arrived')
     )
     LIMIT $2`,
    [riderIds, limit]
  );
  return res.rows.map((row: { id: string }) => ({ id: row.id, distanceKm: 0 }));
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
  useRegionFilter: boolean,
  serviceType: RideServiceType = 'package'
): Promise<NearbyRider[]> {
  const norm = normalizeRegion(region);
  const serviceFilter = rideServiceSqlFilter(serviceType);
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
            cos(radians($1)) * cos(radians(eff.lat)) * cos(radians(eff.lng) - radians($2))
            + sin(radians($1)) * sin(radians(eff.lat))
          ))
        )) AS distance_km
       FROM users u
       LEFT JOIN rider_locations rl ON rl.rider_id = u.id
       CROSS JOIN LATERAL (
         SELECT
           COALESCE(rl.lat, u.lat::double precision) AS lat,
           COALESCE(rl.lng, u.lng::double precision) AS lng
       ) eff
       WHERE u.role = 'rider' AND u.status = 'active' AND u.is_online = true
       AND eff.lat IS NOT NULL AND eff.lng IS NOT NULL
       AND ABS(eff.lat) > 0.001 AND ABS(eff.lng) > 0.001
       AND (
         rl.updated_at > NOW() - INTERVAL '1 minute' * $5
         OR (
           u.lat IS NOT NULL AND u.lng IS NOT NULL
           AND (rl.rider_id IS NULL OR rl.updated_at IS NULL
             OR rl.updated_at <= NOW() - INTERVAL '1 minute' * $5)
         )
       )
       AND (COALESCE(array_length($3::uuid[], 1), 0) = 0 OR NOT (u.id = ANY($3::uuid[])))
       AND NOT EXISTS (
         SELECT 1 FROM orders busy
         WHERE busy.rider_id = u.id
         AND busy.status IN ('ready', 'picked_up', 'arrived')
       )
       ${serviceFilter}
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
  maxRadiusKm: number = DISPATCH_RADIUS_KM_TIERS[0],
  serviceType: RideServiceType = 'package'
): Promise<NearbyRider[]> {
  let riders = await queryNearestActiveRiders(
    pickup,
    region,
    excludeRiderIds,
    limit,
    maxRadiusKm,
    true,
    serviceType
  );
  if (riders.length === 0 && normalizeRegion(region)) {
    riders = await queryNearestActiveRiders(
      pickup,
      region,
      excludeRiderIds,
      limit,
      maxRadiusKm,
      false,
      serviceType
    );
  }
  return riders;
}

async function emitOffersToRiders(order: any, candidates: NearbyRider[], wave: number) {
  const customerId = order?.customer_id ?? null;
  // Candidates already come from online+active rider SQL — only exclude the customer.
  const eligible = candidates.filter((c) => !customerId || c.id !== customerId);
  if (!eligible.length) return 0;

  const expiresAt = new Date(Date.now() + OFFER_TTL_SEC * 1000);
  const orderPayload = { ...order };
  const expiresIso = expiresAt.toISOString();
  const dispatchStarted = Date.now();

  // Persist offers before push/socket so decline/accept never races an empty row.
  await Promise.all(
    eligible.map(({ id: riderId }) =>
      pool.query(
        `INSERT INTO order_dispatch_offers (order_id, rider_id, wave, status, offered_at, expires_at)
         VALUES ($1, $2, $3, 'offered', CURRENT_TIMESTAMP, $4)
         ON CONFLICT (order_id, rider_id) DO UPDATE SET
           wave = EXCLUDED.wave,
           status = 'offered',
           offered_at = CURRENT_TIMESTAMP,
           expires_at = EXCLUDED.expires_at`,
        [order.id, riderId, wave, expiresAt]
      )
    )
  );

  await pool.query(
    `UPDATE orders SET dispatch_wave = $1, offer_expires_at = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3`,
    [wave, expiresAt, order.id]
  );

  void sendPushToRiders(order, eligible, { skipRecipientFilter: true }).catch((err) =>
    console.warn('[push] incoming ride send failed:', err)
  );

  for (const { id: riderId, distanceKm } of eligible) {
    const dist =
      Number.isFinite(distanceKm) && distanceKm >= 0
        ? Math.round(distanceKm * 10) / 10
        : null;
    const payload = {
      ...orderPayload,
      expiresAt: expiresIso,
      dispatchWave: wave,
      offerDistanceKm: dist,
      pickupDistanceKm: dist,
    };
    io.to(String(riderId)).emit('ride:incoming', payload);
  }

  const next = eligible[0];
  console.info(
    `[dispatch] order ${order.id} step ${wave}: offered to ${eligible.length} rider(s), first ${next.id.slice(0, 8)}… (${next.distanceKm.toFixed(1)} km) in ${Date.now() - dispatchStarted}ms`,
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

  const serviceType = normalizeRideServiceType(order.service_type);
  const [exclude, pickup] = await Promise.all([
    getOfferedRiderIds(order.id),
    getPickupPoint(order),
  ]);
  const radiusKm = dispatchRadiusKm(wave);
  const limit = ridersPerWave(wave);

  const widestRadiusKm = DISPATCH_RADIUS_KM_TIERS[DISPATCH_RADIUS_KM_TIERS.length - 1];

  let candidates: NearbyRider[] = [];
  let usedGlobalFallback = false;

  if (pickup) {
    candidates = await getNearestActiveRiders(
      pickup,
      order.region,
      exclude,
      limit,
      radiusKm,
      serviceType
    );
    if (
      candidates.length === 0 &&
      (wave >= EARLY_GLOBAL_FALLBACK_WAVE || radiusKm >= widestRadiusKm)
    ) {
      const fallbackIds = (await getActiveRiderIds(order.region, serviceType)).filter(
        (id) => !exclude.includes(id)
      );
      candidates = await getAvailableOnlineRiders(fallbackIds, limit);
      usedGlobalFallback = candidates.length > 0;
    }
  } else {
    const fallback = (await getActiveRiderIds(order.region, serviceType)).filter(
      (id) => !exclude.includes(id)
    );
    candidates = await getAvailableOnlineRiders(fallback, limit);
  }

  if (candidates.length === 0) {
    if (wave < MAX_DISPATCH_WAVES) {
      console.warn(
        `[dispatch] order ${order.id} step ${wave}: no riders within ${radiusKm}km — widening search`
      );
      await advanceDispatchWave(order, wave + 1);
    } else {
      console.warn(
        `[dispatch] order ${order.id}: no riders available (nearby or online) after ${MAX_DISPATCH_WAVES} attempts`
      );
    }
    return;
  }

  if (usedGlobalFallback) {
    console.info(
      `[dispatch] order ${order.id} step ${wave}: no rider within ${radiusKm}km — falling back to any online rider`
    );
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
  const orderRes = await pool.query('SELECT * FROM orders WHERE id = $1', [orderId]);
  const order = orderRes.rows[0];
  if (!order || !isOfferableOrder(order)) return;

  const wave = order.dispatch_wave || 1;
  await pool.query(
    `INSERT INTO order_dispatch_offers (order_id, rider_id, wave, status, offered_at, expires_at)
     VALUES ($1, $2, $3, 'declined', CURRENT_TIMESTAMP, NOW())
     ON CONFLICT (order_id, rider_id) DO UPDATE SET status = 'declined'`,
    [orderId, riderId, wave]
  );

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
  expiresAt?: string;
  status?: string;
  pickup?: string;
  address?: string;
  orderType?: string;
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
      `SELECT token, platform FROM fcm_tokens WHERE user_id = ANY($1::uuid[])`,
      [ids]
    );
    const rows = fcmRes.rows.filter((r: { token: string }) => r.token);
    if (!rows.length) return;

    const incomingRide = high && alert.type === 'incoming-ride';
    const dataPayload = {
      type: alert.type,
      orderId: String(alert.orderId ?? ''),
      title: alert.title,
      body: alert.body,
      ...(incomingRide
        ? {
            audience: 'rider',
            expiresAt: String(alert.expiresAt ?? ''),
            status: String(alert.status ?? 'ready'),
            pickup: String(alert.pickup ?? ''),
            address: String(alert.address ?? ''),
            orderType: String(alert.orderType ?? 'courier'),
          }
        : {}),
    };

    const iosTokenCount = rows.filter((r: { platform?: string }) => {
      const p = String(r.platform || 'android').toLowerCase();
      return p === 'ios' || p === 'macos';
    }).length;
    if (incomingRide) {
      console.info(
        `[push] incoming-ride → ${ids.length} rider(s), ${rows.length} FCM token(s) (${iosTokenCount} iOS)`
      );
    }

    const apnsExpires =
      incomingRide && alert.expiresAt
        ? String(Math.floor(new Date(alert.expiresAt).getTime() / 1000))
        : String(Math.floor(Date.now() / 1000) + 90);

    const messages = rows.map((row: { token: string; platform?: string }) => {
      const platform = String(row.platform || '').toLowerCase();
      const isIos = platform === 'ios' || platform === 'macos';
      const isAndroid = platform === 'android';
      // Android incoming jobs: data-only (Flutter shows one loud local alarm).
      // iOS / unknown platform: APNs alert+sound only (no FCM notification key — avoids silent iOS banners).
      const androidIncomingRide = incomingRide && isAndroid;
      const iosIncomingRide = incomingRide && isIos;
      const loudAlert = iosIncomingRide || (high && !androidIncomingRide);
      // iOS incoming jobs: alert + content-available so the device wakes and AppDelegate can show CallKit.
      const includeNotification = !incomingRide || iosIncomingRide;
      return {
        token: row.token,
        ...(includeNotification
          ? {
              notification: {
                title: alert.title,
                body: alert.body,
              },
            }
          : {}),
        data: dataPayload,
        android: {
          priority: high ? 'high' : 'normal',
          ttl: high ? 30 * 1000 : 3600 * 1000,
          ...(androidIncomingRide
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
            'apns-priority': iosIncomingRide || loudAlert ? '10' : '5',
            'apns-push-type': iosIncomingRide || loudAlert ? 'alert' : 'background',
            ...(iosIncomingRide ? { 'apns-expiration': apnsExpires } : {}),
          },
          payload: {
            aps: iosIncomingRide
              ? {
                  alert: { title: alert.title, body: alert.body },
                  sound: 'default',
                  'interruption-level': 'time-sensitive',
                  category: 'incoming_ride_offer',
                  contentAvailable: true,
                }
              : loudAlert
                ? {
                    alert: { title: alert.title, body: alert.body },
                    sound: 'default',
                    'interruption-level': 'time-sensitive',
                  }
                : {
                    contentAvailable: true,
                  },
          },
        },
      };
    });

    const result = await admin.messaging().sendEach(messages);
    if (incomingRide && result.failureCount > 0) {
      result.responses.forEach((r, i) => {
        if (!r.success) {
          console.warn(
            `[push] incoming-ride FCM failed token[${i}]:`,
            r.error?.code,
            r.error?.message
          );
        }
      });
    }
  } catch (err) {
    console.warn('[push] FCM send failed:', err);
  }
}

async function sendPushToRiders(
  order: any,
  riders: NearbyRider[],
  opts?: { skipRecipientFilter?: boolean }
) {
  let eligible = riders;
  if (!opts?.skipRecipientFilter) {
    const eligibleIds = await filterIncomingRideRecipientIds(
      riders.map((r) => r.id),
      order?.customer_id ?? null
    );
    eligible = riders.filter((r) => eligibleIds.includes(r.id));
  }
  if (!eligible.length) return;
  const pickup = order.pickup_address || order.pickup || 'Pickup';
  const dropoff = order.address || 'Drop-off';
  const expiresAt = order.offer_expires_at
    ? new Date(order.offer_expires_at).toISOString()
    : new Date(Date.now() + OFFER_TTL_SEC * 1000).toISOString();
  await Promise.all(
    eligible.map(({ id, distanceKm }) => {
      const distLabel =
        Number.isFinite(distanceKm) && distanceKm > 0 && distanceKm < 500
          ? `${distanceKm.toFixed(1)} km to pickup · `
          : '';
      return sendPushToUserIds([id], {
        title: 'New delivery job',
        body: `${distLabel}${pickup} → ${dropoff}`,
        type: 'incoming-ride',
        orderId: order.id,
        channelId: 'incoming_rides_alarm',
        highPriority: true,
        expiresAt,
        status: order.status,
        pickup: String(pickup),
        address: String(dropoff),
        orderType: order.order_type || order.orderType || 'courier',
      });
    })
  );
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
const AUTH_STATUS_CACHE_MS = 60_000;
const authStatusCache = new Map<string, { ok: boolean; expires: number }>();

function invalidateAuthStatus(userId: string) {
  authStatusCache.delete(String(userId));
}

const authenticateToken = (req: any, res: any, next: any) => {
  const authHeader = req.headers['authorization'];
  const token = authHeader && authHeader.split(' ')[1];

  if (!token || !String(token).trim()) {
    return res.status(401).json({ message: 'Sign in required' });
  }
  if (token.length > 2048) {
    return res.status(431).json({
      message: 'Session token is too large. Sign out and sign in again to refresh your session.',
    });
  }

  jwt.verify(token, process.env.JWT_SECRET as string, async (err: any, user: any) => {
    if (err) {
      return res.status(403).json({ message: 'Session expired. Please sign in again.' });
    }

    const cached = authStatusCache.get(user.id);
    if (cached && Date.now() < cached.expires) {
      if (!cached.ok) {
        return res.status(403).json({ error: 'Account disabled or not found' });
      }
      req.user = user;
      return next();
    }

    try {
      const result = await pool.query('SELECT status FROM users WHERE id = $1', [user.id]);
      const ok = result.rowCount !== 0 && result.rows[0].status !== 'disabled';
      authStatusCache.set(user.id, { ok, expires: Date.now() + AUTH_STATUS_CACHE_MS });
      if (!ok) {
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
    apiKey: envKey || dbKey || (process.env.NODE_ENV === 'production' ? '' : DEFAULT_SMS_API_KEY),
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

const smsPause = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

type ApprovalSmsKind = 'rider' | 'vendor' | 'owner' | 'product';

function approvalSmsBody(kind: ApprovalSmsKind, extra?: { productName?: string }): string {
  switch (kind) {
    case 'rider':
      return 'BytzGo: Your rider account is approved! Open the app, go online, and start accepting trips.';
    case 'vendor':
      return 'BytzGo: Your store is approved! Log in to the vendor app to add menu items and receive orders.';
    case 'owner':
      return 'BytzGo: Your fleet owner account is approved. Log in to manage vehicles and drivers.';
    case 'product':
      return `BytzGo: Your menu item "${extra?.productName || 'item'}" is approved and is now live for customers.`;
    default:
      return 'BytzGo: Your account is approved. Open the app to get started.';
  }
}

function roleToApprovalKind(role: string): ApprovalSmsKind | null {
  if (role === 'rider') return 'rider';
  if (role === 'vendor') return 'vendor';
  if (role === 'owner') return 'owner';
  return null;
}

/** Text user when admin approves their account or menu item. Best-effort; never throws. */
async function notifyApprovalSms(
  userId: string,
  kind: ApprovalSmsKind,
  extra?: { productName?: string }
): Promise<void> {
  if (process.env.APPROVAL_SMS === 'false') return;
  try {
    const userRes = await pool.query('SELECT phone FROM users WHERE id = $1', [userId]);
    const phone = userRes.rows[0]?.phone;
    if (!phone || !isValidGhanaPhone(phone)) {
      console.warn(`[approval-sms] No valid phone for user ${userId}`);
      return;
    }
    await sendSMS(phone, approvalSmsBody(kind, extra));
    console.info(`[approval-sms] Sent ${kind} approval SMS to user ${userId}`);
  } catch (err: any) {
    console.warn(`[approval-sms] Failed for user ${userId}:`, err?.message || err);
  }
}

function buildPromotionCustomerSms(promo: RidePromotionRow): string {
  const bits = [`BytzGo promo: ${promo.name}.`];
  const pct = Number(promo.customer_discount_percent) || 0;
  const fixed = Number(promo.customer_discount_fixed) || 0;
  if (pct > 0) bits.push(`${pct}% off`);
  if (fixed > 0) bits.push(`GHS${fixed.toFixed(0)} off`);
  const services = String(promo.service_types || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean)
    .join(', ');
  if (services) bits.push(services);
  if (promo.code) bits.push(`Code ${promo.code}.`);
  if (promo.target_region) bits.push(`Valid in ${promo.target_region}.`);
  bits.push('Book on the BytzGo app.');
  return bits.join(' ').slice(0, 160);
}

function buildPromotionRiderSms(promo: RidePromotionRow): string {
  const bonus = Number(promo.rider_bonus_amount) || 0;
  if (bonus <= 0) return '';
  const region = promo.target_region ? ` in ${promo.target_region}` : '';
  return `BytzGo rider bonus: Earn extra GHS${bonus.toFixed(0)} per trip${region}. Open the rider app and go online.`;
}

/** Broadcast promotion SMS to customers (and riders when bonus applies). Best-effort background job. */
async function announcePromotionSms(
  promo: RidePromotionRow,
  options?: { force?: boolean }
): Promise<{ sent: number; skipped: boolean }> {
  if (process.env.PROMO_SMS === 'false') return { sent: 0, skipped: true };
  if (!promo.enabled || !promotionIsActiveNow(promo)) {
    return { sent: 0, skipped: true };
  }
  if (!options?.force && promo.announced_at) {
    return { sent: 0, skipped: true };
  }

  const maxRecipients = Math.min(
    Math.max(1, parseInt(process.env.PROMO_SMS_MAX_RECIPIENTS || '500', 10) || 500),
    2000
  );
  const region = promo.target_region?.trim() || null;
  const customerBody = buildPromotionCustomerSms(promo);
  const riderBody = buildPromotionRiderSms(promo);
  let sent = 0;

  const fetchPhones = async (role: string) => {
    const params: unknown[] = [role];
    let sql = `SELECT DISTINCT phone FROM users
      WHERE role = $1 AND status = 'active' AND phone IS NOT NULL AND TRIM(phone) <> ''`;
    if (region) {
      sql += ` AND LOWER(TRIM(region)) = LOWER(TRIM($2))`;
      params.push(region);
    }
    sql += ` LIMIT $${params.length + 1}`;
    params.push(maxRecipients);
    return pool.query(sql, params);
  };

  try {
    const customers = await fetchPhones('customer');
    for (const row of customers.rows) {
      if (!isValidGhanaPhone(row.phone)) continue;
      try {
        await sendSMS(row.phone, customerBody);
        sent++;
        await smsPause(120);
      } catch (err: any) {
        console.warn('[promo-sms] customer send failed:', err?.message || err);
      }
    }

    if (riderBody) {
      const riders = await fetchPhones('rider');
      for (const row of riders.rows) {
        if (!isValidGhanaPhone(row.phone)) continue;
        try {
          await sendSMS(row.phone, riderBody);
          sent++;
          await smsPause(120);
        } catch (err: any) {
          console.warn('[promo-sms] rider send failed:', err?.message || err);
        }
      }
    }

    await pool.query(
      `UPDATE ride_promotions SET announced_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $1`,
      [promo.id]
    );
    console.info(`[promo-sms] Announced promotion ${promo.id} (${promo.name}) to ${sent} phones`);
    return { sent, skipped: false };
  } catch (err: any) {
    console.warn('[promo-sms] Broadcast failed:', err?.message || err);
    return { sent, skipped: false };
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
  const { name, email, password, role, phone, adminInviteSecret, otp, vehicle_type, rider_vehicle_type } = req.body;
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
  let riderVehicle: string | null = null;
  if (role === 'rider') {
    if (!vehicle_type && !rider_vehicle_type) {
      return res.status(400).json({
        message: 'Choose your vehicle type: Okada (motorcycle), Keke (tricycle), or Bicycle.',
      });
    }
    riderVehicle = normalizeRiderVehicleType(vehicle_type ?? rider_vehicle_type);
  }
  try {
    const hashedPassword = await bcrypt.hash(password, 10);
    const userStatus = role === 'vendor' || role === 'rider' || role === 'owner' ? 'pending' : 'active';
    const storePhone = phone ? formatGhanaPhone(phone) : phone;
    const result = await pool.query(
      `INSERT INTO users (name, email, password, role, status, phone, rider_vehicle_type)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, name, email, role, balance, phone, status, rider_vehicle_type`,
      [name, email, hashedPassword, role, userStatus, storePhone, riderVehicle]
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

// Google Auth (disabled unless GOOGLE_SIGN_IN_ENABLED=true)
app.post('/api/auth/google', async (req, res) => {
  if (!GOOGLE_SIGN_IN_ENABLED) {
    return res.status(403).json({
      message: 'Google sign-in is disabled. Sign in with your phone or email and password.',
    });
  }
  const { credential, role, vehicle_type, rider_vehicle_type } = req.body;
  try {
    const payload = await verifyGoogleIdToken(credential);
    if (!payload || !payload.email) {
      return res.status(400).json({ message: 'Invalid Google token' });
    }

    const googleId = payload.sub || (payload as { user_id?: string }).user_id;
    const displayName = displayUserName(payload.name || payload.email.split('@')[0], {
      fallback: 'BytzGo member',
    });
    
    // Check if user exists
    let result = await pool.query('SELECT * FROM users WHERE email = $1', [payload.email]);
    let user = result.rows[0];
    if (!user) {
      const newRole = role || 'customer';
      if (newRole === 'admin') {
        return res.status(403).json({ message: 'Admin accounts cannot be created via Google sign-in.' });
      }
      const userStatus = (newRole === 'vendor' || newRole === 'rider' || newRole === 'owner') ? 'pending' : 'active';
      if (newRole === 'rider' && !vehicle_type && !rider_vehicle_type) {
        return res.status(400).json({
          message: 'Choose your vehicle type: Okada (motorcycle), Keke (tricycle), or Bicycle.',
        });
      }
      const riderVehicle =
        newRole === 'rider'
          ? normalizeRiderVehicleType(vehicle_type ?? rider_vehicle_type)
          : null;
      result = await pool.query(
        `INSERT INTO users (name, email, google_id, role, status, rider_vehicle_type)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, name, email, role, balance, phone, status, rider_vehicle_type`,
        [displayName, payload.email, googleId, newRole, userStatus, riderVehicle]
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
    const detail = String(err?.message || err || '');
    if (detail.includes('audience') || detail.includes('Audience')) {
      return res.status(401).json({
        message:
          'Google sign-in token was rejected (wrong app certificate). Install the latest APK from bytzgo.net/download/android, or sign in with phone/email.',
      });
    }
    res.status(401).json({ message: 'Google authentication failed. Try phone or email sign-in.' });
  }
});

// Apple Sign-In (iOS)
app.post('/api/auth/apple', async (req, res) => {
  const { credential, role, email: clientEmail, name: clientName, vehicle_type, rider_vehicle_type } = req.body;
  try {
    if (!credential || typeof credential !== 'string') {
      return res.status(400).json({ message: 'Apple identity token required' });
    }

    const payload = await verifyAppleIdToken(credential);
    const appleId = payload.sub;
    const email =
      (typeof payload.email === 'string' && payload.email.trim()) ||
      (typeof clientEmail === 'string' && clientEmail.trim()) ||
      '';

    let result = await pool.query('SELECT * FROM users WHERE apple_id = $1', [appleId]);
    let user = result.rows[0];

    if (!user && email) {
      result = await pool.query('SELECT * FROM users WHERE email = $1', [email]);
      user = result.rows[0];
    }

    if (!user) {
      if (!email) {
        return res.status(400).json({
          message:
            'Apple did not provide an email. Sign in with phone or email first, or revoke BytzGo in Apple ID settings and try again.',
        });
      }
      const newRole = role || 'customer';
      if (newRole === 'admin') {
        return res.status(403).json({ message: 'Admin accounts cannot be created via Apple sign-in.' });
      }
      const userStatus = (newRole === 'vendor' || newRole === 'rider' || newRole === 'owner') ? 'pending' : 'active';
      if (newRole === 'rider' && !vehicle_type && !rider_vehicle_type) {
        return res.status(400).json({
          message: 'Choose your vehicle type: Okada (motorcycle), Keke (tricycle), or Bicycle.',
        });
      }
      const riderVehicle =
        newRole === 'rider'
          ? normalizeRiderVehicleType(vehicle_type ?? rider_vehicle_type)
          : null;
      const displayName = displayUserName(
        (typeof clientName === 'string' && clientName.trim()) ||
          email.split('@')[0],
        { fallback: 'BytzGo member' },
      );
      result = await pool.query(
        `INSERT INTO users (name, email, apple_id, role, status, rider_vehicle_type)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id, name, email, role, balance, phone, status, rider_vehicle_type`,
        [displayName, email, appleId, newRole, userStatus, riderVehicle],
      );
      user = result.rows[0];
    } else {
      if (!user.apple_id && appleId) {
        await pool.query('UPDATE users SET apple_id = $1 WHERE id = $2', [appleId, user.id]);
      }
      const { password, ...u } = user;
      user = u;
    }

    const token = signAuthToken(user);
    res.json({ user: await userForAuthResponse(user), token });
  } catch (err: any) {
    console.error('Apple auth error:', err);
    res.status(401).json({ message: 'Apple authentication failed. Try phone or email sign-in.' });
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
      const userStatus = role === 'vendor' || role === 'rider' || role === 'owner' ? 'pending' : 'active';
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
    if (row.role === 'owner') {
      await client.query('DELETE FROM vehicles WHERE owner_id = $1', [userId]);
    }
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
      if (isOnline && (await riderHasOverdueCommission(req.user.id))) {
        const settings = await getCommissionSettings();
        return res.status(403).json({
          message: `Pay yesterday's ${settings.totalPercent}% trip commission (due by 8:00 AM Ghana time) before going online.`,
          code: 'COMMISSION_OVERDUE',
        });
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
    invalidateAuthStatus(user.id);
    const token = signAuthToken(user);
    res.json({ user: await userForAuthResponse(user), token });
    io.to(String(user.id)).emit('status:updated', { status });
  } catch (err: any) {
    console.error('Status update error:', err);
    res.status(500).json({ message: 'Status update failed' });
  }
});


/** Rider declares okada (motorcycle) or keke (tricycle) for job matching. */
app.patch('/api/rider/vehicle-type', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') {
    return res.status(403).json({ message: 'Riders only' });
  }
  const vehicleType = normalizeRiderVehicleType(req.body?.vehicle_type ?? req.body?.rider_vehicle_type);
  try {
    const result = await pool.query(
      `UPDATE users SET rider_vehicle_type = $1 WHERE id = $2 RETURNING ${USER_PUBLIC_FIELDS}`,
      [vehicleType, req.user.id]
    );
    const user = result.rows[0];
    res.json({ user: await userForAuthResponse(user), rider_vehicle_type: vehicleType });
  } catch (err) {
    console.error('Rider vehicle type error:', err);
    res.status(500).json({ message: 'Failed to update vehicle type' });
  }
});


// Wallet Routes
app.get('/api/wallet', authenticateToken, async (req: any, res) => {
  try {
    if (req.user.role === 'rider') {
      const withdrawable = await getRiderSpendableBalance(req.user.id);
      return res.json({
        balance: withdrawable,
        withdrawable,
        cash_not_withdrawable: true,
      });
    }
    const result = await pool.query('SELECT balance FROM users WHERE id = $1', [req.user.id]);
    const balance = parseFloat(result.rows[0].balance);
    res.json({ balance, withdrawable: balance });
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/wallet/transactions', authenticateToken, async (req: any, res) => {
  const limit = Math.min(Math.max(parseInt(String(req.query.limit || '50'), 10) || 50, 1), 100);
  try {
    const riderFilter =
      req.user.role === 'rider'
        ? ` AND NOT ${COD_WALLET_REFERENCE_SQL} AND NOT ${EXTERNAL_COMMISSION_REFERENCE_SQL}`
        : '';
    const result = await pool.query(
      `SELECT id, amount, type, status, reference, created_at
       FROM wallet_transactions
       WHERE user_id = $1${riderFilter}
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
        ledgerOnly: isCodLedgerReference(row.reference),
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

    let offers: Record<string, number> = {
      offers_received: 0,
      offers_accepted: 0,
      offers_declined: 0,
    };
    try {
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
      offers = offersRes.rows[0] || offers;
    } catch (offersErr) {
      console.warn('[rider/stats] dispatch offers unavailable:', offersErr);
    }

    const trips = tripsRes.rows[0] || {};
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

/** Fetch one active incoming offer (after push tap / lock-screen alert). */
app.get('/api/rider/incoming-offer/:orderId', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') {
    return res.status(403).json({ message: 'Riders only' });
  }
  const orderId = String(req.params.orderId || '').trim();
  if (!orderId) {
    return res.status(400).json({ message: 'orderId required' });
  }
  try {
    const userRes = await pool.query(
      'SELECT status, is_online FROM users WHERE id = $1',
      [req.user.id]
    );
    const rider = userRes.rows[0];
    if (rider?.status !== 'active' || rider?.is_online !== true) {
      return res.status(400).json({ message: 'Go Online to view incoming offers' });
    }
    const result = await pool.query(
      `SELECT o.*, odo.expires_at AS rider_offer_expires_at, odo.wave AS rider_offer_wave,
        ${ORDER_CONTACT_SELECT}
       FROM orders o
       ${ORDER_CONTACT_JOINS}
       INNER JOIN order_dispatch_offers odo ON odo.order_id = o.id
         AND odo.rider_id = $1
         AND odo.status = 'offered'
         AND odo.expires_at > NOW()
       WHERE o.id = $2
         AND o.rider_id IS NULL
         AND (
           o.status = 'ready'
           OR (
             o.status = 'pending'
             AND o.vendor_id IS NOT NULL
             AND o.order_type IN ('food', 'courier')
           )
         )
       LIMIT 1`,
      [req.user.id, orderId]
    );
    if (!result.rows.length) {
      return res.status(404).json({ message: 'Offer not found or expired' });
    }
    const o = result.rows[0];
    const row = await sanitizeOrderForRole(o, 'rider', req.user.id);
    if (o.rider_offer_expires_at) {
      row.expiresAt = new Date(o.rider_offer_expires_at).toISOString();
      row.dispatchWave = o.rider_offer_wave;
    }
    res.json(row);
  } catch (err) {
    console.error('incoming-offer error:', err);
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
      const balance =
        req.user.role === 'rider'
          ? await getRiderSpendableBalance(req.user.id, client)
          : parseFloat(
              (await client.query('SELECT balance FROM users WHERE id = $1', [req.user.id])).rows[0]
                .balance
            );
      await emitWalletUpdated(req.user.id, req.user.role, client);
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

    const balance =
      req.user.role === 'rider'
        ? await getRiderSpendableBalance(req.user.id)
        : parseFloat(result.rows[0].balance);
    res.json({ balance });
    await emitWalletUpdated(req.user.id, req.user.role);
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

/** Nearby online riders for customer map (ordered nearest-first). */
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
      `SELECT rl.rider_id, rl.lat, rl.lng
       FROM rider_locations rl
       WHERE rl.rider_id = ANY($1::uuid[])
         AND rl.updated_at > NOW() - INTERVAL '1 minute' * $2`,
      [riderIds, LOCATION_MAX_AGE_MIN]
    );
    const locById = new Map<string, { lat: number; lng: number }>();
    for (const row of locs.rows) {
      const latN = parseFloat(row.lat);
      const lngN = parseFloat(row.lng);
      if (Number.isFinite(latN) && Number.isFinite(lngN)) {
        locById.set(String(row.rider_id), { lat: latN, lng: lngN });
      }
    }
    const riders = nearby
      .map((r) => {
        const loc = locById.get(r.id);
        if (!loc) return null;
        return {
          id: r.id,
          lat: loc.lat,
          lng: loc.lng,
          distance_km: Math.round(r.distanceKm * 10) / 10,
        };
      })
      .filter(Boolean);
    res.json({ riders });
  } catch (err) {
    console.error('[riders/nearby]', err);
    res.status(500).json({ message: 'Failed to load nearby riders' });
  }
});

/** Live GPS for an assigned rider (customer must have an active trip with them). */
app.get('/api/riders/:id/location', authenticateToken, async (req: any, res) => {
  const riderId = String(req.params.id ?? '').trim();
  if (!riderId) return res.status(400).json({ message: 'Rider id required' });
  try {
    if (req.user.role === 'customer' || req.user.role === 'vendor') {
      const trip = await pool.query(
        `SELECT id FROM orders
         WHERE customer_id = $1 AND rider_id = $2
           AND status IN ('ready', 'picked_up', 'arrived', 'preparing', 'pending')
         LIMIT 1`,
        [req.user.id, riderId]
      );
      if (!trip.rows.length) {
        return res.status(403).json({ message: 'No active trip with this rider' });
      }
    } else if (req.user.role !== 'admin' && req.user.id !== riderId) {
      return res.status(403).json({ message: 'Unauthorized' });
    }

    const loc = await pool.query(
      `SELECT lat, lng, updated_at FROM rider_locations WHERE rider_id = $1`,
      [riderId]
    );
    if (!loc.rows[0]) {
      return res.json({ lat: null, lng: null, updated_at: null });
    }
    const row = loc.rows[0];
    res.json({
      lat: parseFloat(row.lat),
      lng: parseFloat(row.lng),
      updated_at: row.updated_at,
    });
  } catch (err) {
    console.error('[riders/location]', err);
    res.status(500).json({ message: 'Failed to load rider location' });
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

/** Strip Google's HTML instruction markup ("<b>Turn left</b>") to plain text. */
function stripHtmlTags(html: string): string {
  return html
    .replace(/<\/?div[^>]*>/gi, ' ')
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim();
}

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
    // Live traffic-adjusted driving time (motorcycle couriers use road network + traffic).
    const departureTime = Math.floor(Date.now() / 1000);
    url.searchParams.set('departure_time', String(departureTime));
    url.searchParams.set('traffic_model', 'best_guess');
    url.searchParams.set('key', key);
    const { data } = await axios.get(url.toString());
    if (data.status !== 'OK' || !data.routes?.length) {
      return res.status(404).json({ message: data.error_message || 'No route found' });
    }
    const leg = data.routes[0].legs?.[0];
    const durationSec =
      leg?.duration_in_traffic?.value ?? leg?.duration?.value ?? 0;
    const durationText =
      leg?.duration_in_traffic?.text ?? leg?.duration?.text ?? '';
    const distanceText = leg?.distance?.text ?? '';
    const encoded = data.routes[0].overview_polyline?.points ?? '';
    const points = encoded ? decodeGooglePolyline(encoded) : [];
    const etaMinutes = Math.max(1, Math.ceil(durationSec / 60));
    // Turn-by-turn maneuvers for in-app navigation ("turn left in 200 m").
    const rawSteps = Array.isArray(leg?.steps) ? leg.steps : [];
    const steps = rawSteps.map((s: any) => ({
      instruction: stripHtmlTags(String(s?.html_instructions ?? '')),
      maneuver: s?.maneuver ? String(s.maneuver) : '',
      distance_text: s?.distance?.text ?? '',
      distance_meters: s?.distance?.value ?? 0,
      start_lat: typeof s?.start_location?.lat === 'number' ? s.start_location.lat : null,
      start_lng: typeof s?.start_location?.lng === 'number' ? s.start_location.lng : null,
      end_lat: typeof s?.end_location?.lat === 'number' ? s.end_location.lat : null,
      end_lng: typeof s?.end_location?.lng === 'number' ? s.end_location.lng : null,
    }));
    res.json({
      duration_seconds: durationSec,
      duration_text: durationText,
      distance_text: distanceText,
      eta_minutes: etaMinutes,
      points,
      steps,
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

/** Public Maps SDK key for mobile/web clients (restrict by app bundle in Google Cloud). */
app.get('/api/config/maps', async (_req, res) => {
  const apiKey = mapsApiKey();
  if (!apiKey || apiKey.length < 20) {
    return res.json({ apiKey: '', configured: false });
  }
  res.json({ apiKey, configured: true, keyHint: `…${apiKey.slice(-6)}` });
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
    
    // Check if user has enough spendable balance (riders: excludes COD cash in pocket)
    const available =
      req.user.role === 'rider'
        ? await getRiderSpendableBalance(req.user.id)
        : parseFloat(userData.balance);
    if (available < amount) {
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

    const newBalance =
      req.user.role === 'rider'
        ? await getRiderSpendableBalance(req.user.id)
        : parseFloat(result.rows[0].balance);
    res.json({ balance: newBalance, message: 'Withdrawal successful' });
    await emitWalletUpdated(req.user.id, req.user.role);
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

/** Fleet owner — dashboard + vehicle registry */
app.get('/api/owner/dashboard', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'owner') return res.status(403).json({ message: 'Fleet owners only' });
  try {
    const ownerId = req.user.id;
    const [statsRes, vehiclesRes] = await Promise.all([
      pool.query(
        `SELECT
          (SELECT COUNT(*)::int FROM vehicles WHERE owner_id = $1) AS total_vehicles,
          (SELECT COUNT(*)::int FROM vehicles WHERE owner_id = $1 AND status = 'active') AS active_vehicles,
          (SELECT COUNT(*)::int FROM vehicles WHERE owner_id = $1 AND assigned_rider_id IS NOT NULL) AS assigned_vehicles,
          (SELECT COUNT(*)::int FROM vehicles WHERE owner_id = $1 AND status = 'maintenance') AS maintenance_vehicles`,
        [ownerId]
      ),
      pool.query(
        `SELECT v.*, r.name AS assigned_rider_name, r.phone AS assigned_rider_phone
         FROM vehicles v
         LEFT JOIN users r ON r.id = v.assigned_rider_id
         WHERE v.owner_id = $1
         ORDER BY v.updated_at DESC, v.plate_number ASC
         LIMIT 100`,
        [ownerId]
      ),
    ]);
    const userRes = await pool.query(
      `SELECT id, name, email, phone, status, balance, created_at FROM users WHERE id = $1`,
      [ownerId]
    );
    res.json({
      owner: userRes.rows[0],
      stats: statsRes.rows[0],
      vehicles: vehiclesRes.rows.map(vehicleRowForClient),
    });
  } catch (err) {
    console.error('Owner dashboard error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/owner/vehicles', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'owner') return res.status(403).json({ message: 'Fleet owners only' });
  try {
    const result = await pool.query(
      `SELECT v.*, r.name AS assigned_rider_name, r.phone AS assigned_rider_phone
       FROM vehicles v
       LEFT JOIN users r ON r.id = v.assigned_rider_id
       WHERE v.owner_id = $1
       ORDER BY v.updated_at DESC, v.plate_number ASC`,
      [req.user.id]
    );
    res.json(result.rows.map(vehicleRowForClient));
  } catch (err) {
    console.error('Owner vehicles list error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

app.post('/api/owner/vehicles', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'owner') return res.status(403).json({ message: 'Fleet owners only' });
  const ownerRes = await pool.query('SELECT status FROM users WHERE id = $1', [req.user.id]);
  if (ownerRes.rows[0]?.status !== 'active') {
    return res.status(403).json({
      message: 'Your owner account is pending approval. You can add vehicles after admin approves your account.',
    });
  }
  const plate = String(req.body.plate_number || '').trim().toUpperCase();
  if (!plate || plate.length < 3) {
    return res.status(400).json({ message: 'Enter a valid plate number' });
  }
  const status = normalizeVehicleStatus(req.body.status) ?? 'active';
  const vehicleType = normalizeVehicleType(req.body.vehicle_type) ?? 'motorcycle';
  const yearRaw = req.body.year;
  const year =
    yearRaw != null && String(yearRaw).trim() !== '' ? parseInt(String(yearRaw), 10) : null;
  if (year != null && (Number.isNaN(year) || year < 1980 || year > new Date().getFullYear() + 1)) {
    return res.status(400).json({ message: 'Enter a valid vehicle year' });
  }
  try {
    const result = await pool.query(
      `INSERT INTO vehicles (
         owner_id, plate_number, make, model, year, color, vehicle_type, status, notes
       ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
       RETURNING *`,
      [
        req.user.id,
        plate,
        String(req.body.make || '').trim() || null,
        String(req.body.model || '').trim() || null,
        year,
        String(req.body.color || '').trim() || null,
        vehicleType,
        status,
        String(req.body.notes || '').trim() || null,
      ]
    );
    res.status(201).json(vehicleRowForClient(result.rows[0]));
  } catch (err: any) {
    if (err?.code === '23505') {
      return res.status(409).json({ message: 'You already registered a vehicle with this plate number' });
    }
    console.error('Create vehicle error:', err);
    res.status(500).json({ message: 'Failed to add vehicle' });
  }
});

app.patch('/api/owner/vehicles/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'owner') return res.status(403).json({ message: 'Fleet owners only' });
  const { id } = req.params;
  try {
    const existing = await pool.query(
      'SELECT * FROM vehicles WHERE id = $1 AND owner_id = $2',
      [id, req.user.id]
    );
    if (!existing.rows[0]) return res.status(404).json({ message: 'Vehicle not found' });

    const plate = req.body.plate_number != null
      ? String(req.body.plate_number).trim().toUpperCase()
      : existing.rows[0].plate_number;
    if (!plate || plate.length < 3) {
      return res.status(400).json({ message: 'Enter a valid plate number' });
    }
    const status = req.body.status != null
      ? normalizeVehicleStatus(req.body.status) ?? existing.rows[0].status
      : existing.rows[0].status;
    const vehicleType = req.body.vehicle_type != null
      ? normalizeVehicleType(req.body.vehicle_type) ?? existing.rows[0].vehicle_type
      : existing.rows[0].vehicle_type;
    let year = existing.rows[0].year;
    if (req.body.year !== undefined) {
      const yearRaw = req.body.year;
      year =
        yearRaw != null && String(yearRaw).trim() !== ''
          ? parseInt(String(yearRaw), 10)
          : null;
      if (year != null && (Number.isNaN(year) || year < 1980 || year > new Date().getFullYear() + 1)) {
        return res.status(400).json({ message: 'Enter a valid vehicle year' });
      }
    }

    let assignedRiderId = existing.rows[0].assigned_rider_id;
    if (req.body.assigned_rider_id !== undefined) {
      const raw = req.body.assigned_rider_id;
      if (raw == null || raw === '') {
        assignedRiderId = null;
      } else {
        const riderId = String(raw).trim();
        const riderRes = await pool.query(
          `SELECT id FROM users WHERE id = $1 AND role = 'rider' AND status = 'active'`,
          [riderId]
        );
        if (!riderRes.rows[0]) {
          return res.status(400).json({ message: 'Assigned rider must be an active BytzGo driver' });
        }
        assignedRiderId = riderId;
      }
    }

    const result = await pool.query(
      `UPDATE vehicles SET
         plate_number = $1,
         make = $2,
         model = $3,
         year = $4,
         color = $5,
         vehicle_type = $6,
         status = $7,
         notes = $8,
         assigned_rider_id = $9,
         updated_at = CURRENT_TIMESTAMP
       WHERE id = $10 AND owner_id = $11
       RETURNING *`,
      [
        plate,
        req.body.make !== undefined
          ? String(req.body.make || '').trim() || null
          : existing.rows[0].make,
        req.body.model !== undefined
          ? String(req.body.model || '').trim() || null
          : existing.rows[0].model,
        year,
        req.body.color !== undefined
          ? String(req.body.color || '').trim() || null
          : existing.rows[0].color,
        vehicleType,
        status,
        req.body.notes !== undefined
          ? String(req.body.notes || '').trim() || null
          : existing.rows[0].notes,
        assignedRiderId,
        id,
        req.user.id,
      ]
    );
    const joined = await pool.query(
      `SELECT v.*, r.name AS assigned_rider_name, r.phone AS assigned_rider_phone
       FROM vehicles v
       LEFT JOIN users r ON r.id = v.assigned_rider_id
       WHERE v.id = $1`,
      [result.rows[0].id]
    );
    res.json(vehicleRowForClient(joined.rows[0]));
  } catch (err: any) {
    if (err?.code === '23505') {
      return res.status(409).json({ message: 'You already registered a vehicle with this plate number' });
    }
    console.error('Update vehicle error:', err);
    res.status(500).json({ message: 'Failed to update vehicle' });
  }
});

app.delete('/api/owner/vehicles/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'owner') return res.status(403).json({ message: 'Fleet owners only' });
  const { id } = req.params;
  try {
    const result = await pool.query(
      'DELETE FROM vehicles WHERE id = $1 AND owner_id = $2 RETURNING id',
      [id, req.user.id]
    );
    if (!result.rows[0]) return res.status(404).json({ message: 'Vehicle not found' });
    res.json({ success: true });
  } catch (err) {
    console.error('Delete vehicle error:', err);
    res.status(500).json({ message: 'Failed to delete vehicle' });
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
      `SELECT u.id, u.name, u.email, u.role, u.balance, u.created_at, u.status, u.is_online, u.phone, u.region,
        (SELECT ROUND(AVG(o.rating)::numeric, 1) FROM orders o
         WHERE o.rider_id = u.id AND o.rating IS NOT NULL AND o.rating > 0) AS rider_avg_rating,
        (SELECT COUNT(*)::int FROM orders o
         WHERE o.rider_id = u.id AND o.rating IS NOT NULL AND o.rating > 0) AS rider_rating_count
       FROM users u ORDER BY u.created_at DESC`
    );
    const rows = result.rows.map((u: any) => {
      if (u.role === 'rider') {
        const avg = u.rider_avg_rating != null ? parseFloat(String(u.rider_avg_rating)) : null;
        const cnt = u.rider_rating_count != null ? parseInt(String(u.rider_rating_count), 10) || 0 : 0;
        u.riderAvgRating = avg;
        u.riderRatingCount = cnt;
        u.riderTier = driverTier(avg, cnt);
      }
      delete u.rider_avg_rating;
      delete u.rider_rating_count;
      return u;
    });
    res.json(rows);
  } catch (err) {
    res.status(500).json({ message: 'Server error' });
  }
});

app.get('/api/admin/pending-riders', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  try {
    const result = await pool.query(
      `SELECT u.id, u.name, u.email, u.phone, u.region, u.status, u.is_online, u.created_at,
        u.rider_vehicle_type,
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
    invalidateAuthStatus(id);
    await pool.query(
      `UPDATE rider_documents SET review_status = 'approved', rejection_reason = NULL,
        reviewed_by = $2, reviewed_at = CURRENT_TIMESTAMP
       WHERE user_id = $1`,
      [id, req.user.id]
    );
    res.json(result.rows[0]);
    io.to(id).emit('status:updated', { status: 'active', is_online: false });
    void notifyApprovalSms(id, 'rider');
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
    invalidateAuthStatus(id);
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

app.get('/api/admin/pending-owners', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  try {
    const result = await pool.query(
      `SELECT u.id, u.name, u.email, u.phone, u.region, u.status, u.created_at,
        (SELECT COUNT(*)::int FROM vehicles v WHERE v.owner_id = u.id) AS vehicle_count
       FROM users u
       WHERE u.role = 'owner' AND u.status IN ('pending', 'rejected')
       ORDER BY u.created_at DESC`
    );
    res.json(result.rows);
  } catch (err) {
    console.error('Pending owners error:', err);
    res.status(500).json({ message: 'Failed to fetch pending fleet owners' });
  }
});

app.patch('/api/admin/owners/:id/approve', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { id } = req.params;
  try {
    const check = await pool.query('SELECT id, role FROM users WHERE id = $1', [id]);
    if (!check.rows[0] || check.rows[0].role !== 'owner') {
      return res.status(404).json({ message: 'Fleet owner not found' });
    }
    const result = await pool.query(
      `UPDATE users SET status = 'active' WHERE id = $1
       RETURNING id, name, email, role, status, phone, region`,
      [id]
    );
    res.json(result.rows[0]);
    io.to(id).emit('status:updated', { status: 'active' });
    void notifyApprovalSms(id, 'owner');
  } catch (err) {
    console.error('Approve owner error:', err);
    res.status(500).json({ message: 'Failed to approve fleet owner' });
  }
});

app.patch('/api/admin/owners/:id/reject', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { id } = req.params;
  const reason = typeof req.body?.reason === 'string' ? req.body.reason.trim() : '';
  try {
    const check = await pool.query('SELECT id, role FROM users WHERE id = $1', [id]);
    if (!check.rows[0] || check.rows[0].role !== 'owner') {
      return res.status(404).json({ message: 'Fleet owner not found' });
    }
    const result = await pool.query(
      `UPDATE users SET status = 'rejected' WHERE id = $1
       RETURNING id, name, email, role, status, phone, region`,
      [id]
    );
    res.json(result.rows[0]);
    io.to(id).emit('status:updated', { status: 'rejected', reason: reason || 'Application rejected' });
  } catch (err) {
    console.error('Reject owner error:', err);
    res.status(500).json({ message: 'Failed to reject fleet owner' });
  }
});

/** Add sideload SHA-1 to Firebase Android API key (fixes Google Sign-In error 10). */
app.post('/api/admin/google/configure-signin-apikey', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  if (!loadFirebaseServiceAccount()) {
    return res.status(503).json({ message: 'Firebase service account not configured on server.' });
  }
  try {
    const mod = await import('./scripts/configure-google-signin-apikey.mjs');
    const result = await mod.configureGoogleSignInApiKey();
    res.json({ ok: true, ...result });
  } catch (err: any) {
    console.error('[admin/google/configure-signin-apikey]', err.message || err);
    res.status(502).json({ message: err.message || 'API key configuration failed' });
  }
});

/** Register Android SHA-1 fingerprints in Firebase and refresh google-services.json (uses server Firebase SA). */
app.post('/api/admin/firebase/sync-android', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const serviceAccount = loadFirebaseServiceAccount();
  if (!serviceAccount) {
    return res.status(503).json({
      message:
        'Firebase service account not configured. Set FIREBASE_SERVICE_ACCOUNT_JSON on Render.',
    });
  }
  try {
    const mod = await import('./scripts/setup-firebase-android.mjs');
    const result = await mod.syncFirebaseAndroid({
      credentials: serviceAccount,
      writeFiles: false,
    });
    res.json({
      ok: true,
      packageName: result.packageName,
      hasSideloadSha1: result.hasSideloadSha1,
      hasReleaseSha1: result.hasReleaseSha1,
      shaResults: result.shaResults,
      googleServicesJson: result.googleServicesJson,
    });
  } catch (err: any) {
    console.error('[admin/firebase/sync-android]', err.message || err);
    res.status(502).json({ message: err.message || 'Firebase Android sync failed' });
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

const SMS_BLAST_MAX_RECIPIENTS = 300;
const SMS_BLAST_MAX_LENGTH = 480;

type SmsBlastAudience =
  | 'customers'
  | 'riders'
  | 'riders_active'
  | 'riders_online'
  | 'vendors'
  | 'owners'
  | 'all'
  | 'custom';

function normalizeSmsAudience(value: unknown): SmsBlastAudience | null {
  const s = String(value ?? '').trim().toLowerCase();
  const allowed: SmsBlastAudience[] = [
    'customers',
    'riders',
    'riders_active',
    'riders_online',
    'vendors',
    'owners',
    'all',
    'custom',
  ];
  return (allowed as string[]).includes(s) ? (s as SmsBlastAudience) : null;
}

async function countSmsAudience(audience: SmsBlastAudience, region?: string | null): Promise<number> {
  const phones = await resolveSmsAudiencePhones(audience, { region });
  return phones.length;
}

async function resolveSmsAudiencePhones(
  audience: SmsBlastAudience,
  opts: { phones?: string[]; region?: string | null } = {}
): Promise<string[]> {
  const region = opts.region?.trim() || null;
  const regionClause = region
    ? `AND LOWER(TRIM(COALESCE(region, ''))) = LOWER($1)`
    : '';
  const regionParam = region ? [region] : [];

  if (audience === 'custom') {
    const raw = Array.isArray(opts.phones) ? opts.phones : [];
    const set = new Set<string>();
    for (const p of raw) {
      if (typeof p !== 'string' || !p.trim()) continue;
      if (!isValidGhanaPhone(p)) continue;
      set.add(formatGhanaPhone(p));
    }
    return [...set];
  }

  let roleFilter = '';
  let statusFilter = '';
  if (audience === 'customers') roleFilter = `role = 'customer'`;
  else if (audience === 'riders') roleFilter = `role = 'rider'`;
  else if (audience === 'riders_active') {
    roleFilter = `role = 'rider'`;
    statusFilter = `AND status = 'active'`;
  } else if (audience === 'riders_online') {
    roleFilter = `role = 'rider'`;
    statusFilter = `AND status = 'active' AND is_online = true`;
  } else if (audience === 'vendors') roleFilter = `role = 'vendor'`;
  else if (audience === 'owners') roleFilter = `role = 'owner'`;
  else if (audience === 'all') roleFilter = `role IN ('customer', 'rider', 'vendor', 'owner', 'admin')`;
  else return [];

  const result = await pool.query(
    `SELECT DISTINCT phone FROM users
     WHERE phone IS NOT NULL AND TRIM(phone) <> ''
     AND ${roleFilter}
     ${statusFilter}
     ${regionClause}`,
    regionParam
  );

  const set = new Set<string>();
  for (const row of result.rows) {
    const phone = row.phone?.toString().trim();
    if (!phone || !isValidGhanaPhone(phone)) continue;
    set.add(formatGhanaPhone(phone));
  }
  return [...set];
}

/** Audience counts for admin SMS blast UI. */
app.get('/api/admin/sms/audience', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const region = typeof req.query.region === 'string' ? req.query.region.trim() : null;
  try {
    const audiences: SmsBlastAudience[] = [
      'customers',
      'riders',
      'riders_active',
      'riders_online',
      'vendors',
      'owners',
      'all',
    ];
    const counts: Record<string, number> = {};
    for (const a of audiences) {
      counts[a] = await countSmsAudience(a, region);
    }
    const cfg = await getSmsConfig();
    res.json({
      counts,
      region: region || null,
      sms_configured: Boolean(cfg.apiKey && cfg.apiKey.length > 8),
      sender_id: cfg.senderId,
      max_recipients: SMS_BLAST_MAX_RECIPIENTS,
      max_message_length: SMS_BLAST_MAX_LENGTH,
    });
  } catch (err: any) {
    console.error('[admin/sms/audience]', err);
    res.status(500).json({ message: 'Failed to load SMS audience' });
  }
});

/** Promotional / ops SMS blast to customers, riders, vendors, or custom numbers. */
app.post('/api/admin/sms/blast', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);

  const audience = normalizeSmsAudience(req.body?.audience);
  const message = String(req.body?.message ?? '').trim();
  const region =
    typeof req.body?.region === 'string' && req.body.region.trim()
      ? req.body.region.trim()
      : null;
  const customPhones = Array.isArray(req.body?.phones) ? req.body.phones : [];

  if (!audience) {
    return res.status(400).json({
      message:
        'Choose audience: customers, riders, riders_active, riders_online, vendors, owners, all, or custom.',
    });
  }
  if (!message || message.length < 3) {
    return res.status(400).json({ message: 'Enter a message (at least 3 characters).' });
  }
  if (message.length > SMS_BLAST_MAX_LENGTH) {
    return res.status(400).json({
      message: `Message too long (max ${SMS_BLAST_MAX_LENGTH} characters).`,
    });
  }

  try {
    let phones = await resolveSmsAudiencePhones(audience, { phones: customPhones, region });
    if (!phones.length) {
      return res.status(400).json({ message: 'No valid phone numbers found for this audience.' });
    }
    if (phones.length > SMS_BLAST_MAX_RECIPIENTS) {
      phones = phones.slice(0, SMS_BLAST_MAX_RECIPIENTS);
    }

    const results: { phone: string; ok: boolean; error?: string }[] = [];
    let sent = 0;
    let failed = 0;

    for (const phone of phones) {
      try {
        await sendSMS(phone, message);
        sent += 1;
        results.push({ phone, ok: true });
      } catch (err: any) {
        failed += 1;
        results.push({ phone, ok: false, error: err?.message || 'Send failed' });
      }
      // Gentle throttle for INTEK gateway
      await new Promise((r) => setTimeout(r, 120));
    }

    console.info(
      `[admin/sms/blast] admin=${req.user.id} audience=${audience} sent=${sent} failed=${failed}`,
    );

    res.json({
      success: failed === 0,
      audience,
      region,
      message_preview: message.slice(0, 80) + (message.length > 80 ? '…' : ''),
      total: phones.length,
      sent,
      failed,
      results: results.slice(0, 50),
    });
  } catch (err: any) {
    console.error('[admin/sms/blast]', err);
    res.status(502).json({ message: err.message || 'SMS blast failed' });
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

/** Rider — commission owed (COD trips) and 8am deadline. */
app.get('/api/rider/commission/summary', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') return res.sendStatus(403);
  try {
    await refreshRiderSettlementStatus(req.user.id);
    const settings = await getCommissionSettings();
    const rows = await pool.query(
      `SELECT * FROM rider_daily_settlements
       WHERE rider_id = $1 AND commission_total > amount_paid + 0.01
       ORDER BY settlement_date ASC`,
      [req.user.id]
    );
    const settlements = rows.rows.map((s: any) => {
      const owed = moneyRound(parseFloat(s.commission_total) - parseFloat(s.amount_paid));
      return {
        id: s.id,
        settlement_date: s.settlement_date,
        commission_total: parseFloat(s.commission_total),
        insurance_total: parseFloat(s.insurance_total),
        platform_total: parseFloat(s.platform_total),
        amount_paid: parseFloat(s.amount_paid),
        amount_owed: owed,
        status: s.status,
        due_at: s.due_at,
        paid_at: s.paid_at,
        is_overdue: new Date(s.due_at).getTime() < Date.now() && owed > 0,
      };
    });
    const totalOwed = moneyRound(
      settlements.reduce((sum: number, s: any) => sum + s.amount_owed, 0)
    );
    const overdue = settlements.some((s: any) => s.is_overdue);
    const walletBalance = await getRiderSpendableBalance(req.user.id);
    res.json({
      commission_percent: settings.totalPercent,
      insurance_percent: settings.insurancePercent,
      platform_percent: settings.platformPercent,
      total_owed: totalOwed,
      has_overdue: overdue,
      can_go_online: !overdue,
      wallet_balance: walletBalance,
      withdrawable_balance: walletBalance,
      can_pay_from_wallet: walletBalance >= totalOwed - 0.01,
      settlements,
      policy:
        `BytzGo takes ${settings.totalPercent}% commission per trip. ` +
        'Cash trips: pay commission with Mobile Money or card by 8:00 AM Ghana time the next day. ' +
        'Cash collected from customers is not added to your wallet.',
    });
  } catch (err) {
    console.error('[rider/commission/summary]', err);
    res.status(500).json({ message: 'Failed to load commission summary' });
  }
});

async function loadOwedCommissionSettlements(
  client: { query: typeof pool.query },
  riderId: string,
  settlementId?: string,
  forUpdate = false
) {
  await refreshRiderSettlementStatus(riderId);
  const lock = forUpdate ? ' FOR UPDATE' : '';
  if (settlementId) {
    const r = await client.query(
      `SELECT * FROM rider_daily_settlements
       WHERE id = $1 AND rider_id = $2 AND commission_total > amount_paid + 0.01${lock}`,
      [settlementId, riderId]
    );
    return r.rows;
  }
  const r = await client.query(
    `SELECT * FROM rider_daily_settlements
     WHERE rider_id = $1 AND commission_total > amount_paid + 0.01
     ORDER BY settlement_date ASC${lock}`,
    [riderId]
  );
  return r.rows;
}

function commissionOwedTotal(settlements: any[]): number {
  let totalDue = 0;
  for (const s of settlements) {
    totalDue += parseFloat(s.commission_total) - parseFloat(s.amount_paid);
  }
  return moneyRound(totalDue);
}

async function applyRiderCommissionSettlement(
  client: { query: typeof pool.query },
  riderId: string,
  settlements: any[],
  mode: 'wallet' | 'paystack',
  paystackReference?: string
) {
  if (settlements.length === 0) {
    throw new Error('No commission balance to pay');
  }
  const totalDue = commissionOwedTotal(settlements);

  if (mode === 'paystack') {
    const ref = String(paystackReference || '').trim();
    if (!ref) throw new Error('Payment reference is required');
    const used = await client.query(
      `SELECT 1 FROM wallet_transactions WHERE user_id = $1 AND reference = $2 LIMIT 1`,
      [riderId, ref]
    );
    if (used.rowCount && used.rowCount > 0) {
      return {
        paid: 0,
        balance: await getRiderSpendableBalance(riderId, client),
        alreadyProcessed: true,
      };
    }
    await client.query(
      `INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)`,
      [riderId, -totalDue, 'payment', `MoMo/card commission · ${ref}`]
    );
  } else {
    await client.query('SELECT id FROM users WHERE id = $1 FOR UPDATE', [riderId]);
    const balance = await getRiderSpendableBalance(riderId, client);
    if (balance < totalDue - 0.01) {
      const err = new Error(
        `Insufficient wallet balance. Need ₵${totalDue.toFixed(2)}, have ₵${balance.toFixed(2)}. Pay with Mobile Money or card instead.`
      );
      throw err;
    }
    await client.query('UPDATE users SET balance = balance - $1 WHERE id = $2', [totalDue, riderId]);
    await client.query(
      `INSERT INTO wallet_transactions (user_id, amount, type, reference) VALUES ($1, $2, $3, $4)`,
      [
        riderId,
        -totalDue,
        'payment',
        `Trip commission settlement (${settlements.length} day(s))`,
      ]
    );
  }

  const now = new Date();
  for (const s of settlements) {
    await client.query(
      `UPDATE rider_daily_settlements SET
        amount_paid = commission_total,
        status = 'paid',
        paid_at = $2,
        updated_at = CURRENT_TIMESTAMP
       WHERE id = $1`,
      [s.id, now]
    );
  }

  return {
    paid: totalDue,
    balance: await getRiderSpendableBalance(riderId, client),
    alreadyProcessed: false,
  };
}

app.post('/api/rider/commission/pay', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') return res.sendStatus(403);
  const { settlement_id } = req.body || {};
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const settlements = await loadOwedCommissionSettlements(
      client,
      req.user.id,
      settlement_id,
      true
    );
    if (settlements.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'No commission balance to pay' });
    }
    const result = await applyRiderCommissionSettlement(client, req.user.id, settlements, 'wallet');
    await client.query('COMMIT');
    await emitWalletUpdated(req.user.id, req.user.role);
    res.json({
      success: true,
      paid: result.paid,
      balance: result.balance,
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('[rider/commission/pay]', err);
    const message = err instanceof Error ? err.message : 'Commission payment failed';
    const status = message.includes('Insufficient') ? 400 : 500;
    res.status(status).json({ message });
  } finally {
    client.release();
  }
});

app.post('/api/rider/commission/paystack/initialize', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') return res.sendStatus(403);
  const { settlement_id } = req.body || {};
  try {
    await refreshRiderSettlementStatus(req.user.id);
    const settlements = await loadOwedCommissionSettlements(pool, req.user.id, settlement_id);
    if (settlements.length === 0) {
      return res.status(400).json({ message: 'No commission balance to pay' });
    }
    const totalDue = commissionOwedTotal(settlements);
    const userRes = await pool.query(
      'SELECT id, email, phone, status FROM users WHERE id = $1',
      [req.user.id]
    );
    const row = userRes.rows[0];
    if (!row || row.status === 'disabled') {
      return res.status(403).json({ message: 'Your account is disabled.' });
    }

    const checkout = await initializePaystackPayment(totalDue, row, {
      type: 'rider_commission',
      settlement_ids: settlements.map((s: any) => s.id),
    });

    res.json({
      reference: checkout.reference,
      authorization_url: checkout.authorizationUrl,
      access_code: checkout.accessCode,
      amount: checkout.amountGhs,
      total_owed: totalDue,
    });
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Could not start payment';
    console.error('[rider/commission/paystack/initialize]', message);
    const status = message.includes('not configured') ? 503 : 400;
    res.status(status).json({ message });
  }
});

app.post('/api/rider/commission/paystack/verify', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') return res.sendStatus(403);
  const reference = typeof req.body?.reference === 'string' ? req.body.reference.trim() : '';
  if (!reference) {
    return res.status(400).json({ message: 'Payment reference is required' });
  }

  const client = await pool.connect();
  try {
    const verified = await verifyPaystackTransaction(reference);
    if (verified.currency && verified.currency !== 'GHS') {
      return res.status(400).json({ message: `Unexpected currency: ${verified.currency}` });
    }

    await client.query('BEGIN');
    const settlements = await loadOwedCommissionSettlements(client, req.user.id, undefined, true);
    if (settlements.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ message: 'No commission balance to pay' });
    }
    const totalDue = commissionOwedTotal(settlements);
    if (verified.amountGhs < totalDue - 0.02) {
      await client.query('ROLLBACK');
      return res.status(400).json({
        message: `Payment amount ₵${verified.amountGhs.toFixed(2)} is less than commission owed ₵${totalDue.toFixed(2)}.`,
      });
    }

    const result = await applyRiderCommissionSettlement(
      client,
      req.user.id,
      settlements,
      'paystack',
      reference
    );
    await client.query('COMMIT');
    await emitWalletUpdated(req.user.id, req.user.role);
    res.json({
      success: true,
      paid: result.paid,
      balance: result.balance,
      alreadyProcessed: result.alreadyProcessed === true,
    });
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('[rider/commission/paystack/verify]', err);
    const message = err instanceof Error ? err.message : 'Commission payment failed';
    res.status(500).json({ message });
  } finally {
    client.release();
  }
});

/** Admin — full driver profile for map tap / fleet management. */
app.get('/api/admin/riders/:id/profile', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { id } = req.params;
  try {
    const userRes = await pool.query(
      `SELECT u.id, u.name, u.email, u.phone, u.region, u.status, u.is_online, u.balance,
              u.lat, u.lng, u.address, u.avatar_url, u.created_at, u.rider_vehicle_type,
              rl.lat AS live_lat, rl.lng AS live_lng, rl.updated_at AS location_updated_at
       FROM users u
       LEFT JOIN rider_locations rl ON rl.rider_id = u.id
       WHERE u.id = $1 AND u.role = 'rider'`,
      [id]
    );
    const user = userRes.rows[0];
    if (!user) return res.status(404).json({ message: 'Driver not found' });

    const docsRes = await pool.query(
      `SELECT doc_type, review_status, rejection_reason, uploaded_at, reviewed_at
       FROM rider_documents WHERE user_id = $1 ORDER BY doc_type`,
      [id]
    );

    const statsRes = await pool.query(
      `SELECT
        COUNT(*) FILTER (WHERE status = 'delivered')::int AS trips_delivered,
        COUNT(*) FILTER (WHERE status NOT IN ('delivered', 'cancelled'))::int AS trips_active,
        COALESCE(AVG(rating) FILTER (WHERE rating IS NOT NULL), 0)::float AS avg_rating,
        COUNT(*) FILTER (WHERE rating IS NOT NULL)::int AS rating_count,
        COALESCE(SUM(delivery_fee) FILTER (WHERE status = 'delivered'), 0)::float AS delivery_earnings,
        COALESCE(SUM(total) FILTER (WHERE status = 'delivered'), 0)::float AS order_value_delivered
       FROM orders WHERE rider_id = $1`,
      [id]
    );

    let commissionTotals = {
      commission_accrued: 0,
      insurance_accrued: 0,
      platform_accrued: 0,
    };
    let settlements: any[] = [];
    try {
      const commissionRes = await pool.query(
        `SELECT
          COALESCE(SUM(commission_total), 0)::float AS commission_accrued,
          COALESCE(SUM(insurance_amount), 0)::float AS insurance_accrued,
          COALESCE(SUM(platform_amount), 0)::float AS platform_accrued
         FROM order_commissions WHERE rider_id = $1`,
        [id]
      );
      if (commissionRes.rows[0]) commissionTotals = commissionRes.rows[0];

      await refreshRiderSettlementStatus(id);
      const settlementsRes = await pool.query(
        `SELECT * FROM rider_daily_settlements WHERE rider_id = $1 ORDER BY settlement_date DESC LIMIT 14`,
        [id]
      );
      settlements = settlementsRes.rows.map((s: any) => ({
        id: s.id,
        settlement_date: s.settlement_date,
        commission_total: parseFloat(s.commission_total),
        insurance_total: parseFloat(s.insurance_total),
        platform_total: parseFloat(s.platform_total),
        amount_paid: parseFloat(s.amount_paid),
        amount_owed: moneyRound(parseFloat(s.commission_total) - parseFloat(s.amount_paid)),
        status: s.status,
        due_at: s.due_at,
        paid_at: s.paid_at,
      }));
    } catch (commissionErr) {
      console.warn('[admin/riders/profile] commission data skipped:', commissionErr);
    }

    const recentTripsRes = await pool.query(
      `SELECT id, status, total, delivery_fee, payment_status, rating, created_at, address, pickup_address
       FROM orders WHERE rider_id = $1 ORDER BY created_at DESC LIMIT 15`,
      [id]
    );

    const settings = await getCommissionSettings();

    res.json({
      driver: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        region: user.region,
        status: user.status,
        is_online: user.is_online === true,
        balance: parseFloat(user.balance),
        address: user.address,
        avatar_url: user.avatar_url,
        rider_vehicle_type: user.rider_vehicle_type ?? 'motorcycle',
        created_at: user.created_at,
        profile_lat: user.lat != null ? parseFloat(user.lat) : null,
        profile_lng: user.lng != null ? parseFloat(user.lng) : null,
        live_lat: user.live_lat != null ? parseFloat(user.live_lat) : null,
        live_lng: user.live_lng != null ? parseFloat(user.live_lng) : null,
        location_updated_at: user.location_updated_at,
        has_live_location:
          user.live_lat != null &&
          user.live_lng != null &&
          Math.abs(parseFloat(user.live_lat)) > 0.001 &&
          Math.abs(parseFloat(user.live_lng)) > 0.001,
      },
      stats: statsRes.rows[0],
      commission_policy: settings,
      commission_totals: commissionTotals,
      settlements,
      documents: docsRes.rows,
      recent_trips: recentTripsRes.rows,
    });
  } catch (err) {
    console.error('[admin/riders/profile]', err);
    res.status(500).json({ message: 'Failed to load driver profile' });
  }
});

app.patch('/api/admin/users/:id/status', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const { status } = req.body;
  const { id } = req.params;
  try {
    const before = await pool.query('SELECT status, role FROM users WHERE id = $1', [id]);
    const isRiderActivate = status === 'active';
    const result = await pool.query(
      `UPDATE users SET status = $1,
        is_online = CASE WHEN role = 'rider' AND $3 THEN false ELSE is_online END
       WHERE id = $2 RETURNING id, name, email, role, status, is_online`,
      [status, id, isRiderActivate]
    );
    if (result.rows[0]) {
      const row = result.rows[0];
      invalidateAuthStatus(id);
      if (row.role === 'rider' && status === 'active') {
        await pool.query(
          `UPDATE rider_documents SET review_status = 'approved', rejection_reason = NULL,
            reviewed_by = $2, reviewed_at = CURRENT_TIMESTAMP WHERE user_id = $1`,
          [id, req.user.id]
        );
      }
      res.json(row);
      io.to(id).emit('status:updated', { status, is_online: row.is_online });
      if (status === 'active' && before.rows[0]?.status !== 'active') {
        const kind = roleToApprovalKind(row.role);
        if (kind) void notifyApprovalSms(id, kind);
      }
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
    if (req.user.role === 'customer') {
      await repairStaleTripsForCustomer(req.user.id);
    }
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
          (
            o.status = 'ready'
            OR (
              o.status = 'pending'
              AND o.vendor_id IS NOT NULL
              AND o.order_type IN ('food', 'courier')
            )
          )
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
        try {
          const row = await sanitizeOrderForRole(o, req.user.role, req.user.id);
          if (req.user.role === 'rider' && o.rider_offer_expires_at) {
            row.expiresAt = new Date(o.rider_offer_expires_at).toISOString();
            row.dispatchWave = o.rider_offer_wave;
          }
          return row;
        } catch (rowErr) {
          console.error('[orders] sanitize failed for', o?.id, rowErr);
          const fallback = { ...o };
          delete fallback.delivery_code;
          delete fallback.customer_phone;
          delete fallback.rider_phone;
          return fallback;
        }
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
    service_type,
    serviceType,
    passenger_count,
    passengerCount,
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
  const finalServiceType = normalizeRideServiceType(service_type ?? serviceType);
  const maxPax = RIDE_SERVICE_META[finalServiceType].maxPassengers;
  const rawPax = parseInt(String(passenger_count ?? passengerCount ?? 1), 10) || 1;
  const finalPassengerCount =
    finalServiceType === 'package' ? 0 : Math.max(1, Math.min(maxPax, rawPax));
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
    let orderPromotionId: string | null = null;
    let orderPromotionDiscount = 0;
    let orderRiderBonus = 0;
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
        finalRegion,
        finalServiceType,
        { promo_code: req.body.promo_code ?? req.body.promoCode, region: finalRegion }
      );
      finalDeliveryFee = quote.delivery_fee;
      orderPromotionId = quote.promotion_id;
      orderPromotionDiscount = quote.promotion_discount;
      orderRiderBonus = quote.rider_bonus_amount;
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

    const scheduledRaw = scheduledTime || scheduled_time || null;
    const scheduledDate = parseScheduledTimeInput(scheduledRaw);
    const scheduled = scheduledDate ? scheduledDate.toISOString() : null;
    const initialStatus = isFutureScheduled(scheduledDate)
      ? 'scheduled'
      : finalOrderType === 'courier' || (vendorId && finalOrderType === 'food')
        ? 'ready'
        : 'pending';

    const result = await pool.query(
      `INSERT INTO orders (
        customer_id, vendor_id, items, total, status, address, pickup_address, order_type,
        scheduled_time, lat, lng, pickup_lat, pickup_lng, region, payment_status, payment_method,
        delivery_fee, service_type, passenger_count, promotion_id, promotion_discount, rider_bonus_amount
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19, $20, $21, $22) RETURNING *`,
      [
        req.user.id,
        vendorId,
        JSON.stringify(items),
        total,
        initialStatus,
        address || 'Customer Address',
        finalPickup || 'Pickup',
        finalOrderType,
        scheduled,
        lat,
        lng,
        pickupLat,
        pickupLng,
        finalRegion,
        paymentStatus,
        finalPaymentMethod,
        finalDeliveryFee,
        finalServiceType,
        finalServiceType === 'package' ? 0 : finalPassengerCount,
        orderPromotionId,
        orderPromotionDiscount,
        orderRiderBonus,
      ]
    );
    const order = result.rows[0];
    if (orderPromotionId) {
      await pool.query(
        `UPDATE ride_promotions
         SET redemption_count = redemption_count + 1, updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [orderPromotionId]
      );
    }
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
    const userRes = await pool.query(
      'SELECT status, is_online FROM users WHERE id = $1',
      [req.user.id]
    );
    const account = userRes.rows[0];
    if (account?.status !== 'active') {
      return res.status(403).json({ message: 'Go online to respond to ride offers.' });
    }
    await recordRiderDecline(orderId, req.user.id);
    res.json({ ok: true });
  } catch (err) {
    console.error('[dispatch] decline failed:', err);
    // Idempotent — rider already dismissed UI; don't surface a scary error.
    res.json({ ok: true, note: 'offer_closed' });
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
    await ensureDeliveryCode(orderId);
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
    await ensureDeliveryCode(orderId);
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

    const expectedCode = order.delivery_code || (await ensureDeliveryCode(orderId));
    if (expectedCode !== String(code).trim()) {
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
    void broadcastOrderUpdated(delivered).catch((broadcastErr) => {
      console.error('[complete-delivery] broadcast failed:', broadcastErr);
    });

    let payload = delivered;
    try {
      const loaded = await loadOrderWithContacts(orderId);
      if (loaded) payload = loaded;
    } catch (loadErr) {
      console.warn('[complete-delivery] load contacts failed:', loadErr);
    }

    try {
      return res.json(await sanitizeOrderForRole(payload, 'rider', req.user.id));
    } catch (sanitizeErr) {
      console.error('[complete-delivery] sanitize failed:', sanitizeErr);
      return res.json({
        id: payload.id,
        customer_id: payload.customer_id,
        vendor_id: payload.vendor_id,
        rider_id: payload.rider_id,
        items: payload.items,
        total: payload.total,
        status: payload.status,
        address: payload.address,
        created_at: payload.created_at,
        updated_at: payload.updated_at,
        payment_status: payload.payment_status,
        delivery_fee: payload.delivery_fee,
      });
    }
  } catch (err) {
    console.error('Complete delivery error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/** Customer confirms package received — closes hung PIN trips without rider entering code. */
app.post('/api/orders/:id/confirm-received', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'customer') return res.status(403).json({ message: 'Customers only' });
  const orderId = req.params.id;
  try {
    const orderRes = await pool.query(
      'SELECT * FROM orders WHERE id = $1 AND customer_id = $2',
      [orderId, req.user.id]
    );
    const order = orderRes.rows[0];
    if (!order) return res.status(404).json({ message: 'Order not found' });
    if (order.status !== 'arrived') {
      return res.status(400).json({ message: 'Confirm receipt when your driver has arrived.' });
    }
    if (!isCustomerPaymentReady(order)) {
      return res.status(400).json({ message: 'Confirm payment before marking delivery complete.' });
    }
    const result = await pool.query(
      `UPDATE orders SET status = 'delivered', updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`,
      [orderId]
    );
    const delivered = result.rows[0];
    try {
      await settleOrderPayment(delivered);
    } catch (e) {
      console.error('[confirm-received] settlement failed:', e);
    }
    broadcastOrderUpdated(delivered);
    res.json(await sanitizeOrderForRole(delivered, 'customer', req.user.id));
  } catch (err) {
    console.error('Confirm received error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/** Admin force-complete a stuck trip (no PIN required). */
app.post('/api/admin/orders/:id/complete', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const orderId = req.params.id;
  try {
    const orderRes = await pool.query('SELECT * FROM orders WHERE id = $1', [orderId]);
    const order = orderRes.rows[0];
    if (!order) return res.status(404).json({ message: 'Order not found' });
    if (['delivered', 'cancelled'].includes(order.status)) {
      return res.json(await sanitizeOrderForRole(order, 'admin', req.user.id));
    }
    const result = await pool.query(
      `UPDATE orders SET status = 'delivered', updated_at = CURRENT_TIMESTAMP WHERE id = $1 RETURNING *`,
      [orderId]
    );
    const delivered = result.rows[0];
    try {
      await settleOrderPayment(delivered);
    } catch (e) {
      console.error('[admin/complete] settlement failed:', e);
    }
    broadcastOrderUpdated(delivered);
    res.json(delivered);
  } catch (err) {
    console.error('Admin complete order error:', err);
    res.status(500).json({ message: 'Server error' });
  }
});

/** Admin cancel a stuck trip. */
app.post('/api/admin/orders/:id/cancel', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.sendStatus(403);
  const orderId = req.params.id;
  try {
    const result = await pool.query(
      `UPDATE orders SET status = 'cancelled', rider_id = NULL, updated_at = CURRENT_TIMESTAMP
       WHERE id = $1 AND status NOT IN ('delivered', 'cancelled') RETURNING *`,
      [orderId]
    );
    if (!result.rows[0]) return res.status(404).json({ message: 'Order not found or already closed' });
    broadcastOrderUpdated(result.rows[0]);
    res.json(result.rows[0]);
  } catch (err) {
    console.error('Admin cancel order error:', err);
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
      `SELECT m.*, u.name AS sender_name, u.role AS sender_role
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
    const nameRes = await pool.query('SELECT name, role FROM users WHERE id = $1', [
      req.user.id,
    ]);
    row.sender_name = nameRes.rows[0]?.name;
    row.sender_role = nameRes.rows[0]?.role;

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
      const senderName = displayUserName(nameRes.rows[0]?.name, {
        role: nameRes.rows[0]?.role,
        fallback: 'Someone',
      });
      void sendPushToUserIds([recipientId], {
        title: `Message from ${senderName}`,
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
            body: `${displayUserName(nameRes.rows[0]?.name, {
              role: nameRes.rows[0]?.role,
              fallback: 'BytzGo user',
            })}: ${subject}`,
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
      'UPDATE products SET is_approved = true WHERE id = $1 RETURNING id, name, vendor_id',
      [req.params.id]
    );
    if (!result.rows[0]) return res.status(404).json({ message: 'Product not found' });
    const product = result.rows[0];
    res.json(product);
    if (product.vendor_id) {
      void notifyApprovalSms(product.vendor_id, 'product', { productName: product.name });
    }
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
    const minFee = await getSetting('delivery_min_fee');
    const maxFee = await getSetting('delivery_max_fee');
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
      commission_percent: (await getSetting('commission_percent')) || '10',
      commission_insurance_percent: (await getSetting('commission_insurance_percent')) || '3',
      commission_platform_percent: (await getSetting('commission_platform_percent')) || '7',
      delivery_price_per_km: pricePerKm || '4',
      delivery_min_fee: minFee ?? '',
      delivery_max_fee: maxFee ?? '',
      okada_price_per_km: (await getSetting('okada_price_per_km')) || '3.5',
      okada_min_fee: (await getSetting('okada_min_fee')) || '6',
      keke_price_per_km: (await getSetting('keke_price_per_km')) || '2.5',
      keke_min_fee: (await getSetting('keke_min_fee')) || '5',
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
    commission_percent,
    commission_insurance_percent,
    commission_platform_percent,
    delivery_price_per_km,
    delivery_min_fee,
    delivery_max_fee,
    okada_price_per_km,
    okada_min_fee,
    keke_price_per_km,
    keke_min_fee,
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
    delivery_min_fee != null ||
    delivery_max_fee != null ||
    okada_price_per_km != null ||
    okada_min_fee != null ||
    keke_price_per_km != null ||
    keke_min_fee != null ||
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
    if (commission_percent != null) {
      const pct = Math.max(0, Math.min(100, parseFloat(String(commission_percent)) || 10));
      await setSetting('commission_percent', String(pct));
    }
    if (commission_insurance_percent != null) {
      const pct = Math.max(0, Math.min(100, parseFloat(String(commission_insurance_percent)) || 3));
      await setSetting('commission_insurance_percent', String(pct));
    }
    if (commission_platform_percent != null) {
      const pct = Math.max(0, Math.min(100, parseFloat(String(commission_platform_percent)) || 7));
      await setSetting('commission_platform_percent', String(pct));
    }
    if (delivery_price_per_km != null) {
      const rate = Math.max(0.01, parseFloat(String(delivery_price_per_km)) || 4);
      await setSetting('delivery_price_per_km', String(rate));
      await pool.query(
        `UPDATE delivery_zones SET price_per_km = $1 WHERE is_active = true`,
        [rate]
      );
    }
    if (delivery_min_fee != null) {
      const trimmed = String(delivery_min_fee).trim();
      if (trimmed === '') {
        await setSetting('delivery_min_fee', '');
      } else {
        const min = Math.max(0.01, parseFloat(trimmed) || 0);
        await setSetting('delivery_min_fee', String(min));
      }
    }
    if (delivery_max_fee != null) {
      const trimmed = String(delivery_max_fee).trim();
      if (trimmed === '') {
        await setSetting('delivery_max_fee', '');
      } else {
        const max = Math.max(0.01, parseFloat(trimmed) || 0);
        await setSetting('delivery_max_fee', String(max));
      }
    }
    if (okada_price_per_km != null) {
      const rate = Math.max(0.01, parseFloat(String(okada_price_per_km)) || 3.5);
      await setSetting('okada_price_per_km', String(rate));
    }
    if (okada_min_fee != null) {
      const min = Math.max(0, parseFloat(String(okada_min_fee)) || 0);
      await setSetting('okada_min_fee', String(min));
    }
    if (keke_price_per_km != null) {
      const rate = Math.max(0.01, parseFloat(String(keke_price_per_km)) || 2.5);
      await setSetting('keke_price_per_km', String(rate));
    }
    if (keke_min_fee != null) {
      const min = Math.max(0, parseFloat(String(keke_min_fee)) || 0);
      await setSetting('keke_min_fee', String(min));
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
    let pricing: Awaited<ReturnType<typeof buildPublicPricingPayload>> | undefined;
    if (pricingTouched) {
      pricing = await buildPublicPricingPayload();
      io.emit('pricing:updated', pricing);
    }
    res.json({ success: true, message: 'Settings updated', pricing });
  } catch (err) {
    res.status(500).json({ message: 'Failed to update settings' });
  }
});

app.get('/api/admin/promotions', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  try {
    await ensureRidePromotionsSchema();
    const result = await pool.query(
      `SELECT * FROM ride_promotions ORDER BY updated_at DESC, created_at DESC`
    );
    res.json(result.rows.map((row) => ridePromotionForClient(row as RidePromotionRow)));
  } catch (err) {
    res.status(500).json({ message: 'Failed to load promotions' });
  }
});

app.post('/api/admin/promotions', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  const {
    name,
    code,
    service_types,
    customer_discount_percent,
    customer_discount_fixed,
    rider_bonus_amount,
    target_region,
    enabled,
    starts_at,
    ends_at,
    max_redemptions,
    announce_sms,
  } = req.body;
  if (!String(name || '').trim()) {
    return res.status(400).json({ message: 'Promotion name is required' });
  }
  try {
    await ensureRidePromotionsSchema();
    const result = await pool.query(
      `INSERT INTO ride_promotions (
        name, code, service_types, customer_discount_percent, customer_discount_fixed,
        rider_bonus_amount, target_region, enabled, starts_at, ends_at, max_redemptions
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING *`,
      [
        String(name).trim(),
        code ? String(code).trim().toUpperCase() : null,
        String(service_types || 'okada,keke,package').trim(),
        Math.max(0, Math.min(100, parseFloat(String(customer_discount_percent)) || 0)),
        Math.max(0, parseFloat(String(customer_discount_fixed)) || 0),
        Math.max(0, parseFloat(String(rider_bonus_amount)) || 0),
        target_region ? String(target_region).trim() : null,
        enabled !== false,
        starts_at || null,
        ends_at || null,
        max_redemptions != null && max_redemptions !== ''
          ? Math.max(1, parseInt(String(max_redemptions), 10) || 0)
          : null,
      ]
    );
    const promo = result.rows[0] as RidePromotionRow;
    res.status(201).json(ridePromotionForClient(promo));
    const shouldAnnounce = announce_sms !== false && promo.enabled !== false;
    if (shouldAnnounce) {
      void announcePromotionSms(promo, { force: true });
    }
  } catch (err) {
    res.status(500).json({ message: 'Failed to create promotion' });
  }
});

app.patch('/api/admin/promotions/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  const { id } = req.params;
  const fields = [
    'name',
    'code',
    'service_types',
    'customer_discount_percent',
    'customer_discount_fixed',
    'rider_bonus_amount',
    'target_region',
    'enabled',
    'starts_at',
    'ends_at',
    'max_redemptions',
  ] as const;
  const updates: string[] = [];
  const values: unknown[] = [];
  let idx = 1;
  for (const key of fields) {
    if (req.body[key] === undefined) continue;
    let val = req.body[key];
    if (key === 'code') val = val ? String(val).trim().toUpperCase() : null;
    else if (key === 'name') val = String(val).trim();
    else if (key === 'service_types') val = String(val).trim();
    else if (key === 'target_region') val = val ? String(val).trim() : null;
    else if (key === 'enabled') val = val === true || val === 'true' || val === 1 || val === '1';
    else if (key === 'customer_discount_percent') {
      val = Math.max(0, Math.min(100, parseFloat(String(val)) || 0));
    } else if (
      key === 'customer_discount_fixed' ||
      key === 'rider_bonus_amount'
    ) {
      val = Math.max(0, parseFloat(String(val)) || 0);
    } else if (key === 'max_redemptions') {
      val =
        val != null && val !== ''
          ? Math.max(1, parseInt(String(val), 10) || 0)
          : null;
    }
    updates.push(`${key} = $${idx++}`);
    values.push(val);
  }
  if (!updates.length) return res.status(400).json({ message: 'No fields to update' });
  updates.push('updated_at = CURRENT_TIMESTAMP');
  values.push(id);
  try {
    await ensureRidePromotionsSchema();
    const prev = await pool.query('SELECT * FROM ride_promotions WHERE id = $1', [id]);
    const result = await pool.query(
      `UPDATE ride_promotions SET ${updates.join(', ')} WHERE id = $${idx} RETURNING *`,
      values
    );
    if (!result.rows[0]) return res.status(404).json({ message: 'Promotion not found' });
    const promo = result.rows[0] as RidePromotionRow;
    res.json(ridePromotionForClient(promo));
    const enabledNow = promo.enabled === true;
    const wasEnabled = prev.rows[0]?.enabled === true;
    const shouldAnnounce =
      req.body.announce_sms === true || (req.body.enabled === true && !wasEnabled && enabledNow);
    if (shouldAnnounce) {
      void announcePromotionSms(promo, { force: req.body.announce_sms === true });
    }
  } catch (err) {
    res.status(500).json({ message: 'Failed to update promotion' });
  }
});

app.post('/api/admin/promotions/:id/announce', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  try {
    await ensureRidePromotionsSchema();
    const result = await pool.query('SELECT * FROM ride_promotions WHERE id = $1', [req.params.id]);
    if (!result.rows[0]) return res.status(404).json({ message: 'Promotion not found' });
    const promo = result.rows[0] as RidePromotionRow;
    if (!promo.enabled) {
      return res.status(400).json({ message: 'Enable the promotion before sending SMS' });
    }
    const outcome = await announcePromotionSms(promo, { force: true });
    res.json({
      success: true,
      sent: outcome.sent,
      skipped: outcome.skipped,
      message:
        outcome.sent > 0
          ? `Promotion SMS sent to ${outcome.sent} phone(s)`
          : outcome.skipped
            ? 'SMS already announced for this promotion (use force via re-enable)'
            : 'No matching phone numbers found',
    });
  } catch (err: any) {
    res.status(502).json({ message: err?.message || 'Failed to announce promotion' });
  }
});

app.delete('/api/admin/promotions/:id', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'admin') return res.status(403).json({ message: 'Unauthorized' });
  try {
    await ensureRidePromotionsSchema();
    const result = await pool.query('DELETE FROM ride_promotions WHERE id = $1 RETURNING id', [
      req.params.id,
    ]);
    if (!result.rows[0]) return res.status(404).json({ message: 'Promotion not found' });
    res.json({ success: true });
  } catch (err) {
    res.status(500).json({ message: 'Failed to delete promotion' });
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
    const globalBounds = await getGlobalDeliveryBounds();
    const km = distance_km || 0;
    const feeFromDistance = Math.round(km * globalRate * 100) / 100;
    const price = applyDeliveryFeeCaps(feeFromDistance, zone, globalBounds);

    res.json({
      price,
      zone: zone?.name ?? null,
      fallback: !zone,
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
    service_type,
    serviceType,
    promo_code,
    promoCode,
  } = req.body;
  const pLat = Number(pickup_lat);
  const pLng = Number(pickup_lng);
  const dLat = Number(dest_lat ?? destination_lat);
  const dLng = Number(dest_lng ?? destination_lng);
  const rideService = normalizeRideServiceType(service_type ?? serviceType);
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
      destination_region,
      rideService,
      { promo_code: promo_code ?? promoCode, region: destination_region ?? pickup_region }
    );
    const meta = RIDE_SERVICE_META[rideService];
    res.json({
      ...quote,
      service_type: rideService,
      service_label: meta.label,
      max_passengers: meta.maxPassengers,
      route: {
        legs: [
          {
            from: rideService === 'package' ? 'pickup' : 'you',
            to: 'destination',
            label:
              rideService === 'package'
                ? 'Pickup → Drop-off'
                : `${meta.label} ride`,
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
      [req.user.id, token.trim(), String(platform || 'android').toLowerCase()]
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

/** Rider: verify FCM token is saved (debug lock-screen job alerts). */
app.get('/api/push/status', authenticateToken, async (req: any, res) => {
  try {
    const rows = await pool.query(
      `SELECT platform, updated_at FROM fcm_tokens WHERE user_id = $1 ORDER BY updated_at DESC`,
      [req.user.id]
    );
    res.json({
      fcmEnabled: firebaseAdminHasCredentials,
      tokens: rows.rows,
    });
  } catch (err) {
    res.status(500).json({ message: 'Failed to read push status' });
  }
});

/** Rider must be online. Sends a test incoming-job push to this device. */
app.post('/api/push/test-incoming-ride', authenticateToken, async (req: any, res) => {
  if (req.user.role !== 'rider') {
    return res.status(403).json({ message: 'Riders only' });
  }
  if (!req.user.is_online) {
    return res.status(400).json({
      message: 'Go Online first — then lock the screen and call this again',
    });
  }
  try {
    const tokRes = await pool.query(
      `SELECT token, platform FROM fcm_tokens WHERE user_id = $1`,
      [req.user.id]
    );
    if (!tokRes.rows.length) {
      return res.status(400).json({
        message:
          'No push token on file. Open BytzGo, allow notifications, go Online, wait a few seconds.',
        tokens: 0,
      });
    }
    await sendPushToUserIds([req.user.id], {
      title: 'Test delivery job',
      body: 'Screen-off alert test — tap to open BytzGo',
      type: 'incoming-ride',
      orderId: 'test-push',
      channelId: 'incoming_rides_alarm',
      highPriority: true,
    });
    res.json({
      ok: true,
      hint: 'Lock your phone now — you should get a banner and sound within a few seconds.',
      tokens: tokRes.rows.map((r: { platform?: string; token: string }) => ({
        platform: r.platform,
        prefix: `${String(r.token).slice(0, 10)}…`,
      })),
    });
  } catch (err) {
    console.error('test incoming-ride push error:', err);
    res.status(500).json({ message: 'Test push failed' });
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
function socketTokenFromHandshake(socket: any): string | null {
  const authToken = socket.handshake?.auth?.token;
  if (typeof authToken === 'string' && authToken.trim()) return authToken.trim();
  const header = socket.handshake?.headers?.authorization;
  if (typeof header === 'string' && header.startsWith('Bearer ')) {
    return header.slice(7).trim();
  }
  return null;
}

io.use((socket, next) => {
  const token = socketTokenFromHandshake(socket);
  if (!token) {
    (socket as any).data = { user: null };
    return next();
  }
  jwt.verify(token, process.env.JWT_SECRET as string, (err: any, user: any) => {
    (socket as any).data = { user: err ? null : user };
    next();
  });
});

io.on('connection', (socket) => {
  console.log('User connected:', socket.id);

  socket.on('join', (userId) => {
    if (!userId) return;
    const user = (socket as any).data?.user;
    const room = String(userId).trim();
    if (user && String(user.id) !== room) {
      console.warn(`[socket] join rejected for ${socket.id}: room ${room} != user ${user.id}`);
      return;
    }
    socket.join(room);
    console.log(`User ${room} joined their room`);
  });

  socket.on('location:update', async ({ userId, lat, lng }) => {
    if (!userId || lat == null || lng == null) return;
    const user = (socket as any).data?.user;
    const riderId = String(userId).trim();
    if (user) {
      if (String(user.id) !== riderId || user.role !== 'rider') return;
    }
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

/** In-app browser Google Sign-In for Android sideload APKs (avoids native certificate error 10). */
app.get('/auth/google-mobile', (_req, res) => {
  const file = path.join(__dirname, '..', 'public', 'google-sign-in-mobile.html');
  if (!fs.existsSync(file)) {
    return res.status(404).type('text/plain').send('Google mobile sign-in page not found');
  }
  res.set('Cache-Control', 'no-store');
  res.type('html').sendFile(file);
});

/** iOS build metadata (App Store / TestFlight — no IPA hosted here). */
app.get('/download/ios/version', (_req, res) => {
  const candidates = [
    path.join(__dirname, '..', 'public', 'ios-version.json'),
    path.join(__dirname, '..', 'dist', 'ios-version.json'),
  ];
  const file = candidates.find((p) => fs.existsSync(p));
  if (!file) {
    return res.json({ version: 'unknown', platform: 'ios' });
  }
  res.setHeader('Cache-Control', 'no-store');
  res.type('json').sendFile(file);
});

/** Direct APK install for testers / before Play listing (file copied by scripts/copy-apk-to-public.mjs). */
app.get('/download/android/version', (_req, res) => {
  const candidates = [
    path.join(__dirname, '..', 'public', 'android-version.json'),
    path.join(__dirname, '..', 'dist', 'android-version.json'),
  ];
  const file = candidates.find((p) => fs.existsSync(p));
  if (!file) {
    return res.json({ version: 'unknown' });
  }
  res.setHeader('Cache-Control', 'no-store');
  res.type('json').sendFile(file);
});

app.get('/download/android', (_req, res) => {
  // Prefer public/ — git-tracked release APK. dist/ is vite copy and can lag on Render.
  const candidates = [
    path.join(__dirname, '..', 'public', 'bytzgo.apk'),
    path.join(__dirname, '..', 'dist', 'bytzgo.apk'),
  ];
  const apk = candidates.find((p) => fs.existsSync(p));
  if (!apk) {
    return res.status(404).type('text/plain').send('APK not published yet. Check back after the next release.');
  }
  const stat = fs.statSync(apk);
  res.setHeader('Content-Type', 'application/vnd.android.package-archive');
  res.setHeader('Content-Disposition', 'attachment; filename="BytzGo.apk"');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Content-Length', String(stat.size));
  res.setHeader('Last-Modified', stat.mtime.toUTCString());
  res.setHeader('ETag', `"bytzgo-apk-${stat.size}-${stat.mtimeMs}"`);
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

app.use((err: any, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (err?.message === 'Not allowed by CORS') {
    return res.status(403).json({ message: 'Origin not allowed' });
  }
  console.error('Unhandled route error:', err);
  if (!res.headersSent) {
    res.status(500).json({ message: 'Server error' });
  }
});

assertProductionConfig();

const PORT = Number(process.env.PORT) || 3000;
const HOST = process.env.HOST || '0.0.0.0';

function shutdown(signal: string) {
  console.log(`[shutdown] ${signal} — closing HTTP server and DB pool`);
  httpServer.close(() => {
    pool
      .end()
      .then(() => process.exit(0))
      .catch(() => process.exit(1));
  });
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));
process.on('unhandledRejection', (reason) => {
  console.error('[process] unhandledRejection:', reason);
});
process.on('uncaughtException', (err) => {
  console.error('[process] uncaughtException:', err);
  shutdown('uncaughtException');
});

httpServer.listen(PORT, HOST, () => {
  console.log(`Server running on http://${HOST}:${PORT}`);
  console.log(`[dispatch] offer TTL ${OFFER_TTL_SEC}s, early waves offer ${ridersPerWave(1)} rider(s)`);
  void ensureRidePromotionsSchema().catch((err) =>
    console.warn('[promotions] schema init failed:', err)
  );
  void activateDueScheduledOrders().catch((err) =>
    console.warn('[dispatch] scheduled order activation failed:', err)
  );
  setInterval(() => {
    void activateDueScheduledOrders().catch((err) =>
      console.warn('[dispatch] scheduled order activation failed:', err)
    );
  }, 60_000);
});
