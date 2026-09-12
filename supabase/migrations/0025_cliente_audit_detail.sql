-- Audit na kartě musí říct CO se stalo: který soubor, karta vs. složka.
-- `after` u nahrání už v logu je; RPC ho dřív nevracelo.

DROP FUNCTION IF EXISTS public.audit_open(TEXT, UUID, UUID);

CREATE FUNCTION public.audit_open(
  p_entity_table TEXT,
  p_entity_id UUID,
  p_tenant_id UUID,
  p_after JSONB DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  )
  VALUES (
    p_tenant_id,
    auth.uid(),
    (SELECT id FROM support_view_sessions
     WHERE support_user_id = auth.uid() AND ended_at IS NULL AND expires_at > now()
     ORDER BY started_at DESC LIMIT 1),
    p_entity_table || '.open',
    p_entity_table,
    p_entity_id,
    p_after
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.audit_open(TEXT, UUID, UUID, JSONB) TO authenticated;

DROP FUNCTION IF EXISTS public.cliente_audit_log(UUID);

CREATE FUNCTION public.cliente_audit_log(p_cliente_id UUID)
RETURNS TABLE (
  id UUID,
  created_at TIMESTAMPTZ,
  action TEXT,
  entity_table TEXT,
  actor_name TEXT,
  actor_email TEXT,
  impersonating BOOLEAN,
  detail JSONB
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
    (a.impersonation_session_id IS NOT NULL),
    CASE
      WHEN a.entity_table = 'documentos' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'tipo', nullif(coalesce(a.after->>'tipo', d.tipo), ''),
          'original_name', nullif(
            coalesce(a.after->>'original_name', d.original_name),
            ''
          )
        ))
      WHEN a.entity_table = 'mensajes' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'asunto', nullif(a.after->>'asunto', '')
        ))
      WHEN a.entity_table = 'client_contacts' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'nombre', nullif(a.after->>'nombre', ''),
          'relacion', nullif(a.after->>'relacion', '')
        ))
      WHEN a.entity_table = 'clientes' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'surface', nullif(a.after->>'surface', ''),
          'changed', (
            SELECT jsonb_agg(x.key ORDER BY x.key)
            FROM jsonb_each(coalesce(a.after, '{}'::jsonb)) x
            WHERE a.before IS NOT NULL
              AND x.key NOT IN (
                'id', 'tenant_id', 'created_at', 'updated_at', 'deleted_at',
                'created_by', 'search_vector'
              )
              AND (a.before -> x.key) IS DISTINCT FROM x.value
          )
        ))
      ELSE '{}'::jsonb
    END
  FROM audit_logs a
  LEFT JOIN profiles p ON p.id = a.actor_id
  LEFT JOIN documentos d
    ON d.id = a.entity_id AND a.entity_table = 'documentos'
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
          SELECT 1 FROM documentos dx
          WHERE dx.id = a.entity_id AND dx.cliente_id = p_cliente_id
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
  'LOPDGDD stopa karty s detail.tipo / original_name. Jen owner. Append-only.';
