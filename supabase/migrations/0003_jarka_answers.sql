-- Gestorie Jarka: druhý kontakt, stav klienta, další moduly, outbound překlad.

INSERT INTO modules (key, label_i18n, always_on, sort_order) VALUES
  ('policia', '{"cs":"Policie","en":"Police","es":"Policía"}', false, 60),
  ('ayuntamiento', '{"cs":"Magistrát","en":"Town hall","es":"Ayuntamiento"}', false, 70),
  ('testament', '{"cs":"Závěť / úmrtí","en":"Will / death","es":"Testamento"}', false, 80)
ON CONFLICT (key) DO NOTHING;

ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS display_name TEXT,
  ADD COLUMN IF NOT EXISTS send_translated_outbound BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS iban_required_for_debit_only BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS allow_client_without_nie BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS ibi_warn_days INT NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS seguro_warn_days INT NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS alarma_warn_days INT NOT NULL DEFAULT 60,
  ADD COLUMN IF NOT EXISTS poder_warn_days INT NOT NULL DEFAULT 60;

COMMENT ON COLUMN tenant_settings.send_translated_outbound IS
  'true = e-mail/WhatsApp odchází v clientes.locale; originál zůstane v mensajes.cuerpo.';
COMMENT ON COLUMN tenant_settings.display_name IS
  'Volitelný název na obrazovce (Gestorie Jarka). NULL = tenants.name.';

ALTER TABLE clientes
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'activo'
    CHECK (status IN ('activo', 'inactivo'));

CREATE TABLE client_contacts (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    UUID NOT NULL REFERENCES tenants (id),
  cliente_id   UUID NOT NULL REFERENCES clientes (id),
  nombre       TEXT NOT NULL,
  relacion     TEXT,
  tel          TEXT,
  email        TEXT,
  locale       TEXT NOT NULL DEFAULT 'cs',
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at   TIMESTAMPTZ
);

CREATE INDEX idx_client_contacts_cliente
  ON client_contacts (cliente_id)
  WHERE deleted_at IS NULL;

ALTER TABLE client_contacts ENABLE ROW LEVEL SECURITY;

CREATE POLICY client_contacts_select ON client_contacts
  FOR SELECT TO authenticated USING (public.can_access_tenant(tenant_id));
CREATE POLICY client_contacts_insert ON client_contacts
  FOR INSERT TO authenticated WITH CHECK (public.can_access_tenant(tenant_id));
CREATE POLICY client_contacts_update ON client_contacts
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

CREATE TRIGGER trg_client_contacts_updated
  BEFORE UPDATE ON client_contacts
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_client_contacts_no_hard_delete
  BEFORE DELETE ON client_contacts
  FOR EACH ROW EXECUTE FUNCTION forbid_hard_delete();

-- Papíry podle kanceláře: smlouvy + faktury, CUPS, číslo klienta, SUMA id.
UPDATE bloque_templates SET
  required_field_keys = '{proveedor,numero_cliente,numero_contrato,titular}',
  required_doc_types = '{contrato_agua,factura_agua}'
WHERE key = 'agua';

UPDATE bloque_templates SET
  required_field_keys = '{proveedor,cups,numero_contrato,titular}',
  required_doc_types = '{contrato_luz,factura_luz}'
WHERE key = 'luz';

UPDATE bloque_templates SET
  required_field_keys = '{proveedor,cups,numero_contrato,titular}',
  required_doc_types = '{contrato_gaz,factura_gaz}'
WHERE key = 'gaz';

UPDATE bloque_templates SET
  required_field_keys = '{proveedor,numero_contrato,titular}',
  required_doc_types = '{certificado_comunidad}'
WHERE key = 'comunidad';

UPDATE bloque_templates SET
  required_field_keys = '{identificacion_suma,domiciliado}',
  required_doc_types = '{recibo_ibi}'
WHERE key = 'suma';
