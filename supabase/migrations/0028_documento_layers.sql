-- Dokument: jedna cesta, přepis, koš blobu, office-wide čtení.
-- Canonical pole desky = fields.* (0020). Historické klíče čte bloque_field.

ALTER TABLE documentos
  ADD COLUMN IF NOT EXISTS body_text TEXT,
  ADD COLUMN IF NOT EXISTS storage_purged_at TIMESTAMPTZ;

COMMENT ON COLUMN documentos.body_text IS
  'Přepis PDF po Guardar. AI sem nezapisuje. Originál zůstává ve Storage.';
COMMENT ON COLUMN documentos.storage_purged_at IS
  'Owner vysypal blob. Řádek a přepis zůstanou. NULL = soubor ještě je.';

-- ---------------------------------------------------------------------------
-- Cesta musí patřit tenantovi (a klientovi). Zabrání zápisu do cizí složky.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.documentos_storage_path_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.storage_path IS NULL
     OR position('..' in NEW.storage_path) > 0
     OR NEW.storage_path NOT LIKE (NEW.tenant_id::text || '/%') THEN
    RAISE EXCEPTION 'storage_path outside tenant';
  END IF;
  IF NEW.cliente_id IS NOT NULL
     AND NEW.storage_path NOT LIKE (
       NEW.tenant_id::text || '/' || NEW.cliente_id::text || '/%'
     ) THEN
    RAISE EXCEPTION 'storage_path outside cliente';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_documentos_storage_path ON documentos;
CREATE TRIGGER trg_documentos_storage_path
  BEFORE INSERT OR UPDATE OF storage_path, tenant_id, cliente_id
  ON documentos
  FOR EACH ROW
  EXECUTE FUNCTION public.documentos_storage_path_guard();

-- Orphan blob (žádný řádek) smí staff smazat — rollback po spadlém INSERT.
-- Živý i schovaný dokument maže jen purge_documento_storage (owner).
DROP POLICY IF EXISTS documentos_storage_delete ON storage.objects;
CREATE POLICY documentos_storage_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
    AND NOT EXISTS (
      SELECT 1 FROM public.documentos d
      WHERE d.storage_path = name
        AND d.storage_purged_at IS NULL
    )
  );

-- ---------------------------------------------------------------------------
-- Čtení pole bloku: UI klíč, jinak starý SQL název.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bloque_field(fields JSONB, canonical TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT nullif(trim(coalesce(
    fields ->> canonical,
    CASE canonical
      WHEN 'fields.company' THEN coalesce(fields->>'proveedor', fields->>'compania')
      WHEN 'fields.expiry' THEN fields->>'fecha_vencimiento'
      WHEN 'fields.policy' THEN fields->>'numero_poliza'
      WHEN 'fields.contractNo' THEN fields->>'numero_contrato'
      WHEN 'fields.holder' THEN fields->>'titular'
      WHEN 'fields.clientNo' THEN fields->>'numero_cliente'
      WHEN 'fields.notary' THEN fields->>'notario'
      WHEN 'fields.date' THEN coalesce(fields->>'escritura_fecha', fields->>'fecha')
      WHEN 'fields.protocol' THEN fields->>'protocolo'
      WHEN 'fields.admin' THEN fields->>'proveedor'
      WHEN 'fields.sumaId' THEN fields->>'identificacion_suma'
      ELSE NULL
    END
  )), '');
$$;

-- ---------------------------------------------------------------------------
-- Vysypat blob. Řádek, audit a přepis zůstanou. Jen owner / impersonace.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_documento_storage(p_documento_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, storage
AS $$
DECLARE
  d RECORD;
BEGIN
  SELECT * INTO d FROM documentos WHERE id = p_documento_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.is_tenant_owner(d.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF d.deleted_at IS NULL THEN
    RAISE EXCEPTION 'not_in_trash';
  END IF;
  IF d.storage_purged_at IS NOT NULL THEN
    RETURN true;
  END IF;
  DELETE FROM storage.objects
  WHERE bucket_id = 'documentos'
    AND name = d.storage_path;
  UPDATE documentos
     SET storage_purged_at = now(),
         updated_at = now()
   WHERE id = d.id;
  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  ) VALUES (
    d.tenant_id,
    auth.uid(),
    (SELECT s.id FROM support_view_sessions s
      WHERE s.support_user_id = auth.uid()
        AND s.ended_at IS NULL
      ORDER BY s.started_at DESC LIMIT 1),
    'documentos.purge_storage',
    'documentos',
    d.id,
    jsonb_build_object('tipo', d.tipo, 'original_name', d.original_name)
  );
  RETURN true;
END;
$$;

-- ---------------------------------------------------------------------------
-- Office-wide čtení. Žádný execute_sql. Limit 20. Jen živé desky.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.query_suministro(
  p_tenant_id UUID,
  p_company TEXT,
  p_bloque_key TEXT DEFAULT 'luz',
  p_limit INT DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_q TEXT := trim(coalesce(p_company, ''));
  v_key TEXT := coalesce(nullif(trim(p_bloque_key), ''), 'luz');
  v_limit INT := least(greatest(coalesce(p_limit, 20), 1), 20);
  v_total BIGINT;
  v_items JSONB;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_key NOT IN ('luz', 'agua', 'gaz') THEN
    RAISE EXCEPTION 'bad_bloque';
  END IF;
  IF length(v_q) < 2 THEN
    RAISE EXCEPTION 'query_too_short';
  END IF;

  SELECT count(*) INTO v_total
  FROM bloques b
  JOIN expedientes e ON e.id = b.expediente_id
  JOIN clientes c ON c.id = e.cliente_id
  WHERE b.tenant_id = p_tenant_id
    AND b.deleted_at IS NULL
    AND e.deleted_at IS NULL
    AND c.deleted_at IS NULL
    AND b.status <> 'off'
    AND b.template_key = v_key
    AND public.bloque_field(b.fields, 'fields.company') ILIKE '%' || v_q || '%';

  SELECT coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT jsonb_build_object(
      'cliente_id', c.id,
      'nombre', trim(both from concat_ws(' ', c.nombre, c.apellidos)),
      'company', public.bloque_field(b.fields, 'fields.company'),
      'bloque_key', b.template_key
    ) AS obj
    FROM bloques b
    JOIN expedientes e ON e.id = b.expediente_id
    JOIN clientes c ON c.id = e.cliente_id
    WHERE b.tenant_id = p_tenant_id
      AND b.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND b.status <> 'off'
      AND b.template_key = v_key
      AND public.bloque_field(b.fields, 'fields.company') ILIKE '%' || v_q || '%'
    ORDER BY c.nombre
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
    jsonb_build_object('tool', 'query_suministro', 'q', v_q, 'bloque', v_key, 'total', v_total)
  );

  RETURN jsonb_build_object('total', v_total, 'filled_on_desk', v_total > 0, 'items', v_items);
END;
$$;

CREATE OR REPLACE FUNCTION public.query_plazos_office(
  p_tenant_id UUID,
  p_kind TEXT DEFAULT 'seguro_renovacion',
  p_within_days INT DEFAULT 90,
  p_limit INT DEFAULT 20
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_kind TEXT := coalesce(nullif(trim(p_kind), ''), 'seguro_renovacion');
  v_days INT := least(greatest(coalesce(p_within_days, 90), 1), 366);
  v_limit INT := least(greatest(coalesce(p_limit, 20), 1), 20);
  v_today DATE := (timezone('Europe/Madrid', now()))::date;
  v_total BIGINT;
  v_items JSONB;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_kind NOT IN (
    'seguro_renovacion', 'alarma_renovacion', 'poder_caducidad',
    'nie_caducidad', 'ibi_anual', 'plusvalia_plazo'
  ) THEN
    RAISE EXCEPTION 'bad_kind';
  END IF;

  SELECT count(*) INTO v_total
  FROM plazos p
  JOIN bloques b ON b.id = p.bloque_id
  JOIN expedientes e ON e.id = coalesce(p.expediente_id, b.expediente_id)
  JOIN clientes c ON c.id = e.cliente_id
  WHERE p.tenant_id = p_tenant_id
    AND p.deleted_at IS NULL
    AND b.deleted_at IS NULL
    AND e.deleted_at IS NULL
    AND c.deleted_at IS NULL
    AND p.kind = v_kind
    AND p.completed_at IS NULL
    AND p.due_on >= v_today
    AND p.due_on <= v_today + v_days;

  SELECT coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT jsonb_build_object(
      'cliente_id', c.id,
      'nombre', trim(both from concat_ws(' ', c.nombre, c.apellidos)),
      'due_on', p.due_on,
      'kind', p.kind
    ) AS obj
    FROM plazos p
    JOIN bloques b ON b.id = p.bloque_id
    JOIN expedientes e ON e.id = coalesce(p.expediente_id, b.expediente_id)
    JOIN clientes c ON c.id = e.cliente_id
    WHERE p.tenant_id = p_tenant_id
      AND p.deleted_at IS NULL
      AND b.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND p.kind = v_kind
      AND p.completed_at IS NULL
      AND p.due_on >= v_today
      AND p.due_on <= v_today + v_days
    ORDER BY p.due_on, c.nombre
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
    'plazos',
    jsonb_build_object('tool', 'query_plazos_office', 'kind', v_kind, 'days', v_days, 'total', v_total)
  );

  RETURN jsonb_build_object('total', v_total, 'items', v_items);
END;
$$;

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

  SELECT count(*) INTO v_total
  FROM bloques b
  JOIN expedientes e ON e.id = b.expediente_id
  JOIN clientes c ON c.id = e.cliente_id
  WHERE b.tenant_id = p_tenant_id
    AND b.deleted_at IS NULL
    AND e.deleted_at IS NULL
    AND c.deleted_at IS NULL
    AND b.status <> 'off'
    AND b.template_key = 'escritura'
    AND public.bloque_field(b.fields, 'fields.notary') ILIKE '%' || v_q || '%';

  SELECT coalesce(jsonb_agg(x.obj), '[]'::jsonb)
  INTO v_items
  FROM (
    SELECT jsonb_build_object(
      'cliente_id', c.id,
      'nombre', trim(both from concat_ws(' ', c.nombre, c.apellidos)),
      'notary', public.bloque_field(b.fields, 'fields.notary'),
      'date', public.bloque_field(b.fields, 'fields.date'),
      'protocol', public.bloque_field(b.fields, 'fields.protocol')
    ) AS obj
    FROM bloques b
    JOIN expedientes e ON e.id = b.expediente_id
    JOIN clientes c ON c.id = e.cliente_id
    WHERE b.tenant_id = p_tenant_id
      AND b.deleted_at IS NULL
      AND e.deleted_at IS NULL
      AND c.deleted_at IS NULL
      AND b.status <> 'off'
      AND b.template_key = 'escritura'
      AND public.bloque_field(b.fields, 'fields.notary') ILIKE '%' || v_q || '%'
    ORDER BY c.nombre
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

  RETURN jsonb_build_object('total', v_total, 'filled_on_desk', v_total > 0, 'items', v_items);
END;
$$;

GRANT EXECUTE ON FUNCTION public.bloque_field(JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.purge_documento_storage(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.query_suministro(UUID, TEXT, TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.query_plazos_office(UUID, TEXT, INT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.query_escritura(UUID, TEXT, INT) TO authenticated;

COMMENT ON FUNCTION public.purge_documento_storage(UUID) IS
  'Owner smaže blob schovaného dokumentu. Řádek a přepis zůstanou.';
COMMENT ON FUNCTION public.query_suministro(UUID, TEXT, TEXT, INT) IS
  'Read-only: klienti s dodavatelem na desce. AI nesmí ukládat.';
COMMENT ON FUNCTION public.query_plazos_office(UUID, TEXT, INT, INT) IS
  'Read-only: termíny kanceláře v intervalu (Madrid date).';
COMMENT ON FUNCTION public.query_escritura(UUID, TEXT, INT) IS
  'Read-only: escritura s notářem na desce.';

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

  RETURN jsonb_build_object(
    'cliente', v_cliente,
    'holes', v_holes,
    'documentos', v_docs,
    'bloques', v_bloques
  );
END;
$$;
