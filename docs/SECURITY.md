# Security notes

## Dependency audits

- **Root (Vite web):** run `npm audit` after `npm install`. We removed unused `firebase` and `@react-oauth/google` client packages to reduce supply-chain surface.
- **Backend:** run `npm audit` in `backend/`. Some findings come from transitive deps (e.g. `firebase-admin` → Firestore); use `npm audit fix` where safe; review `npm audit fix --force` before using.

## Authentication

- **Google Sign-In** is **disabled** by default. The API returns `403` for `POST /api/auth/google` unless `GOOGLE_SIGN_IN_ENABLED=true` is set on the server. Mobile and web use email/password (and Supabase OAuth redirect where configured).

## HTTP hardening (API)

- **Helmet** sets safer defaults (CSP disabled for API JSON responses to avoid breaking clients).
- **CORS:** when `APP_URL` or `CORS_ORIGINS` is set (comma-separated), only those origins are allowed. Local dev with no env uses open CORS.

## Session handling (web)

- Axios only auto-logs out on **401** (invalid/expired JWT), not on **403** (forbidden / feature disabled), to avoid kicking users out for role or policy denials.

## Reporting

Report suspected vulnerabilities to the repository maintainers privately; do not open public issues with exploit details until patched.
