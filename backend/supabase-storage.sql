-- =============================================================================
-- BytzGo — Supabase Storage (production)
-- Run once in: Supabase Dashboard → SQL Editor
-- Bucket name must match SUPABASE_STORAGE_BUCKET (default: pictures)
-- =============================================================================

-- 1) Bucket — public flag enables CDN; RLS still restricts which objects are readable
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'pictures',
  'pictures',
  true,
  5242880,
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- 2) Ensure RLS is enabled on storage.objects (Supabase default)
ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

-- 3) Reset policies (idempotent re-run)
DROP POLICY IF EXISTS "pictures_public_read_storefront" ON storage.objects;
DROP POLICY IF EXISTS "pictures_deny_public_rider_docs" ON storage.objects;
DROP POLICY IF EXISTS "pictures_authenticated_insert" ON storage.objects;
DROP POLICY IF EXISTS "pictures_authenticated_update" ON storage.objects;
DROP POLICY IF EXISTS "pictures_authenticated_delete" ON storage.objects;
DROP POLICY IF EXISTS "pictures_public_read" ON storage.objects;
DROP POLICY IF EXISTS "pictures_service_insert" ON storage.objects;
DROP POLICY IF EXISTS "pictures_service_update" ON storage.objects;
DROP POLICY IF EXISTS "pictures_service_delete" ON storage.objects;

-- 4) Public read — storefront assets only (avatars, menu photos, shop covers)
CREATE POLICY "pictures_public_read_storefront"
ON storage.objects FOR SELECT
TO public
USING (
  bucket_id = 'pictures'
  AND (storage.foldername(name))[1] IN ('avatars', 'products', 'covers')
);

-- 5) Rider KYC — never public; API returns short-lived signed URLs (service role)
-- (No SELECT policy for anon/authenticated on rider-documents/)

-- 6) Optional: direct client uploads when using Supabase Auth JWT (future)
CREATE POLICY "pictures_authenticated_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'pictures'
  AND (storage.foldername(name))[1] IN ('avatars', 'products', 'covers')
);

CREATE POLICY "pictures_authenticated_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (bucket_id = 'pictures')
WITH CHECK (bucket_id = 'pictures');

CREATE POLICY "pictures_authenticated_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (bucket_id = 'pictures');

-- BytzGo API uploads use SUPABASE_SERVICE_ROLE_KEY (bypasses RLS).
-- Set in backend/.env:
--   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, SUPABASE_STORAGE_BUCKET=pictures
