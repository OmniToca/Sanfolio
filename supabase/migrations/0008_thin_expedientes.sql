-- Tenké spisy 210 / renta / NIE: plazo z pole na bloku, inbox zná expediente.

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
    -- Datum jen z pole kanceláře, žádný zadrátovaný 30.6.
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
  END IF;
END;
$$;

DROP FUNCTION IF EXISTS public.inbox_feed();

CREATE FUNCTION public.inbox_feed()
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  bloque_key TEXT,
  item_kind TEXT,
  due_on DATE,
  expediente_id UUID,
  expediente_tipo TEXT
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
      e.tipo::text AS expediente_tipo
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
      e.tipo::text AS expediente_tipo
    FROM plazos p
    JOIN bloques b ON b.id = p.bloque_id AND b.deleted_at IS NULL AND b.status <> 'off'
    JOIN expedientes e ON e.id = coalesce(p.expediente_id, b.expediente_id) AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
    WHERE p.deleted_at IS NULL
      AND p.completed_at IS NULL
      AND public.can_access_tenant(p.tenant_id)
  )
  SELECT * FROM (
    SELECT * FROM holes
    UNION ALL
    SELECT * FROM dates
  ) feed
  ORDER BY
    CASE feed.item_kind
      WHEN 'overdue' THEN 0
      WHEN 'due_today' THEN 1
      WHEN 'due_soon' THEN 2
      WHEN 'missing_document' THEN 3
      WHEN 'missing_data' THEN 4
      ELSE 5
    END,
    feed.due_on NULLS LAST,
    feed.cliente_nombre;
$$;

GRANT EXECUTE ON FUNCTION public.recompute_bloque_plazos(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.inbox_feed() TO authenticated;
