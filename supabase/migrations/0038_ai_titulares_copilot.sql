-- Copilot u spoluvlastníka: jméno bez normalize_id, snapshot titular finca,
-- query_escritura podle strany. AI dál jen čte.

-- Fold ES+CS diakritiky na ASCII. Bez extension unaccent.
CREATE OR REPLACE FUNCTION public.normalize_search_text(raw TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT translate(
    lower(trim(coalesce(raw, ''))),
    'áàäâãåéèëêíìïîóòöôõúùüûýÿñçčďěňřšťůžÁÀÄÂÃÅÉÈËÊÍÌÏÎÓÒÖÔÕÚÙÜÛÝŸÑÇČĎĚŇŘŠŤŮŽ',
    'aaaaaaeeeeiiiiooooouuuuyynccdenrstuzAAAAAAEEEEIIIIOOOOOUUUUYYNCCDENRSTUZ'
  );
$$;

COMMENT ON FUNCTION public.normalize_search_text(TEXT) IS
  'Jméno/adresa: lower + translate diakritiky. Nesmí jít přes normalize_id (smaže mezery).';

-- Celý řetězec, nebo každé slovo (AND). Token kratší než 2 se přeskočí.
CREATE OR REPLACE FUNCTION public.search_name_matches(p_hay TEXT, p_q TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
PARALLEL SAFE
AS $$
DECLARE
  hay TEXT := public.normalize_search_text(p_hay);
  q TEXT := public.normalize_search_text(p_q);
  tok TEXT;
  seen BOOLEAN := false;
BEGIN
  IF q IS NULL OR q = '' OR hay IS NULL OR hay = '' THEN
    RETURN false;
  END IF;
  IF strpos(hay, q) > 0 THEN
    RETURN true;
  END IF;
  FOREACH tok IN ARRAY regexp_split_to_array(q, '\s+')
  LOOP
    IF char_length(tok) < 2 THEN
      CONTINUE;
    END IF;
    seen := true;
    IF strpos(hay, tok) = 0 THEN
      RETURN false;
    END IF;
  END LOOP;
  RETURN seen;
END;
$$;

COMMENT ON FUNCTION public.search_name_matches(TEXT, TEXT) IS
  'name_hits: celý q nebo token AND po normalize_search_text.';

-- Cena listiny na finca složky, ne doklady karty spoluvlastníka.
CREATE OR REPLACE FUNCTION public.inmueble_sale_price(p_inmueble_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT d.extracted->>'fields.salePrice'
  FROM expedientes e
  JOIN documentos d
    ON d.deleted_at IS NULL
   AND d.tenant_id = e.tenant_id
   AND coalesce(d.extracted->>'fields.salePrice', '') <> ''
   AND (
     EXISTS (
       SELECT 1 FROM bloques b
       WHERE b.id = d.bloque_id
         AND b.expediente_id = e.id
         AND b.deleted_at IS NULL
     )
     OR (d.cliente_id = e.cliente_id AND d.tipo = 'copia_escritura')
   )
  WHERE e.inmueble_id = p_inmueble_id
    AND e.deleted_at IS NULL
  ORDER BY d.created_at DESC
  LIMIT 1;
$$;

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
  'NIE přes normalize_id. Jméno: token AND + fold diakritiky, ne normalize_id.';

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
  v_docs JSONB;
  v_bloques JSONB;
  v_titulares JSONB;
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

  SELECT coalesce(
    jsonb_agg(
      jsonb_build_object(
        'tipo', d.tipo,
        'original_name', d.original_name,
        'extracted', d.extracted,
        'body_excerpt', left(d.body_text, 2500)
      )
      ORDER BY d.created_at DESC
    ),
    '[]'::jsonb
  )
  INTO v_docs
  FROM documentos d
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
    'holes', v_holes,
    'documentos', v_docs,
    'bloques', v_bloques,
    'titular_inmuebles', coalesce(v_titulares, '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.ai_get_cliente(UUID) IS
  'Snapshot + díry + doklady + titular finca (složka, salePrice, cuota). Audit ai.read.cliente. Žádný save/send.';

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
  v_id TEXT := public.normalize_id(trim(coalesce(p_notary, '')));
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
      OR EXISTS (
        SELECT 1
          FROM inmueble_titulares t
          JOIN inmuebles ii ON ii.id = t.inmueble_id AND ii.deleted_at IS NULL
         WHERE ii.cliente_id = c.id
           AND t.deleted_at IS NULL
           AND t.tenant_id = p_tenant_id
           AND (
             public.search_name_matches(t.nombre, v_q)
             OR (
               t.nie_normalized <> ''
               AND v_id <> ''
               AND t.nie_normalized LIKE '%' || v_id || '%'
             )
             OR (
               t.cliente_id IS NOT NULL
               AND EXISTS (
                 SELECT 1 FROM clientes tc
                 WHERE tc.id = t.cliente_id
                   AND tc.deleted_at IS NULL
                   AND public.search_name_matches(
                     concat_ws(' ', tc.nombre, tc.apellidos),
                     v_q
                   )
               )
             )
           )
      )
    );

  SELECT coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT DISTINCT ON (c.id) jsonb_build_object(
      'cliente_id', c.id,
      'folder_cliente_id', c.id,
      'titular_cliente_id', mt.titular_cliente_id,
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
      'address', i.direccion,
      'sale_price', CASE WHEN i.id IS NULL THEN NULL ELSE public.inmueble_sale_price(i.id) END,
      'bloque_key', 'escritura'
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
    LEFT JOIN LATERAL (
      SELECT t.cliente_id AS titular_cliente_id
      FROM inmueble_titulares t
      WHERE i.id IS NOT NULL
        AND t.inmueble_id = i.id
        AND t.deleted_at IS NULL
        AND (
          public.search_name_matches(t.nombre, v_q)
          OR (
            t.nie_normalized <> ''
            AND v_id <> ''
            AND t.nie_normalized LIKE '%' || v_id || '%'
          )
          OR (
            t.cliente_id IS NOT NULL
            AND EXISTS (
              SELECT 1 FROM clientes tc
              WHERE tc.id = t.cliente_id
                AND tc.deleted_at IS NULL
                AND public.search_name_matches(
                  concat_ws(' ', tc.nombre, tc.apellidos),
                  v_q
                )
            )
          )
        )
      LIMIT 1
    ) mt ON true
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
        OR EXISTS (
          SELECT 1
            FROM inmueble_titulares t
            JOIN inmuebles ii ON ii.id = t.inmueble_id AND ii.deleted_at IS NULL
           WHERE ii.cliente_id = c.id
             AND t.deleted_at IS NULL
             AND t.tenant_id = p_tenant_id
             AND (
               public.search_name_matches(t.nombre, v_q)
               OR (
                 t.nie_normalized <> ''
                 AND v_id <> ''
                 AND t.nie_normalized LIKE '%' || v_id || '%'
               )
               OR (
                 t.cliente_id IS NOT NULL
                 AND EXISTS (
                   SELECT 1 FROM clientes tc
                   WHERE tc.id = t.cliente_id
                     AND tc.deleted_at IS NULL
                     AND public.search_name_matches(
                       concat_ws(' ', tc.nombre, tc.apellidos),
                       v_q
                     )
                 )
               )
             )
        )
      )
    ORDER BY c.id,
      CASE WHEN b.template_key = 'escritura' THEN 0 ELSE 1 END,
      CASE WHEN i.id IS NOT NULL THEN 0 ELSE 1 END
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
  'Read-only: escritura podle notáře, strany v titulares, adresy. Řádek = složka. Věta ve smlouvě = search_document_text.';

GRANT EXECUTE ON FUNCTION public.normalize_search_text(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_name_matches(TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.inmueble_sale_price(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_clients(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_get_cliente(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.query_escritura(UUID, TEXT, INT) TO authenticated;
