-- Veřejná schránka kanceláře = Reply-To výzvy. Ingest plus-adresa zůstane jen technická.
ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS office_email TEXT NOT NULL DEFAULT '';

COMMENT ON COLUMN tenant_settings.office_email IS
  'Adresa, na kterou klient odpovídá (Gmail kanceláře). Kopie padá na ingest přes přeposílání.';
