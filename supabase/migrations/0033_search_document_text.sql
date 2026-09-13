-- Fulltext v documentos.body_text. Žádný pgvector. AI jen čte.

CREATE INDEX IF NOT EXISTS idx_documentos_body_fts
  ON documentos
  USING GIN (to_tsvector('spanish', coalesce(body_text, '')))
  WHERE deleted_at IS NULL
    AND body_text IS NOT NULL
    AND length(btrim(body_text)) > 0;

CREATE OR REPLACE FUNCTION public.search_document_text(
  p_tenant_id UUID,
  p_q TEXT,
  p_limit INT DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := btrim(coalesce(p_q, ''));
  v_limit INT := least(greatest(coalesce(p_limit, 20), 1), 20);
  v_total BIGINT;
  v_items JSONB;
  v_has_text BOOLEAN;
  v_tsquery tsquery;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF char_length(v_q) < 3 THEN
    RAISE EXCEPTION 'query_too_short';
  END IF;

  SELECT exists(
    SELECT 1
      FROM documentos d
     WHERE d.tenant_id = p_tenant_id
       AND d.deleted_at IS NULL
       AND d.body_text IS NOT NULL
       AND length(btrim(d.body_text)) > 0
  ) INTO v_has_text;

  v_tsquery := plainto_tsquery('spanish', v_q);
  IF v_tsquery::text = '' THEN
    RETURN jsonb_build_object(
      'total', 0,
      'filled_on_desk', v_has_text,
      'items', '[]'::jsonb
    );
  END IF;

  SELECT count(*) INTO v_total
    FROM documentos d
    JOIN clientes c ON c.id = d.cliente_id
   WHERE d.tenant_id = p_tenant_id
     AND d.deleted_at IS NULL
     AND c.deleted_at IS NULL
     AND d.body_text IS NOT NULL
     AND to_tsvector('spanish', d.body_text) @@ v_tsquery;

  SELECT coalesce(jsonb_agg(x.obj), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT jsonb_build_object(
        'cliente_id', c.id,
        'nombre', trim(both from concat_ws(' ', c.nombre, c.apellidos)),
        'document_id', d.id,
        'original_name', d.original_name,
        'tipo', d.tipo,
        'bloque_key', b.template_key,
        'storage_path', d.storage_path,
        'snippet', ts_headline(
          'spanish',
          d.body_text,
          v_tsquery,
          'MaxFragments=1,MaxWords=28,MinWords=8'
        )
      ) AS obj
      FROM documentos d
      JOIN clientes c ON c.id = d.cliente_id
      LEFT JOIN bloques b ON b.id = d.bloque_id AND b.deleted_at IS NULL
      WHERE d.tenant_id = p_tenant_id
        AND d.deleted_at IS NULL
        AND c.deleted_at IS NULL
        AND d.body_text IS NOT NULL
        AND to_tsvector('spanish', d.body_text) @@ v_tsquery
      ORDER BY ts_rank(to_tsvector('spanish', d.body_text), v_tsquery) DESC
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
    'documentos',
    jsonb_build_object('tool', 'search_document_text', 'q', v_q, 'total', v_total)
  );

  RETURN jsonb_build_object(
    'total', v_total,
    'filled_on_desk', v_has_text,
    'items', v_items
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_document_text(UUID, TEXT, INT) TO authenticated;

COMMENT ON FUNCTION public.search_document_text(UUID, TEXT, INT) IS
  'Read-only fulltext v body_text. Prázdný přepis ≠ věta ve smlouvě není.';
