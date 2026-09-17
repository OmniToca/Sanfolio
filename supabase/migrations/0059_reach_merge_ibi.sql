-- Kanál z druhého kontaktu, sloučení duplicit, kampaň IBI. AI neukládá.

CREATE OR REPLACE FUNCTION public.cliente_channel_flags(p_cliente_id UUID)
RETURNS TABLE (has_email BOOLEAN, has_tel BOOLEAN)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    (
      EXISTS (
        SELECT 1 FROM clientes x
         WHERE x.id = p_cliente_id
           AND nullif(btrim(x.email), '') IS NOT NULL
      )
      OR EXISTS (
        SELECT 1 FROM client_contacts cc
         WHERE cc.cliente_id = p_cliente_id
           AND cc.deleted_at IS NULL
           AND nullif(btrim(cc.email), '') IS NOT NULL
      )
    ),
    (
      EXISTS (
        SELECT 1 FROM clientes x
         WHERE x.id = p_cliente_id
           AND nullif(btrim(x.tel), '') IS NOT NULL
      )
      OR EXISTS (
        SELECT 1 FROM client_contacts cc
         WHERE cc.cliente_id = p_cliente_id
           AND cc.deleted_at IS NULL
           AND nullif(btrim(cc.tel), '') IS NOT NULL
      )
    );
$$;

GRANT EXECUTE ON FUNCTION public.cliente_channel_flags(UUID) TO authenticated;

COMMENT ON FUNCTION public.cliente_channel_flags(UUID) IS
  'E-mail/telefon karty nebo živého druhého kontaktu. Pedir sem sahá.';

DROP FUNCTION IF EXISTS public.inbox_feed();

CREATE FUNCTION public.inbox_feed()
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  bloque_key TEXT,
  item_kind TEXT,
  due_on DATE,
  expediente_id UUID,
  expediente_tipo TEXT,
  bloque_id UUID,
  last_requested_at TIMESTAMPTZ,
  has_email BOOLEAN,
  has_tel BOOLEAN,
  plazo_id UUID,
  plazo_source TEXT,
  plazo_note TEXT
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH today AS (
    SELECT (timezone('Europe/Madrid', now()))::date AS d
  ),
  holes AS (
    SELECT
      c.id AS cliente_id,
      coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''), c.razon_social, c.nombre) AS cliente_nombre,
      b.template_key AS bloque_key,
      CASE b.status
        WHEN 'missing_document' THEN 'missing_document'
        ELSE 'missing_data'
      END AS item_kind,
      NULL::date AS due_on,
      e.id AS expediente_id,
      e.tipo::text AS expediente_tipo,
      b.id AS bloque_id,
      b.last_requested_at,
      ch.has_email,
      ch.has_tel,
      NULL::uuid AS plazo_id,
      NULL::text AS plazo_source,
      NULL::text AS plazo_note
    FROM bloques b
    JOIN expedientes e ON e.id = b.expediente_id AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
    CROSS JOIN LATERAL public.cliente_channel_flags(c.id) ch
    WHERE b.deleted_at IS NULL
      AND b.status IN ('missing_data', 'missing_document')
      AND public.can_access_tenant(b.tenant_id)
  ),
  dates AS (
    SELECT
      c.id AS cliente_id,
      coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''), c.razon_social, c.nombre) AS cliente_nombre,
      coalesce(b.template_key, 'manual') AS bloque_key,
      CASE
        WHEN p.due_on < (SELECT d FROM today) THEN 'overdue'
        WHEN p.due_on = (SELECT d FROM today) THEN 'due_today'
        ELSE 'due_soon'
      END AS item_kind,
      p.due_on,
      e.id AS expediente_id,
      e.tipo::text AS expediente_tipo,
      b.id AS bloque_id,
      b.last_requested_at,
      ch.has_email,
      ch.has_tel,
      p.id AS plazo_id,
      p.source::text AS plazo_source,
      p.note AS plazo_note
    FROM plazos p
    LEFT JOIN bloques b
      ON b.id = p.bloque_id AND b.deleted_at IS NULL
    JOIN expedientes e
      ON e.id = coalesce(p.expediente_id, b.expediente_id) AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
    CROSS JOIN LATERAL public.cliente_channel_flags(c.id) ch
    LEFT JOIN tenant_settings ts ON ts.tenant_id = p.tenant_id
    WHERE p.deleted_at IS NULL
      AND p.completed_at IS NULL
      AND public.can_access_tenant(p.tenant_id)
      AND (p.snooze_until IS NULL OR p.snooze_until <= (SELECT d FROM today))
      AND (
        p.source = 'manual'
        OR (b.id IS NOT NULL AND b.status <> 'off')
      )
      AND (
        p.kind IS DISTINCT FROM 'ibi_anual'
        OR p.due_on <= (SELECT d FROM today)
          + (coalesce(ts.ibi_warn_days, 60) * INTERVAL '1 day')
      )
  ),
  provision AS (
    SELECT
      c.id AS cliente_id,
      coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''), c.razon_social, c.nombre) AS cliente_nombre,
      b.template_key AS bloque_key,
      'provision_alert'::text AS item_kind,
      NULL::date AS due_on,
      e.id AS expediente_id,
      e.tipo::text AS expediente_tipo,
      b.id AS bloque_id,
      b.last_requested_at,
      ch.has_email,
      ch.has_tel,
      NULL::uuid AS plazo_id,
      NULL::text AS plazo_source,
      NULL::text AS plazo_note
    FROM bloques b
    JOIN expedientes e ON e.id = b.expediente_id AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
    CROSS JOIN LATERAL public.cliente_channel_flags(c.id) ch
    WHERE b.deleted_at IS NULL
      AND b.template_key = 'provision_factura'
      AND b.status <> 'off'
      AND public.can_access_tenant(b.tenant_id)
      AND (
        CASE WHEN b.fields->>'fields.received' ~ '^-?[0-9]+$'
             THEN (b.fields->>'fields.received')::int ELSE 0 END
      ) > 0
      AND (
        (
          CASE WHEN b.fields->>'fields.invoiced' ~ '^-?[0-9]+$'
               THEN (b.fields->>'fields.invoiced')::int ELSE 0 END
        ) = 0
        OR (
          CASE WHEN b.fields->>'fields.remaining' ~ '^-?[0-9]+$'
               THEN (b.fields->>'fields.remaining')::int
               ELSE
                 CASE WHEN b.fields->>'fields.received' ~ '^-?[0-9]+$'
                      THEN (b.fields->>'fields.received')::int ELSE 0 END
                 -
                 CASE WHEN b.fields->>'fields.invoiced' ~ '^-?[0-9]+$'
                      THEN (b.fields->>'fields.invoiced')::int ELSE 0 END
          END
        ) <= 0
      )
  ),
  stale AS (
    SELECT
      c.id AS cliente_id,
      coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''), c.razon_social, c.nombre) AS cliente_nombre,
      'stale_expediente'::text AS bloque_key,
      'stale_expediente'::text AS item_kind,
      NULL::date AS due_on,
      e.id AS expediente_id,
      e.tipo::text AS expediente_tipo,
      NULL::uuid AS bloque_id,
      NULL::timestamptz AS last_requested_at,
      ch.has_email,
      ch.has_tel,
      NULL::uuid AS plazo_id,
      NULL::text AS plazo_source,
      NULL::text AS plazo_note
    FROM expedientes e
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
    CROSS JOIN LATERAL public.cliente_channel_flags(c.id) ch
    LEFT JOIN tenant_settings ts ON ts.tenant_id = e.tenant_id
    WHERE e.deleted_at IS NULL
      AND e.estado = 'en_curso'
      AND public.can_access_tenant(e.tenant_id)
      AND coalesce(ts.stale_expediente_days, 14) > 0
      AND (e.updated_at AT TIME ZONE 'Europe/Madrid')::date
          <= (SELECT d FROM today) - coalesce(ts.stale_expediente_days, 14)
  )
  SELECT * FROM (
    SELECT * FROM holes
    UNION ALL
    SELECT * FROM dates
    UNION ALL
    SELECT * FROM provision
    UNION ALL
    SELECT * FROM stale
  ) feed
  ORDER BY
    CASE feed.item_kind
      WHEN 'overdue' THEN 0
      WHEN 'due_today' THEN 1
      WHEN 'due_soon' THEN 2
      WHEN 'missing_document' THEN 3
      WHEN 'missing_data' THEN 4
      WHEN 'provision_alert' THEN 5
      WHEN 'stale_expediente' THEN 6
      ELSE 7
    END,
    feed.due_on NULLS LAST,
    feed.cliente_nombre;
$$;

GRANT EXECUTE ON FUNCTION public.inbox_feed() TO authenticated;

CREATE OR REPLACE FUNCTION public.reach_gaps(p_tenant_id UUID)
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  email TEXT,
  tel TEXT,
  locale TEXT,
  contact_nombre TEXT,
  contact_email TEXT,
  contact_tel TEXT,
  contact_locale TEXT,
  sin_canal BOOLEAN,
  contact_only BOOLEAN,
  no_locale BOOLEAN,
  can_copy BOOLEAN
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
    c.id,
    coalesce(
      nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
      c.razon_social,
      c.nombre
    ),
    nullif(btrim(c.email), ''),
    nullif(btrim(c.tel), ''),
    nullif(btrim(c.locale), ''),
    cc.nombre,
    cc.email,
    cc.tel,
    cc.locale,
    g.sin_canal,
    g.contact_only,
    g.no_locale,
    g.can_copy
  FROM clientes c
  LEFT JOIN LATERAL (
    SELECT
      nullif(btrim(x.nombre), '') AS nombre,
      nullif(btrim(x.email), '') AS email,
      nullif(btrim(x.tel), '') AS tel,
      lower(nullif(btrim(x.locale), '')) AS locale
    FROM client_contacts x
    WHERE x.cliente_id = c.id
      AND x.deleted_at IS NULL
    ORDER BY
      (nullif(btrim(x.email), '') IS NOT NULL) DESC,
      (nullif(btrim(x.tel), '') IS NOT NULL) DESC,
      x.created_at
    LIMIT 1
  ) cc ON TRUE
  CROSS JOIN LATERAL (
    SELECT
      (
        nullif(btrim(c.email), '') IS NULL
        AND nullif(btrim(c.tel), '') IS NULL
        AND cc.email IS NULL
        AND cc.tel IS NULL
      ) AS sin_canal,
      (
        nullif(btrim(c.email), '') IS NULL
        AND nullif(btrim(c.tel), '') IS NULL
        AND (cc.email IS NOT NULL OR cc.tel IS NOT NULL)
      ) AS contact_only,
      (
        coalesce(lower(btrim(c.locale)), '') NOT IN ('cs', 'en', 'es', 'de', 'fr')
      ) AS no_locale,
      (
        (nullif(btrim(c.email), '') IS NULL AND cc.email IS NOT NULL)
        OR (nullif(btrim(c.tel), '') IS NULL AND cc.tel IS NOT NULL)
        OR (
          coalesce(lower(btrim(c.locale)), '') NOT IN ('cs', 'en', 'es', 'de', 'fr')
          AND cc.locale IN ('cs', 'en', 'es', 'de', 'fr')
        )
      ) AS can_copy
  ) g
  WHERE c.tenant_id = p_tenant_id
    AND c.deleted_at IS NULL
    AND c.status = 'activo'
    AND coalesce(c.nombre, '') <> 'ANON'
    AND (g.sin_canal OR g.contact_only OR g.no_locale OR g.can_copy)
  ORDER BY g.sin_canal DESC, g.contact_only DESC, c.nombre;
END;
$$;

CREATE OR REPLACE FUNCTION public.reach_gaps_count(p_tenant_id UUID)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INT;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT COUNT(*)::INT INTO v_n
    FROM public.reach_gaps(p_tenant_id);
  RETURN COALESCE(v_n, 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.copy_channel_from_contact(p_cliente_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  c RECORD;
  cc RECORD;
  v_email TEXT;
  v_tel TEXT;
  v_locale TEXT;
  v_copied JSONB := jsonb_build_object('email', false, 'tel', false, 'locale', false);
BEGIN
  SELECT * INTO c FROM clientes WHERE id = p_cliente_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found' USING ERRCODE = '22023';
  END IF;
  IF NOT public.can_access_tenant(c.tenant_id) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT
    nullif(btrim(x.email), '') AS email,
    nullif(btrim(x.tel), '') AS tel,
    lower(nullif(btrim(x.locale), '')) AS locale
  INTO cc
  FROM client_contacts x
  WHERE x.cliente_id = c.id
    AND x.deleted_at IS NULL
  ORDER BY
    (nullif(btrim(x.email), '') IS NOT NULL) DESC,
    (nullif(btrim(x.tel), '') IS NOT NULL) DESC,
    x.created_at
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN v_copied;
  END IF;

  v_email := nullif(btrim(c.email), '');
  v_tel := nullif(btrim(c.tel), '');
  v_locale := lower(nullif(btrim(c.locale), ''));

  IF v_email IS NULL AND cc.email IS NOT NULL THEN
    v_email := cc.email;
    v_copied := v_copied || jsonb_build_object('email', true);
  END IF;
  IF v_tel IS NULL AND cc.tel IS NOT NULL THEN
    v_tel := cc.tel;
    v_copied := v_copied || jsonb_build_object('tel', true);
  END IF;
  IF coalesce(v_locale, '') NOT IN ('cs', 'en', 'es', 'de', 'fr')
     AND cc.locale IN ('cs', 'en', 'es', 'de', 'fr') THEN
    v_locale := cc.locale;
    v_copied := v_copied || jsonb_build_object('locale', true);
  END IF;

  UPDATE clientes SET
    email = v_email,
    tel = v_tel,
    locale = coalesce(v_locale, locale),
    updated_at = now()
  WHERE id = c.id;

  RETURN v_copied;
END;
$$;

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

CREATE OR REPLACE FUNCTION public.season_ibi(p_tenant_id UUID)
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  expediente_id UUID,
  bloque_id UUID,
  periodo TEXT,
  due_on DATE,
  bloque_status TEXT,
  missing_docs TEXT[]
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := (timezone('Europe/Madrid', now()))::date;
  v_warn INT := 60;
  v_month INT;
  v_day INT;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT
    ts.ibi_due_month,
    ts.ibi_due_day,
    coalesce(ts.ibi_warn_days, 60)
  INTO v_month, v_day, v_warn
  FROM tenant_settings ts
  WHERE ts.tenant_id = p_tenant_id
    AND ts.deleted_at IS NULL;
  IF v_month IS NULL OR v_day IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    c.id,
    coalesce(
      nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
      c.razon_social,
      c.nombre
    ),
    e.id,
    b.id,
    nullif(btrim(coalesce(b.fields->>'fields.period', '')), ''),
    p.due_on,
    b.status::TEXT,
    (
      SELECT coalesce(array_agg(req.tipo ORDER BY req.tipo), '{}')
      FROM unnest(coalesce(t.required_doc_types, '{}'::TEXT[])) AS req(tipo)
      WHERE NOT EXISTS (
        SELECT 1 FROM documentos d
         WHERE d.bloque_id = b.id
           AND d.deleted_at IS NULL
           AND d.tipo = req.tipo
      )
    ) AS missing_docs
  FROM bloques b
  JOIN expedientes e
    ON e.id = b.expediente_id AND e.deleted_at IS NULL
  JOIN clientes c
    ON c.id = e.cliente_id AND c.deleted_at IS NULL
  LEFT JOIN bloque_templates t ON t.key = b.template_key
  LEFT JOIN LATERAL (
    SELECT pz.due_on
      FROM plazos pz
     WHERE pz.bloque_id = b.id
       AND pz.kind = 'ibi_anual'
       AND pz.deleted_at IS NULL
       AND pz.completed_at IS NULL
     ORDER BY pz.due_on
     LIMIT 1
  ) p ON TRUE
  WHERE b.tenant_id = p_tenant_id
    AND b.deleted_at IS NULL
    AND b.template_key = 'suma'
    AND b.status NOT IN ('off', 'done')
    AND e.estado NOT IN ('hecho', 'archivado')
    AND (
      EXISTS (
        SELECT 1
          FROM unnest(coalesce(t.required_doc_types, '{}'::TEXT[])) AS req(tipo)
         WHERE NOT EXISTS (
           SELECT 1 FROM documentos d
            WHERE d.bloque_id = b.id
              AND d.deleted_at IS NULL
              AND d.tipo = req.tipo
         )
      )
      OR (
        p.due_on IS NOT NULL
        AND p.due_on <= v_today + (v_warn * INTERVAL '1 day')
      )
    )
  ORDER BY
    (p.due_on IS NULL) ASC,
    p.due_on ASC NULLS LAST,
    c.nombre;
END;
$$;

CREATE OR REPLACE FUNCTION public.season_ibi_count(p_tenant_id UUID)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INT;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT COUNT(*)::INT INTO v_n
    FROM public.season_ibi(p_tenant_id);
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reach_gaps(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reach_gaps_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.copy_channel_from_contact(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suggest_cliente_duplicates(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.merge_clientes(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.season_ibi(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.season_ibi_count(UUID) TO authenticated;

COMMENT ON FUNCTION public.reach_gaps(UUID) IS
  'Karty bez kanálu / s kanálem jen u kontaktu / bez locale. AI neodesílá.';
COMMENT ON FUNCTION public.merge_clientes(UUID, UUID) IS
  'Soft-merge duplicit. Drop se schová, NIE konflikt odmítne. AI neslučuje.';
COMMENT ON FUNCTION public.season_ibi(UUID) IS
  'IBI/SUMA v okně warn_days nebo bez recibo. Termín z nastavení kanceláře.';
