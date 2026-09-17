-- Import CSV, dlužné zálohy a city dne. Čtení desky + open_carpeta; AI neukládá.

-- Jedna dávka, ať 500 karet nespadne na timeout. Flutter skládá po 40.
CREATE OR REPLACE FUNCTION public.import_carpeta_compraventa(
  p_tenant_id UUID,
  p_rows JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  rec RECORD;
  v_created INT := 0;
  v_empty INT := 0;
  v_dup INT := 0;
  v_errors JSONB := '[]'::jsonb;
  v_nombre TEXT;
  v_nie TEXT;
  v_nie_norm TEXT;
  v_email TEXT;
  v_tel TEXT;
  v_direccion TEXT;
  v_locale TEXT;
  v_cliente UUID;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'import_carpeta_compraventa: forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_rows IS NULL OR jsonb_typeof(p_rows) <> 'array' THEN
    RAISE EXCEPTION 'import_carpeta_compraventa: rows must be array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_rows) > 80 THEN
    RAISE EXCEPTION 'import_carpeta_compraventa: max 80' USING ERRCODE = '22023';
  END IF;

  FOR rec IN
    SELECT t.val, t.n
      FROM jsonb_array_elements(p_rows) WITH ORDINALITY AS t(val, n)
  LOOP
    v_nombre := btrim(coalesce(rec.val->>'nombre', ''));
    IF v_nombre = '' THEN
      v_empty := v_empty + 1;
      CONTINUE;
    END IF;

    v_nie := nullif(btrim(coalesce(rec.val->>'nie', '')), '');
    v_nie_norm := public.normalize_id(v_nie);
    IF v_nie_norm IS NOT NULL AND v_nie_norm <> '' THEN
      IF EXISTS (
        SELECT 1
          FROM client_identifiers i
         WHERE i.tenant_id = p_tenant_id
           AND i.deleted_at IS NULL
           AND i.kind IN ('nie', 'dni', 'nif')
           AND i.value_normalized = v_nie_norm
      ) THEN
        v_dup := v_dup + 1;
        CONTINUE;
      END IF;
    END IF;

    v_email := nullif(btrim(coalesce(rec.val->>'email', '')), '');
    v_tel := nullif(btrim(coalesce(rec.val->>'tel', '')), '');
    v_direccion := nullif(btrim(coalesce(rec.val->>'direccion', '')), '');
    v_locale := lower(btrim(coalesce(rec.val->>'locale', '')));
    IF v_locale NOT IN ('cs', 'en', 'es', 'de', 'fr') THEN
      v_locale := NULL;
    END IF;

    BEGIN
      v_cliente := public.open_carpeta_compraventa(
        p_tenant_id,
        v_nombre,
        v_email,
        v_tel,
        v_direccion,
        NULL,
        v_nie
      );
      IF v_locale IS NOT NULL THEN
        UPDATE clientes
           SET locale = v_locale
         WHERE id = v_cliente
           AND tenant_id = p_tenant_id;
      END IF;
      v_created := v_created + 1;
    EXCEPTION
      WHEN unique_violation THEN
        v_dup := v_dup + 1;
      WHEN OTHERS THEN
        IF SQLSTATE = '42501' THEN
          RAISE;
        END IF;
        v_errors := v_errors || jsonb_build_object(
          'row', rec.n,
          'reason', SQLERRM
        );
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'created', v_created,
    'skipped_empty', v_empty,
    'skipped_duplicate', v_dup,
    'errors', v_errors
  );
END;
$$;

-- Saldo = přijato − vyúčtováno. Prázdná složka bez pohybů sem nepatří.
CREATE OR REPLACE FUNCTION public.provision_owing(p_tenant_id UUID)
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  expediente_id UUID,
  bloque_id UUID,
  received_cents INT,
  invoiced_cents INT,
  remaining_cents INT,
  has_email BOOLEAN,
  has_tel BOOLEAN,
  last_requested_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN QUERY
  SELECT
    c.id,
    coalesce(
      nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
      c.razon_social,
      c.nombre
    ),
    e.id,
    b.id,
    s.received_cents,
    s.invoiced_cents,
    s.remaining_cents,
    coalesce(nullif(btrim(c.email), ''), '') <> '',
    coalesce(nullif(btrim(c.tel), ''), '') <> '',
    b.last_requested_at
  FROM bloques b
  JOIN expedientes e
    ON e.id = b.expediente_id
   AND e.deleted_at IS NULL
  JOIN clientes c
    ON c.id = e.cliente_id
   AND c.deleted_at IS NULL
  JOIN LATERAL public.provision_sums(e.id) s ON TRUE
  WHERE b.tenant_id = p_tenant_id
    AND b.deleted_at IS NULL
    AND b.template_key = 'provision_factura'
    AND b.status <> 'off'
    AND e.estado <> 'archivado'
    AND (s.received_cents <> 0 OR s.invoiced_cents <> 0)
    AND s.remaining_cents <= 0
  ORDER BY s.remaining_cents ASC, c.nombre;
END;
$$;

CREATE OR REPLACE FUNCTION public.provision_owing_count(p_tenant_id UUID)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INT;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT COUNT(*)::INT INTO v_n
    FROM public.provision_owing(p_tenant_id);
  RETURN COALESCE(v_n, 0);
END;
$$;

-- Policie / magistrát / NIE / notář v jednom kalendářním dni (Madrid).
CREATE OR REPLACE FUNCTION public.office_citas(
  p_tenant_id UUID,
  p_on DATE DEFAULT NULL
)
RETURNS TABLE (
  cliente_id UUID,
  cliente_nombre TEXT,
  expediente_id UUID,
  bloque_id UUID,
  bloque_key TEXT,
  plazo_kind TEXT,
  due_on DATE,
  has_email BOOLEAN,
  has_tel BOOLEAN,
  last_requested_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_on DATE := coalesce(
    p_on,
    (timezone('Europe/Madrid', now()))::date
  );
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  RETURN QUERY
  SELECT
    x.cliente_id,
    x.cliente_nombre,
    x.expediente_id,
    x.bloque_id,
    x.bloque_key,
    x.plazo_kind,
    x.due_on,
    x.has_email,
    x.has_tel,
    x.last_requested_at
  FROM (
    SELECT
      c.id AS cliente_id,
      coalesce(
        nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
        c.razon_social,
        c.nombre
      ) AS cliente_nombre,
      e.id AS expediente_id,
      b.id AS bloque_id,
      b.template_key AS bloque_key,
      p.kind::text AS plazo_kind,
      p.due_on,
      coalesce(nullif(btrim(c.email), ''), '') <> '' AS has_email,
      coalesce(nullif(btrim(c.tel), ''), '') <> '' AS has_tel,
      b.last_requested_at
    FROM plazos p
    JOIN bloques b
      ON b.id = p.bloque_id
     AND b.deleted_at IS NULL
     AND b.status <> 'off'
    JOIN expedientes e
      ON e.id = coalesce(p.expediente_id, b.expediente_id)
     AND e.deleted_at IS NULL
    JOIN clientes c
      ON c.id = e.cliente_id
     AND c.deleted_at IS NULL
    WHERE p.tenant_id = p_tenant_id
      AND p.deleted_at IS NULL
      AND p.completed_at IS NULL
      AND p.kind IN ('cita_nie', 'cita_tramite')
      AND p.due_on = v_on

    UNION ALL

    SELECT
      c.id,
      coalesce(
        nullif(btrim(concat_ws(' ', c.nombre, c.apellidos)), ''),
        c.razon_social,
        c.nombre
      ),
      e.id,
      b.id,
      b.template_key,
      'escritura'::text,
      coalesce(
        i.escritura_fecha,
        public.parse_office_date(b.fields->>'fields.date')
      ),
      coalesce(nullif(btrim(c.email), ''), '') <> '',
      coalesce(nullif(btrim(c.tel), ''), '') <> '',
      b.last_requested_at
    FROM bloques b
    JOIN expedientes e
      ON e.id = b.expediente_id
     AND e.deleted_at IS NULL
     AND e.estado <> 'archivado'
    JOIN clientes c
      ON c.id = e.cliente_id
     AND c.deleted_at IS NULL
    LEFT JOIN inmuebles i
      ON i.id = e.inmueble_id
     AND i.deleted_at IS NULL
    WHERE b.tenant_id = p_tenant_id
      AND b.deleted_at IS NULL
      AND b.template_key = 'escritura'
      AND b.status <> 'off'
      AND coalesce(
        i.escritura_fecha,
        public.parse_office_date(b.fields->>'fields.date')
      ) = v_on
  ) x
  ORDER BY x.plazo_kind, x.cliente_nombre;
END;
$$;

CREATE OR REPLACE FUNCTION public.office_citas_count(
  p_tenant_id UUID,
  p_on DATE DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n INT;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  SELECT COUNT(*)::INT INTO v_n
    FROM public.office_citas(p_tenant_id, p_on);
  RETURN COALESCE(v_n, 0);
END;
$$;

GRANT EXECUTE ON FUNCTION public.import_carpeta_compraventa(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.provision_owing(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.provision_owing_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.office_citas(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.office_citas_count(UUID, DATE) TO authenticated;

COMMENT ON FUNCTION public.import_carpeta_compraventa(UUID, JSONB) IS
  'CSV dávka open_carpeta_compraventa. Duplikát NIE přeskočí, nic se nemaže. AI nevolá.';
COMMENT ON FUNCTION public.provision_owing(UUID) IS
  'Složky se zálohou remaining <= 0 a reálnými pohyby. AI neodesílá.';
COMMENT ON FUNCTION public.office_citas(UUID, DATE) IS
  'City policie / magistrát / NIE / notář v jednom dni Madrid. AI neodesílá.';
