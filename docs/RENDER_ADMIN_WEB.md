# Render — admin web only (laptop / browser)

Customers, riders, and vendors use the **Flutter app**. Only **admins** use the website.

## URLs (production)

| Who | URL |
|-----|-----|
| **Admin dashboard** | https://www.bytzgo.net/admin |
| **API + mobile app** | https://www.bytzgo.net/api/... |
| **Privacy (Play Store)** | https://www.bytzgo.net/privacy |
| **Homepage** | https://www.bytzgo.net/ — short info + link to `/admin` (not full customer app) |

`/vendor` and `/motor` on the web are **not** offered; visitors see the landing page.

## Render service settings (byzgo-api or byzgo)

Your **Web Service** must build the Vite admin UI **and** run the API:

| Setting | Value |
|---------|--------|
| **Build Command** | `npm ci && npm run build:render` |
| **Start Command** | `npm run start:render` |
| **Health Check** | `/api/health` |

**Environment:**

| Variable | Value |
|----------|--------|
| `NODE_ENV` | `production` |
| `SERVE_WEB` | `true` |
| `SERVE_ADMIN_WEB_ONLY` | `true` |
| `DATABASE_URL` | *(your Postgres)* |
| `JWT_SECRET` | *(secret)* |
| Firebase / Maps / Paystack / SMS | *(as before)* |

Redeploy after changing build command (old deploys that only run `npm install --prefix backend` do **not** include `/admin`).

## Create admin user (production DB)

Point `backend/.env` `DATABASE_URL` at Render Postgres, then:

```powershell
npm run create:admin
```

Default: `admin@bytzgo.net` / `Admin@2026`

## Local admin (your laptop)

```powershell
npm run admin
```

Opens http://localhost:5173/admin with local API.

## Verify after deploy

```powershell
curl -s https://www.bytzgo.net/api/health
# {"ok":true,...}

curl -sI https://www.bytzgo.net/admin
# HTTP 200

curl -sI https://www.bytzgo.net/vendor
# Should NOT return full customer app (landing or redirect)
```
