# Media storage (production standard)

BytzGo uses a **validated upload pipeline** and **Supabase Storage** for images — the same pattern used by global marketplaces (object storage + CDN URLs, not base64 in Postgres).

## Architecture

```
Client (Flutter / Web)
    → POST /api/upload  (multipart + folder)
    → API: validate → resize/WebP → Supabase bucket
    → Returns HTTPS URL stored in Postgres
    → Apps load via CDN (cached_network_image / <img>)
```

| Folder | Visibility | Format | Max size | Use |
|--------|------------|--------|----------|-----|
| `avatars/` | Public CDN | WebP | 512px | Profile photos |
| `products/` | Public CDN | WebP | 1200px | Menu items |
| `covers/` | Public CDN | WebP | 1920×1080 | Shop banners |
| `rider-documents/` | Private | JPEG | 2400px | KYC (signed URLs only) |

## Security (international practice)

- **Magic-byte validation** — rejects non-images disguised as photos  
- **MIME allowlist** — JPEG, PNG, WebP only (no SVG/HTML)  
- **Dimension cap** — blocks decompression bombs (>8000px edge)  
- **EXIF stripped** — auto-rotate + re-encode via Sharp  
- **UUID paths only** — `/{userId}/avatar.webp`  
- **Rate limit** — 30 uploads / minute / user  
- **RLS** — public read only for storefront folders; rider KYC never public  
- **Signed URLs** — rider documents expire in 15 minutes (1 hour for admin review)

## Setup

### 1. Supabase SQL

Dashboard → **SQL Editor** → run [`backend/supabase-storage.sql`](../backend/supabase-storage.sql).

### 2. Environment

`backend/.env` and production (Render):

```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...   # Settings → API → service_role (secret)
SUPABASE_STORAGE_BUCKET=pictures
```

Never commit the service role key. Do not expose it in the mobile app.

### 3. Verify

```bash
cd backend
npm run verify:storage
```

Expect: `OK — bucket reachable: pictures`

### 4. Health check

`GET /api/health` includes:

```json
"media": {
  "storage": "supabase",
  "bucket": "pictures",
  "storageOk": true
}
```

## API

### `POST /api/upload` (auth required)

| Field | Values |
|-------|--------|
| `image` | file (multipart) |
| `folder` | `avatars` \| `products` \| `covers` |

**Response:**

```json
{
  "url": "https://….supabase.co/storage/v1/object/public/pictures/products/…/173….webp?v=…",
  "storage": "supabase",
  "contentType": "image/webp",
  "width": 800,
  "height": 600
}
```

### Rider KYC

`POST /api/rider/documents/:docType/upload` — same pipeline, private storage + signed URL in responses.

## Clients

- **Mobile** — `AppNetworkImage` / `dataUrlImage()` with `cached_network_image`  
- **Web** — standard `<img src={url}>`; works with WebP in modern browsers  

## Fallback

If `SUPABASE_SERVICE_ROLE_KEY` is missing, the API falls back to **compressed inline base64** (legacy). Production should always use object storage.

## Ops checklist

- [ ] SQL policies applied  
- [ ] Service role key on Render  
- [ ] `npm run verify:storage` passes  
- [ ] `/api/health` → `storageOk: true`  
- [ ] Test avatar + product upload from app  
- [ ] Confirm DB `image_url` / `avatar_url` are `https://` not `data:`
