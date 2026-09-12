-- Stav bloku počítá Postgres. Flutter stav nezapisuje (kromě tužky off/on s důvodem).

ALTER TABLE bloques
  ADD COLUMN IF NOT EXISTS status_locked BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS status_reason TEXT;

COMMENT ON COLUMN bloques.status_locked IS
  'true = gestor přebil stroj (off/done) s důvodem v status_reason + auditu.';

-- Klíče jako ve Flutter `fields.*`, ať recompute čte totéž co deska.
UPDATE bloque_templates SET required_field_keys = '{}'
WHERE key IN ('cliente_snapshot', 'escritura', 'plusvalia', 'provision_factura');

UPDATE bloque_templates SET
  required_field_keys = '{fields.company,fields.clientNo,fields.contractNo,fields.holder}'
WHERE key = 'agua';

UPDATE bloque_templates SET
  required_field_keys = '{fields.company,fields.cups,fields.contractNo,fields.holder}'
WHERE key IN ('luz', 'gaz');

UPDATE bloque_templates SET
  required_field_keys = '{fields.admin,fields.reference,fields.holder}'
WHERE key = 'comunidad';

UPDATE bloque_templates SET
  required_field_keys = '{fields.sumaId,fields.directDebit}'
WHERE key = 'suma';

UPDATE bloque_templates SET
  required_field_keys = '{fields.company,fields.policy,fields.expiry}'
WHERE key = 'seguro';

UPDATE bloque_templates SET
  required_field_keys = '{fields.company,fields.contractNo,fields.expiry}'
WHERE key = 'alarma';

UPDATE bloque_templates SET
  required_field_keys = '{fields.nieStatus}'
WHERE key = 'nie_tramite';

UPDATE bloque_templates SET
  required_field_keys = '{fields.attorney,fields.expiry}'
WHERE key = 'poder';

UPDATE bloque_templates SET
  required_field_keys = '{fields.periodicity,fields.modeloPeriod,fields.deadline}'
WHERE key = 'modelo_210';

UPDATE bloque_templates SET
  required_field_keys = '{fields.exercise,fields.deadline}'
WHERE key = 'renta';

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
BEGIN
  SELECT * INTO b FROM bloques WHERE id = p_bloque_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  IF NOT public.can_access_tenant(b.tenant_id) THEN
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
      IF nullif(btrim(b.fields->>v_key), '') IS NULL THEN
        v_missing_data := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  IF t.required_doc_types IS NOT NULL THEN
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

CREATE OR REPLACE FUNCTION public.override_bloque_status(
  p_bloque_id UUID,
  p_enabled BOOLEAN,
  p_reason TEXT
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b RECORD;
  v_reason TEXT := nullif(btrim(p_reason), '');
  v_status TEXT;
BEGIN
  SELECT * INTO b FROM bloques WHERE id = p_bloque_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(b.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_enabled THEN
    UPDATE bloques
       SET status_locked = false,
           status_reason = NULL,
           status = 'missing_data'
     WHERE id = b.id;
    v_status := public.recompute_bloque_status(b.id);
    INSERT INTO audit_logs (
      tenant_id, actor_id, impersonation_session_id,
      action, entity_table, entity_id, after
    ) VALUES (
      b.tenant_id, auth.uid(),
      (SELECT s.id FROM support_view_sessions s
       WHERE s.support_user_id = auth.uid() AND s.ended_at IS NULL AND s.expires_at > now()
       ORDER BY s.started_at DESC LIMIT 1),
      'bloque.enabled', 'bloques', b.id,
      jsonb_build_object('status', v_status)
    );
    RETURN v_status;
  END IF;

  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'reason_required';
  END IF;

  UPDATE bloques
     SET status = 'off',
         status_locked = true,
         status_reason = v_reason
   WHERE id = b.id;
  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  ) VALUES (
    b.tenant_id, auth.uid(),
    (SELECT s.id FROM support_view_sessions s
     WHERE s.support_user_id = auth.uid() AND s.ended_at IS NULL AND s.expires_at > now()
     ORDER BY s.started_at DESC LIMIT 1),
    'bloque.disabled', 'bloques', b.id,
    jsonb_build_object('reason', v_reason)
  );
  RETURN 'off';
END;
$$;

GRANT EXECUTE ON FUNCTION public.override_bloque_status(UUID, BOOLEAN, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.trg_recompute_bloque_status_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.recompute_bloque_status(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recompute_bloque_status_fields ON bloques;
CREATE TRIGGER trg_recompute_bloque_status_fields
  AFTER UPDATE OF fields ON bloques
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_recompute_bloque_status_fields();

CREATE OR REPLACE FUNCTION public.trg_recompute_bloque_status_docs()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.bloque_id IS NOT NULL THEN
    PERFORM public.recompute_bloque_status(NEW.bloque_id);
  END IF;
  IF TG_OP = 'UPDATE' AND OLD.bloque_id IS NOT NULL AND OLD.bloque_id IS DISTINCT FROM NEW.bloque_id THEN
    PERFORM public.recompute_bloque_status(OLD.bloque_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recompute_bloque_status_docs ON documentos;
CREATE TRIGGER trg_recompute_bloque_status_docs
  AFTER INSERT OR UPDATE OF deleted_at, bloque_id, tipo ON documentos
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_recompute_bloque_status_docs();
