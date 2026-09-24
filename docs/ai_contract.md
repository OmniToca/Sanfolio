# AI kontrakt

AI je copilota nad složkou. **Připraví a otevře. Uživatel ukládá, maže a odesílá.**  
Toto pravidlo je v kódu (whitelist tools), ne v promptu.

Klíč modelu žije jen v Supabase Edge Function (lekce OmniToca: žádný Gemini v Flutter assetu).

## 1. Endpoint

Jedna funkce `ai-assistant` (Deno).

```json
{
  "tenant_id": "uuid",
  "conversation_id": "uuid | null",
  "message": "string",
  "locale": "es",
  "current_route": "/clientes/…"
}
```

Extract a draft výzvy nejsou purpose tohoto endpointu — viz 2b.

Auth: JWT uživatele. Funkce ověří membership a `deleted_at IS NULL` tenantu. Support jen s živou impersonací.

Model nikdy nedostane service_role do promptu. Tools volá runtime funkce podle whitelistu níže; každé tool volání = audit `ai.tool`.

## 2. Povolené tools (chat `ai-assistant`)

Whitelist v `supabase/functions/ai-assistant/index.ts`. Nic jiného runtime modelovi nenabídne.

### 2.1 `search_clients`

```json
{
  "name": "search_clients",
  "parameters": {
    "q": "string",
    "limit": { "type": "integer", "default": 10, "maximum": 20 }
  }
}
```

Volá RPC z [search_spec.md](search_spec.md). Vrací id, **jméno**, skóre, matched_via. Edge před LLM ještě vytáhne NIE/jméno ze věty (stopslova) a vloží hits do promptu. Žádný update.

### 2.2 `get_cliente`

Read-only snapshot karty + identifikátory (NIE/DNI) + bloky + díry + `titular_inmuebles`. Prázdná vlastní deska ≠ „dům nemáme“. PII jde do modelu — audit `ai.read.cliente`. AI neukládá. Edge při `cliente_id` v requestu snapshot přednačte do kontextu (otevřená karta).

### 2.3 `query_suministro` / `query_plazos_office` / `query_escritura`

Office-wide čtení desky (dodavatel, termíny, notář / catastral / strany listiny). Limitovaný RPC, ne `execute_sql`.

### 2.4 `search_document_text`

Read-only fulltext v `documentos.body_text` **plus** cosine v `documento_chunks` (pgvector, `text-embedding-3-small`). Hybrid v `ai-assistant`. Limit 20 / 12. Prázdný přepis ≠ „ve smlouvě to není“. Výsledek nese `albums` (prázdné = hromada), `inmueble_id` a `direccion`. `ai_get_cliente.documentos` totéž.

## 2b. Samostatné Edge (ne chat tools)

- **`extract-document`** — JWT, fotka/PDF → `ai_drafts`. `classify` navrhne blok a tipo (název Poder/FACTURA přebije notáře v těle i LLM). Kódy mají typ (IBAN, CUPS, NIE); regex z nich nedělá telefon. Listinu zarovná jen u COMPARECEN. Po LLM zapíše OCR `documentos.body_text` + kousky (`documento_chunks`) pro search a 1–2 věty `ai_summary` ve **staff locale** (`locale` z requestu / `profiles.locale`) — **ne** album, **ne** `tipo`/`inmueble_id` (to až lidský Guardar přes `set_documento_placement` / `set_documento_inmueble`). `extracted` a pole desky Guardar. Při classify vytáhne až 5 podobných **zařazených** papírů (`similar_placed_papers` + `can_access_cliente`; scoped = jen stejná karta) — album a klíče jako vzor, ne trénink modelu.
- **`merge-document-pages`** — JWT, 2–20 JPG/PNG v pořadí → jedno PDF, zdroje do koše. AI nespojuje. PDF se neřeže.
- **`embed-pending-chunks`** — dopočet vektorů. Auth: JWT kanceláře **nebo** exact `SUPABASE_SERVICE_ROLE_KEY` / `CRON_SECRET` (žádný unsigned JWT `role`).
- **`ai-draft-message`** — JWT, nachystá `mensajes.status = draft`. `sent_at` zůstane null. Tool `send_message` **neexistuje**.
- **`translate-message`** — při odeslání člověkem; `tenant_id` + `can_access_tenant` (M5).
- **`impersonation-handoff`** — Support create / kancelář redeem jednorázového kódu (M6); raw refresh ne v URL.

Navigate / prefill žlutý diff dělá Flutter panel, ne tool v `ai-assistant`. Routy Support app AI neotevírá.

Při odeslání člověkem: do kanálu jde překlad (`clientes.locale`), originál v `cuerpo`. AI ten krok nesmí spustit.

## 3. Zakázané tools (nesmí být v schématu)

- `save_*`, `update_*`, `insert_*`, `upsert_*`
- `delete_*`, `soft_delete_*`
- `send_message`, `send_email`, `send_whatsapp`
- `execute_sql`
- `impersonate`
- cokoliv na jiný tenant

Pokud model „chce uložit“, runtime extract/draft zůstane v `ai_drafts` / `mensajes.draft` a UI řekne, ať klikne Guardar / Odeslat.

## 4. Prompt (zkráceně)

Systémový prompt ES, česky tu jako smlouva:

- Jsi asistent despacho. Data čteš tools. Nevymýšlíš NIE.
- Neříkej, že jsi něco uložil, pokud nepřišel UI event Guardar.
- Když si nejsi jistý klientem, vrať seznam z `search_clients`.
- Odpovídej jazykem UI (`es`).

## 5. Conversation

`ai_conversations` + `ai_messages` (soft-delete). Tenant scoped.  
Přílohy: jen Storage paths tenantu. Max velikost a MIME: jpeg, png, webp, pdf.

## 6. UI kontrakt (Flutter)

Trvalý panel vpravo (na širokém stole dockovaný, na úzkém překryv). Žádný FAB — ať se nepřekrývá s „Nová složka“. Lišta / položka Asistent panel jen přepíná.

Turny se ukládají do `ai_conversations` + `ai_messages` (soft-delete, scoped na uživatele v UI). Stream / HTTP `ai-assistant` volá whitelist tools (`search_clients`, `get_cliente`, `query_suministro`, `query_plazos_office`, `query_escritura`, `search_document_text`). Dokud funkce není nasazená, panel skládá facts + office RPC ve Flutter.

Office-wide otázky (dodavatel, konce seguro, notář) = read-only tools / RPC, viz [roadmap_dokumenty_ai.md](roadmap_dokumenty_ai.md). Žádný `execute_sql`. Vektory až po FTS.

Prefill žlutý diff a compose výzvy spouští Flutter (Guardar / Nachystat výzvu), ne chat tool.

Guardar / Eliminar / Enviar jsou běžné use-casy mimo AI.
