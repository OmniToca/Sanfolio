-- Modul facturacion: kniha přijatých (žádný SIF) + koncepty vydaných.
-- Emitir volá Edge `sif-emit` (cizí API / vlastní SIF-app). Hash/QR/AEAT nepatří do Flutteru.

INSERT INTO modules (key, label_i18n, always_on, sort_order) VALUES
  (
    'facturacion',
    '{"cs":"Fakturace","en":"Invoicing","es":"Facturación","de":"Rechnungen","fr":"Facturation"}',
    false,
    55
  )
ON CONFLICT (key) DO NOTHING;

INSERT INTO organization_modules (tenant_id, module_key, status)
SELECT t.id, 'facturacion', 'active'
FROM tenants t
WHERE t.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM organization_modules m
    WHERE m.tenant_id = t.id
      AND m.module_key = 'facturacion'
      AND m.deleted_at IS NULL
  );

ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS emisor_nif TEXT,
  ADD COLUMN IF NOT EXISTS emisor_nombre TEXT,
  ADD COLUMN IF NOT EXISTS factura_serie TEXT NOT NULL DEFAULT 'A';

COMMENT ON COLUMN tenant_settings.emisor_nif IS
  'NIF kanceláře jako emisor vydaných. SIF adapter čte odsud, ne z Flutteru.';
COMMENT ON COLUMN tenant_settings.emisor_nombre IS
  'Razón social emisoru. Prázdné = display_name / tenants.name.';
COMMENT ON COLUMN tenant_settings.factura_serie IS
  'Výchozí série vydaných konceptů. Číslování per tenant + série + rok.';

CREATE TABLE facturas (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            UUID NOT NULL REFERENCES tenants (id),
  cliente_id           UUID REFERENCES clientes (id),
  documento_id         UUID REFERENCES documentos (id),
  direccion            TEXT NOT NULL
                       CHECK (direccion IN ('recibida', 'emitida')),
  estado               TEXT NOT NULL DEFAULT 'borrador'
                       CHECK (estado IN (
                         'borrador', 'guardada', 'emitida', 'anulada', 'error'
                       )),
  proveedor_nombre     TEXT,
  proveedor_nif        TEXT,
  destinatario_nombre  TEXT,
  destinatario_nif     TEXT,
  serie                TEXT,
  numero               TEXT,
  fecha                DATE,
  vencimiento          DATE,
  concepto             TEXT,
  base_cents           INT NOT NULL DEFAULT 0,
  iva_cents            INT NOT NULL DEFAULT 0,
  iva_bps              INT,
  total_cents          INT NOT NULL DEFAULT 0,
  moneda               TEXT NOT NULL DEFAULT 'EUR',
  sif_provider         TEXT,
  sif_external_id      TEXT,
  sif_status           TEXT,
  sif_qr_url           TEXT,
  sif_error            TEXT,
  created_by           UUID REFERENCES profiles (id),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at           TIMESTAMPTZ
);

COMMENT ON TABLE facturas IS
  'Kniha kanceláře. Přijaté = Guardar z extractu, žádná AEAT. Vydané = koncept; Emitir = Edge SIF.';
COMMENT ON COLUMN facturas.direccion IS
  'recibida = dodavatel→kancelář/klient. emitida = kancelář→klient.';
COMMENT ON COLUMN facturas.estado IS
  'Přijaté končí na guardada. emitida až po SIF. AI sem nezapisuje.';
COMMENT ON COLUMN facturas.sif_external_id IS
  'Id u dodavatele SIF. Flutter ho jen ukáže, nepočítá huella.';

CREATE INDEX idx_facturas_tenant_dir_fecha
  ON facturas (tenant_id, direccion, fecha DESC)
  WHERE deleted_at IS NULL;

CREATE INDEX idx_facturas_cliente
  ON facturas (cliente_id, direccion)
  WHERE deleted_at IS NULL;

CREATE UNIQUE INDEX uq_facturas_documento_recibida
  ON facturas (documento_id)
  WHERE deleted_at IS NULL
    AND direccion = 'recibida'
    AND documento_id IS NOT NULL;

ALTER TABLE facturas ENABLE ROW LEVEL SECURITY;

CREATE POLICY facturas_select ON facturas
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));
CREATE POLICY facturas_insert ON facturas
  FOR INSERT TO authenticated
  WITH CHECK (public.can_access_tenant(tenant_id));
CREATE POLICY facturas_update ON facturas
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE TRIGGER trg_facturas_updated
  BEFORE UPDATE ON facturas
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_facturas_no_hard_delete
  BEFORE DELETE ON facturas
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();

CREATE TRIGGER trg_facturas_audit
  AFTER INSERT OR UPDATE ON facturas
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

-- Gestor ukládá přijatou z papíru. AI tuhle RPC nevolá.
CREATE OR REPLACE FUNCTION public.guardar_factura_recibida(
  p_documento_id UUID,
  p_proveedor_nombre TEXT,
  p_proveedor_nif TEXT,
  p_numero TEXT,
  p_fecha DATE,
  p_vencimiento DATE,
  p_base_cents INT,
  p_iva_cents INT,
  p_iva_bps INT,
  p_total_cents INT,
  p_concepto TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d RECORD;
  v_id UUID;
BEGIN
  SELECT id, tenant_id, cliente_id
    INTO d
    FROM documentos
   WHERE id = p_documento_id
     AND deleted_at IS NULL;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'documento_missing';
  END IF;
  IF NOT public.can_access_tenant(d.tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT id INTO v_id
    FROM facturas
   WHERE documento_id = p_documento_id
     AND deleted_at IS NULL
     AND direccion = 'recibida'
   LIMIT 1;

  IF v_id IS NULL THEN
    INSERT INTO facturas (
      tenant_id, cliente_id, documento_id, direccion, estado,
      proveedor_nombre, proveedor_nif, numero, fecha, vencimiento,
      concepto, base_cents, iva_cents, iva_bps, total_cents, created_by
    ) VALUES (
      d.tenant_id, d.cliente_id, p_documento_id, 'recibida', 'guardada',
      nullif(btrim(p_proveedor_nombre), ''),
      nullif(upper(btrim(p_proveedor_nif)), ''),
      nullif(btrim(p_numero), ''),
      p_fecha, p_vencimiento,
      nullif(btrim(p_concepto), ''),
      coalesce(p_base_cents, 0),
      coalesce(p_iva_cents, 0),
      p_iva_bps,
      coalesce(p_total_cents, 0),
      auth.uid()
    )
    RETURNING id INTO v_id;
  ELSE
    UPDATE facturas
       SET proveedor_nombre = nullif(btrim(p_proveedor_nombre), ''),
           proveedor_nif = nullif(upper(btrim(p_proveedor_nif)), ''),
           numero = nullif(btrim(p_numero), ''),
           fecha = p_fecha,
           vencimiento = p_vencimiento,
           concepto = nullif(btrim(p_concepto), ''),
           base_cents = coalesce(p_base_cents, 0),
           iva_cents = coalesce(p_iva_cents, 0),
           iva_bps = p_iva_bps,
           total_cents = coalesce(p_total_cents, 0),
           estado = 'guardada'
     WHERE id = v_id;
  END IF;
  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.guardar_factura_recibida(
  UUID, TEXT, TEXT, TEXT, DATE, DATE, INT, INT, INT, INT, TEXT
) TO authenticated;

-- Další číslo vydaného konceptu v sérii za kalendářní rok (Madrid).
CREATE OR REPLACE FUNCTION public.next_factura_numero(
  p_tenant_id UUID,
  p_serie TEXT DEFAULT NULL
)
RETURNS INT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_serie TEXT;
  v_year INT;
  v_n INT;
BEGIN
  IF NOT public.can_access_tenant(p_tenant_id) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  v_serie := nullif(btrim(coalesce(p_serie, '')), '');
  IF v_serie IS NULL THEN
    SELECT nullif(btrim(factura_serie), '') INTO v_serie
      FROM tenant_settings
     WHERE tenant_id = p_tenant_id;
    v_serie := coalesce(v_serie, 'A');
  END IF;
  v_year := extract(year from timezone('Europe/Madrid', now()))::int;
  SELECT coalesce(max(numero::int), 0) + 1
    INTO v_n
    FROM facturas
   WHERE tenant_id = p_tenant_id
     AND deleted_at IS NULL
     AND direccion = 'emitida'
     AND coalesce(serie, '') = v_serie
     AND numero ~ '^[0-9]+$'
     AND extract(year from coalesce(fecha, (timezone('Europe/Madrid', created_at))::date))
         = v_year;
  RETURN v_n;
END;
$$;

GRANT EXECUTE ON FUNCTION public.next_factura_numero(UUID, TEXT) TO authenticated;
