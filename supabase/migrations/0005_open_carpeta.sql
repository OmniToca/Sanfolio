-- Otevření papírové složky: klient + inmueble + expediente compraventa.
-- Bloky semeňuje trg_seed_compraventa_bloques (všechny off); tužka CLIENTE
-- zapne cliente_snapshot. Flutter INSERT do tenants nesmí — tady RLS stačí.

CREATE OR REPLACE FUNCTION public.open_carpeta_compraventa(
  p_tenant_id UUID,
  p_nombre TEXT,
  p_email TEXT DEFAULT NULL,
  p_tel TEXT DEFAULT NULL,
  p_direccion TEXT DEFAULT NULL,
  p_iban TEXT DEFAULT NULL,
  p_nie TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_nombre TEXT := trim(coalesce(p_nombre, ''));
  v_locale TEXT;
  v_cliente UUID;
  v_inmueble UUID;
  v_exp UUID;
  v_nie TEXT := public.normalize_id(p_nie);
  v_kind identifier_kind;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'open_carpeta_compraventa: forbidden' USING ERRCODE = '42501';
  END IF;
  IF v_nombre = '' THEN
    RAISE EXCEPTION 'open_carpeta_compraventa: nombre required' USING ERRCODE = '22023';
  END IF;

  SELECT default_client_locale INTO v_locale
    FROM tenant_settings
   WHERE tenant_id = p_tenant_id;
  v_locale := coalesce(nullif(trim(v_locale), ''), 'cs');

  INSERT INTO clientes (
    tenant_id, kind, nombre, email, tel, direccion, iban, locale, status
  ) VALUES (
    p_tenant_id,
    'persona',
    v_nombre,
    nullif(trim(coalesce(p_email, '')), ''),
    nullif(trim(coalesce(p_tel, '')), ''),
    nullif(trim(coalesce(p_direccion, '')), ''),
    nullif(trim(coalesce(p_iban, '')), ''),
    v_locale,
    'activo'
  )
  RETURNING id INTO v_cliente;

  IF v_nie IS NOT NULL AND v_nie <> '' THEN
    v_kind := CASE
      WHEN v_nie ~ '^[XYZ][0-9*]{7}[A-Z]$' THEN 'nie'::identifier_kind
      WHEN v_nie ~ '^[0-9*]{8}[A-Z]$' THEN 'dni'::identifier_kind
      WHEN v_nie ~ '^[A-HJ-NP-SUVW][0-9*]{7}[0-9A-J]$' THEN 'nif'::identifier_kind
      ELSE 'other'::identifier_kind
    END;
    INSERT INTO client_identifiers (
      tenant_id, cliente_id, kind, value_raw, value_normalized, checksum
    ) VALUES (
      p_tenant_id, v_cliente, v_kind, trim(p_nie), v_nie, 'unknown'
    );
  END IF;

  INSERT INTO inmuebles (tenant_id, cliente_id, direccion)
  VALUES (p_tenant_id, v_cliente, coalesce(nullif(trim(coalesce(p_direccion, '')), ''), ''))
  RETURNING id INTO v_inmueble;

  INSERT INTO expedientes (
    tenant_id, cliente_id, inmueble_id, tipo, estado, titulo
  ) VALUES (
    p_tenant_id, v_cliente, v_inmueble, 'compraventa', 'abierto', v_nombre
  )
  RETURNING id INTO v_exp;

  UPDATE bloques
     SET status = 'done'
   WHERE expediente_id = v_exp
     AND template_key = 'cliente_snapshot'
     AND deleted_at IS NULL;

  PERFORM public.audit_open('clientes', v_cliente, p_tenant_id);

  RETURN v_cliente;
END;
$$;

GRANT EXECUTE ON FUNCTION public.open_carpeta_compraventa(
  UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.normalize_id(TEXT) TO authenticated;

COMMENT ON FUNCTION public.open_carpeta_compraventa IS
  'Založí klienta a desku compraventa. NIE je volitelné.';
