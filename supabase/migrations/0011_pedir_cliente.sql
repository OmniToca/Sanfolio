-- Pedir al cliente: last_requested_at na bloku. Draft chystá gestor, ne cron.

ALTER TABLE bloques
  ADD COLUMN IF NOT EXISTS last_requested_at TIMESTAMPTZ;

COMMENT ON COLUMN bloques.last_requested_at IS
  'Poslední výzva klientovi. Další návrh až po tenant_settings.nudge_interval_days.';

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
  has_tel BOOLEAN
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
      (nullif(btrim(c.tel), '') IS NOT NULL) AS has_tel
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
      b.template_key AS bloque_key,
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
      (nullif(btrim(c.tel), '') IS NOT NULL) AS has_tel
    FROM plazos p
    JOIN bloques b ON b.id = p.bloque_id AND b.deleted_at IS NULL AND b.status <> 'off'
    JOIN expedientes e ON e.id = coalesce(p.expediente_id, b.expediente_id) AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
    WHERE p.deleted_at IS NULL
      AND p.completed_at IS NULL
      AND public.can_access_tenant(p.tenant_id)
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
      (nullif(btrim(c.tel), '') IS NOT NULL) AS has_tel
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
