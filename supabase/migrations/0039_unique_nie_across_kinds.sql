-- NIE/DNI/NIF je jedno číslo na tenanta. kind dál říká, co to je;
-- nesmí existovat Petr jako nie a Monika jako dni se stejným value.

DROP INDEX IF EXISTS public.uq_client_identifiers_live;

CREATE UNIQUE INDEX uq_client_identifiers_live
  ON client_identifiers (tenant_id, value_normalized)
  WHERE deleted_at IS NULL
    AND position('*' IN value_normalized) = 0
    AND kind IN ('nie', 'dni', 'nif');

COMMENT ON INDEX public.uq_client_identifiers_live IS
  'Živý NIE/DNI/NIF unique v tenantu, bez ohledu na kind. Pas a other mimo.';
