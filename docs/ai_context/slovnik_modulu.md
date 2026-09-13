# Slovník modulů (AI kontext)

Před novou feature ověř, že tu už není. Po novém modulu/provideru doplň řádek.

| Klíč | Kde | Účel |
| --- | --- | --- |
| `core` | shell, clientes, search | vždy zapnuto |
| `carpeta_inmueble` | `features/carpeta` | deska 1:1 s tiskem, slot `carpeta.blocks`; klik na blok → `/carpeta/:key` |
| `impuestos` | `features/expedientes` | tenké 210 / renta; 210 počítá IRNR, AEAT nepodává |
| `modelo_210.dart` | `features/expedientes` | IRNR formule `irnr-210-2026.1`; imputace / nájem / prodej; gestor ukládá |
| `policia` / `ayuntamiento` / `testament` | `features/expedientes` | tenký spis na kartě (FeatureGate); cita → inbox |
| `translate-message` | Edge Function | překlad výzvy při kliknutí gestora |
| `nie_poder` | bloky na desce | extras NIE = samostatný úkol |
| `ai_copilot` | `features/ai` | search / open / prefill; uživatel ukládá |
| `AiPanel` / `aiChatProvider` | `features/ai/ai_panel.dart` | trvalý chat; zápis `ai_conversations` + `ai_messages` |
| `extract-document` | Edge Function | fotka/PDF → text LLM nebo vision → `ai_drafts`; compraventa: všichni kupující/prodávající, cena, finca, právník; Guardar je gestor |
| `documentos.extracted` | JSONB na dokladu | uložená pole po Guardar; AI sem nezapisuje |
| `documentos.body_text` | TEXT na dokladu | přepis PDF po Guardar |
| `purge_documento_storage` | SQL RPC | owner vysype blob schovaného dokumentu; `legal_hold` když drží hold |
| `legal_holds` | SQL | zákaz purge/anonymizace do `until` (date Madrid) |
| `anonymize_cliente` | SQL RPC + karta | owner; PII → ANON; blob pryč; hold blokuje; bez cronu |
| `ClienteCardSection` | `cliente_card_widgets.dart` | obal sekcí karty; audit a locale mimo obří screen |
| `trashVisibleOnCard` | karta klienta | koš schovaných s originálem z karty i ze složky; vysypané zmizí |
| `pickOfficeFile` | `office_file_pick.dart` | web: `<input>` overlay na tlačítku (Safari); raw POST do Storage, ne multipart |
| `paper_glance` | `features/ai/paper_glance.dart` | součet faktur a krátký řádek na šanonu |
| `ai_get_cliente` | SQL RPC | snapshot karty + díry + doklady + titular finca (složka, salePrice, cuota); žádný save |
| `query_suministro` / `query_plazos_office` / `query_escritura` | SQL RPC | office-wide čtení desky; escritura i notář / strana v `inmueble_titulares` / catastral |
| `ai-assistant` | Edge Function | whitelist tools; žádný save/send |
| `roadmap_dokumenty_ai` | `docs/roadmap_dokumenty_ai.md` | Fáze A–G + FTS v `body_text`; vektory později |
| `ai-draft-message` | Edge Function | díry složky → `mensajes.draft`; odesílá gestor |
| `client_portal` | není | v2, čte `mensajes.translations` |
| `gestoria_auth` | `packages/gestoria_auth` | login, PortalUrls, hash `setSession` |
| `AuthController` | `gestoria_auth` | session, profil, impersonace, změna hesla |
| `OfficeAccountSection` | `office_account_section.dart` | odhlášení a změna hesla v Nastavení; AI sem nesahá |
| `create-office` | Edge Function | založení tenanta + invite owner |
| `start_impersonation` | SQL RPC | auditní session 8 h |
| `apps/support` | Flutter web | HQ kanceláře, Impersonar |
| `CarpetaController` | `carpeta_controller.dart` | tužka, `bloques`, `clientes`, `documentos` |
| `TitularesPanel` | `carpeta_titulares.dart` | spoluvlastníci na desce; mimo obří `carpeta_screen` |
| `bloqueStatusFill` | `carpeta_controller.dart` | sémantika chipu; zelená jen `done` |
| `bloqueDocsHint` | kryt bloku | any = text bez 2/3; all + 2 typy = lišta chybějících |
| `expiryTone` | `core/time/office_date.dart` | DNI/pas badge; dny z `poder_warn_days` |
| `recompute_bloque_status` | SQL RPC | missing_data/document/watching/done; agua/luz/gaz `required_docs_mode=any` |
| `add_inmueble_compraventa` | SQL RPC | druhá koupě = nové inmueble + deska |
| `add_manual_plazo` / `snooze_plazo` | SQL RPC | ruční termín; odklad inboxu, nic se nemaže |
| `clienteMensajesProvider` | karta klienta | historie draft/sent; zahodit = `discarded` |
| `set_expediente_estado` | SQL RPC + deska | abierto…archivado; stale v inboxu z nastavení |
| `open_carpeta_compraventa` | SQL RPC | založení klienta a desky compraventa |
| `clientesListProvider` | `clientes_providers.dart` | seznam / `search_clients` |
| `OfficeSettingsController` | `office_settings_controller.dart` | `tenant_settings` (název + lhůty z DB) |
| `FeatureGate` | `core/modules/feature_gate.dart` | schová UI bez licence |
| `inbox_feed` | SQL RPC | dnešní smyčka (plazos + díry + Pedir) |
| `pedirAlCliente` | `inbox_providers.dart` | razítko `last_requested_at` + draft; odesílá gestor |
| `ClienteCardController` | `cliente_card_controller.dart` | karta + DNI/pasaporte |
| `run_plazo_reminders` | SQL + Edge `plazo-reminders` | 07:00 Madrid drafty; nikdy neodesílá |
| `cents` | `core/money/cents.dart` | integer cents |
| `provision_movements` | SQL + deska | ingreso/factura/ajuste; zbývá odvozené |
| `invite-staff` | Edge Function | owner zve gestor/asistente, max 3 |
| `cliente_audit_log` | SQL RPC + karta | LOPDGDD stopa; `audit_open` při vstupu; jen owner |
| `tenant_settings` | SQL 1:1 tenant | display_name, offsety, slot_order, send_translated_outbound |
| `client_contacts` | SQL | druhý kontakt + locale (komunikace, ne vlastnictví) |
| `inmueble_titulares` | SQL + šanon escritura | spoluvlastníci finca; Guardar založí kartu kupujícího bez carpeta; 210 čte sharePercent |
| `organization_modules` | SQL | které moduly kancelář má |

Jazyky UI: `cs` `en` `es` `de` `fr` (per `profiles.locale`). Klient: `clientes.locale`. Outbound zpráva = překlad.
