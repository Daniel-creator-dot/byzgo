# Fix bytzgo.net apex DNS (Cloudflare)

## Problem

`www.bytzgo.net` works and points to **byzgoback-eu** (Frankfurt).

`bytzgo.net` (apex) still points to the **deleted Oregon** service:

```
bytzgo.net → byzgoback-pgxo.onrender.com  ❌ (old, suspended/deleted)
```

Render shows apex as **unverified** on `byzgoback-eu` until DNS is updated.

## Fix in Cloudflare

1. Log in to [Cloudflare Dashboard](https://dash.cloudflare.com) → zone **bytzgo.net**
2. **DNS** → find the record for `bytzgo.net` (apex / `@`)
3. Change the target from `byzgoback-pgxo.onrender.com` to:

   ```
   byzgoback-eu.onrender.com
   ```

4. Keep **Proxy status** the same as `www` (typically **Proxied** / orange cloud)
5. Save — propagation is usually under 5 minutes

## Verify

```bash
dig +short bytzgo.net CNAME
# Should show byzgoback-eu.onrender.com (or Cloudflare flattening to Render origin)

curl -sI https://bytzgo.net | head -5
curl -s https://bytzgo.net/api/health | python3 -m json.tool
# Should return service: byzgoback-eu
```

In Render Dashboard → **byzgoback-eu** → Custom Domains → `bytzgo.net` should change to **verified**.

## Current production targets

| Host | Should point to |
|------|-----------------|
| `www.bytzgo.net` | `byzgoback-eu.onrender.com` ✅ |
| `bytzgo.net` | `byzgoback-eu.onrender.com` (redirects to www) |
