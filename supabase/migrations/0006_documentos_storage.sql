-- Soukromý bucket dokumentů. Cesta: {tenant_id}/{cliente_id}/{bloque_id}/{soubor}.
-- Soft-delete je jen v `documentos.deleted_at`; objekt ve Storage se nemaže.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'documentos',
  'documentos',
  false,
  15728640,
  ARRAY[
    'application/pdf',
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic'
  ]
)
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.storage_tenant_id(object_name TEXT)
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  folder TEXT := (storage.foldername(object_name))[1];
BEGIN
  IF folder IS NULL OR folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RETURN NULL;
  END IF;
  RETURN folder::uuid;
END;
$$;

CREATE POLICY documentos_storage_select ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
  );

CREATE POLICY documentos_storage_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
  );

CREATE POLICY documentos_storage_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
  )
  WITH CHECK (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
  );

COMMENT ON FUNCTION public.storage_tenant_id IS
  'První složka cesty ve Storage = tenant_id. Jinak NULL → RLS odmítne.';
