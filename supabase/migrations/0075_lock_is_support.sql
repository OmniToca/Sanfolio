-- C1: klient nesmí self-promote na Support přes UPDATE profiles.
-- Bootstrap is_support jen service_role / SQL editor (role bypass RLS + trigger guard).

CREATE OR REPLACE FUNCTION public.forbid_client_is_support_change()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- service_role (Edge / SQL jako admin) smí měnit flag. Authenticated klient ne.
  IF TG_OP = 'UPDATE'
     AND NEW.is_support IS DISTINCT FROM OLD.is_support
     AND coalesce(auth.role(), '') <> 'service_role'
  THEN
    RAISE EXCEPTION 'profiles.is_support is service_role only'
      USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_forbid_is_support ON public.profiles;
CREATE TRIGGER trg_profiles_forbid_is_support
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.forbid_client_is_support_change();

COMMENT ON FUNCTION public.forbid_client_is_support_change() IS
  'Zákaz self-promote is_support z JWT klienta; jen service_role / SQL.';
