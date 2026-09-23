-- Vzory kanceláře pro další sken. Jen zařazené papíry téhož tenantu.
-- AI čte album / tipo / klíče, neukládá desku.

CREATE OR REPLACE FUNCTION public.similar_placed_papers(
  p_tenant_id UUID,
  p_query_embedding JSONB,
  p_exclude_documento_id UUID DEFAULT NULL,
  p_limit INT DEFAULT 5
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_limit INT := least(greatest(coalesce(p_limit, 5), 1), 8);
  v_arr FLOAT[];
  v_emb extensions.vector(1536);
  v_items JSONB;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT array_agg(x::float ORDER BY ord)
    INTO v_arr
    FROM jsonb_array_elements_text(p_query_embedding) WITH ORDINALITY AS t(x, ord);
  IF v_arr IS NULL OR array_length(v_arr, 1) IS DISTINCT FROM 1536 THEN
    RAISE EXCEPTION 'bad_embedding';
  END IF;
  v_emb := v_arr::extensions.vector(1536);

  SELECT coalesce(jsonb_agg(x.obj ORDER BY x.dist), '[]'::jsonb)
    INTO v_items
    FROM (
      SELECT jsonb_build_object(
        'document_id', best.documento_id,
        'tipo', best.tipo,
        'albums', coalesce((
          SELECT jsonb_agg(b2.template_key ORDER BY db.created_at)
            FROM public.documento_bloques db
            JOIN public.bloques b2
              ON b2.id = db.bloque_id AND b2.deleted_at IS NULL
           WHERE db.documento_id = best.documento_id AND db.deleted_at IS NULL
        ), '[]'::jsonb),
        'source', CASE WHEN best.human_album THEN 'human' ELSE 'ai' END,
        'caption', left(coalesce(best.caption, ''), 160),
        'title', left(coalesce(nullif(btrim(best.title), ''), ''), 120),
        'filled_keys', coalesce(best.filled_keys, '[]'::jsonb),
        'dist', round(best.dist::numeric, 4)
      ) AS obj,
      best.dist
      FROM (
        SELECT DISTINCT ON (ch.documento_id)
          d.id AS documento_id,
          d.tipo,
          d.caption,
          regexp_replace(
            split_part(coalesce(d.body_text, ''), E'\n', 1),
            '\s+', ' ', 'g'
          ) AS title,
          EXISTS (
            SELECT 1
              FROM public.documento_bloques dbh
             WHERE dbh.documento_id = d.id
               AND dbh.deleted_at IS NULL
               AND dbh.source = 'human'
          ) AS human_album,
          (
            SELECT coalesce(jsonb_agg(k ORDER BY k), '[]'::jsonb)
              FROM jsonb_each_text(coalesce(d.extracted, '{}'::jsonb)) e(k, v)
             WHERE btrim(coalesce(e.v, '')) <> ''
               AND e.k NOT IN (
                 'extract_status', 'body_text',
                 'proposed_bloque_key', 'proposed_tipo'
               )
               AND e.k NOT IN (
                 'fields.nie', 'fields.sellerNie', 'fields.nombre',
                 'fields.email', 'fields.tel', 'fields.buyers',
                 'fields.sellers', 'fields.attorney'
               )
          ) AS filled_keys,
          (ch.embedding <=> v_emb) AS dist
        FROM public.documento_chunks ch
        JOIN public.documentos d
          ON d.id = ch.documento_id AND d.deleted_at IS NULL
        JOIN public.clientes c
          ON c.id = d.cliente_id AND c.deleted_at IS NULL
        WHERE ch.tenant_id = p_tenant_id
          AND ch.deleted_at IS NULL
          AND (p_exclude_documento_id IS NULL OR d.id <> p_exclude_documento_id)
          AND c.erasure_requested_at IS NULL
          AND EXISTS (
            SELECT 1
              FROM public.documento_bloques db
             WHERE db.documento_id = d.id AND db.deleted_at IS NULL
          )
        ORDER BY ch.documento_id, ch.embedding <=> v_emb
      ) best
      ORDER BY best.dist
      LIMIT v_limit
    ) x;

  INSERT INTO public.audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, after
  ) VALUES (
    p_tenant_id,
    auth.uid(),
    (SELECT s.id FROM public.support_view_sessions s
      WHERE s.support_user_id = auth.uid()
        AND s.ended_at IS NULL
      ORDER BY s.started_at DESC LIMIT 1),
    'ai.tool',
    'documento_chunks',
    jsonb_build_object(
      'tool', 'similar_placed_papers',
      'total', coalesce(jsonb_array_length(v_items), 0)
    )
  );

  RETURN jsonb_build_object('items', coalesce(v_items, '[]'::jsonb));
END;
$$;

GRANT EXECUTE ON FUNCTION public.similar_placed_papers(UUID, JSONB, UUID, INT)
  TO authenticated;

COMMENT ON FUNCTION public.similar_placed_papers(UUID, JSONB, UUID, INT) IS
  'Read-only vzory zařazených papírů kanceláře. Extract z nich čte album, ne desku.';
