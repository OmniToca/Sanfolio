-- Ranní drafty výzev. Cron nikdy neodesílá. Madrid 07:00.

CREATE TABLE IF NOT EXISTS plazo_reminders (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   UUID NOT NULL REFERENCES tenants (id),
  plazo_id    UUID NOT NULL REFERENCES plazos (id),
  offset_days INT NOT NULL,
  mensaje_id  UUID REFERENCES mensajes (id),
  fired_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_plazo_reminders_offset
  ON plazo_reminders (plazo_id, offset_days);

COMMENT ON TABLE plazo_reminders IS
  'Jedna výzva na (plazo, offset). offset -1 = overdue. Cron jen draft.';

ALTER TABLE plazo_reminders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS plazo_reminders_select ON plazo_reminders;
CREATE POLICY plazo_reminders_select ON plazo_reminders
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));

CREATE OR REPLACE FUNCTION public.run_plazo_reminders(p_force BOOLEAN DEFAULT false)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE;
  v_hour INT;
  v_drafts INT := 0;
  v_skip_channel INT := 0;
  r RECORD;
  v_offsets INT[];
  v_off INT;
  v_tpl TEXT;
  v_asunto TEXT;
  v_cuerpo TEXT;
  v_nombre TEXT;
  v_despacho TEXT;
  v_fecha TEXT;
  v_canal TEXT;
  v_msg UUID;
  v_rem UUID;
  v_has_channel BOOLEAN;
BEGIN
  v_today := (timezone('Europe/Madrid', now()))::date;
  v_hour := extract(hour FROM timezone('Europe/Madrid', now()))::int;
  IF NOT p_force AND v_hour <> 7 THEN
    RETURN jsonb_build_object(
      'ok', true,
      'skipped_hour', true,
      'madrid_hour', v_hour,
      'drafts', 0
    );
  END IF;

  FOR r IN
    SELECT
      p.id AS plazo_id,
      p.tenant_id,
      p.kind,
      p.due_on,
      p.bloque_id,
      b.template_key AS bloque_key,
      c.id AS cliente_id,
      c.email,
      c.tel,
      coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''), c.razon_social, c.nombre, '') AS cliente_nombre,
      coalesce(nullif(btrim(ts.display_name), ''), t.name, '') AS despacho,
      ts.plazo_offsets,
      pr.offset_days AS rule_offsets,
      ts.ibi_warn_days,
      ts.seguro_warn_days,
      ts.alarma_warn_days,
      ts.poder_warn_days
    FROM plazos p
    JOIN bloques b ON b.id = p.bloque_id AND b.deleted_at IS NULL AND b.status <> 'off'
    JOIN expedientes e ON e.id = coalesce(p.expediente_id, b.expediente_id) AND e.deleted_at IS NULL
    JOIN clientes c ON c.id = e.cliente_id AND c.deleted_at IS NULL
    JOIN tenants t ON t.id = p.tenant_id AND t.deleted_at IS NULL
    LEFT JOIN tenant_settings ts ON ts.tenant_id = p.tenant_id
    LEFT JOIN plazo_rules pr ON pr.kind = p.kind
    WHERE p.deleted_at IS NULL
      AND p.completed_at IS NULL
      AND (p.snooze_until IS NULL OR p.snooze_until <= v_today)
  LOOP
    v_has_channel :=
      nullif(btrim(coalesce(r.email, '')), '') IS NOT NULL
      OR nullif(btrim(coalesce(r.tel, '')), '') IS NOT NULL;

    IF jsonb_typeof(r.plazo_offsets -> r.kind) = 'array'
       AND jsonb_array_length(r.plazo_offsets -> r.kind) > 0 THEN
      v_offsets := ARRAY(
        SELECT jsonb_array_elements_text(r.plazo_offsets -> r.kind)::int
      );
    ELSIF r.rule_offsets IS NOT NULL THEN
      v_offsets := r.rule_offsets;
    ELSE
      v_offsets := CASE r.kind
        WHEN 'ibi_anual' THEN ARRAY[coalesce(r.ibi_warn_days, 60)]
        WHEN 'seguro_renovacion' THEN ARRAY[coalesce(r.seguro_warn_days, 60)]
        WHEN 'alarma_renovacion' THEN ARRAY[coalesce(r.alarma_warn_days, 60)]
        WHEN 'poder_caducidad' THEN ARRAY[coalesce(r.poder_warn_days, 60)]
        ELSE ARRAY[7]
      END;
    END IF;

    v_nombre := coalesce(nullif(btrim(r.cliente_nombre), ''), '—');
    v_despacho := coalesce(nullif(btrim(r.despacho), ''), '—');
    v_fecha := to_char(r.due_on, 'YYYY-MM-DD');
    v_canal := CASE
      WHEN nullif(btrim(coalesce(r.email, '')), '') IS NOT NULL THEN 'email'
      ELSE 'whatsapp'
    END;

    FOREACH v_off IN ARRAY v_offsets
    LOOP
      IF r.due_on - v_off IS DISTINCT FROM v_today THEN
        CONTINUE;
      END IF;
      IF NOT v_has_channel THEN
        v_skip_channel := v_skip_channel + 1;
        CONTINUE;
      END IF;
      v_rem := NULL;
      INSERT INTO plazo_reminders (tenant_id, plazo_id, offset_days)
      VALUES (r.tenant_id, r.plazo_id, v_off)
      ON CONFLICT (plazo_id, offset_days) DO NOTHING
      RETURNING id INTO v_rem;
      IF v_rem IS NULL THEN
        CONTINUE;
      END IF;
      v_tpl := 'recordatorio';
      v_asunto := 'Recordatorio: ' || r.bloque_key || ' — ' || v_fecha;
      v_cuerpo :=
        'Hola ' || v_nombre || E',\n\n'
        || 'Le recordamos el plazo de ' || r.bloque_key
        || ' con fecha ' || v_fecha || E'.\n\n'
        || v_despacho;
      INSERT INTO mensajes (
        tenant_id, cliente_id, plazo_id, bloque_id, template_key,
        canal, asunto, cuerpo, locale_original, translations, status
      ) VALUES (
        r.tenant_id, r.cliente_id, r.plazo_id, r.bloque_id, v_tpl,
        v_canal, v_asunto, v_cuerpo, 'es', '{}'::jsonb, 'draft'
      ) RETURNING id INTO v_msg;
      UPDATE plazo_reminders SET mensaje_id = v_msg WHERE id = v_rem;
      v_drafts := v_drafts + 1;
      v_rem := NULL;
    END LOOP;

    IF r.due_on < v_today THEN
      IF NOT v_has_channel THEN
        v_skip_channel := v_skip_channel + 1;
      ELSE
        v_rem := NULL;
        INSERT INTO plazo_reminders (tenant_id, plazo_id, offset_days)
        VALUES (r.tenant_id, r.plazo_id, -1)
        ON CONFLICT (plazo_id, offset_days) DO NOTHING
        RETURNING id INTO v_rem;
        IF v_rem IS NOT NULL THEN
          v_tpl := 'vencido';
          v_asunto := 'Plazo vencido — ' || r.bloque_key;
          v_cuerpo :=
            'Hola ' || v_nombre || E',\n\n'
            || 'El plazo de ' || r.bloque_key || ' (' || v_fecha
            || ') ya ha vencido. Contacte con nosotros lo antes posible.'
            || E'\n\n' || v_despacho;
          INSERT INTO mensajes (
            tenant_id, cliente_id, plazo_id, bloque_id, template_key,
            canal, asunto, cuerpo, locale_original, translations, status
          ) VALUES (
            r.tenant_id, r.cliente_id, r.plazo_id, r.bloque_id, v_tpl,
            v_canal, v_asunto, v_cuerpo, 'es', '{}'::jsonb, 'draft'
          ) RETURNING id INTO v_msg;
          UPDATE plazo_reminders SET mensaje_id = v_msg WHERE id = v_rem;
          v_drafts := v_drafts + 1;
        END IF;
        v_rem := NULL;
      END IF;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'skipped_hour', false,
    'madrid_date', v_today,
    'drafts', v_drafts,
    'skipped_no_channel', v_skip_channel
  );
END;
$$;

REVOKE ALL ON FUNCTION public.run_plazo_reminders(BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.run_plazo_reminders(BOOLEAN) TO service_role;

DO $$
BEGIN
  IF to_regclass('cron.job') IS NULL THEN
    RAISE NOTICE 'pg_cron není, Edge Function plazo-reminders se plánuje v dashboardu.';
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'gestoria-plazo-reminders') THEN
    PERFORM cron.unschedule('gestoria-plazo-reminders');
  END IF;
  PERFORM cron.schedule(
    'gestoria-plazo-reminders',
    '0 5,6 * * *',
    $c$SELECT public.run_plazo_reminders(false)$c$
  );
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron se nepodařilo naplánovat: %', SQLERRM;
END;
$$;
