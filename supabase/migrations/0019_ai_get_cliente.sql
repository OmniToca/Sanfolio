-- Read-only snapshot karty pro AI. PII do modelu jen s auditem ai.read.cliente.
-- Nic neukládá na clientes/bloques. Odeslání zprávy tu není.

CREATE OR REPLACE FUNCTION public.ai_get_cliente(p_cliente_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_cliente JSONB;
  v_holes JSONB;
BEGIN
  SELECT c.tenant_id INTO v_tenant
  FROM clientes c
  WHERE c.id = p_cliente_id
    AND c.deleted_at IS NULL;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_tenant) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id
  ) VALUES (
    v_tenant,
    auth.uid(),
    (SELECT s.id FROM support_view_sessions s
     WHERE s.support_user_id = auth.uid()
       AND s.ended_at IS NULL
       AND s.expires_at > now()
     ORDER BY s.started_at DESC LIMIT 1),
    'ai.read.cliente',
    'clientes',
    p_cliente_id
  );

  SELECT jsonb_build_object(
    'id', c.id,
    'nombre', concat_ws(' ', nullif(btrim(c.nombre), ''), nullif(btrim(c.apellidos), '')),
    'email', c.email,
    'tel', c.tel,
    'locale', c.locale,
    'tenant_id', c.tenant_id
  )
  INTO v_cliente
  FROM clientes c
  WHERE c.id = p_cliente_id;

  SELECT coalesce(jsonb_agg(x.hole ORDER BY x.ord), '[]'::jsonb)
  INTO v_holes
  FROM (
    SELECT jsonb_build_object(
      'bloque_id', b.id,
      'bloque_key', b.template_key,
      'status', b.status::text
    ) AS hole,
    CASE b.status::text
      WHEN 'missing_document' THEN 1
      WHEN 'missing_data' THEN 2
      ELSE 3
    END AS ord
    FROM bloques b
    JOIN expedientes e ON e.id = b.expediente_id
    WHERE e.cliente_id = p_cliente_id
      AND e.deleted_at IS NULL
      AND b.deleted_at IS NULL
      AND b.status IN ('missing_data', 'missing_document')
  ) x;

  RETURN jsonb_build_object(
    'cliente', v_cliente,
    'holes', v_holes
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.ai_get_cliente(UUID) TO authenticated;

COMMENT ON FUNCTION public.ai_get_cliente(UUID) IS
  'Snapshot + díry pro copilot. Audit ai.read.cliente. Žádný save/send.';
