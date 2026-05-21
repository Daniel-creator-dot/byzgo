/**
 * Seed popular Accra shops (restaurants, groceries, etc.).
 *
 *   npm run seed:accra-places
 *   npm run seed:accra-groceries
 *   node backend/scripts/seed-accra-popular-places.mjs --file=accra_popular_places.json
 *
 * Optional: GOOGLE_MAPS_API_KEY fetches storefront photos from Google Places.
 */
import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import bcrypt from 'bcryptjs';
import pg from 'pg';
import axios from 'axios';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, '..', '..');
const DATA_DIR = path.join(__dirname, '..', 'data');
const PLACE_PASSWORD = 'Place@2026';

dotenv.config({ path: path.join(__dirname, '..', '.env') });
dotenv.config({ path: path.join(root, '.env.local') });

const fileArg = process.argv.find((a) => a.startsWith('--file='));
const DATA_FILE = fileArg
  ? fileArg.split('=')[1]
  : process.argv.includes('--groceries')
    ? 'accra_grocery_places.json'
    : 'accra_popular_places.json';
const DATA_PATH = path.join(DATA_DIR, DATA_FILE);

const GOOGLE_KEY =
  process.env.GOOGLE_MAPS_API_KEY?.trim() ||
  process.env.VITE_GOOGLE_MAPS_API_KEY?.trim() ||
  '';
const SUPABASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SUPABASE_KEY = (process.env.SUPABASE_SERVICE_ROLE_KEY || '').trim();
const SUPABASE_BUCKET = (process.env.SUPABASE_STORAGE_BUCKET || 'pictures').trim();

if (!process.env.DATABASE_URL) {
  console.error('DATABASE_URL is not set (backend/.env)');
  process.exit(1);
}

const pool = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.DATABASE_URL.includes('supabase.com')
    ? { rejectUnauthorized: false }
    : false,
});

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

async function fetchGooglePhotoUrl(place) {
  if (!GOOGLE_KEY) return place.cover_image || null;
  const query = place.google_query || `${place.name} ${place.address} Ghana`;
  try {
    const findRes = await axios.get(
      'https://maps.googleapis.com/maps/api/place/findplacefromtext/json',
      {
        params: {
          input: query,
          inputtype: 'textquery',
          fields: 'place_id,photos',
          locationbias: `circle:3000@${place.lat},${place.lng}`,
          key: GOOGLE_KEY,
        },
        timeout: 15000,
      }
    );
    const placeId = findRes.data?.candidates?.[0]?.place_id;
    if (!placeId) return place.cover_image || null;

    const detailRes = await axios.get(
      'https://maps.googleapis.com/maps/api/place/details/json',
      {
        params: { place_id: placeId, fields: 'photos', key: GOOGLE_KEY },
        timeout: 15000,
      }
    );
    const photoRef = detailRes.data?.result?.photos?.[0]?.photo_reference;
    if (!photoRef) return place.cover_image || null;

    const photoRes = await axios.get(
      'https://maps.googleapis.com/maps/api/place/photo',
      {
        params: { maxwidth: 800, photo_reference: photoRef, key: GOOGLE_KEY },
        responseType: 'arraybuffer',
        maxRedirects: 5,
        timeout: 20000,
      }
    );
    const buf = Buffer.from(photoRes.data);
    if (buf.length < 500) return place.cover_image || null;

    if (SUPABASE_URL && SUPABASE_KEY) {
      const objectKey = `covers/accra/${place.slug}.jpg`;
      const uploadUrl = `${SUPABASE_URL}/storage/v1/object/${SUPABASE_BUCKET}/${objectKey}`;
      await axios.post(uploadUrl, buf, {
        headers: {
          Authorization: `Bearer ${SUPABASE_KEY}`,
          apikey: SUPABASE_KEY,
          'Content-Type': 'image/jpeg',
          'x-upsert': 'true',
        },
        timeout: 30000,
      });
      return `${SUPABASE_URL}/storage/v1/object/public/${SUPABASE_BUCKET}/${objectKey}`;
    }

    if (buf.length <= 120_000) {
      return `data:image/jpeg;base64,${buf.toString('base64')}`;
    }
    return place.cover_image || null;
  } catch (err) {
    console.warn(`  photo skip ${place.name}: ${err.message}`);
    return place.cover_image || null;
  }
}

async function upsertPlace(client, place, hashedPassword, coverImage) {
  const email = `${place.slug}@places.bytzgo.net`;
  const description = [
    place.tagline,
    'Listed on BytzGo — coordinates match Google Maps.',
    `Call: ${place.phone}`,
  ]
    .filter(Boolean)
    .join(' · ');

  const category = place.shop_category || 'restaurant';

  const vendorRes = await client.query(
    `INSERT INTO users (name, email, password, role, region, address, lat, lng, phone, status, shop_category, cover_image, balance)
     VALUES ($1, $2, $3, 'vendor', 'Greater Accra', $4, $5, $6, $7, 'active', $8, $9, 0)
     ON CONFLICT (email) DO UPDATE SET
       name = EXCLUDED.name,
       region = EXCLUDED.region,
       address = EXCLUDED.address,
       lat = EXCLUDED.lat,
       lng = EXCLUDED.lng,
       phone = EXCLUDED.phone,
       status = 'active',
       shop_category = EXCLUDED.shop_category,
       cover_image = COALESCE(EXCLUDED.cover_image, users.cover_image)
     RETURNING id, name, email`,
    [
      place.name,
      email,
      hashedPassword,
      place.address,
      place.lat,
      place.lng,
      place.phone,
      category,
      coverImage,
    ]
  );

  const vendorId = vendorRes.rows[0].id;
  await client.query('DELETE FROM products WHERE vendor_id = $1', [vendorId]);

  for (const item of place.menu || []) {
    await client.query(
      `INSERT INTO products (vendor_id, name, description, price, category, is_available, is_approved)
       VALUES ($1, $2, $3, $4, 'Popular', true, true)`,
      [vendorId, item.name, description.slice(0, 200), item.price]
    );
  }

  return { row: vendorRes.rows[0], hasPhoto: Boolean(coverImage) };
}

async function main() {
  if (!fs.existsSync(DATA_PATH)) {
    console.error(`Missing ${DATA_PATH}`);
    process.exit(1);
  }

  const places = JSON.parse(fs.readFileSync(DATA_PATH, 'utf8'));
  if (!Array.isArray(places) || places.length === 0) {
    console.error('No places in JSON');
    process.exit(1);
  }

  const categoryLabel = places[0]?.shop_category || 'shop';
  console.log(`Seeding ${places.length} Accra ${categoryLabel} places from ${DATA_FILE}`);
  if (GOOGLE_KEY) {
    console.log('Google Places: fetching storefront photos…');
  } else {
    console.log('Tip: set GOOGLE_MAPS_API_KEY to pull photos from Google.');
  }

  const hashed = await bcrypt.hash(PLACE_PASSWORD, 10);
  const client = await pool.connect();

  try {
    await client.query('BEGIN');
    let n = 0;
    let photos = 0;
    for (const place of places) {
      let coverImage = place.cover_image || null;
      if (!coverImage && GOOGLE_KEY) {
        coverImage = await fetchGooglePhotoUrl(place);
        await sleep(250);
      }
      if (coverImage) photos += 1;

      const { row } = await upsertPlace(client, place, hashed, coverImage);
      n += 1;
      const photoTag = coverImage ? ' 📷' : '';
      console.log(`  ${n}. ${row.name} — ${place.phone}${photoTag}`);
    }
    await client.query('COMMIT');
    console.log('');
    console.log(`Done — ${n} places (${categoryLabel}), ${photos} with photos.`);
    console.log('App: Shops tab → pick category → call, map, menu & checkout.');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

main()
  .catch((err) => {
    console.error('Seed failed:', err.message);
    process.exit(1);
  })
  .finally(() => pool.end());
