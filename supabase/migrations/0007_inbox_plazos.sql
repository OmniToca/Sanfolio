-- Inbox: odvozené plazos + díry dat/papírů. due_on je date (Madrid).
-- Derived plazos se nemažou natvrdo — jen deleted_at / completed_at.

CREATE OR REPLACE FUNCTION public.try_parse_date(raw TEXT)
RETURNS DATE
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF raw IS NULL OR btrim(raw) = '' THEN
    RETURN NULL;
  END IF;
  RETURN btrim(raw)::date;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_derived_plazo(
  p_tenant_id UUID,
  p_bloque_id UUID,
  p_expediente_id UUID,
  p_kind TEXT,
  p_due DATE
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF p_due IS NULL THEN
    UPDATE plazos
       SET deleted_at = now()
     WHERE bloque_id = p_bloque_id
       AND kind = p_kind
       AND source = 'derived'
       AND completed_at IS NULL
       AND deleted_at IS NULL;
    RETURN;
  END IF;

  SELECT id INTO v_id
    FROM plazos
   WHERE bloque_id = p_bloque_id
     AND kind = p_kind
     AND source = 'derived'
     AND deleted_at IS NULL
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO plazos (
      tenant_id, bloque_id, expediente_id, kind, due_on, source
    ) VALUES (
      p_tenant_id, p_bloque_id, p_expediente_id, p_kind, p_due, 'derived'
    );
  ELSE
    UPDATE plazos
       SET due_on = p_due,
           expediente_id = p_expediente_id,
           deleted_at = NULL,
           completed_at = NULL
     WHERE id = v_id;
  END IF;
END;
$$;

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
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_recompute_bloque_plazos()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.recompute_bloque_plazos(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recompute_bloque_plazos ON bloques;
CREATE TRIGGER trg_recompute_bloque_plazos
  AFTER INSERT OR UPDATE OF status, fields ON bloques
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_recompute_bloque_plazos();

CREATE OR REPLACE FUNCTION public.inbox_feed()
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  bloque_key TEXT,
  item_kind TEXT,
  due_on DATE
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
      NULL::date AS due_on
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
      p.due_on
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

GRANT EXECUTE ON FUNCTION public.try_parse_date(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.recompute_bloque_plazos(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.inbox_feed() TO authenticated;
