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
| `0018_ai_drafts.sql` | `ai_drafts` / konverzace; extract u souboru bez TTL, dokud Guardar; jinak 24 h |
| `0019_ai_get_cliente.sql` | snapshot + díry; audit `ai.read.cliente`; žádný save/send |
| `0020_bloque_status.sql` | `recompute_bloque_status`; tužka off/on s důvodem v auditu |
| `0021_multi_inmueble.sql` | `add_inmueble_compraventa` — nová koupě, bloky jen na tom spisu |
| `0022_manual_plazo_snooze.sql` | ruční `plazos.source=manual` + `snooze_until` v inboxu |
| `0024_documento_extracted.sql` | `documentos.extracted`; `ai_get_cliente` vrací doklady + bloky |
| `0027_search_clients_score.sql` | `search_clients` bez ambiguous `score`; prefix NIE (`Y` → Y973…) |
| `0028_documento_layers.sql` | cesta `{tenant}/{cliente}/…`; `body_text`; `storage_purged_at`; `bloque_field`; `purge_documento_storage`; office-wide `query_*` |
| `0029_purge_storage_allow_delete.sql` | `purge_documento_storage` zapne `storage.allow_delete_query` — hosted trigger jinak přímý DELETE z SQL zakáže |
| `0030_suministro_invoice_enough.sql` | agua/luz/gaz: `required_docs_mode=any` (stačí faktura); `fields.contractNo` nepovinné; bucket 32 MB |
| `0031_attach_recompute_must_not_fail.sql` | trigger po INSERT dokumentu neshodí nahrání; bucket přijme image/jpg a HEIF |
| `0032_storage_octet_stream.sql` | bucket `documentos` přijme `application/octet-stream` (Safari / pošta) |
| `0033_search_document_text.sql` | GIN + RPC `search_document_text` (spanish FTS, bez pgvector) |
| `0034_cita_tramite_plazos.sql` | `cita_tramite` u policia / ayuntamiento / testament |
| `0035_thin_tramite_templates.sql` | `bloque_templates` pro tenké spisy; FK `bloques.template_key` |
| `0036_query_escritura_facts.sql` | `query_escritura` i podle právníka, catastral, stran z `extracted` |
| `0037_inmueble_titulares.sql` | spoluvlastníci finca (`cuota_bps`); audit na kartě složky; [roadmap_titulares.md](roadmap_titulares.md) |
| `0039_unique_nie_across_kinds.sql` | živý NIE/DNI/NIF unique v tenantu bez ohledu na `kind` |
| `0040_legal_holds.sql` | `legal_holds`; `purge_documento_storage` padne na `legal_hold` |
| `0041_anonymize_cliente.sql` | `erasure_requested_at`; RPC `anonymize_cliente` (owner, ne při hold) |
| `0042_facturacion.sql` | modul `facturacion`; kniha `facturas`; RPC `guardar_factura_recibida` / `next_factura_numero`; NIF emisoru v `tenant_settings` |
| `0043_sif_status.sql` | `facturas.estado` + `pendiente`; `sif_fecha_expedicion` (dnešek Madrid při Emitir) |
| `0044_sif_aeat_url.sql` | `facturas.sif_aeat_url` — HTTPS ValidarQR z create |
| `0045_factura_emitida_form.sql` | vydaná: `tipo_factura` F1/F2, obchodní `lineas` JSONB, adresa/e-mail příjemce, notes, forma úhrady |
| `0046_emitida_provision_link.sql` | `provision_movements.factura_id`; vydaná s kartou → pohyb `factura` na složce |
| `0047_posta_inbound.sql` | `posta_accounts` / `posta_messages` / `posta_attachments`; ingest webhook; přiřazení ke klientovi; příloha do `documentos` až gestor |
| `0048_posta_desk.sql` | přiřazení From na kartu; návrh bloku z odesílatele |
| `0049_posta_office_email.sql` | `tenant_settings.office_email` — Reply-To výzvy |
| `0050_posta_wow.sql` | `done_at`, `body_html`, podpis `office_phone`, bounce výzvy, paměť bloku odesílatele, FTS + realtime `/posta` |
| `0051_extract_queue.sql` | `ai_drafts.documento_id`; extract bez TTL; RPC `pending_extract_queue` / `pending_extract_count` |
| `0052_ofertas.sql` | modul `ofertas`; `office_offers` (luz/gaz/seguro, cents); kancelář vyplní tarify, ne trh |
| `0053_overpaying.sql` | RPC `overpaying_suministro` — kdo z uložených faktur platí víc než tarif kanceláře |
| `0054_office_packs.sql` | RPC `season_210` / `after_notary` — 210 a koupě po notáři; AI neodesílá |
| `0055_tenant_rpc_guards.sql` | `recompute_bloque_plazos` + legal-hold helpery: `can_access_tenant` když je JWT |
| `0056_stoh.sql` | `/prepis` jen extract s `bloque_id`; stoh bez bloku je `/stoh` |
| `0057_expiring.sql` | RPC `expiring_items` — DNI/pas/poder/seguro v okně warn_days; AI neodesílá |
| `0058_desk_lists.sql` | CSV `import_carpeta_compraventa`; RPC `provision_owing` / `office_citas`; AI neukládá |
| `0059_reach_merge_ibi.sql` | `cliente_channel_flags`; `reach_gaps` / `copy_channel_from_contact`; `suggest_cliente_duplicates` / `merge_clientes`; `season_ibi`; AI neukládá |
| `0060_office_modules.sql` | ceník `modules.monthly_cents`; sleva `licence_discount_bps`; RPC `set_office_module` / `set_office_discount` / `set_module_monthly_cents` (jen Support) |
| `0061_licence_plans.sql` | tarify carpeta / despacho / asesoria; RPC `set_office_plan` / `set_plan_monthly_cents` |
| `0062_documento_library.sql` | `documento_bloques` alba; `documentos.inmueble_id` + `content_sha256`; RPC `set_documento_placement` / `set_documento_inmueble` / `place_documento_ai`; backfill z `bloque_id` |
| `0063_poder_glance.sql` | RPC `cliente_poder_glance` — kopie poderu + datum z desky; seznam a karta |
| `0064_desk_albums_ai.sql` | `recompute_bloque_status` čte junction `documento_bloques.tipo`; `search_document_text` / `ai_get_cliente` vrací `albums` + finca; trigger po albu |
| `0065_documento_chunks.sql` | `pgvector`; `documento_chunks`; RPC `replace_documento_chunks` / `search_document_chunks`; AI jen čte |
| `0066_folder_lado_campaign.sql` | `after_notary`: čerstvé 210 a díry dodávek jen u kupujícího; plusvalía i u prodávajícího |
| `0067_unplace_ai_escritura_misfile.sql` | AI-alba escritura u Poder/FACTURA zpět na hromadu; lidské album ne |
| `0068_documento_caption.sql` | `documentos.caption` ruční popis v knihovně; AI nesahá; anonymize maže |

Edge: [`create-office`](../supabase/functions/create-office/index.ts) — založení kanceláře. [`translate-message`](../supabase/functions/translate-message/index.ts) — překlad výzvy (klíč `OPENAI_API_KEY`, jinak originál). [`plazo-reminders`](../supabase/functions/plazo-reminders/index.ts) — ranní drafty, nikdy `sent` (tajný `CRON_SECRET` nebo service_role). [`invite-staff`](../supabase/functions/invite-staff/index.ts) — owner zve gestor/asistente (max 3). [`ai-assistant`](../supabase/functions/ai-assistant/index.ts) — chat tools (search, get_cliente, query_suministro / plazos / escritura, search_document_text hybrid FTS+vektory), žádný zápis. [`extract-document`](../supabase/functions/extract-document/index.ts) — fotka/PDF → pending `ai_drafts`, LLM na pozadí; `body_text` + kousky + jistý album po extractu, `extracted` až Guardar. [`merge-document-pages`](../supabase/functions/merge-document-pages/index.ts) — fotky v pořadí → jedno PDF, zdroje soft-delete. [`embed-pending-chunks`](../supabase/functions/embed-pending-chunks/index.ts) — dopočet vektorů. [`sif-emit`](../supabase/functions/sif-emit/index.ts) — koncept vydané → Verifacti create; bez klíčů `sif_not_configured`; po 200 `pendiente`. [`sif-status`](../supabase/functions/sif-status/index.ts) — Ověřit u AEAT; `emitida` až přijme. Due diligence: [facturacion_verifactu.md](facturacion_verifactu.md). [`posta-inbound`](../supabase/functions/posta-inbound/index.ts) — kopie kancelářské schránky (tajný `POSTA_INBOUND_SECRET` / Svix); ukládá metadata + HTML + přílohy, nepřiřazuje blok; bounce odchozí výzvy. [`send-client-message`](../supabase/functions/send-client-message/index.ts) — výzva přes Resend po kliknutí gestora; podpis z `tenant_settings`; bez `RESEND_API_KEY` Flutter otevře Gmail.

Hledání NIE s maskou: `search_clients('Y123**6E')` → `id_mask_match`.

Smlouva s kanceláří: [partner/odpovedi_gestorie_jarka.md](partner/odpovedi_gestorie_jarka.md).

První Support účet (SQL editor, až existuje profil):

```sql
UPDATE profiles SET is_support = true WHERE email = 'tvuj@email';
```
