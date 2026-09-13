-- Citace u tenkých spisů policie / magistrát / závěť. Offset není v kódu — due_on je datum citace.

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
  ELSIF b.template_key IN ('policia', 'ayuntamiento', 'testament') THEN
    v_estado := coalesce(
      b.fields->>'fields.tramiteStatus',
      b.fields->>'estado_tramite'
    );
    v_fecha := public.try_parse_date(b.fields->>'fields.appointment');
    IF v_estado = 'cita' THEN
      PERFORM public.sync_derived_plazo(
        b.tenant_id, b.id, v_exp, 'cita_tramite', v_fecha
      );
    ELSE
      PERFORM public.sync_derived_plazo(
        b.tenant_id, b.id, v_exp, 'cita_tramite', NULL
      );
    END IF;
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
