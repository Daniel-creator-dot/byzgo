-- Run in Supabase Dashboard → SQL Editor (requires owner on storage.objects)
-- Bucket "pictures" should already exist (see apply-storage-sql.mjs)

DROP POLICY IF EXISTS "pictures_public_read_storefront" ON storage.objects;
DROP POLICY IF EXISTS "pictures_authenticated_insert" ON storage.objects;
DROP POLICY IF EXISTS "pictures_authenticated_update" ON storage.objects;
DROP POLICY IF EXISTS "pictures_authenticated_delete" ON storage.objects;
DROP POLICY IF EXISTS "pictures_public_read" ON storage.objects;
DROP POLICY IF EXISTS "pictures_service_insert" ON storage.objects;
DROP POLICY IF EXISTS "pictures_service_update" ON storage.objects;
DROP POLICY IF EXISTS "pictures_service_delete" ON storage.objects;

CREATE POLICY "pictures_public_read_storefront"
ON storage.objects FOR SELECT
TO public
USING (
  bucket_id = 'pictures'
  AND (storage.foldername(name))[1] IN ('avatars', 'products', 'covers')
);

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
