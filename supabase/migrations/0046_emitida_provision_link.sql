-- Vydaná s cliente_id se propsuje na zálohu složky. Kniha zůstává zdrojem DPH / Verifactu.

ALTER TABLE provision_movements
  ADD COLUMN IF NOT EXISTS factura_id UUID REFERENCES facturas (id);

CREATE UNIQUE INDEX IF NOT EXISTS provision_movements_factura_id_uidx
  ON provision_movements (factura_id);

COMMENT ON COLUMN provision_movements.factura_id IS
  'Vydaná z knihy. Pohyb factura sem, ne ruční přepis částky.';

CREATE OR REPLACE FUNCTION public.sync_emitida_provision(p_factura_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  f facturas%ROWTYPE;
  v_exp UUID;
  v_note TEXT;
BEGIN
  SELECT * INTO f FROM facturas WHERE id = p_factura_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;
  IF current_setting('request.jwt.claim.sub', true) IS NOT NULL
     AND NOT public.can_access_tenant(f.tenant_id) THEN
    RETURN;
  END IF;

  IF f.direccion IS DISTINCT FROM 'emitida' THEN
    RETURN;
  END IF;

  IF f.deleted_at IS NOT NULL OR f.cliente_id IS NULL THEN
    UPDATE provision_movements
       SET deleted_at = coalesce(f.deleted_at, now())
     WHERE factura_id = f.id
       AND deleted_at IS NULL;
    RETURN;
  END IF;

  SELECT e.id INTO v_exp
  FROM expedientes e
  JOIN bloques b
    ON b.expediente_id = e.id
   AND b.template_key = 'provision_factura'
   AND b.deleted_at IS NULL
   AND b.status IS DISTINCT FROM 'off'
  WHERE e.cliente_id = f.cliente_id
    AND e.tenant_id = f.tenant_id
    AND e.deleted_at IS NULL
    AND e.estado IS DISTINCT FROM 'archivado'
  ORDER BY CASE WHEN e.tipo = 'compraventa' THEN 0 ELSE 1 END,
           e.created_at DESC
  LIMIT 1;

  IF v_exp IS NULL THEN
    RETURN;
  END IF;

  v_note := nullif(btrim(concat_ws('-', f.serie, f.numero)), '');

  INSERT INTO provision_movements (
    tenant_id, expediente_id, kind, amount_cents, note, factura_id
  ) VALUES (
    f.tenant_id, v_exp, 'factura', f.total_cents, v_note, f.id
  )
  ON CONFLICT (factura_id)
  DO UPDATE SET
    amount_cents = EXCLUDED.amount_cents,
    note = COALESCE(EXCLUDED.note, provision_movements.note),
    expediente_id = EXCLUDED.expediente_id,
    deleted_at = NULL,
    updated_at = now();
END;
$$;

-- Partial unique index as ON CONFLICT target (Postgres).
-- If the unique index is partial, conflict_target must include the predicate.

CREATE OR REPLACE FUNCTION public.trg_sync_emitida_provision()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.sync_emitida_provision(NEW.id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_emitida_provision ON facturas;
CREATE TRIGGER trg_sync_emitida_provision
  AFTER INSERT OR UPDATE OF cliente_id, total_cents, serie, numero, deleted_at, direccion
  ON facturas
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_sync_emitida_provision();

GRANT EXECUTE ON FUNCTION public.sync_emitida_provision(UUID) TO authenticated;

-- RPC z Flutteru jen na živý tenant. Trigger běží jako definer i při migraci.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id FROM facturas
     WHERE direccion = 'emitida'
       AND cliente_id IS NOT NULL
       AND deleted_at IS NULL
  LOOP
    PERFORM public.sync_emitida_provision(r.id);
  END LOOP;
END $$;
