-- Ruční plazo (source=manual) a odklad inboxu. Derived se nepřepisují.

ALTER TABLE plazos
  ADD COLUMN IF NOT EXISTS note TEXT;

COMMENT ON COLUMN plazos.note IS
  'Popisek ručního termínu. Odvozené plazos nechávají NULL.';

CREATE OR REPLACE FUNCTION public.add_manual_plazo(
  p_expediente_id UUID,
  p_due_on DATE,
  p_note TEXT,
  p_bloque_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exp RECORD;
  v_note TEXT := nullif(btrim(p_note), '');
  v_id UUID;
  v_bloque UUID;
BEGIN
  IF p_due_on IS NULL THEN
    RAISE EXCEPTION 'due_required';
  END IF;
  IF v_note IS NULL THEN
    RAISE EXCEPTION 'note_required';
  END IF;

  SELECT e.id, e.tenant_id, e.deleted_at
    INTO v_exp
  FROM expedientes e
  WHERE e.id = p_expediente_id;
  IF v_exp.id IS NULL OR v_exp.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_exp.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF p_bloque_id IS NOT NULL THEN
    SELECT b.id INTO v_bloque
      FROM bloques b
     WHERE b.id = p_bloque_id
       AND b.expediente_id = v_exp.id
       AND b.deleted_at IS NULL;
    IF v_bloque IS NULL THEN
      RAISE EXCEPTION 'bloque_mismatch';
    END IF;
  END IF;

  INSERT INTO plazos (
    tenant_id, bloque_id, expediente_id, kind, due_on, source, note
  ) VALUES (
    v_exp.tenant_id, v_bloque, v_exp.id, 'manual', p_due_on, 'manual', v_note
  )
  RETURNING id INTO v_id;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  ) VALUES (
    v_exp.tenant_id, auth.uid(),
    (SELECT s.id FROM support_view_sessions s
     WHERE s.support_user_id = auth.uid() AND s.ended_at IS NULL AND s.expires_at > now()
     ORDER BY s.started_at DESC LIMIT 1),
    'plazo.manual', 'plazos', v_id,
    jsonb_build_object('due_on', p_due_on, 'note', v_note)
  );

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.snooze_plazo(
  p_plazo_id UUID,
  p_until DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_p RECORD;
  v_today DATE := (timezone('Europe/Madrid', now()))::date;
BEGIN
  SELECT * INTO v_p
    FROM plazos
   WHERE id = p_plazo_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_p.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_until IS NULL OR p_until <= v_today THEN
    RAISE EXCEPTION 'snooze_future';
  END IF;

  -- Jen odklad. due_on ani source (derived) se nemění.
  UPDATE plazos
     SET snooze_until = p_until,
         updated_at = now()
   WHERE id = v_p.id;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  ) VALUES (
    v_p.tenant_id, auth.uid(),
    (SELECT s.id FROM support_view_sessions s
     WHERE s.support_user_id = auth.uid() AND s.ended_at IS NULL AND s.expires_at > now()
     ORDER BY s.started_at DESC LIMIT 1),
    'plazo.snooze', 'plazos', v_p.id,
    jsonb_build_object('snooze_until', p_until, 'due_on', v_p.due_on)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_manual_plazo(UUID, DATE, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.snooze_plazo(UUID, DATE) TO authenticated;

COMMENT ON FUNCTION public.add_manual_plazo(UUID, DATE, TEXT, UUID) IS
  'Ruční termín. sync_derived_plazo sahá jen na source=derived.';
COMMENT ON FUNCTION public.snooze_plazo(UUID, DATE) IS
  'Schová řádek inboxu do data. Nic se nemaže, cron neodesílá.';

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
      (nullif(btrim(c.email), '') IS NOT NULL) AS has_email,
      (nullif(btrim(c.tel), '') IS NOT NULL) AS has_tel,
      NULL::uuid AS plazo_id,
      NULL::text AS plazo_source,
      NULL::text AS plazo_note
    FROM bloques b
    JOIN expedientes e ON e.id = b.expediente_id AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
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
      (nullif(btrim(c.email), '') IS NOT NULL) AS has_email,
      (nullif(btrim(c.tel), '') IS NOT NULL) AS has_tel,
      p.id AS plazo_id,
      p.source::text AS plazo_source,
      p.note AS plazo_note
    FROM plazos p
    LEFT JOIN bloques b
      ON b.id = p.bloque_id AND b.deleted_at IS NULL
    JOIN expedientes e
      ON e.id = coalesce(p.expediente_id, b.expediente_id) AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
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
      (nullif(btrim(c.email), '') IS NOT NULL) AS has_email,
      (nullif(btrim(c.tel), '') IS NOT NULL) AS has_tel,
      NULL::uuid AS plazo_id,
      NULL::text AS plazo_source,
      NULL::text AS plazo_note
    FROM bloques b
    JOIN expedientes e ON e.id = b.expediente_id AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
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
  )
  SELECT * FROM (
    SELECT * FROM holes
    UNION ALL
    SELECT * FROM dates
    UNION ALL
    SELECT * FROM provision
  ) feed
  ORDER BY
    CASE feed.item_kind
      WHEN 'overdue' THEN 0
      WHEN 'due_today' THEN 1
      WHEN 'due_soon' THEN 2
      WHEN 'missing_document' THEN 3
      WHEN 'missing_data' THEN 4
      WHEN 'provision_alert' THEN 5
      ELSE 6
    END,
    feed.due_on NULLS LAST,
    feed.cliente_nombre;
$$;

GRANT EXECUTE ON FUNCTION public.inbox_feed() TO authenticated;
