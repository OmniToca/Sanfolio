-- Modul ofertas: tarify kanceláře, ne srovnávač trhu. AI nepřepíná smlouvu.

INSERT INTO modules (key, label_i18n, always_on, sort_order) VALUES
  (
    'ofertas',
    '{"cs":"Nabídky kanceláře","en":"Office offers","es":"Ofertas del despacho","de":"Büro-Angebote","fr":"Offres du cabinet"}',
    false,
    58
  )
ON CONFLICT (key) DO NOTHING;

INSERT INTO organization_modules (tenant_id, module_key, status)
SELECT t.id, 'ofertas', 'active'
FROM tenants t
WHERE t.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1
    FROM organization_modules m
    WHERE m.tenant_id = t.id
      AND m.module_key = 'ofertas'
      AND m.deleted_at IS NULL
  );

CREATE TABLE public.office_offers (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     UUID NOT NULL REFERENCES public.tenants (id),
  kind          TEXT NOT NULL CHECK (kind IN ('luz', 'gaz', 'seguro')),
  title         TEXT NOT NULL,
  partner       TEXT,
  unit_cents    INT,
  annual_cents  INT,
  notes         TEXT,
  created_by    UUID REFERENCES public.profiles (id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at    TIMESTAMPTZ,
  CONSTRAINT office_offers_money_ok CHECK (
    (unit_cents IS NULL OR unit_cents >= 0)
    AND (annual_cents IS NULL OR annual_cents >= 0)
    AND (unit_cents IS NOT NULL OR annual_cents IS NOT NULL)
  )
);

COMMENT ON TABLE public.office_offers IS
  '2–5 tarifů, se kterými kancelář umí přepsat. Není crawl CNMC/Selectra.';

CREATE INDEX idx_office_offers_tenant
  ON public.office_offers (tenant_id, kind)
  WHERE deleted_at IS NULL;

CREATE TRIGGER trg_office_offers_updated
  BEFORE UPDATE ON public.office_offers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
CREATE TRIGGER trg_office_offers_no_hard_delete
  BEFORE DELETE ON public.office_offers
  FOR EACH ROW EXECUTE FUNCTION public.forbid_hard_delete();
CREATE TRIGGER trg_office_offers_audit
  AFTER INSERT OR UPDATE ON public.office_offers
  FOR EACH ROW EXECUTE FUNCTION public.audit_row_change();

ALTER TABLE public.office_offers ENABLE ROW LEVEL SECURITY;

CREATE POLICY office_offers_select ON public.office_offers
  FOR SELECT TO authenticated
  USING (public.can_access_tenant(tenant_id));
CREATE POLICY office_offers_insert ON public.office_offers
  FOR INSERT TO authenticated
  WITH CHECK (public.can_access_tenant(tenant_id));
CREATE POLICY office_offers_update ON public.office_offers
  FOR UPDATE TO authenticated
  USING (public.can_access_tenant(tenant_id))
  WITH CHECK (public.can_access_tenant(tenant_id));

GRANT SELECT, INSERT, UPDATE ON TABLE public.office_offers TO authenticated;
GRANT ALL ON TABLE public.office_offers TO service_role;
