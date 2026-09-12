-- Druhá (a další) koupě: nové inmueble + deska. Energie bytu A zůstanou na spisu A.

CREATE OR REPLACE FUNCTION public.add_inmueble_compraventa(
  p_cliente_id UUID,
  p_direccion TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_tenant UUID;
  v_dir TEXT := nullif(btrim(p_direccion), '');
  v_inmueble UUID;
  v_exp UUID;
  v_nombre TEXT;
BEGIN
  SELECT c.tenant_id, coalesce(nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''), c.nombre)
    INTO v_tenant, v_nombre
  FROM clientes c
  WHERE c.id = p_cliente_id
    AND c.deleted_at IS NULL;
  IF v_tenant IS NULL THEN
    RAISE EXCEPTION 'not_found';
  END IF;
  IF NOT public.can_access_tenant(v_tenant) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_dir IS NULL THEN
    RAISE EXCEPTION 'direccion_required';
  END IF;

  INSERT INTO inmuebles (tenant_id, cliente_id, direccion)
  VALUES (v_tenant, p_cliente_id, v_dir)
  RETURNING id INTO v_inmueble;

  INSERT INTO expedientes (
    tenant_id, cliente_id, inmueble_id, tipo, estado, titulo
  ) VALUES (
    v_tenant, p_cliente_id, v_inmueble, 'compraventa', 'abierto', v_dir
  )
  RETURNING id INTO v_exp;

  UPDATE bloques
     SET status = 'done'
   WHERE expediente_id = v_exp
     AND template_key = 'cliente_snapshot'
     AND deleted_at IS NULL;

  RETURN v_exp;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_inmueble_compraventa(UUID, TEXT) TO authenticated;

COMMENT ON FUNCTION public.add_inmueble_compraventa(UUID, TEXT) IS
  'Nová koupě u existujícího klienta. Bloky patří jen tomuto inmueble.';
