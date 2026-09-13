-- Tenké spisy policie / magistrát / závěť potřebují řádek v bloque_templates.
-- bloques.template_key má FK; bez něj Nová policía spadne.

INSERT INTO bloque_templates (
  key, label_es, sort_order,
  required_field_keys, required_doc_types, plazo_kind, on_compraventa
) VALUES
  (
    'policia', 'Policía', 220,
    '{fields.tramiteStatus}', '{justificante_cita}', 'cita_tramite', false
  ),
  (
    'ayuntamiento', 'Ayuntamiento', 230,
    '{fields.tramiteStatus}', '{justificante_cita}', 'cita_tramite', false
  ),
  (
    'testament', 'Testamento', 240,
    '{fields.tramiteStatus}', '{copia_escritura,justificante_cita}',
    'cita_tramite', false
  )
ON CONFLICT (key) DO UPDATE SET
  required_field_keys = EXCLUDED.required_field_keys,
  required_doc_types = EXCLUDED.required_doc_types,
  plazo_kind = EXCLUDED.plazo_kind,
  on_compraventa = EXCLUDED.on_compraventa;

UPDATE bloque_templates
   SET required_docs_mode = 'any'
 WHERE key = 'testament';

INSERT INTO plazo_rules (kind, offset_days, notes)
VALUES ('cita_tramite', '{3,1}', 'Citace úkonu — due_on je datum z fields.appointment')
ON CONFLICT (kind) DO NOTHING;

-- Spisy založené před šablonou: expediente je, blok chybí.
INSERT INTO bloques (
  tenant_id, expediente_id, template_key, status, fields
)
SELECT
  e.tenant_id,
  e.id,
  e.tipo::text,
  'missing_data',
  '{}'::jsonb
FROM expedientes e
WHERE e.tipo IN ('policia', 'ayuntamiento', 'testament')
  AND e.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1
      FROM bloques b
     WHERE b.expediente_id = e.id
       AND b.template_key = e.tipo::text
       AND b.deleted_at IS NULL
  );
