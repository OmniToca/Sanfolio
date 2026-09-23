-- Stopa na kartě: kdo kartu otevře, vidí co se s klientem dělo.
-- Owner-only schovávalo audit gestorovi. Append-only se nemění.

CREATE OR REPLACE FUNCTION public.cliente_audit_log(p_cliente_id UUID)
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
  IF NOT public.can_access_cliente(p_cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF NOT (
    public.is_tenant_owner(v_tenant)
    OR public.current_member_role(v_tenant) IN ('owner', 'gestor', 'asistente')
  ) THEN
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
      WHEN a.entity_table = 'inmueble_titulares' THEN
        jsonb_strip_nulls(jsonb_build_object(
          'nombre', nullif(a.after->>'nombre', ''),
          'lado', nullif(a.after->>'lado', ''),
          'cuota_bps', a.after->'cuota_bps'
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
      OR (
        a.entity_table = 'inmueble_titulares'
        AND EXISTS (
          SELECT 1
          FROM inmueble_titulares t
          JOIN inmuebles i ON i.id = t.inmueble_id AND i.deleted_at IS NULL
          WHERE t.id = a.entity_id
            AND i.cliente_id = p_cliente_id
        )
      )
    )
  ORDER BY a.created_at DESC
  LIMIT 50;
END;
$$;

GRANT EXECUTE ON FUNCTION public.cliente_audit_log(UUID) TO authenticated;

COMMENT ON FUNCTION public.cliente_audit_log(UUID) IS
  'Stopa karty pro člena, který kartu smí otevřít. Append-only. Scoped jen svoje karty.';
