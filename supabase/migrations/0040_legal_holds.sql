-- Legal hold: daň/obchod 4–6 let. Purge blobu nesmí hold přehlédnout.

CREATE TABLE public.legal_holds (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES tenants (id),
  cliente_id    UUID REFERENCES clientes (id),
  documento_id  UUID REFERENCES documentos (id),
  until         DATE NOT NULL,
  reason        TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ,
  CONSTRAINT legal_holds_target CHECK (
    cliente_id IS NOT NULL OR documento_id IS NOT NULL
  )
);

CREATE INDEX idx_legal_holds_cliente
  ON legal_holds (cliente_id)
  WHERE deleted_at IS NULL AND cliente_id IS NOT NULL;

CREATE INDEX idx_legal_holds_documento
  ON legal_holds (documento_id)
  WHERE deleted_at IS NULL AND documento_id IS NOT NULL;

ALTER TABLE legal_holds ENABLE ROW LEVEL SECURITY;

CREATE POLICY legal_holds_select ON legal_holds
  FOR SELECT TO authenticated USING (public.can_access_tenant(tenant_id));
CREATE POLICY legal_holds_insert ON legal_holds
  FOR INSERT TO authenticated
  WITH CHECK (public.is_tenant_owner(tenant_id));
CREATE POLICY legal_holds_update ON legal_holds
  FOR UPDATE TO authenticated
  USING (public.is_tenant_owner(tenant_id))
  WITH CHECK (public.is_tenant_owner(tenant_id));

CREATE TRIGGER trg_legal_holds_updated
  BEFORE UPDATE ON legal_holds
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_legal_holds_no_hard_delete
  BEFORE DELETE ON legal_holds
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();

GRANT SELECT, INSERT, UPDATE ON TABLE public.legal_holds TO authenticated;

COMMENT ON TABLE public.legal_holds IS
  'Zákaz anonymizace a vysypání blobu do until (date, Europe/Madrid).';

CREATE OR REPLACE FUNCTION public.documento_has_legal_hold(p_documento_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := (timezone('Europe/Madrid', now()))::date;
BEGIN
  RETURN EXISTS (
    SELECT 1
      FROM documentos d
      JOIN legal_holds h ON h.tenant_id = d.tenant_id
     WHERE d.id = p_documento_id
       AND h.deleted_at IS NULL
       AND h.until >= v_today
       AND (
         h.documento_id = d.id
         OR h.cliente_id = d.cliente_id
       )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.documento_has_legal_hold(UUID) TO authenticated;

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
  IF public.documento_has_legal_hold(d.id) THEN
    RAISE EXCEPTION 'legal_hold';
  END IF;

  PERFORM set_config('storage.allow_delete_query', 'true', true);

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
  'Owner smaže blob schovaného dokumentu, pokud není legal hold. Řádek a přepis zůstanou.';
