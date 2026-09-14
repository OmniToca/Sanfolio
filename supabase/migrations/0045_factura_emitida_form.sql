-- Formulář vydané: obchodní řádky, F1/F2, adresa příjemce.
-- Verifacti lineas = součet DPH sazeb (max 12), ne tyto obchodní položky.

ALTER TABLE facturas
  ADD COLUMN IF NOT EXISTS destinatario_direccion TEXT,
  ADD COLUMN IF NOT EXISTS destinatario_email TEXT,
  ADD COLUMN IF NOT EXISTS notas TEXT,
  ADD COLUMN IF NOT EXISTS forma_pago TEXT,
  ADD COLUMN IF NOT EXISTS tipo_factura TEXT NOT NULL DEFAULT 'F1',
  ADD COLUMN IF NOT EXISTS lineas JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE facturas DROP CONSTRAINT IF EXISTS facturas_tipo_factura_check;
ALTER TABLE facturas
  ADD CONSTRAINT facturas_tipo_factura_check
  CHECK (tipo_factura IN ('F1', 'F2'));

COMMENT ON COLUMN facturas.tipo_factura IS
  'F1 completa (NIF+nombre). F2 simplificada bez příjemce, limit 3000 €.';
COMMENT ON COLUMN facturas.lineas IS
  'Obchodní položky [{descripcion, cantidad, precio_cents, iva_bps, descuento_bps, base_cents, iva_cents}]. Edge je sloučí podle sazby.';
COMMENT ON COLUMN facturas.destinatario_direccion IS
  'Adresa na faktuře. Může být z karty klienta, vždy editovatelná.';
COMMENT ON COLUMN facturas.destinatario_email IS
  'E-mail příjemce na konceptu. Do Verifacti create nejde.';
COMMENT ON COLUMN facturas.notas IS
  'Poznámka na konceptu. Do AEAT popis operace je concepto.';
COMMENT ON COLUMN facturas.forma_pago IS
  'transferencia / efectivo / tarjeta / domiciliacion / otro. Jen kniha, ne SIF.';
