# Supabase + Render + Firebase performance

## Current production layout (checked live)

| Component | Value |
|-----------|--------|
| **Render API** | `byzgoback-eu` (`srv-d98738e7r5hc73cjogv0`) — **Frankfurt** (EU), Starter plan |
| **Legacy (suspended)** | `byzgoback` (`srv-d8a8j34m0tmc739suuqg`) — Oregon — do not use |
| **Supabase Postgres** | `ypmiurbtmfiyzmrygonh` — **EU Central** (`aws-1-eu-central-1`) |
| **DATABASE_URL** | Uses **transaction pooler** ✅ — `...pooler.supabase.com:6543?pgbouncer=true` |
| **Supabase Storage** | Same project — `pictures` bucket |
| **Firebase** | `bytzgo-9bd89` — push only (FCM), **not** the database |

## Does Supabase + Firebase work together?

**Yes.** They are separate:

- **Supabase** = Postgres + file storage
- **Firebase** = rider/customer push notifications
- **Render** = API + Socket.IO real-time

Firebase does **not** slow Supabase. Rider dispatch speed is mostly **Render ↔ Supabase** latency.

## Region alignment (done)

```
Render API     Frankfurt (EU)  ──┐
                                  ├── same region — low DB latency
Supabase DB    EU Central       ──┘
```

Production API was migrated from Oregon to Frankfurt on **2026-07-10** by creating `byzgoback-eu` and moving `www.bytzgo.net` / `bytzgo.net` to it. The old Oregon service is **suspended**.

Render does not allow changing region on an existing service; migration requires a new service in the target region.

### If you need to migrate again

**Move Render to EU**  
1. Create a new web service in **Frankfurt** with the same env vars and build/start commands  
2. Deploy and verify `/api/health` on the `.onrender.com` URL  
3. Move custom domains from the old service to the new one  
4. Suspend or delete the old service  

**Option B — New Supabase project in US West**  
1. Create Supabase in `us-west-1` (or closest US region)  
2. Migrate data  
3. Update `DATABASE_URL` on Render  

**Option C — Ghana-focused (advanced)**  
Run API in **EU (Frankfurt)** + Supabase **EU** — good for Ghana users and API↔DB speed.

## DATABASE_URL pooler tuning

You already use the **Supabase pooler** (good). For a Node server with many short queries, also try **transaction mode**:

1. Supabase Dashboard → Project → **Connect** → **Transaction pooler**  
2. Copy URI (port **6543**)  
3. Render → **byzgoback** → Environment → update `DATABASE_URL`  
4. Redeploy  

Example shape:

```text
postgresql://postgres.ypmiurbtmfiyzmrygonh:PASSWORD@aws-1-eu-central-1.pooler.supabase.com:6543/postgres
```

Optional env on Render:

```text
PG_POOL_MAX=10
PG_IDLE_TIMEOUT_MS=30000
PG_CONNECT_TIMEOUT_MS=10000
```

## Verify after changes

```bash
curl -s https://www.bytzgo.net/api/health | jq .database
```

Look for:

- `regionAligned: true`
- `pooler: true`
- `useTransactionPooler: true` (if you switched to port 6543)

## Firebase checklist (push speed)

- `fcm: true` on `/api/health` ✅  
- iOS: upload **APNs .p8 key** in Firebase → Cloud Messaging  
- Rider app: **Online**, notifications allowed, battery unrestricted  

Push is parallel to Socket.IO — it does not block dispatch, but riders need it when the phone is locked.
