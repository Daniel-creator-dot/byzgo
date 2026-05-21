# Fix byzgo-api on Render (admin web + API)

Open: https://dashboard.render.com/web/srv-d86e8qv7f7vs7395kgrg

## Settings → Build & Deploy

| Field | Set to |
|-------|--------|
| **Build Command** | `npm ci && npm run build:render` |
| **Start Command** | `npm run start:render` |
| **Health Check Path** | `/api/health` |

## Environment (already set via automation)

- `SERVE_WEB` = `true`
- `SERVE_ADMIN_WEB_ONLY` = `true`

Save → **Manual Deploy** → Deploy latest commit.

## Test

- https://www.bytzgo.net/admin — admin login
- https://www.bytzgo.net/ — info page (not full customer app)
- https://www.bytzgo.net/api/health — JSON
