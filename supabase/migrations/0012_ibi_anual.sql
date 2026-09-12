-- IBI / SUMA roční plazo: měsíc+den jen z tenant_settings. Žádné 1. 11. v kódu.

ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS ibi_due_month INT
    CHECK (ibi_due_month IS NULL OR ibi_due_month BETWEEN 1 AND 12),
  ADD COLUMN IF NOT EXISTS ibi_due_day INT
    CHECK (ibi_due_day IS NULL OR ibi_due_day BETWEEN 1 AND 31);

COMMENT ON COLUMN tenant_settings.ibi_due_month IS
  'Měsíc splatnosti IBI/SUMA. NULL = kancelář ještě nenastavila, plazo se nederivuje.';
COMMENT ON COLUMN tenant_settings.ibi_due_day IS
  'Den splatnosti IBI/SUMA. NULL = kancelář ještě nenastavila.';

CREATE OR REPLACE FUNCTION public.recompute_bloque_plazos(p_bloque_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b RECORD;
  v_exp UUID;
  v_inmueble UUID;
  v_fecha DATE;
  v_days INT;
  v_due DATE;
  v_expiry DATE;
  v_estado TEXT;
  v_year INT;
  v_month INT;
  v_day INT;
BEGIN
  SELECT * INTO b FROM bloques WHERE id = p_bloque_id AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  v_exp := b.expediente_id;

  SELECT e.inmueble_id INTO v_inmueble
    FROM expedientes e
   WHERE e.id = v_exp;

  IF b.status = 'off' THEN
    UPDATE plazos
       SET completed_at = coalesce(completed_at, now())
     WHERE bloque_id = b.id
       AND source = 'derived'
       AND deleted_at IS NULL
       AND completed_at IS NULL;
    RETURN;
  END IF;

  IF b.status = 'done' THEN
    UPDATE plazos
       SET completed_at = coalesce(completed_at, now())
     WHERE bloque_id = b.id
       AND source = 'derived'
       AND deleted_at IS NULL
       AND completed_at IS NULL;
  END IF;

  IF b.template_key = 'plusvalia' THEN
    SELECT ts.plusvalia_days INTO v_days
      FROM tenant_settings ts
     WHERE ts.tenant_id = b.tenant_id;
    v_days := coalesce(v_days, 30);
    SELECT i.escritura_fecha INTO v_fecha
      FROM inmuebles i
     WHERE i.id = v_inmueble;
    v_fecha := coalesce(
      v_fecha,
      public.try_parse_date(b.fields->>'fields.deadline'),
      public.try_parse_date(b.fields->>'fields.date')
    );
    IF v_fecha IS NOT NULL THEN
      v_due := v_fecha + v_days;
    END IF;
    PERFORM public.sync_derived_plazo(
      b.tenant_id, b.id, v_exp, 'plusvalia_plazo', v_due
    );
  ELSIF b.template_key IN ('seguro', 'alarma', 'poder') THEN
    v_expiry := coalesce(
      public.try_parse_date(b.fields->>'fields.expiry'),
      public.try_parse_date(b.fields->>'fecha_vencimiento'),
      public.try_parse_date(b.fields->>'fecha_caducidad')
    );
    PERFORM public.sync_derived_plazo(
      b.tenant_id, b.id, v_exp,
      CASE b.template_key
        WHEN 'seguro' THEN 'seguro_renovacion'
        WHEN 'alarma' THEN 'alarma_renovacion'
        ELSE 'poder_caducidad'
      END,
      v_expiry
    );
  ELSIF b.template_key IN ('modelo_210', 'renta') THEN
    v_due := public.try_parse_date(b.fields->>'fields.deadline');
    PERFORM public.sync_derived_plazo(
      b.tenant_id, b.id, v_exp,
      CASE b.template_key WHEN 'renta' THEN 'renta' ELSE 'modelo_210' END,
      v_due
    );
  ELSIF b.template_key = 'nie_tramite' THEN
    v_estado := coalesce(b.fields->>'fields.nieStatus', b.fields->>'estado_tramite');
    v_fecha := public.try_parse_date(b.fields->>'fields.appointment');
    IF v_estado = 'cita' THEN
      PERFORM public.sync_derived_plazo(
        b.tenant_id, b.id, v_exp, 'cita_nie', v_fecha
      );
    ELSE
      PERFORM public.sync_derived_plazo(
        b.tenant_id, b.id, v_exp, 'cita_nie', NULL
      );
    END IF;
    v_expiry := public.try_parse_date(b.fields->>'fields.expiry');
    PERFORM public.sync_derived_plazo(
      b.tenant_id, b.id, v_exp, 'nie_caducidad', v_expiry
    );
  ELSIF b.template_key = 'suma' AND b.status <> 'done' THEN
    SELECT ts.ibi_due_month, ts.ibi_due_day
      INTO v_month, v_day
      FROM tenant_settings ts
     WHERE ts.tenant_id = b.tenant_id;
    IF v_month IS NULL OR v_day IS NULL THEN
      PERFORM public.sync_derived_plazo(
        b.tenant_id, b.id, v_exp, 'ibi_anual', NULL
      );
    ELSE
      BEGIN
        v_year := substring(
          coalesce(b.fields->>'fields.period', '') FROM '\d{4}'
        )::int;
      EXCEPTION
        WHEN OTHERS THEN
          v_year := NULL;
      END;
      IF v_year IS NULL THEN
        v_year := extract(year FROM timezone('Europe/Madrid', now()))::int;
      END IF;
      BEGIN
        v_due := make_date(v_year, v_month, v_day);
      EXCEPTION
        WHEN datetime_field_overflow THEN
          v_due := (
            make_date(v_year, v_month, 1) + INTERVAL '1 month - 1 day'
          )::date;
      END;
      PERFORM public.sync_derived_plazo(
        b.tenant_id, b.id, v_exp, 'ibi_anual', v_due
      );
    END IF;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_recompute_tenant_ibi()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id
      FROM bloques
     WHERE tenant_id = NEW.tenant_id
       AND template_key = 'suma'
       AND deleted_at IS NULL
  LOOP
    PERFORM public.recompute_bloque_plazos(r.id);
  END LOOP;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recompute_tenant_ibi ON tenant_settings;
CREATE TRIGGER trg_recompute_tenant_ibi
  AFTER INSERT OR UPDATE OF ibi_due_month, ibi_due_day, ibi_warn_days
  ON tenant_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_recompute_tenant_ibi();

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
    LEFT JOIN tenant_settings ts ON ts.tenant_id = p.tenant_id
    WHERE p.deleted_at IS NULL
      AND p.completed_at IS NULL
      AND public.can_access_tenant(p.tenant_id)
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
