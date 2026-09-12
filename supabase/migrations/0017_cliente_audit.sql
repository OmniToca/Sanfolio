-- Audit karty klienta: kdo otevřel / změnil / odeslal. Insert jen trigger + RPC.
-- Log se nemaže (forbid_audit_mutation). Čtení na kartě jen owner.

CREATE INDEX IF NOT EXISTS idx_audit_logs_entity
  ON audit_logs (tenant_id, entity_table, entity_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.audit_row_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action TEXT;
  v_before JSONB;
  v_after JSONB;
  v_strip TEXT[] := ARRAY['search_vector', 'updated_at', 'cuerpo', 'translations'];
  v_imp UUID;
BEGIN
  IF TG_OP = 'UPDATE'
     AND (to_jsonb(NEW) - 'updated_at' - 'search_vector')
       = (to_jsonb(OLD) - 'updated_at' - 'search_vector') THEN
    RETURN NEW;
  END IF;

  SELECT s.id INTO v_imp
  FROM support_view_sessions s
  WHERE s.support_user_id = auth.uid()
    AND s.ended_at IS NULL
    AND s.expires_at > now()
  ORDER BY s.started_at DESC
  LIMIT 1;

  IF TG_OP = 'INSERT' THEN
    v_after := to_jsonb(NEW) - v_strip;
    IF TG_TABLE_NAME = 'clientes' THEN
      v_action := 'clientes.insert';
    ELSIF TG_TABLE_NAME = 'mensajes' THEN
      v_action := 'mensajes.' || NEW.status::text;
    ELSIF TG_TABLE_NAME = 'documentos' THEN
      v_action := 'documentos.insert';
    ELSIF TG_TABLE_NAME = 'client_contacts' THEN
      v_action := 'client_contacts.insert';
    ELSE
      v_action := TG_TABLE_NAME || '.insert';
    END IF;
    INSERT INTO audit_logs (
      tenant_id, actor_id, impersonation_session_id,
      action, entity_table, entity_id, after
    ) VALUES (
      NEW.tenant_id, auth.uid(), v_imp, v_action, TG_TABLE_NAME, NEW.id, v_after
    );
    RETURN NEW;
  END IF;

  v_before := to_jsonb(OLD) - v_strip;
  v_after := to_jsonb(NEW) - v_strip;

  IF TG_TABLE_NAME = 'clientes' THEN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
      v_action := 'clientes.soft_delete';
    ELSIF OLD.deleted_at IS NOT NULL AND NEW.deleted_at IS NULL THEN
      v_action := 'clientes.restore';
    ELSE
      v_action := 'clientes.update';
    END IF;
  ELSIF TG_TABLE_NAME = 'mensajes' THEN
    IF NEW.status IS DISTINCT FROM OLD.status THEN
      v_action := 'mensajes.' || NEW.status::text;
    ELSE
      v_action := 'mensajes.update';
    END IF;
  ELSIF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
    v_action := TG_TABLE_NAME || '.soft_delete';
  ELSE
    v_action := TG_TABLE_NAME || '.update';
  END IF;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, before, after
  ) VALUES (
    NEW.tenant_id, auth.uid(), v_imp, v_action, TG_TABLE_NAME, NEW.id, v_before, v_after
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_clientes_audit ON clientes;
CREATE TRIGGER trg_clientes_audit
  AFTER INSERT OR UPDATE ON clientes
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_row_change();

DROP TRIGGER IF EXISTS trg_mensajes_audit ON mensajes;
CREATE TRIGGER trg_mensajes_audit
  AFTER INSERT OR UPDATE ON mensajes
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_row_change();

DROP TRIGGER IF EXISTS trg_documentos_audit ON documentos;
CREATE TRIGGER trg_documentos_audit
  AFTER INSERT OR UPDATE ON documentos
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_row_change();

DROP TRIGGER IF EXISTS trg_client_contacts_audit ON client_contacts;
CREATE TRIGGER trg_client_contacts_audit
  AFTER INSERT OR UPDATE ON client_contacts
  FOR EACH ROW
  EXECUTE FUNCTION public.audit_row_change();

-- Owner (nebo Support v impersonaci) čte stopu karty. Gestor/asistente ne.
CREATE OR REPLACE FUNCTION public.cliente_audit_log(p_cliente_id UUID)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  action TEXT,
  entity_table TEXT,
  actor_name TEXT,
  actor_email TEXT,
  impersonating BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
BEGIN
  SELECT c.tenant_id INTO v_tenant
  FROM clientes c
  WHERE c.id = p_cliente_id;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.is_tenant_owner(v_tenant) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.created_at,
    a.action,
    a.entity_table,
    coalesce(nullif(btrim(p.full_name), ''), p.email)::TEXT,
    p.email,
    (a.impersonation_session_id IS NOT NULL)
  FROM audit_logs a
  LEFT JOIN profiles p ON p.id = a.actor_id
  WHERE a.tenant_id = v_tenant
    AND (
      (a.entity_table = 'clientes' AND a.entity_id = p_cliente_id)
      OR (
        a.entity_table = 'mensajes'
        AND EXISTS (
          SELECT 1 FROM mensajes m
          WHERE m.id = a.entity_id AND m.cliente_id = p_cliente_id
        )
      )
      OR (
        a.entity_table = 'documentos'
        AND EXISTS (
          SELECT 1 FROM documentos d
          WHERE d.id = a.entity_id AND d.cliente_id = p_cliente_id
        )
      )
      OR (
        a.entity_table = 'client_contacts'
        AND EXISTS (
          SELECT 1 FROM client_contacts cc
          WHERE cc.id = a.entity_id AND cc.cliente_id = p_cliente_id
        )
      )
    )
  ORDER BY a.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cliente_audit_log(UUID) TO authenticated;

COMMENT ON FUNCTION public.cliente_audit_log(UUID) IS
  'LOPDGDD stopa karty. Jen owner. Append-only — mazání logu tu není.';
