-- query_escritura: notář, právník, catastral, strany z desky i z přepisu listiny.

CREATE OR REPLACE FUNCTION public.query_escritura(
  p_tenant_id UUID,
  p_notary TEXT,
  p_limit INT DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := trim(coalesce(p_notary, ''));
  v_like TEXT;
  v_limit INT := least(greatest(coalesce(p_limit, 20), 1), 20);
  v_total BIGINT;
  v_items JSONB;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF length(v_q) < 2 THEN
    RAISE EXCEPTION 'query_too_short';
  END IF;
  v_like := '%' || v_q || '%';

  SELECT count(DISTINCT c.id) INTO v_total
  FROM clientes c
  LEFT JOIN expedientes e
    ON e.cliente_id = c.id AND e.deleted_at IS NULL
  LEFT JOIN bloques b
    ON b.expediente_id = e.id
   AND b.deleted_at IS NULL
   AND b.status <> 'off'
   AND b.template_key = 'escritura'
  LEFT JOIN inmuebles i
    ON i.id = e.inmueble_id AND i.deleted_at IS NULL
  WHERE c.tenant_id = p_tenant_id
    AND c.deleted_at IS NULL
    AND (
      public.bloque_field(b.fields, 'fields.notary') ILIKE v_like
      OR public.bloque_field(b.fields, 'fields.protocol') ILIKE v_like
      OR i.notario ILIKE v_like
      OR i.direccion ILIKE v_like
      OR i.referencia_catastral ILIKE v_like
      OR EXISTS (
        SELECT 1
          FROM documentos d
         WHERE d.cliente_id = c.id
           AND d.tenant_id = p_tenant_id
           AND d.deleted_at IS NULL
           AND (
             coalesce(d.extracted->>'fields.notary', '') ILIKE v_like
             OR coalesce(d.extracted->>'fields.lawyer', '') ILIKE v_like
             OR coalesce(d.extracted->>'fields.sellers', '') ILIKE v_like
             OR coalesce(d.extracted->>'fields.buyers', '') ILIKE v_like
             OR coalesce(d.extracted->>'fields.cadastral', '') ILIKE v_like
             OR coalesce(d.extracted->>'fields.address', '') ILIKE v_like
             OR coalesce(d.extracted->>'fields.registry', '') ILIKE v_like
             OR coalesce(d.extracted->>'fields.attorney', '') ILIKE v_like
           )
      )
    );

  SELECT coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT DISTINCT ON (c.nombre, c.id) jsonb_build_object(
      'cliente_id', c.id,
      'nombre', trim(both from concat_ws(' ', c.nombre, c.apellidos)),
      'notary', coalesce(
        public.bloque_field(b.fields, 'fields.notary'),
        i.notario
      ),
      'date', public.bloque_field(b.fields, 'fields.date'),
      'protocol', coalesce(
        public.bloque_field(b.fields, 'fields.protocol'),
        i.protocolo
      ),
      'cadastral', i.referencia_catastral,
      'address', i.direccion
    ) AS obj
    FROM clientes c
    LEFT JOIN expedientes e
      ON e.cliente_id = c.id AND e.deleted_at IS NULL
    LEFT JOIN bloques b
      ON b.expediente_id = e.id
     AND b.deleted_at IS NULL
     AND b.status <> 'off'
     AND b.template_key = 'escritura'
    LEFT JOIN inmuebles i
      ON i.id = e.inmueble_id AND i.deleted_at IS NULL
    WHERE c.tenant_id = p_tenant_id
      AND c.deleted_at IS NULL
      AND (
        public.bloque_field(b.fields, 'fields.notary') ILIKE v_like
        OR public.bloque_field(b.fields, 'fields.protocol') ILIKE v_like
        OR i.notario ILIKE v_like
        OR i.direccion ILIKE v_like
        OR i.referencia_catastral ILIKE v_like
        OR EXISTS (
          SELECT 1
            FROM documentos d
           WHERE d.cliente_id = c.id
             AND d.tenant_id = p_tenant_id
             AND d.deleted_at IS NULL
             AND (
               coalesce(d.extracted->>'fields.notary', '') ILIKE v_like
               OR coalesce(d.extracted->>'fields.lawyer', '') ILIKE v_like
               OR coalesce(d.extracted->>'fields.sellers', '') ILIKE v_like
               OR coalesce(d.extracted->>'fields.buyers', '') ILIKE v_like
               OR coalesce(d.extracted->>'fields.cadastral', '') ILIKE v_like
               OR coalesce(d.extracted->>'fields.address', '') ILIKE v_like
               OR coalesce(d.extracted->>'fields.registry', '') ILIKE v_like
               OR coalesce(d.extracted->>'fields.attorney', '') ILIKE v_like
             )
        )
      )
    ORDER BY c.nombre, c.id
    LIMIT v_limit
  ) x;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, after
  ) VALUES (
    p_tenant_id,
    auth.uid(),
    (SELECT s.id FROM support_view_sessions s
      WHERE s.support_user_id = auth.uid()
        AND s.ended_at IS NULL
      ORDER BY s.started_at DESC LIMIT 1),
    'ai.tool',
    'bloques',
    jsonb_build_object('tool', 'query_escritura', 'q', v_q, 'total', v_total)
  );

  RETURN jsonb_build_object(
    'total', v_total,
    'filled_on_desk', v_total > 0,
    'items', v_items
  );
END;
$$;

COMMENT ON FUNCTION public.query_escritura(UUID, TEXT, INT) IS
  'Read-only: escritura podle notáře, právníka, catastral nebo strany. Věta ve smlouvě = search_document_text.';
