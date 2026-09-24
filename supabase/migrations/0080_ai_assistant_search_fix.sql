-- AI asistent regress:
-- 1) 0070 search_clients zase prohání jméno přes normalize_id (smaže mezery) →
--    „Renata Sušičová“ nenajde. Vrátit token AND + fold z 0038 + can_access_cliente.
-- 2) 0071 AI RPC → SECURITY INVOKER, ale audit_logs nemá INSERT policy →
--    ai_get_cliente / search_document_* padnou dřív, než vrátí snapshot.
--    Povolit append jen vlastnímu actor_id v tenantovi; AI RPC zůstanou INVOKER (RLS scope).
-- 3) Snapshot doplní identifikátory (NIE) a split jména — asistent na otevřené kartě.

CREATE OR REPLACE FUNCTION public.search_clients(p_q TEXT, p_limit INT DEFAULT 20)
RETURNS TABLE (
  cliente_id UUID,
  score INT,
  matched_via TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public, extensions
AS $$
#variable_conflict use_column
DECLARE
  id_q TEXT := public.normalize_id(p_q);
  name_q TEXT := btrim(coalesce(p_q, ''));
BEGIN
  IF name_q = '' THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH id_hits AS (
    SELECT
      ci.cliente_id AS hit_id,
      CASE
        WHEN ci.value_normalized = id_q THEN 100
        WHEN public.id_mask_match(ci.value_normalized, id_q) THEN 90
        WHEN starts_with(ci.value_normalized, id_q) THEN 80
        WHEN char_length(id_q) >= 3 AND ci.value_normalized % id_q THEN 60
        ELSE 0
      END AS hit_score,
      CASE
        WHEN ci.value_normalized = id_q THEN 'id_exact'::TEXT
        WHEN public.id_mask_match(ci.value_normalized, id_q) THEN 'id_mask'
        WHEN starts_with(ci.value_normalized, id_q) THEN 'id_prefix'
        ELSE 'id_trgm'
      END AS hit_via
    FROM client_identifiers ci
    WHERE ci.deleted_at IS NULL
      AND public.can_access_tenant(ci.tenant_id)
      AND public.can_access_cliente(ci.cliente_id)
      AND id_q <> ''
      AND (
        ci.value_normalized = id_q
        OR public.id_mask_match(ci.value_normalized, id_q)
        OR starts_with(ci.value_normalized, id_q)
        OR (char_length(id_q) >= 3 AND ci.value_normalized % id_q)
      )
  ),
  fts_hits AS (
    SELECT
      c.id AS hit_id,
      40 AS hit_score,
      'fts'::TEXT AS hit_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND public.can_access_cliente(c.id)
      AND char_length(name_q) >= 2
      AND c.search_vector @@ plainto_tsquery('simple', name_q)
  ),
  name_hits AS (
    SELECT
      c.id AS hit_id,
      50 AS hit_score,
      'name'::TEXT AS hit_via
    FROM clientes c
    WHERE c.deleted_at IS NULL
      AND public.can_access_tenant(c.tenant_id)
      AND public.can_access_cliente(c.id)
      AND char_length(name_q) >= 2
      AND public.search_name_matches(
        concat_ws(' ', c.nombre, c.apellidos, c.email, c.tel),
        name_q
      )
  ),
  combined AS (
    SELECT hit_id, hit_score, hit_via FROM id_hits WHERE hit_score > 0
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM fts_hits
    UNION ALL
    SELECT hit_id, hit_score, hit_via FROM name_hits
  )
  SELECT
    combined.hit_id,
    max(combined.hit_score)::INT,
    (array_agg(combined.hit_via ORDER BY combined.hit_score DESC))[1]
  FROM combined
  GROUP BY combined.hit_id
  ORDER BY max(combined.hit_score) DESC
  LIMIT greatest(1, least(coalesce(p_limit, 20), 50));
END;
$$;

COMMENT ON FUNCTION public.search_clients(TEXT, INT) IS
  'NIE přes normalize_id. Jméno: token AND + fold diakritiky (ne normalize_id). Scope: can_access_cliente.';

-- Append-only: UPDATE/DELETE pořád zakázané. INSERT jen vlastní actor v tenantovi.
DROP POLICY IF EXISTS audit_logs_insert ON public.audit_logs;
CREATE POLICY audit_logs_insert ON public.audit_logs
  FOR INSERT TO authenticated
  WITH CHECK (
    actor_id IS NOT DISTINCT FROM auth.uid()
    AND public.can_access_tenant(tenant_id)
  );

CREATE OR REPLACE FUNCTION public.ai_get_cliente(p_cliente_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_cliente JSONB;
  v_holes JSONB;
  v_docs JSONB;
  v_bloques JSONB;
  v_titulares JSONB;
  v_ids JSONB;
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
  IF NOT public.can_access_cliente(p_cliente_id) THEN
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
    'nombre_given', nullif(btrim(c.nombre), ''),
    'apellidos', nullif(btrim(c.apellidos), ''),
    'email', c.email,
    'tel', c.tel,
    'locale', c.locale,
    'tenant_id', c.tenant_id
  )
  INTO v_cliente
  FROM clientes c
  WHERE c.id = p_cliente_id;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'kind', ci.kind::text,
      'value_raw', ci.value_raw,
      'value_normalized', ci.value_normalized
    )
    ORDER BY
      CASE ci.kind::text
        WHEN 'nie' THEN 1
        WHEN 'dni' THEN 2
        WHEN 'nif' THEN 3
        ELSE 4
      END,
      ci.created_at
  ), '[]'::jsonb)
  INTO v_ids
  FROM client_identifiers ci
  WHERE ci.cliente_id = p_cliente_id
    AND ci.deleted_at IS NULL;

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

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', d.id,
        'tipo', d.tipo,
        'original_name', d.original_name,
        'extracted', d.extracted,
        'body_excerpt', left(d.body_text, 2500),
        'ai_summary', d.ai_summary,
        'inmueble_id', d.inmueble_id,
        'direccion', i.direccion,
        'albums', coalesce((
          SELECT jsonb_agg(b2.template_key ORDER BY db.created_at)
            FROM public.documento_bloques db
            JOIN public.bloques b2
              ON b2.id = db.bloque_id AND b2.deleted_at IS NULL
           WHERE db.documento_id = d.id AND db.deleted_at IS NULL
        ), '[]'::jsonb)
      )
      ORDER BY d.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_docs
  FROM documentos d
  LEFT JOIN inmuebles i
    ON i.id = d.inmueble_id AND i.deleted_at IS NULL
  WHERE d.cliente_id = p_cliente_id
    AND d.deleted_at IS NULL;

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'bloque_key', b.template_key,
        'status', b.status::text,
        'fields', b.fields
      )
    ),
    '[]'::jsonb
  )
  INTO v_bloques
  FROM bloques b
  JOIN expedientes e ON e.id = b.expediente_id
  WHERE e.cliente_id = p_cliente_id
    AND e.deleted_at IS NULL
    AND b.deleted_at IS NULL
    AND b.status <> 'off';

  SELECT coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  INTO v_titulares
  FROM (
    SELECT jsonb_build_object(
      'inmueble_id', i.id,
      'direccion', i.direccion,
      'lado', t.lado,
      'cuota_bps', t.cuota_bps,
      'share_percent', (t.cuota_bps / 100.0),
      'folder_cliente_id', i.cliente_id,
      'folder_nombre', trim(both from concat_ws(' ', fo.nombre, fo.apellidos)),
      'sale_price', public.inmueble_sale_price(i.id),
      'folder_has_carpeta', i.cliente_id IS DISTINCT FROM p_cliente_id
    ) AS obj
    FROM inmueble_titulares t
    JOIN inmuebles i ON i.id = t.inmueble_id AND i.deleted_at IS NULL
    JOIN clientes fo ON fo.id = i.cliente_id AND fo.deleted_at IS NULL
    WHERE t.cliente_id = p_cliente_id
      AND t.deleted_at IS NULL
      AND t.tenant_id = v_tenant
    ORDER BY t.created_at DESC
    LIMIT 10
  ) x;

  RETURN jsonb_build_object(
    'cliente', v_cliente,
    'identifiers', coalesce(v_ids, '[]'::jsonb),
    'holes', v_holes,
    'documentos', v_docs,
    'bloques', v_bloques,
    'titular_inmuebles', coalesce(v_titulares, '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.ai_get_cliente(UUID) IS
  'Snapshot + identifikátory + díry + doklady + titular. INVOKER + audit insert policy. Žádný save.';

GRANT EXECUTE ON FUNCTION public.search_clients(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_get_cliente(UUID) TO authenticated;
