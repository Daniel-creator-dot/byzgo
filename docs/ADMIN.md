# Admin portal (laptop)

The admin dashboard is the **web app** at path `/admin` (not the Flutter mobile app).

## Local URL

| Page | URL |
|------|-----|
| **Admin login** | http://localhost:5173/admin |
| Customer app | http://localhost:5173/ |
| Vendor portal | http://localhost:5173/vendor |
| Rider portal | http://localhost:5173/motor |

## Run on your laptop

**Terminal 1 — API**

```bash
npm run backend
```

**Terminal 2 — Admin web UI**

```bash
npm run dev:admin
```

Your browser should open to http://localhost:5173/admin automatically.

## First admin account

**Option A — CLI (recommended)**

```bash
npm run create:admin
```

Default login: `admin@bytzgo.net` / `Admin@2026`

## Create vendor (store) accounts

**Mobile admin app:** open **Stores** tab → **Create store account**. Enter shop name, email, Ghana phone, password, and category. Turn on **Activate immediately** so the merchant can log in on the app as **Vendor** and upload menu photos (Menu tab → Add item).

**API:** `POST /api/admin/vendors` (admin token) with `name`, `email`, `password`, optional `phone`, `shop_category`, `activate` (default active).

Merchants sign in on the Flutter app with the credentials you share. New menu items need admin product approval before they appear to customers in Shops.

Custom email/password:

```bash
node backend/scripts/create-admin.mjs you@example.com YourSecurePass "Your Name"
```

**Option B — Sign up in the browser**

1. Open http://localhost:5173/admin
2. Tap **Join**
3. Enter the **Admin invite code** from `ADMIN_INVITE_SECRET` in `backend/.env`
4. Complete registration (email + password; no phone OTP for admin)

Google sign-in cannot create admin accounts.

## Admin against production API

To use the admin UI locally while talking to production:

1. In `.env.local` set `VITE_API_URL=https://bytzgo.net` (or your Render API host)
2. Run `npm run dev:admin`
3. Log in with an admin user that exists in that database (`npm run create:admin` only affects the DB in `backend/.env` `DATABASE_URL`)

## Production admin URL

After deploy with `SERVE_WEB=true` (see `render.yaml`):

| URL |
|-----|
| https://bytzgo.net/admin |
| https://www.bytzgo.net/admin |

If you see **`Cannot GET /admin`**, the server is API-only: redeploy with the latest `render.yaml` (builds Vite `dist/` and sets `SERVE_WEB=true`), and ensure the domain points to the **Web Service**, not a Static Site.

Create a production admin user against your production database (set `DATABASE_URL` in `backend/.env` to the Render Postgres URL, then run `npm run create:admin`).
