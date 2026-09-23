# Slovník modulů (AI kontext)

Před novou feature ověř, že tu už není. Po novém modulu/provideru doplň řádek.

| Klíč | Kde | Účel |
| --- | --- | --- |
| `core` | shell, clientes, search | vždy zapnuto |
| `carpeta_inmueble` | `features/carpeta` | deska 1:1 s tiskem, slot `carpeta.blocks`; klik na blok → `/carpeta/:key` |
| `carpeta_print` | `carpeta_print.dart`, `printHtmlDocument` | dva A4 z desky; čas papíru, ne slot_order; PDF z dialogu prohlížeče |
| `impuestos` | `features/expedientes` | tenké 210 / renta; 210 počítá IRNR, AEAT nepodává |
| `modelo_210.dart` | `features/expedientes` | IRNR formule `irnr-210-2026.1`; imputace / nájem / prodej; gestor ukládá |
| `policia` / `ayuntamiento` / `testament` | `features/expedientes` | tenký spis na kartě (FeatureGate); cita → inbox |
| `translate-message` | Edge Function | překlad výzvy při kliknutí gestora |
| `nie_poder` | bloky na desce | extras NIE = samostatný úkol |
| `ai_copilot` | `features/ai` | search / open / prefill; uživatel ukládá |
| `facturacion` | `features/facturacion` | kniha přijatých + koncepty vydaných; Guardar / Emitir / Ověřit je člověk |
| `guardar_factura_recibida` | SQL RPC | extract → cents do `facturas`; AI nevolá |
| `sif-emit` | Edge Function | JSON konceptu → Verifacti create; po 200 `pendiente`, ne `emitida` |
| `sif-status` | Edge Function | Ověřit: GET /verifactu/status; `emitida` až AEAT přijme |
| `sif_aeat_url` | `facturas.sif_aeat_url` | HTTPS ValidarQR z create; Flutter jen otevře |
| `roadmap_facturacion` | `docs/roadmap_facturacion.md` | napojení Verifacti API (DR + Emitir); přijaté bez SIF |
| `audit_verifacti` | `docs/audit_verifacti.md` | Verifacti docs vs. `sif-emit`; datum, Pendiente, klíč per NIF |
| `facturas` | SQL | `recibida` bez AEAT; `pendiente` u Verifacti; `emitida` až po Ověřit; s `cliente_id` i záloha složky |
| `factura_emit_screen` | `features/facturacion` | plný koncept vydané: klient ze seznamu nebo ručně, řádky, F1/F2 |
| `facturacion_nav` | `features/facturacion` | vnitřní knihy Ventas/Compras; nová agenda sem, ne do railu |
| `factura_detail_screen` | `features/facturacion` | náhled (karty + tabulka řádků) + Imprimir A4 (španělský papír, QR, blob URL) |
| `printHtmlDocument` | `core/print/office_print.dart` | blob URL + `window.print()`; Safari nesnese about:srcdoc |
| `AiPanel` / `aiChatProvider` | `features/ai/ai_panel.dart` | trvalý chat; zápis `ai_conversations` + `ai_messages` |
| `AiPanel` / `aiChatProvider` | `features/ai/ai_panel.dart` | trvalý chat; zápis `ai_conversations` + `ai_messages` |
| `extract-document` | Edge Function | fotka/PDF → text LLM nebo vision → `ai_drafts`; po LLM `body_text` + jistý album **z první strany PDF**, ne z `scan_01.pdf`; Poder/FACTURA v názvu není escritura; Guardar polí desky je gestor |
| `documentos.extracted` | JSONB na dokladu | uložená pole po Guardar; AI sem nezapisuje |
| `documentos.body_text` | TEXT na dokladu | přepis PDF po extractu (i bez alba) |
| `documentos.caption` | TEXT na dokladu | ruční „co v souboru je“ v knihovně; AI nezapisuje; není extracted |
| `purge_documento_storage` | SQL RPC | owner vysype blob schovaného dokumentu; `legal_hold` když drží hold |
| `legal_holds` | SQL | zákaz purge/anonymizace do `until` (date Madrid) |
| `anonymize_cliente` | SQL RPC + karta | owner; PII → ANON; blob pryč; hold blokuje; bez cronu |
| `ClienteCardSection` | `cliente_card_widgets.dart` | obal sekcí karty; audit a locale mimo obří screen |
| `trashVisibleOnCard` | karta klienta | koš schovaných s originálem z karty i ze složky; vysypané zmizí |
| `pickOfficeFile` | `office_file_pick.dart` | web: `<input>` overlay na tlačítku (Safari); raw POST do Storage, ne multipart |
| `paper_glance` | `features/ai/paper_glance.dart` | součet faktur, efektivní €/kWh (m³), roční odhad, prémie pólizy |
| `extract_queue` | `features/ai/extract_queue*.dart`, `/prepis` | slot `inbox.feed`; Guardar/Zahodit; AI neukládá |
| `pending_extract_queue` | SQL RPC | extract_document bez `extracted`, dokud gestor |
| `ofertas` | `features/ofertas`, FeatureGate | slot `carpeta.blocks` + `settings.section`; žádná ikona v railu |
| `office_offers` | SQL | tarify kanceláře (luz/gaz/seguro) v cents; soft-delete |
| `overpaying_suministro` | SQL RPC + `/preplatek` | inbox `inbox.feed`; jen Guardar + office_offers; AI neodesílá |
| `season_210` / `after_notary` | SQL RPC + `/kampane` | jeden banner `inbox.feed`; 210 bez podání a koupě po escritura; AI neodesílá |
| `expiring_items` | SQL RPC + `/kampane` | DNI / pas / poder / seguro končí; stejný chip jako karta; AI neodesílá |
| `import_carpeta_compraventa` | SQL RPC + `/clientes/import` | CSV dávka `open_carpeta`; duplicitní NIE přeskočí; AI nezakládá |
| `provision_owing` | SQL RPC + `/dluh` | inbox `inbox.feed`; remaining <= 0 s pohyby; AI neodesílá |
| `office_citas` | SQL RPC + `/citas` | inbox `inbox.feed`; policie / magistrát / NIE / notář v jednom dni; AI neodesílá |
| `cliente_channel_flags` | SQL | e-mail/tel karty **nebo** živého kontaktu; `inbox_feed` i Pedir |
| `reach_gaps` | SQL RPC + `/kanal` | banner `inbox.feed`; locale jen cs/en/es/de/fr; AI neodesílá |
| `copy_channel_from_contact` | SQL RPC | prázdný e-mail/tel/locale z kontaktu; platný locale se nepřepíše |
| `suggest_cliente_duplicates` / `merge_clientes` | SQL RPC + `/clientes/sloucit` | e-mail/tel/jméno; dvě živá NIE ne; owner/gestor; soft-delete |
| `season_ibi` | SQL RPC + `/kampane` | SUMA bez recibo nebo plazo v `ibi_warn_days`; prázdné bez splatnosti |
| `ai_get_cliente` | SQL RPC | snapshot karty + díry + doklady (`albums` [] = hromada, finca) + titular finca; žádný save |
| `query_suministro` / `query_plazos_office` / `query_escritura` | SQL RPC | office-wide čtení desky; escritura i notář / strana v `inmueble_titulares` / catastral |
| `search_document_text` | SQL RPC + Edge hybrid | FTS v `body_text` i bez alba; cosine `documento_chunks`; `albums` [] = hromada |
| `ai-assistant` | Edge Function | whitelist tools; žádný save/send |
| `roadmap_dokumenty_ai` | `docs/roadmap_dokumenty_ai.md` | Fáze A–G + FTS v `body_text`; vektory později |
| `ai-draft-message` | Edge Function | díry složky → `mensajes.draft`; odesílá gestor |
| `stoh` | `features/carpeta/stoh_*.dart`, `/stoh` | sken bez bloku; classify; Guardar zapne blok; AI neukládá |
| `documento_library` | `documento_library.dart`, SQL 0062–0065 | knihovna u klienta; alba `documento_bloques`; finca; duplicita; spojení fotek; AI place jen album |
| `library_view` | `library_view.dart`, `/stoh` | filtry hromady, pohled bez dump, hromadný výběr |
| `cliente_poder_glance` | SQL RPC + čip seznam/karta | máme kopii poderu? deska datum; AI neukládá |
| `documento_chunks` | SQL 0065 | kousky `body_text` + embedding; tenant scoped; AI jen čte |
| `merge-document-pages` | Edge Function | 2–20 JPG/PNG → jedno PDF; zdroje soft-delete; AI nespojuje |
| `pickOfficeFiles` | `office_file_pick.dart` | multi-select šanonu, max 40 |
| `client_portal` | není | #1 na `docs/vyvoj.md`; čte `mensajes.translations`; klient nenahrazuje Guardar |
| `gestoria_auth` | `packages/gestoria_auth` | login, PortalUrls, hash `setSession` |
| `AuthController` | `gestoria_auth` | session, profil, impersonace, změna hesla |
| `OfficeAccountSection` | `office_account_section.dart` | odhlášení a změna hesla v Nastavení; AI sem nesahá |
| `create-office` | Edge Function | založení tenanta + invite owner; balíček z dialogu Supportu |
| `licence_plans` | SQL | 3 tarify carpeta / despacho / asesoria; included v `licence_plan_modules` |
| `set_office_plan` | SQL RPC | jen Support nastaví tarif a syncne `organization_modules` |
| `set_office_module` | SQL RPC | jen Support zapne doplněk (AI, faktury); vypnutí `deleted_at`, ne `cancelled` |
| `set_office_discount` | SQL RPC | sleva kanceláře v bps; 10000 = měsíc zdarma |
| `set_module_monthly_cents` | SQL RPC | ceník doplňků; Support HQ `/cenik` |
| `set_plan_monthly_cents` | SQL RPC | ceník balíčku; Support HQ `/cenik` |
| `OfficeModulesSection` | Nastavení kanceláře | read-only: název balíčku + měsíční poplatek |
| `start_impersonation` | SQL RPC | auditní session 8 h |
| `apps/support` | Flutter web | HQ kanceláře, Impersonar |
| `CarpetaController` | `carpeta_controller.dart` | tužka, `bloques`, `clientes`, `documentos`; přiložení na blok = album, ne druhý blob |
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
| `pedirAlCliente` | `inbox_providers.dart` / `pedir.dart` | razítko `last_requested_at` + draft; odesílá gestor |
| `writePedirDrafts` | `pedir.dart` | hromadný Pedir z `/kampane`; kanál i z kontaktu, nudge; AI neodesílá |
| `ClienteCardController` | `cliente_card_controller.dart` | karta + DNI/pasaporte |
| `run_plazo_reminders` | SQL + Edge `plazo-reminders` | 07:00 Madrid drafty; nikdy neodesílá |
| `cents` | `core/money/cents.dart` | integer cents |
| `provision_movements` | SQL + deska | ingreso/factura/ajuste; zbývá odvozené |
| `invite-staff` | Edge Function | owner zve gestor/asistente, max 3 |
| `cliente_audit_log` | SQL RPC + karta | LOPDGDD stopa; `audit_open` při vstupu; jen owner |
| `tenant_settings` | SQL 1:1 tenant | display_name, offsety, slot_order, send_translated_outbound |
| `client_contacts` | SQL | druhý kontakt + locale (komunikace, ne vlastnictví) |
| `inmueble_titulares` | SQL + šanon escritura | spoluvlastníci finca; Guardar založí kartu kupujícího bez carpeta; 210 čte sharePercent; čip strany složky |
| `organization_modules` | SQL | které moduly kancelář má |
| `posta` | `features/posta`, modul `messaging` | příchozí pošta; `/posta` třídírna; příloha → `documentos` |
| `posta_accounts` | SQL | ingest adresa tenanta (`p{8hex}@inbound…`) |
| `posta_messages` | SQL | inbound, ne `mensajes`; status unassigned/assigned/ignored |
| `posta_attachments` | SQL | blob `{tenant}/posta/{id}/…`; `documento_id` až gestor uloží |
| `posta-inbound` | Edge Function | webhook Resend/Postmark; AI neukládá |
| `assign_posta_message` | SQL RPC | gestor přiřadí klienta; auto jen unique From / plus-adresa |
| `postaReplyTo` | `posta_address.dart` | technická plus-adresa ingestu |
| `postaClientReplyTo` | `posta_address.dart` | Reply-To = `office_email` |
| `posta_senders` | SQL | From, který gestor jednou přiřadil; další mail spadne na stejnou kartu |
| `posta_sender_domains` | SQL | firemní doména → blok desky (iberdrola = luz); Gmail ne |
| `posta.done_at` | `/posta` | zapsáno bez přílohy; fronta pryč, karta drží |
| `search_posta` | SQL RPC | hledání v Poště (From, předmět, tělo, jméno) |
| `mark_mensaje_bounce` | SQL + webhook | Resend nedoručil výzvu |
| `officeEmailSignature` | `posta_address.dart` | podpis výzvy z názvu, telefonu, e-mailu, NIF |
| `postaThreadProvider` | `/posta` | vlákno výzva + odpověď v náhledu |
| `postaRealtimeTickProvider` | `/posta` | postgres changes, seznam bez F5 |
| `isPostaNoiseMail` | `posta_address.dart` | Gmail forwarding / mailer-daemon → ignorovat, ne deska |
| `postaQuickFileProvider` | `/posta` | jedno tlačítko klient→blok; gestor kliká |
| `tenant_settings.office_email` | Nastavení | Reply-To výzvy; Gmail kanceláře, ne plus-adresa |
| `clienteMailTimelineProvider` | karta klienta | Od + Pro: přiřazená `posta_messages` + odeslané `mensajes` email; WhatsApp ne |
| `send-client-message` | Edge Function | Resend po kliknutí gestora; `POSTA_FROM_EMAIL`; AI neposílá |

Jazyky UI: `cs` `en` `es` `de` `fr` (per `profiles.locale`). Klient: `clientes.locale`. Outbound zpráva = překlad.
