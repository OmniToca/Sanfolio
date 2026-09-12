-- Záloha: tři čísla z pohybů. Políčka na bloku jsou cache pro inbox.

CREATE OR REPLACE FUNCTION public.provision_sums(p_expediente_id UUID)
RETURNS TABLE (
  received_cents INT,
  invoiced_cents INT,
  remaining_cents INT
)
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT
    coalesce(sum(amount_cents) FILTER (
      WHERE kind IN ('ingreso', 'ajuste') AND deleted_at IS NULL
    ), 0)::int,
    coalesce(sum(amount_cents) FILTER (
      WHERE kind = 'factura' AND deleted_at IS NULL
    ), 0)::int,
    (
      coalesce(sum(amount_cents) FILTER (
        WHERE kind IN ('ingreso', 'ajuste') AND deleted_at IS NULL
      ), 0)
      -
      coalesce(sum(amount_cents) FILTER (
        WHERE kind = 'factura' AND deleted_at IS NULL
      ), 0)
    )::int
  FROM provision_movements
  WHERE expediente_id = p_expediente_id;
$$;

CREATE OR REPLACE FUNCTION public.sync_provision_bloque_fields(p_expediente_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  s RECORD;
BEGIN
  SELECT * INTO s FROM public.provision_sums(p_expediente_id);
  UPDATE bloques
     SET fields = coalesce(fields, '{}'::jsonb)
       || jsonb_build_object(
            'fields.received', s.received_cents::text,
            'fields.invoiced', s.invoiced_cents::text,
            'fields.remaining', s.remaining_cents::text
          )
   WHERE expediente_id = p_expediente_id
     AND template_key = 'provision_factura'
     AND deleted_at IS NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_sync_provision_fields()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_exp UUID;
BEGIN
  v_exp := coalesce(NEW.expediente_id, OLD.expediente_id);
  PERFORM public.sync_provision_bloque_fields(v_exp);
  RETURN coalesce(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_provision_fields ON provision_movements;
CREATE TRIGGER trg_sync_provision_fields
  AFTER INSERT OR UPDATE OF kind, amount_cents, deleted_at OR DELETE
  ON provision_movements
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_provision_fields();

GRANT EXECUTE ON FUNCTION public.provision_sums(UUID) TO authenticated;

INSERT INTO provision_movements (tenant_id, expediente_id, kind, amount_cents, note)
SELECT
  b.tenant_id,
  b.expediente_id,
  'ingreso'::provision_kind,
  CASE WHEN b.fields->>'fields.received' ~ '^-?[0-9]+$'
       THEN (b.fields->>'fields.received')::int ELSE 0 END,
  'migrace z pole bloku'
FROM bloques b
WHERE b.template_key = 'provision_factura'
  AND b.deleted_at IS NULL
  AND CASE WHEN b.fields->>'fields.received' ~ '^-?[0-9]+$'
           THEN (b.fields->>'fields.received')::int ELSE 0 END <> 0
  AND NOT EXISTS (
    SELECT 1 FROM provision_movements m
     WHERE m.expediente_id = b.expediente_id AND m.deleted_at IS NULL
  );

INSERT INTO provision_movements (tenant_id, expediente_id, kind, amount_cents, note)
SELECT
  b.tenant_id,
  b.expediente_id,
  'factura'::provision_kind,
  CASE WHEN b.fields->>'fields.invoiced' ~ '^-?[0-9]+$'
       THEN (b.fields->>'fields.invoiced')::int ELSE 0 END,
  'migrace z pole bloku'
FROM bloques b
WHERE b.template_key = 'provision_factura'
  AND b.deleted_at IS NULL
  AND CASE WHEN b.fields->>'fields.invoiced' ~ '^-?[0-9]+$'
           THEN (b.fields->>'fields.invoiced')::int ELSE 0 END <> 0
  AND NOT EXISTS (
    SELECT 1 FROM provision_movements m
     WHERE m.expediente_id = b.expediente_id
       AND m.kind = 'factura'
       AND m.deleted_at IS NULL
  );
