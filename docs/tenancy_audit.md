# Tenancy, portály, audit, GDPR

Vzory z OmniToca (Support ≠ Cloud, impersonace s důvodem) a LeoDejvIT (soft-delete, append-only `audit_logs`, membership oddělené od identity). Offline/Drift se **nepřenáší**.

## 1. Tři plus jeden povrch

| App | Kdo | Runtime | Data |
| --- | --- | --- | --- |
| `www` | veřejnost | statický web | žádné JWT |
| `support` | náš tým | Flutter web | `is_support`, žádní klienti bez impersonace |
| `gestoria` | kancelář | Flutter web | RLS na `tenant_id` |
| `cliente` | klienti kanceláře | později | v MVP se nestaví |

Cross-app URL: `GESTORIA_BASE_URL`, `SUPPORT_APP_URL`. Release zakazuje localhost. Handoff **vždy** nese `refresh_token` v hash (dvě origin = dvě localStorage). Produkční build na Netlify: env `SUPABASE_*`; URL default `$URL` (viz root `netlify.toml`).

Licence: tabulky `modules` + `organization_modules` (`trial` \| `active` \| `cancelled` \| `past_due`). Kill-switch Gestoría app při `cancelled`/`past_due` → `/payment-required`. Support se nezamyká.

## 2. Identity

```
auth.users.id
    └── profiles.id            -- globální, BEZ tenant_id, flag is_support
            └── tenant_members -- tenant_id, role, deleted_at
```

Role tenant: `owner` | `gestor` | `asistente`.  
Jeden e-mail smí být ve více kancelářích (Leo cross-tenant). Switcher organizace když `count(memberships) > 1`.

Reset hesla: login má „Zapomenuté heslo“ → `resetPasswordForEmail` (`redirectTo` = `GESTORIA_BASE_URL`). Routa `/reset-password` je veřejná; inbox až po `updateUser(password)`. AI heslo nemění.

Helper RLS (SECURITY DEFINER, `stable`):

- `auth_is_support_user()`
- `auth_tenant_ids()` → uuid[] živých memberships
- `auth_has_role(tenant, roles[])`

Žádné `FOR DELETE` na business tabulkách. Aplikace jen `UPDATE deleted_at`. Postgres role `authenticated` nemá table DELETE (kromě výjimek, které nechceme).

## 3. Tabulky (návrh schématu, ještě ne migrace)

Každá ne-globální tabulka: `id uuid`, `tenant_id uuid not null`, `created_at`, `updated_at`, `deleted_at`.

| Tabulka | Poznámka |
| --- | --- |
| `tenants` | despacho, locale `es`, timezone `Europe/Madrid` |
| `profiles` | `is_support boolean` |
| `tenant_members` | unique živý (tenant, profile) |
| `modules` / `organization_modules` | licence |
| `clientes` | kind, jméno, kontakt, iban, search_vector |
| `client_identifiers` | viz search_spec |
| `inmuebles` | cliente_id, escritura pole |
| `expedientes` | tipo, estado, cliente_id, inmueble_id nullable |
| `bloques` | expediente_id, key, status, fields jsonb |
| `documentos` | storage_path, tipo, cliente/bloque |
| `plazos` | kind, due_on, source, bloque/expediente |
| `plazo_reminders` | offset + fired_at |
| `mensajes` | draft/sent/discarded, canal email |
| `provision_movements` | ingreso/factura/ajuste |
| `ai_conversations` / `ai_messages` / `ai_drafts` | TTL drafty |
| `support_view_sessions` | impersonace |
| `audit_logs` | **bez** deleted_at |
| `legal_holds` | zákaz anonymizace do data |

`bloques.fields` jsonb je v MVP záměr: různé bloky, stejná tabulka. Index GIN na fields až podle potřeby. Klíče polí jsou smlouva v [folder_template.md](folder_template.md), ne volný chaos.

## 4. Soft-delete

- `deleted_at` na všem business.
- Unique indexy `WHERE deleted_at IS NULL`.
- List API default filtruje smazané.
- Obnova: `owner` (a Support v impersonaci) `deleted_at = null` + audit `restore`.
- Fyzický DELETE zakázán triggerem:

```sql
CREATE FUNCTION forbid_hard_delete() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'hard delete forbidden';
END;
$$ LANGUAGE plpgsql;
```

Na `audit_logs` místo toho `forbid_update_delete` (append-only). FalcoNest cron mazající audit po 6 měsících se **nesmí** zkopírovat.

## 5. Audit log

Insert jen z triggerů a SECURITY DEFINER funkcí, ne z Flutter klienta (klient by mohl lhát).

| Sloupec | Význam |
| --- | --- |
| `id` | uuid |
| `tenant_id` | nullable u Support akcí |
| `actor_id` | profiles.id |
| `impersonation_session_id` | pokud Support |
| `action` | `cliente.open`, `cliente.update`, `bloque.enabled`, `message.sent`, `ai.tool`, `search`, `restore`, … |
| `entity_table` | |
| `entity_id` | |
| `before` | jsonb |
| `after` | jsonb |
| `ip` / `user_agent` | z Edge kde jde |
| `created_at` | |

**Čtení karty** (`clientes.open`) je povinný audit (LOPDGDD). Flutter volá RPC `audit_open` jednou při vstupu na kartu; změny `clientes` / `mensajes` / `documentos` / `client_contacts` zapisuje trigger `audit_row_change` (ne Flutter). Owner čte stopu RPC `cliente_audit_log`. Append-only — mazání logu v UI není.

Retention: audit se **neanonymizuje** spolu s klientem; po legal hold se v `before/after` nahradí PII za `{"_redacted": true}` funkcí, řádek zůstane.

## 6. Impersonace (handoff, který drží)

OmniToca posílala jen `session_id`. Support a kancelář jsou **dvě origin** → dvě `localStorage` → kancelář nemá JWT → tichý `/login`.

Tady:

1. Support: povinný důvod → RPC `start_impersonation`.
2. Stejná záložka: `{GESTORIA_BASE_URL}/impersonation/accept?session_id=…#refresh_token=…`  
   Token je v **hash**, ne v query.
3. Accept nejdřív `setSession(refresh_token)`, pak ověří živou session. Chybí-li token, **řekne to na obrazovce** — nikdy tichý login.
4. Banner „Režim podpory: {despacho}“ + Ukončit → `end_impersonation` → `SUPPORT_APP_URL`.
5. Support JWT v kanceláři **bez** živé session → `/forbidden`.

Localhost v debugu smí; v release musí být veřejné URL. Handoff i na dvou `flutter run` portech nese token, takže funguje.

Založení kanceláře: Edge Function `create-office` (service_role). Flutter INSERT do `tenants` ne.

## 7. Storage

Bucket `tenant-docs` v EU. Cesta `{tenant_id}/{cliente_id}/{documento_id}`.  
Policy: membership tenantu. Žádné veřejné URL. Signed URL max 10 min.

## 8. GDPR / LOPDGDD vs. „100 % soft-delete“

Kancelář = správce. My = zpracovatel. DPA před ostrým provozem.

| Požadavek | Jak |
| --- | --- |
| Hosting EU | Supabase region EU |
| Soft-delete jako undo | `deleted_at`, UI „Eliminar“ |
| Právo na výmaz | není okamžité fyzické smazání |
| Legal hold | daň/obchod 4–6 let: `legal_holds` na klienta/dokument |
| Po hold + žádost o výmaz | `anonymize_cliente`: jméno → `ANON`, identifikátory pryč, soubory overwrite/delete v Storage, expedientes zůstanou jako kostra bez PII, audit redacted |
| Přístup k PII | audit `*.open` |
| Portabilita | později export JSON/PDF složky; neblokuje MVP |

Anonymizace je jediný povolený „tvrdý“ úklid PII a spouští ji owner + potvrzení, nebo cron po `legal_hold.until` AND `erasure_requested_at`.

## 9. RLS náčrt

```sql
-- example
CREATE POLICY clientes_tenant_select ON clientes
  FOR SELECT TO authenticated
  USING (
    deleted_at IS NULL
    AND tenant_id IN (SELECT auth_tenant_ids())
    OR auth_is_support_user() AND current_impersonation_tenant() = tenant_id
  );

CREATE POLICY clientes_tenant_update ON clientes
  FOR UPDATE TO authenticated
  USING (tenant_id IN (SELECT auth_tenant_ids()))
  WITH CHECK (tenant_id IN (SELECT auth_tenant_ids()));
```

INSERT musí `tenant_id` = membership, ne z body libovolně — trigger `_stamp_tenant`.

Support SELECT bez impersonace: jen `tenants`, `organization_modules`, `tenant_members` (bez jmen klientů).

## 10. Co nepřenášet z předchozích projektů

- Drift / SyncEngine / LAN
- Fyzické mazání audit_logs
- Mock fiskální signer jako GTM blocker
- Tajemství AI v klientovi
- `my_tenant_id()` vracící NULL u speciálních rolí (FalcoNest owner portal) — tady žádný klientský portál v MVP, membership je jediná cesta
