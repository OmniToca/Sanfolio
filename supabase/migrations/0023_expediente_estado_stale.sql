-- Stavy spisu + inbox stale_expediente. Dny jen z tenant_settings (0 = vypnuto).

ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS stale_expediente_days INT NOT NULL DEFAULT 14;

COMMENT ON COLUMN tenant_settings.stale_expediente_days IS
  'en_curso bez pohybu N dní = inbox stale. 0 = vypnuto. Není to hardcoded 14 v UI.';

CREATE OR REPLACE FUNCTION public.set_expediente_estado(
  p_expediente_id UUID,
  p_estado TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_e RECORD;
  v_estado expediente_estado;
BEGIN
  BEGIN
    v_estado := p_estado::expediente_estado;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE EXCEPTION 'bad_estado';
  END;

  SELECT * INTO v_e
    FROM expedientes
   WHERE id = p_expediente_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_e.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE expedientes
     SET estado = v_estado,
         updated_at = now()
   WHERE id = v_e.id;

  INSERT INTO audit_logs (
    tenant_id, actor_id, impersonation_session_id,
    action, entity_table, entity_id, after
  ) VALUES (
    v_e.tenant_id, auth.uid(),
    (SELECT s.id FROM support_view_sessions s
     WHERE s.support_user_id = auth.uid() AND s.ended_at IS NULL AND s.expires_at > now()
     ORDER BY s.started_at DESC LIMIT 1),
    'expediente.estado', 'expedientes', v_e.id,
    jsonb_build_object('from', v_e.estado, 'to', v_estado)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_expediente_estado(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.set_expediente_estado(UUID, TEXT) IS
  'Gestor posune spis abierto…archivado. Soft, append-only audit.';

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
      (nullif(btrim(c.email), '') IS NOT NULL) AS has_email,
      (nullif(btrim(c.tel), '') IS NOT NULL) AS has_tel,
      NULL::uuid AS plazo_id,
      NULL::text AS plazo_source,
      NULL::text AS plazo_note
    FROM expedientes e
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
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
