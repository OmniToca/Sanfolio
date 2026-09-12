# Schéma databáze

Zdroj pravdy: [`supabase/migrations/0001_initial_schema.sql`](../supabase/migrations/0001_initial_schema.sql).

Primární klíče: `gen_random_uuid()` (pg_catalog). Ne `uuid_generate_v4()` — na hosted projektu je uuid-ossp ve schématu `extensions`.

Pořadí souborů je čtyřmístné (`0001`, `0002`, …), ne timestamp.

| Soubor | Obsah |
| --- | --- |
| `0001_initial_schema.sql` | tenanti, RLS, složka, NIE search |
| `0002_modules_settings_i18n.sql` | moduly, `tenant_settings`, `clientes.locale`, `mensajes.translations` |
| `0003_jarka_answers.sql` | kontakty, CUPS / SUMA, NIE volitelné, outbound překlad |
| `0004_auth_support.sql` | `start_impersonation` / `end_impersonation` / `current_impersonation` |
| `0007_inbox_plazos.sql` | `inbox_feed`, odvozené `plazos` |
| `0008_thin_expedientes.sql` | tenké 210 / renta / NIE plazos v inboxu |
| `0009_provision_inbox.sql` | `provision_alert` v `inbox_feed` |
| `0010_ai_copilot_module.sql` | zapne `ai_copilot` u existujících kanceláří |
| `0011_pedir_cliente.sql` | `bloques.last_requested_at`; `inbox_feed` + `bloque_id`, kanál |
| `0012_ibi_anual.sql` | IBI/SUMA `ibi_due_month`/`ibi_due_day` v `tenant_settings`, plazo `ibi_anual` |
| `0013_plazo_reminders.sql` | `plazo_reminders` + `run_plazo_reminders` (draft, ne sent) |
| `0014_modelo_210_docs.sql` | checklist papírů modelo 210 |
| `0015_provision_movements.sql` | záloha z `provision_movements`, cache na bloku |
| `0016_invite_staff.sql` | owner-only členství; asistente neschová expediente |
| `0017_cliente_audit.sql` | trigger změn + RPC `cliente_audit_log` (owner, append-only) |
| `0018_ai_drafts.sql` | `ai_drafts` / konverzace; TTL 24 h; AI neukládá klienta |
| `0019_ai_get_cliente.sql` | snapshot + díry; audit `ai.read.cliente`; žádný save/send |
| `0020_bloque_status.sql` | `recompute_bloque_status`; tužka off/on s důvodem v auditu |
| `0021_multi_inmueble.sql` | `add_inmueble_compraventa` — nová koupě, bloky jen na tom spisu |
| `0022_manual_plazo_snooze.sql` | ruční `plazos.source=manual` + `snooze_until` v inboxu |
| `0024_documento_extracted.sql` | `documentos.extracted`; `ai_get_cliente` vrací doklady + bloky |
| `0026_ai_chat_grants.sql` | GRANT na `ai_conversations` / `ai_messages` / `ai_drafts`; `ai_get_cliente` vrací i doklady bez extracted |

Edge: [`create-office`](../supabase/functions/create-office/index.ts) — založení kanceláře. [`translate-message`](../supabase/functions/translate-message/index.ts) — překlad výzvy (klíč `OPENAI_API_KEY`, jinak originál). [`plazo-reminders`](../supabase/functions/plazo-reminders/index.ts) — ranní drafty, nikdy `sent` (tajný `CRON_SECRET` nebo service_role). [`invite-staff`](../supabase/functions/invite-staff/index.ts) — owner zve gestor/asistente (max 3). [`extract-document`](../supabase/functions/extract-document/index.ts) — fotka/PDF → `ai_drafts` podle typu dokladu; Guardar zapíše `documentos.extracted`. [`ai-draft-message`](../supabase/functions/ai-draft-message/index.ts) — `get_cliente` + `mensajes.draft`, nikdy `sent`.

Hledání NIE s maskou: `search_clients('Y123**6E')` → `id_mask_match`.

Smlouva s kanceláří: [partner/odpovedi_gestorie_jarka.md](partner/odpovedi_gestorie_jarka.md).

První Support účet (SQL editor, až existuje profil):

```sql
UPDATE profiles SET is_support = true WHERE email = 'tvuj@email';
```
