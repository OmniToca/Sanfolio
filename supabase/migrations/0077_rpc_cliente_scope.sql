-- H1: DEFINER mutate/read RPC vyžadují can_access_cliente (scoped staff).
-- M3: storage DELETE stejně. M4: forbid_hard_delete na staff_* / documento_bloques.

-- ---------------------------------------------------------------------------
-- Pošta
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.match_posta_cliente(
  p_tenant_id UUID,
  p_email TEXT
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_email);
  v_id UUID;
  v_n INT;
BEGIN
  IF v_email IS NULL THEN
    RETURN NULL;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT s.cliente_id INTO v_id
    FROM public.posta_senders s
   WHERE s.tenant_id = p_tenant_id
     AND s.email = v_email
     AND s.deleted_at IS NULL
   LIMIT 1;
  IF v_id IS NOT NULL THEN
    IF auth.uid() IS NOT NULL AND NOT public.can_access_cliente(v_id) THEN
      RETURN NULL;
    END IF;
    RETURN v_id;
  END IF;

  SELECT COUNT(DISTINCT x.cliente_id), MIN(x.cliente_id)
    INTO v_n, v_id
    FROM (
      SELECT c.id AS cliente_id
        FROM public.clientes c
       WHERE c.tenant_id = p_tenant_id
         AND c.deleted_at IS NULL
         AND public.posta_normalize_email(c.email) = v_email
      UNION
      SELECT cc.cliente_id
        FROM public.client_contacts cc
       WHERE cc.tenant_id = p_tenant_id
         AND cc.deleted_at IS NULL
         AND public.posta_normalize_email(cc.email) = v_email
    ) x;

  IF v_n = 1 AND v_id IS NOT NULL THEN
    IF auth.uid() IS NOT NULL AND NOT public.can_access_cliente(v_id) THEN
      RETURN NULL;
    END IF;
    RETURN v_id;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.suggest_posta_cliente(
  p_tenant_id UUID,
  p_email TEXT,
  p_from_name TEXT DEFAULT NULL
)
RETURNS TABLE (
  cliente_id UUID,
  nombre TEXT,
  match_method TEXT,
  auto BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_email TEXT := public.posta_normalize_email(p_email);
  v_id UUID;
  v_method TEXT;
  v_auto BOOLEAN := false;
  v_name TEXT := lower(btrim(coalesce(p_from_name, '')));
  v_n INT;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF v_email IS NOT NULL THEN
    SELECT s.cliente_id INTO v_id
      FROM public.posta_senders s
     WHERE s.tenant_id = p_tenant_id
       AND s.email = v_email
       AND s.deleted_at IS NULL
     LIMIT 1;
    IF v_id IS NOT NULL THEN
      v_method := 'remembered';
      v_auto := true;
    ELSE
      v_id := public.match_posta_cliente(p_tenant_id, v_email);
      IF v_id IS NOT NULL THEN
        v_method := 'from_email';
        v_auto := true;
      END IF;
    END IF;
  END IF;

  IF v_id IS NULL AND char_length(v_name) >= 5 THEN
    SELECT COUNT(*)::INT, MIN(c.id)
      INTO v_n, v_id
      FROM public.clientes c
     WHERE c.tenant_id = p_tenant_id
       AND c.deleted_at IS NULL
       AND (
         lower(btrim(concat_ws(' ', c.nombre, c.apellidos))) = v_name
         OR lower(btrim(concat_ws(' ', c.apellidos, c.nombre))) = v_name
         OR lower(btrim(coalesce(c.razon_social, ''))) = v_name
       );
    IF v_n = 1 AND v_id IS NOT NULL THEN
      v_method := 'from_name';
      v_auto := false;
    ELSE
      v_id := NULL;
    END IF;
  END IF;

  IF v_id IS NULL THEN
    RETURN;
  END IF;
  -- Scoped: nevracej kartu mimo rozsah.
  IF auth.uid() IS NOT NULL AND NOT public.can_access_cliente(v_id) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    COALESCE(
      NULLIF(btrim(c.razon_social), ''),
      NULLIF(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
      '—'
    ),
    v_method,
    v_auto
  FROM public.clientes c
  WHERE c.id = v_id
    AND c.deleted_at IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.assign_posta_message(
  p_message_id UUID,
  p_cliente_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
  v_c RECORD;
BEGIN
  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF NOT public.can_access_cliente(p_cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT id, tenant_id INTO v_c
    FROM public.clientes
   WHERE id = p_cliente_id
     AND deleted_at IS NULL;
  IF NOT FOUND OR v_c.tenant_id <> v_m.tenant_id THEN
    RAISE EXCEPTION 'cliente_missing';
  END IF;

  UPDATE public.posta_messages
     SET cliente_id = p_cliente_id,
         status = 'assigned',
         match_method = 'manual',
         updated_at = now()
   WHERE id = v_m.id;

  PERFORM public.remember_posta_sender(
    v_m.tenant_id, v_m.from_address, p_cliente_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.ignore_posta_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
BEGIN
  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  -- Přiřazená pošta: jen kdo smí ke kartě. Nepřiřazená = office fronta.
  IF v_m.cliente_id IS NOT NULL
     AND NOT public.can_access_cliente(v_m.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.posta_messages
     SET status = 'ignored',
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.unassign_posta_message(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
BEGIN
  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_m.cliente_id IS NOT NULL
     AND NOT public.can_access_cliente(v_m.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.posta_messages
     SET cliente_id = NULL,
         status = 'unassigned',
         match_method = NULL,
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_posta_attachment_filed(
  p_attachment_id UUID,
  p_documento_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_a RECORD;
  v_m RECORD;
  v_d RECORD;
BEGIN
  SELECT * INTO v_a
    FROM public.posta_attachments
   WHERE id = p_attachment_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_a.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = v_a.message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF v_m.cliente_id IS NULL THEN
    RAISE EXCEPTION 'unassigned';
  END IF;
  IF NOT public.can_access_cliente(v_m.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT id, tenant_id, cliente_id INTO v_d
    FROM public.documentos
   WHERE id = p_documento_id
     AND deleted_at IS NULL;
  IF NOT FOUND
     OR v_d.tenant_id <> v_a.tenant_id
     OR v_d.cliente_id IS DISTINCT FROM v_m.cliente_id THEN
    RAISE EXCEPTION 'documento_mismatch';
  END IF;
  IF v_d.cliente_id IS NOT NULL
     AND NOT public.can_access_cliente(v_d.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.posta_attachments
     SET documento_id = p_documento_id,
         updated_at = now()
   WHERE id = v_a.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_posta_done(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
BEGIN
  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_m.cliente_id IS NULL THEN
    RAISE EXCEPTION 'need_cliente';
  END IF;
  IF NOT public.can_access_cliente(v_m.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.posta_messages
     SET done_at = now(),
         status = 'assigned',
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_posta_undone(p_message_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_m RECORD;
BEGIN
  SELECT * INTO v_m
    FROM public.posta_messages
   WHERE id = p_message_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_m.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_m.cliente_id IS NOT NULL
     AND NOT public.can_access_cliente(v_m.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.posta_messages
     SET done_at = NULL,
         updated_at = now()
   WHERE id = v_m.id;
END;
$$;

-- ---------------------------------------------------------------------------
-- Dokumenty / knihovna
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.set_documento_inmueble(
  p_documento_id UUID,
  p_inmueble_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.documentos%ROWTYPE;
BEGIN
  SELECT * INTO v_doc FROM public.documentos
   WHERE id = p_documento_id AND deleted_at IS NULL;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_doc.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_doc.cliente_id IS NULL
     OR NOT public.can_access_cliente(v_doc.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE public.documentos
     SET inmueble_id = p_inmueble_id,
         updated_at = now()
   WHERE id = p_documento_id;

  IF p_inmueble_id IS NOT NULL THEN
    UPDATE public.documento_bloques db
       SET deleted_at = now()
      FROM public.bloques b
      JOIN public.expedientes e ON e.id = b.expediente_id
     WHERE db.documento_id = p_documento_id
       AND db.deleted_at IS NULL
       AND db.bloque_id = b.id
       AND e.inmueble_id IS NOT NULL
       AND e.inmueble_id IS DISTINCT FROM p_inmueble_id;
  END IF;

  PERFORM public.sync_documento_primary_bloque(p_documento_id);

  INSERT INTO public.audit_logs (
    tenant_id, actor_id, action, entity_table, entity_id, after
  ) VALUES (
    v_doc.tenant_id,
    auth.uid(),
    'documento.set_inmueble',
    'documentos',
    p_documento_id,
    jsonb_build_object('inmueble_id', p_inmueble_id)
  );

  RETURN p_documento_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_documento_placement(
  p_documento_id UUID,
  p_bloque_id UUID,
  p_tipo TEXT,
  p_on BOOLEAN
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.documentos%ROWTYPE;
  v_tenant UUID;
  v_exp_inm UUID;
  v_tipo TEXT := nullif(btrim(coalesce(p_tipo, '')), '');
BEGIN
  SELECT * INTO v_doc FROM public.documentos
   WHERE id = p_documento_id AND deleted_at IS NULL;
  IF v_doc.id IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_doc.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_doc.cliente_id IS NULL
     OR NOT public.can_access_cliente(v_doc.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  v_tenant := v_doc.tenant_id;
  IF v_tipo IS NULL THEN
    v_tipo := coalesce(nullif(btrim(v_doc.tipo), ''), 'other');
  END IF;

  SELECT e.inmueble_id INTO v_exp_inm
    FROM public.bloques b
    JOIN public.expedientes e ON e.id = b.expediente_id
   WHERE b.id = p_bloque_id AND b.deleted_at IS NULL AND e.deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;

  IF p_on
     AND v_doc.inmueble_id IS NULL
     AND v_exp_inm IS NOT NULL THEN
    UPDATE public.documentos
       SET inmueble_id = v_exp_inm, updated_at = now()
     WHERE id = p_documento_id;
    v_doc.inmueble_id := v_exp_inm;
  END IF;

  IF p_on THEN
    UPDATE public.documento_bloques
       SET tipo = v_tipo,
           source = 'human',
           created_by = auth.uid()
     WHERE documento_id = p_documento_id
       AND bloque_id = p_bloque_id
       AND deleted_at IS NULL;
    IF NOT FOUND THEN
      UPDATE public.documento_bloques db
         SET deleted_at = NULL,
             tipo = v_tipo,
             source = 'human',
             created_by = auth.uid()
        FROM (
          SELECT id
            FROM public.documento_bloques
           WHERE documento_id = p_documento_id
             AND bloque_id = p_bloque_id
             AND deleted_at IS NOT NULL
           ORDER BY created_at DESC
           LIMIT 1
        ) x
       WHERE db.id = x.id;
      IF NOT FOUND THEN
        INSERT INTO public.documento_bloques (
          tenant_id, documento_id, bloque_id, tipo, source, created_by
        )
        SELECT v_tenant, p_documento_id, p_bloque_id, v_tipo, 'human', auth.uid()
         WHERE NOT EXISTS (
           SELECT 1 FROM public.documento_bloques
            WHERE documento_id = p_documento_id
              AND bloque_id = p_bloque_id
              AND deleted_at IS NULL
         );
      END IF;
    END IF;
  ELSE
    UPDATE public.documento_bloques
       SET deleted_at = now()
     WHERE documento_id = p_documento_id
       AND bloque_id = p_bloque_id
       AND deleted_at IS NULL;
  END IF;

  PERFORM public.sync_documento_primary_bloque(p_documento_id);

  INSERT INTO public.audit_logs (
    tenant_id, actor_id, action, entity_table, entity_id, after
  ) VALUES (
    v_tenant,
    auth.uid(),
    CASE WHEN p_on THEN 'documento.place' ELSE 'documento.unplace' END,
    'documento_bloques',
    p_documento_id,
    jsonb_build_object('bloque_id', p_bloque_id, 'tipo', v_tipo, 'on', p_on)
  );

  RETURN p_documento_id;
END;
$$;

-- Extract už place nevolá (H3). RPC zůstává pro zpětnou kompatibilitu + scope.
CREATE OR REPLACE FUNCTION public.place_documento_ai(
  p_documento_id UUID,
  p_bloque_id UUID,
  p_tipo TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_doc public.documentos%ROWTYPE;
  v_tipo TEXT := nullif(btrim(coalesce(p_tipo, '')), '');
  v_exp_inm UUID;
  v_human INT;
BEGIN
  SELECT * INTO v_doc FROM public.documentos
   WHERE id = p_documento_id AND deleted_at IS NULL;
  IF v_doc.id IS NULL THEN
    RETURN false;
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.can_access_tenant(v_doc.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF auth.uid() IS NOT NULL
     AND (v_doc.cliente_id IS NULL OR NOT public.can_access_cliente(v_doc.cliente_id)) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_tipo IS NULL THEN
    v_tipo := coalesce(nullif(btrim(v_doc.tipo), ''), 'other');
  END IF;

  SELECT count(*) INTO v_human
    FROM public.documento_bloques
   WHERE documento_id = p_documento_id
     AND deleted_at IS NULL
     AND source = 'human';
  IF v_human > 0 THEN
    RETURN false;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.documento_bloques
     WHERE documento_id = p_documento_id AND deleted_at IS NULL
  ) THEN
    RETURN false;
  END IF;

  SELECT e.inmueble_id INTO v_exp_inm
    FROM public.bloques b
    JOIN public.expedientes e ON e.id = b.expediente_id
   WHERE b.id = p_bloque_id AND b.deleted_at IS NULL AND e.deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF v_doc.inmueble_id IS NOT NULL
     AND v_exp_inm IS NOT NULL
     AND v_doc.inmueble_id IS DISTINCT FROM v_exp_inm THEN
    RETURN false;
  END IF;
  IF v_doc.inmueble_id IS NULL AND v_exp_inm IS NOT NULL THEN
    UPDATE public.documentos
       SET inmueble_id = v_exp_inm, updated_at = now()
     WHERE id = p_documento_id;
  END IF;

  INSERT INTO public.documento_bloques (
    tenant_id, documento_id, bloque_id, tipo, source, created_by
  ) VALUES (
    v_doc.tenant_id, p_documento_id, p_bloque_id, v_tipo, 'ai', auth.uid()
  );

  PERFORM public.sync_documento_primary_bloque(p_documento_id);

  INSERT INTO public.audit_logs (
    tenant_id, actor_id, action, entity_table, entity_id, after
  ) VALUES (
    v_doc.tenant_id,
    auth.uid(),
    'documento.place',
    'documento_bloques',
    p_documento_id,
    jsonb_build_object('bloque_id', p_bloque_id, 'tipo', v_tipo, 'source', 'ai')
  );
  RETURN true;
EXCEPTION
  WHEN unique_violation THEN
    RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.replace_documento_chunks(
  p_documento_id UUID,
  p_chunks JSONB
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  d RECORD;
  c JSONB;
  v_i INT := 0;
  v_emb FLOAT[];
BEGIN
  SELECT id, tenant_id, cliente_id, deleted_at
    INTO d
    FROM public.documentos
   WHERE id = p_documento_id;
  IF d.id IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF d.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF auth.role() = 'service_role' THEN
    NULL; -- cron / backfill
  ELSIF NOT public.can_access_tenant(d.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  ELSIF d.cliente_id IS NULL OR NOT public.can_access_cliente(d.cliente_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_chunks IS NULL OR jsonb_typeof(p_chunks) <> 'array' THEN
    RAISE EXCEPTION 'bad_chunks';
  END IF;
  IF jsonb_array_length(p_chunks) > 80 THEN
    RAISE EXCEPTION 'too_many_chunks';
  END IF;

  UPDATE public.documento_chunks
     SET deleted_at = now()
   WHERE documento_id = p_documento_id
     AND deleted_at IS NULL;

  FOR c IN SELECT value FROM jsonb_array_elements(p_chunks)
  LOOP
    v_i := v_i + 1;
    SELECT array_agg(x::float ORDER BY ord)
      INTO v_emb
      FROM jsonb_array_elements_text(c->'embedding') WITH ORDINALITY AS t(x, ord);
    IF v_emb IS NULL OR array_length(v_emb, 1) IS DISTINCT FROM 1536 THEN
      RAISE EXCEPTION 'bad_embedding';
    END IF;
    INSERT INTO public.documento_chunks (
      tenant_id, documento_id, cliente_id, chunk_index, content, embedding
    ) VALUES (
      d.tenant_id,
      p_documento_id,
      d.cliente_id,
      coalesce((c->>'chunk_index')::int, v_i - 1),
      left(btrim(coalesce(c->>'content', '')), 4000),
      v_emb::extensions.vector(1536)
    );
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------------
-- Merge / duplicity / podobné papíry
-- ---------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.merge_clientes(
  p_keep_id UUID,
  p_drop_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  k RECORD;
  d RECORD;
  ident RECORD;
BEGIN
  IF p_keep_id = p_drop_id THEN
    RAISE EXCEPTION 'same_cliente' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO k FROM clientes WHERE id = p_keep_id;
  SELECT * INTO d FROM clientes WHERE id = p_drop_id;
  IF k.id IS NULL OR d.id IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF k.tenant_id <> d.tenant_id THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF NOT public.can_access_tenant(k.tenant_id) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF NOT public.can_access_cliente(p_keep_id)
     OR NOT public.can_access_cliente(p_drop_id) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF NOT public.can_soft_delete_expediente(k.tenant_id) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF k.deleted_at IS NOT NULL OR d.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'deleted' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM client_identifiers i
     WHERE i.cliente_id = k.id
       AND i.deleted_at IS NULL
       AND i.kind IN ('nie', 'dni', 'nif')
       AND position('*' IN i.value_normalized) = 0
  ) AND EXISTS (
    SELECT 1 FROM client_identifiers i
     WHERE i.cliente_id = d.id
       AND i.deleted_at IS NULL
       AND i.kind IN ('nie', 'dni', 'nif')
       AND position('*' IN i.value_normalized) = 0
  ) THEN
    RAISE EXCEPTION 'nie_conflict' USING ERRCODE = '23505';
  END IF;

  UPDATE clientes SET
    email = coalesce(nullif(btrim(k.email), ''), nullif(btrim(d.email), '')),
    tel = coalesce(nullif(btrim(k.tel), ''), nullif(btrim(d.tel), '')),
    direccion = coalesce(nullif(btrim(k.direccion), ''), nullif(btrim(d.direccion), '')),
    iban = coalesce(nullif(btrim(k.iban), ''), nullif(btrim(d.iban), '')),
    locale = CASE
      WHEN lower(coalesce(btrim(k.locale), '')) IN ('cs', 'en', 'es', 'de', 'fr')
        THEN k.locale
      ELSE d.locale
    END,
    notas = CASE
      WHEN nullif(btrim(k.notas), '') IS NULL THEN d.notas
      WHEN nullif(btrim(d.notas), '') IS NULL THEN k.notas
      ELSE k.notas || E'\n' || d.notas
    END,
    updated_at = now()
  WHERE id = k.id;

  FOR ident IN
    SELECT * FROM client_identifiers
     WHERE cliente_id = d.id AND deleted_at IS NULL
  LOOP
    IF EXISTS (
      SELECT 1 FROM client_identifiers i
       WHERE i.cliente_id = k.id
         AND i.deleted_at IS NULL
         AND i.value_normalized = ident.value_normalized
         AND i.kind IN ('nie', 'dni', 'nif')
         AND ident.kind IN ('nie', 'dni', 'nif')
    ) THEN
      UPDATE client_identifiers
         SET deleted_at = now()
       WHERE id = ident.id;
    ELSE
      BEGIN
        UPDATE client_identifiers
           SET cliente_id = k.id, updated_at = now()
         WHERE id = ident.id;
      EXCEPTION
        WHEN unique_violation THEN
          UPDATE client_identifiers
             SET deleted_at = now()
           WHERE id = ident.id;
      END;
    END IF;
  END LOOP;

  UPDATE inmuebles SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE expedientes SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE documentos SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE mensajes SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE client_contacts SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE facturas SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE legal_holds SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE posta_messages SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE ai_drafts SET cliente_id = k.id WHERE cliente_id = d.id;
  UPDATE inmueble_titulares SET cliente_id = k.id
   WHERE cliente_id = d.id
     AND NOT EXISTS (
       SELECT 1 FROM inmueble_titulares t
        WHERE t.inmueble_id = inmueble_titulares.inmueble_id
          AND t.cliente_id = k.id
          AND t.deleted_at IS NULL
          AND t.id <> inmueble_titulares.id
     );

  UPDATE clientes SET
    deleted_at = now(),
    updated_at = now()
  WHERE id = d.id;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  ) VALUES (
    k.tenant_id,
    auth.uid(),
    (SELECT s.id FROM support_view_sessions s
      WHERE s.support_user_id = auth.uid()
        AND s.ended_at IS NULL
      ORDER BY s.started_at DESC LIMIT 1),
    'clientes.merge',
    'clientes',
    k.id,
    jsonb_build_object('keep_id', k.id, 'drop_id', d.id)
  );
  RETURN true;
END;
$$;

-- suggest: jen páry, ke kterým má scoped člen přístup (keep i drop).
CREATE OR REPLACE FUNCTION public.suggest_cliente_duplicates(p_tenant_id UUID)
RETURNS TABLE (
  keep_id UUID,
  keep_nombre TEXT,
  drop_id UUID,
  drop_nombre TEXT,
  reason TEXT,
  score INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN QUERY
  SELECT
    x.keep_id,
    x.keep_nombre,
    x.drop_id,
    x.drop_nombre,
    x.reason,
    x.score
  FROM (
    SELECT DISTINCT ON (LEAST(a.id, b.id), GREATEST(a.id, b.id))
      CASE
        WHEN a.has_nie AND NOT b.has_nie THEN a.id
        WHEN b.has_nie AND NOT a.has_nie THEN b.id
        WHEN a.created_at <= b.created_at THEN a.id
        ELSE b.id
      END AS keep_id,
      CASE
        WHEN a.has_nie AND NOT b.has_nie THEN a.nombre
        WHEN b.has_nie AND NOT a.has_nie THEN b.nombre
        WHEN a.created_at <= b.created_at THEN a.nombre
        ELSE b.nombre
      END AS keep_nombre,
      CASE
        WHEN a.has_nie AND NOT b.has_nie THEN b.id
        WHEN b.has_nie AND NOT a.has_nie THEN a.id
        WHEN a.created_at <= b.created_at THEN b.id
        ELSE a.id
      END AS drop_id,
      CASE
        WHEN a.has_nie AND NOT b.has_nie THEN b.nombre
        WHEN b.has_nie AND NOT a.has_nie THEN a.nombre
        WHEN a.created_at <= b.created_at THEN b.nombre
        ELSE a.nombre
      END AS drop_nombre,
      CASE
        WHEN a.email_key IS NOT NULL AND a.email_key = b.email_key THEN 'email'
        WHEN a.tel_key IS NOT NULL AND a.tel_key = b.tel_key THEN 'tel'
        ELSE 'name'
      END AS reason,
      CASE
        WHEN a.email_key IS NOT NULL AND a.email_key = b.email_key THEN 90
        WHEN a.tel_key IS NOT NULL AND a.tel_key = b.tel_key THEN 80
        ELSE 50
      END AS score
    FROM (
      SELECT
        c.id,
        coalesce(
          nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
          c.razon_social,
          c.nombre
        ) AS nombre,
        c.created_at,
        lower(nullif(btrim(c.email), '')) AS email_key,
        nullif(regexp_replace(coalesce(c.tel, ''), '[^0-9]', '', 'g'), '') AS tel_key,
        public.normalize_search_text(
          coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''), c.nombre)
        ) AS name_key,
        EXISTS (
          SELECT 1 FROM client_identifiers i
           WHERE i.cliente_id = c.id
             AND i.deleted_at IS NULL
             AND i.kind IN ('nie', 'dni', 'nif')
             AND position('*' IN i.value_normalized) = 0
        ) AS has_nie,
        (
          SELECT i.value_normalized
            FROM client_identifiers i
           WHERE i.cliente_id = c.id
             AND i.deleted_at IS NULL
             AND i.kind IN ('nie', 'dni', 'nif')
             AND position('*' IN i.value_normalized) = 0
           LIMIT 1
        ) AS nie
      FROM clientes c
      WHERE c.tenant_id = p_tenant_id
        AND c.deleted_at IS NULL
        AND coalesce(c.nombre, '') <> 'ANON'
        AND public.can_access_cliente(c.id)
    ) a
    JOIN (
      SELECT
        c.id,
        coalesce(
          nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
          c.razon_social,
          c.nombre
        ) AS nombre,
        c.created_at,
        lower(nullif(btrim(c.email), '')) AS email_key,
        nullif(regexp_replace(coalesce(c.tel, ''), '[^0-9]', '', 'g'), '') AS tel_key,
        public.normalize_search_text(
          coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''), c.nombre)
        ) AS name_key,
        EXISTS (
          SELECT 1 FROM client_identifiers i
           WHERE i.cliente_id = c.id
             AND i.deleted_at IS NULL
             AND i.kind IN ('nie', 'dni', 'nif')
             AND position('*' IN i.value_normalized) = 0
        ) AS has_nie,
        (
          SELECT i.value_normalized
            FROM client_identifiers i
           WHERE i.cliente_id = c.id
             AND i.deleted_at IS NULL
             AND i.kind IN ('nie', 'dni', 'nif')
             AND position('*' IN i.value_normalized) = 0
           LIMIT 1
        ) AS nie
      FROM clientes c
      WHERE c.tenant_id = p_tenant_id
        AND c.deleted_at IS NULL
        AND coalesce(c.nombre, '') <> 'ANON'
        AND public.can_access_cliente(c.id)
    ) b ON a.id < b.id
    WHERE NOT (a.has_nie AND b.has_nie AND a.nie IS DISTINCT FROM b.nie)
      AND (
        (a.email_key IS NOT NULL AND a.email_key = b.email_key)
        OR (
          a.tel_key IS NOT NULL
          AND a.tel_key = b.tel_key
          AND length(a.tel_key) >= 8
        )
        OR (
          a.name_key <> ''
          AND a.name_key = b.name_key
          AND length(a.name_key) >= 6
          AND (NOT a.has_nie OR NOT b.has_nie)
        )
      )
    ORDER BY LEAST(a.id, b.id), GREATEST(a.id, b.id), 6 DESC
  ) x
  ORDER BY x.score DESC, x.keep_nombre
  LIMIT 80;
END;
$$;

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
          AND public.can_access_cliente(d.cliente_id)
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

-- M3: orphan DELETE ve Storage jen v rozsahu klienta.
DROP POLICY IF EXISTS documentos_storage_delete ON storage.objects;
CREATE POLICY documentos_storage_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'documentos'
    AND public.can_access_tenant(public.storage_tenant_id(name))
    AND public.storage_cliente_id(name) IS NOT NULL
    AND public.can_access_cliente(public.storage_cliente_id(name))
    AND NOT EXISTS (
      SELECT 1 FROM public.documentos d
      WHERE d.storage_path = name
        AND d.storage_purged_at IS NULL
    )
  );

-- M4: hard-delete zakázán na staff scope + album junction.
DROP TRIGGER IF EXISTS trg_staff_scopes_no_hard_delete ON public.staff_scopes;
CREATE TRIGGER trg_staff_scopes_no_hard_delete
  BEFORE DELETE ON public.staff_scopes
  FOR EACH ROW EXECUTE FUNCTION public.forbid_hard_delete();

DROP TRIGGER IF EXISTS trg_staff_cliente_access_no_hard_delete
  ON public.staff_cliente_access;
CREATE TRIGGER trg_staff_cliente_access_no_hard_delete
  BEFORE DELETE ON public.staff_cliente_access
  FOR EACH ROW EXECUTE FUNCTION public.forbid_hard_delete();

DROP TRIGGER IF EXISTS trg_documento_bloques_no_hard_delete
  ON public.documento_bloques;
CREATE TRIGGER trg_documento_bloques_no_hard_delete
  BEFORE DELETE ON public.documento_bloques
  FOR EACH ROW EXECUTE FUNCTION public.forbid_hard_delete();

DROP POLICY IF EXISTS staff_scopes_modify ON public.staff_scopes;
CREATE POLICY staff_scopes_insert ON public.staff_scopes
  FOR INSERT TO authenticated
  WITH CHECK (public.is_tenant_owner(tenant_id));
CREATE POLICY staff_scopes_update ON public.staff_scopes
  FOR UPDATE TO authenticated
  USING (public.is_tenant_owner(tenant_id))
  WITH CHECK (public.is_tenant_owner(tenant_id));

DROP POLICY IF EXISTS staff_cliente_access_modify ON public.staff_cliente_access;
CREATE POLICY staff_cliente_access_insert ON public.staff_cliente_access
  FOR INSERT TO authenticated
  WITH CHECK (public.is_tenant_owner(tenant_id));
CREATE POLICY staff_cliente_access_update ON public.staff_cliente_access
  FOR UPDATE TO authenticated
  USING (public.is_tenant_owner(tenant_id))
  WITH CHECK (public.is_tenant_owner(tenant_id));

COMMENT ON FUNCTION public.assign_posta_message(UUID, UUID) IS
  'Přiřadí poštu kartě; vyžaduje can_access_cliente.';
COMMENT ON FUNCTION public.merge_clientes(UUID, UUID) IS
  'Soft-merge; keep i drop musí projít can_access_cliente. AI neslučuje.';
COMMENT ON FUNCTION public.similar_placed_papers(UUID, JSONB, UUID, INT) IS
  'Vzory jen z karet v rozsahu volajícího (can_access_cliente).';
COMMENT ON FUNCTION public.place_documento_ai(UUID, UUID, TEXT) IS
  'Legacy AI place; extract ji nevolá (H3). Scope: can_access_cliente.';
