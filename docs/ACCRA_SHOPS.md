# Accra marketplace shops (restaurants & groceries)

## Seed data

| Command | Data file | Category |
|---------|-----------|----------|
| `npm run seed:accra-places` | `backend/data/accra_popular_places.json` | Restaurants |
| `npm run seed:accra-groceries` | `backend/data/accra_grocery_places.json` | Groceries |
| `npm run seed:accra-shops` | Both files | All |

Requires `DATABASE_URL` in `backend/.env`.

### Google storefront photos

Set `GOOGLE_MAPS_API_KEY` (Places API + Place Photos enabled). The seed script:

1. Finds each shop on Google Places
2. Downloads the first photo
3. Uploads to Supabase `pictures/covers/accra/{slug}.jpg` when `SUPABASE_SERVICE_ROLE_KEY` is set
4. Otherwise stores a small inline image (or skips if too large)

Re-run seeds anytime to refresh menus, phones, coordinates, and photos.

## App

- **Shops** tab → category chips (Groceries, Restaurants, …)
- List shows photo, phone, **Call**, **Maps**, menu → checkout (items + km delivery)
- Shop orders use `order_type: food` (not courier-only billing)
