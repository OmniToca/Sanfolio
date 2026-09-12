# Slovník modulů (AI kontext)

Před novou feature ověř, že tu už není. Po novém modulu/provideru doplň řádek.

| Klíč | Kde | Účel |
| --- | --- | --- |
| `core` | shell, clientes, search | vždy zapnuto |
| `carpeta_inmueble` | `features/carpeta` | deska 1:1 s tiskem, slot `carpeta.blocks`; klik na blok → `/carpeta/:key` |
| `impuestos` | `features/expedientes` | tenké 210 / renta, checklist + plazo |
| `policia` / `ayuntamiento` / `testament` | moduly zapnuté u Jarky | desky až po složce koupě |
| `translate-message` | Edge Function | překlad výzvy při kliknutí gestora |
| `nie_poder` | bloky na desce | extras NIE = samostatný úkol |
| `ai_copilot` | `features/ai` | search / open / prefill; uživatel ukládá |
| `AiPanel` / `aiChatProvider` | `features/ai/ai_panel.dart` | trvalý chat; zápis `ai_conversations` + `ai_messages` |
| `extract-document` | Edge Function | fotka/PDF → text LLM (faktura) nebo vision (průkaz) → `ai_drafts`; Guardar je gestor |
| `documentos.extracted` | JSONB na dokladu | uložená pole po Guardar; AI sem nezapisuje |
| `documentos.body_text` | TEXT na dokladu | přepis PDF po Guardar |
| `purge_documento_storage` | SQL RPC | owner vysype blob schovaného dokumentu |
| `query_suministro` / `query_plazos_office` / `query_escritura` | SQL RPC | office-wide čtení desky pro chat |
| `ai-assistant` | Edge Function | whitelist tools; žádný save/send |
| `roadmap_dokumenty_ai` | `docs/roadmap_dokumenty_ai.md` | Fáze A–G: přepis, PDF, koš, office-wide tools, otevřený blok; později FTS |
| `ai-draft-message` | Edge Function | díry složky → `mensajes.draft`; odesílá gestor |
| `client_portal` | není | v2, čte `mensajes.translations` |
| `gestoria_auth` | `packages/gestoria_auth` | login, PortalUrls, hash `setSession` |
| `AuthController` | `gestoria_auth` | session, profil, impersonace |
| `create-office` | Edge Function | založení tenanta + invite owner |
| `start_impersonation` | SQL RPC | auditní session 8 h |
| `apps/support` | Flutter web | HQ kanceláře, Impersonar |
| `CarpetaController` | `carpeta_controller.dart` | tužka, `bloques`, `clientes`, `documentos` |
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
| `client_contacts` | SQL | druhý kontakt + locale |
| `organization_modules` | SQL | které moduly kancelář má |

Jazyky UI: `cs` `en` `es` `de` `fr` (per `profiles.locale`). Klient: `clientes.locale`. Outbound zpráva = překlad.
