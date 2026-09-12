-- Hosted Storage má trigger protect_delete: přímý DELETE z SQL padá.
-- RPC proto v transakci zapne storage.allow_delete_query (stejně jako Storage API).

CREATE OR REPLACE FUNCTION public.purge_documento_storage(p_documento_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  d RECORD;
BEGIN
  SELECT * INTO d FROM documentos WHERE id = p_documento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.is_tenant_owner(d.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF d.deleted_at IS NULL THEN
    RAISE EXCEPTION 'not_in_trash';
  END IF;
  IF d.storage_purged_at IS NOT NULL THEN
    RETURN true;
  END IF;

  -- PROČ: bez tohoto GUC trigger storage.protect_delete zruší DELETE.
  PERFORM set_config('storage.allow_delete_query', 'true', true);

  -- Blob drží, dokud na cestu ukazuje jiný nevysypaný řádek.
  IF NOT EXISTS (
    SELECT 1 FROM documentos x
    WHERE x.storage_path = d.storage_path
      AND x.id <> d.id
      AND x.storage_purged_at IS NULL
  ) THEN
    DELETE FROM storage.objects
    WHERE bucket_id = 'documentos'
      AND name = d.storage_path;
  END IF;

  UPDATE documentos
     SET storage_purged_at = now(),
         updated_at = now()
   WHERE id = d.id;
  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  ) VALUES (
    d.tenant_id,
    auth.uid(),
    (SELECT s.id FROM support_view_sessions s
      WHERE s.support_user_id = auth.uid()
        AND s.ended_at IS NULL
      ORDER BY s.started_at DESC LIMIT 1),
    'documentos.purge_storage',
    'documentos',
    d.id,
    jsonb_build_object('tipo', d.tipo, 'original_name', d.original_name)
  );
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.purge_documento_storage(UUID) TO authenticated;

COMMENT ON FUNCTION public.purge_documento_storage(UUID) IS
  'Owner smaže blob schovaného dokumentu. Řádek a přepis zůstanou. Storage API GUC kvůli protect_delete.';
