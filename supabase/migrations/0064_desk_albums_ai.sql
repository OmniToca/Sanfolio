-- Deska a povinné doklady čtou alba (documento_bloques).
-- Asistent vidí hromadu, víc alb a finca. AI neukládá.

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
  v_mode TEXT;
BEGIN
  SELECT * INTO b FROM bloques WHERE id = p_bloque_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(b.tenant_id) THEN
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
      IF nullif(btrim(public.bloque_field(b.fields, v_key)), '') IS NULL
         AND nullif(btrim(b.fields->>v_key), '') IS NULL THEN
        v_missing_data := true;
        EXIT;
      END IF;
    END LOOP;
  END IF;

  v_mode := coalesce(t.required_docs_mode, 'all');
  IF t.required_doc_types IS NOT NULL
     AND cardinality(t.required_doc_types) > 0 THEN
    IF v_mode = 'any' THEN
      v_missing_doc := NOT EXISTS (
        SELECT 1
          FROM public.documento_bloques db
          JOIN public.documentos d
            ON d.id = db.documento_id
           AND d.deleted_at IS NULL
         WHERE db.bloque_id = b.id
           AND db.deleted_at IS NULL
           AND coalesce(nullif(btrim(db.tipo), ''), d.tipo)
               = ANY (t.required_doc_types)
      ) AND NOT EXISTS (
        SELECT 1
          FROM public.documentos d
         WHERE d.bloque_id = b.id
           AND d.deleted_at IS NULL
           AND d.tipo = ANY (t.required_doc_types)
           AND NOT EXISTS (
             SELECT 1
               FROM public.documento_bloques db
              WHERE db.documento_id = d.id
                AND db.deleted_at IS NULL
           )
      );
    ELSE
      FOREACH v_tipo IN ARRAY t.required_doc_types
      LOOP
        IF NOT EXISTS (
          SELECT 1
            FROM public.documento_bloques db
            JOIN public.documentos d
              ON d.id = db.documento_id
             AND d.deleted_at IS NULL
           WHERE db.bloque_id = b.id
             AND db.deleted_at IS NULL
             AND coalesce(nullif(btrim(db.tipo), ''), d.tipo) = v_tipo
        ) AND NOT EXISTS (
          SELECT 1
            FROM public.documentos d
           WHERE d.bloque_id = b.id
             AND d.deleted_at IS NULL
             AND d.tipo = v_tipo
             AND NOT EXISTS (
               SELECT 1
                 FROM public.documento_bloques db
                WHERE db.documento_id = d.id
                  AND db.deleted_at IS NULL
             )
        ) THEN
          v_missing_doc := true;
          EXIT;
        END IF;
      END LOOP;
    END IF;
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

COMMENT ON FUNCTION public.recompute_bloque_status(UUID) IS
  'Stav desky. Papír v albu (documento_bloques.tipo) stačí jako sken. Pole desky dál Guardar.';

CREATE OR REPLACE FUNCTION public.trg_documento_bloques_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.recompute_bloque_status(OLD.bloque_id);
    RETURN OLD;
  END IF;
  PERFORM public.recompute_bloque_status(NEW.bloque_id);
  IF TG_OP = 'UPDATE' AND OLD.bloque_id IS DISTINCT FROM NEW.bloque_id THEN
    PERFORM public.recompute_bloque_status(OLD.bloque_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documento_bloques_status ON public.documento_bloques;
CREATE TRIGGER trg_documento_bloques_status
  AFTER INSERT OR UPDATE OR DELETE
  ON public.documento_bloques
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_documento_bloques_status();

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
       SELECT 1
         FROM public.documento_bloques db
         JOIN public.bloques b ON b.id = db.bloque_id AND b.deleted_at IS NULL
        WHERE db.documento_id = d.id
          AND db.deleted_at IS NULL
          AND b.expediente_id = e.id
     )
     OR EXISTS (
       SELECT 1 FROM public.bloques b
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
        'bloque_key', (
          SELECT b2.template_key
            FROM public.documento_bloques db
            JOIN public.bloques b2
              ON b2.id = db.bloque_id AND b2.deleted_at IS NULL
           WHERE db.documento_id = d.id AND db.deleted_at IS NULL
           ORDER BY db.created_at
           LIMIT 1
        ),
        'albums', coalesce((
          SELECT jsonb_agg(b2.template_key ORDER BY db.created_at)
            FROM public.documento_bloques db
            JOIN public.bloques b2
              ON b2.id = db.bloque_id AND b2.deleted_at IS NULL
           WHERE db.documento_id = d.id AND db.deleted_at IS NULL
        ), '[]'::jsonb),
        'inmueble_id', d.inmueble_id,
        'direccion', i.direccion,
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
      LEFT JOIN inmuebles i
        ON i.id = d.inmueble_id AND i.deleted_at IS NULL
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

COMMENT ON FUNCTION public.search_document_text(UUID, TEXT, INT) IS
  'Read-only FTS v body_text i bez alba. albums [] = hromada. inmueble_id = finca.';

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
        'id', d.id,
        'tipo', d.tipo,
        'original_name', d.original_name,
        'extracted', d.extracted,
        'body_excerpt', left(d.body_text, 2500),
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
    'holes', v_holes,
    'documentos', v_docs,
    'bloques', v_bloques,
    'titular_inmuebles', coalesce(v_titulares, '[]'::jsonb)
  );
END;
$$;

COMMENT ON FUNCTION public.ai_get_cliente(UUID) IS
  'Snapshot + díry + doklady (albums [], inmueble) + titular finca. Audit ai.read.cliente. Žádný save.';

GRANT EXECUTE ON FUNCTION public.recompute_bloque_status(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_document_text(UUID, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ai_get_cliente(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.inmueble_sale_price(UUID) TO authenticated;
