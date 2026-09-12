-- Voda / elektřina / plyn: stačí jeden papír (smlouva NEBO faktura).
-- Identita z faktury. Číslo smlouvy na desce je bonus, ne díra.
-- Bucket 32 MB — vícestránkové facturas PDF padaly na 15 MB.

ALTER TABLE bloque_templates
  ADD COLUMN IF NOT EXISTS required_docs_mode TEXT NOT NULL DEFAULT 'all';

ALTER TABLE bloque_templates
  DROP CONSTRAINT IF EXISTS bloque_templates_required_docs_mode_chk;
ALTER TABLE bloque_templates
  ADD CONSTRAINT bloque_templates_required_docs_mode_chk
  CHECK (required_docs_mode IN ('all', 'any'));

COMMENT ON COLUMN bloque_templates.required_docs_mode IS
  'all = každý typ z required_doc_types. any = stačí jeden (suministro).';

UPDATE bloque_templates SET
  required_docs_mode = 'any',
  required_doc_types = '{contrato_agua,factura_agua,recibo_agua}',
  required_field_keys = '{fields.company,fields.clientNo,fields.holder}'
WHERE key = 'agua';

UPDATE bloque_templates SET
  required_docs_mode = 'any',
  required_doc_types = '{contrato_luz,factura_luz}',
  required_field_keys = '{fields.company,fields.cups,fields.holder}'
WHERE key = 'luz';

UPDATE bloque_templates SET
  required_docs_mode = 'any',
  required_doc_types = '{contrato_gaz,factura_gaz}',
  required_field_keys = '{fields.company,fields.cups,fields.holder}'
WHERE key = 'gaz';

UPDATE storage.buckets
   SET file_size_limit = 33554432
 WHERE id = 'documentos';

CREATE OR REPLACE FUNCTION public.recompute_bloque_status(p_bloque_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b RECORD;
  t RECORD;
  v_key TEXT;
  v_tipo TEXT;
  v_missing_data BOOLEAN := false;
  v_missing_doc BOOLEAN := false;
  v_has_plazo BOOLEAN := false;
  v_new TEXT;
  v_mode TEXT;
BEGIN
  SELECT * INTO b FROM bloques WHERE id = p_bloque_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  -- Migrace volá bez JWT. Staff pořád přes membership.
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(b.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF b.status_locked THEN
    RETURN b.status::text;
  END IF;
  IF b.status = 'off' THEN
    RETURN 'off';
  END IF;

  SELECT * INTO t FROM bloque_templates WHERE key = b.template_key;

  IF t.required_field_keys IS NOT NULL THEN
    FOREACH v_key IN ARRAY t.required_field_keys
    LOOP
      IF nullif(btrim(public.bloque_field(b.fields, v_key)), '') IS NULL
         AND nullif(btrim(b.fields->>v_key), '') IS NULL THEN
        v_missing_data := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  v_mode := coalesce(t.required_docs_mode, 'all');
  IF t.required_doc_types IS NOT NULL
     AND cardinality(t.required_doc_types) > 0 THEN
    IF v_mode = 'any' THEN
      v_missing_doc := NOT EXISTS (
        SELECT 1 FROM documentos d
        WHERE d.bloque_id = b.id
          AND d.deleted_at IS NULL
          AND d.tipo = ANY (t.required_doc_types)
      );
    ELSE
      FOREACH v_tipo IN ARRAY t.required_doc_types
      LOOP
        IF NOT EXISTS (
          SELECT 1 FROM documentos d
          WHERE d.bloque_id = b.id
            AND d.tipo = v_tipo
            AND d.deleted_at IS NULL
        ) THEN
          v_missing_doc := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;
  END IF;

  IF v_missing_data THEN
    v_new := 'missing_data';
  ELSIF v_missing_doc THEN
    v_new := 'missing_document';
  ELSE
    SELECT EXISTS (
      SELECT 1 FROM plazos p
      WHERE p.bloque_id = b.id
        AND p.deleted_at IS NULL
        AND p.completed_at IS NULL
    ) INTO v_has_plazo;
    v_new := CASE WHEN v_has_plazo THEN 'watching' ELSE 'done' END;
  END IF;

  IF b.status::text IS DISTINCT FROM v_new THEN
    UPDATE bloques SET status = v_new::bloque_status WHERE id = b.id;
  END IF;
  RETURN v_new;
END;
$$;

GRANT EXECUTE ON FUNCTION public.recompute_bloque_status(UUID) TO authenticated;

-- Přepočítat zapnuté dodávky po změně katalogu.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id FROM bloques
    WHERE deleted_at IS NULL
      AND status IS DISTINCT FROM 'off'
      AND coalesce(status_locked, false) = false
      AND template_key IN ('agua', 'luz', 'gaz')
  LOOP
    PERFORM public.recompute_bloque_status(r.id);
  END LOOP;
END;
$$;
