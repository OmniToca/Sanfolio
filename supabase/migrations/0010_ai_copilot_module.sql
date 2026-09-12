-- Modul AI pro existující kanceláře. Tools jen search/open/prefill.

INSERT INTO organization_modules (tenant_id, module_key, status)
SELECT t.id, 'ai_copilot', 'active'
FROM tenants t
WHERE t.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM organization_modules m
    WHERE m.tenant_id = t.id
      AND m.module_key = 'ai_copilot'
      AND m.deleted_at IS NULL
  );
