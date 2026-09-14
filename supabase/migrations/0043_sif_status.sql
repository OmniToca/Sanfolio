-- Stav po Emitir, než AEAT přijme záznam. fecha_expedicion u Verifacti
-- je dnešek (Madrid); facturas.fecha zůstává den služby (fecha_operacion).

ALTER TABLE facturas DROP CONSTRAINT IF EXISTS facturas_estado_check;

ALTER TABLE facturas
  ADD CONSTRAINT facturas_estado_check
  CHECK (estado IN (
    'borrador', 'guardada', 'pendiente', 'emitida', 'anulada', 'error'
  ));

ALTER TABLE facturas
  ADD COLUMN IF NOT EXISTS sif_fecha_expedicion DATE;

COMMENT ON COLUMN facturas.estado IS
  'Přijaté končí na guardada. pendiente = u Verifacti, čeká AEAT. emitida až po ověření. AI sem nezapisuje.';
COMMENT ON COLUMN facturas.sif_fecha_expedicion IS
  'Den odeslaný jako fecha_expedicion (dnešek Madrid při Emitir). POST /verifactu/status ho potřebuje, když chybí uuid.';
COMMENT ON COLUMN facturas.sif_qr_url IS
  'QR z SIF: data-URI (base64) nebo URL. Flutter ho jen ukáže, nekreslí huellu.';
