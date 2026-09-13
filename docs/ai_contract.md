# AI kontrakt

AI je copilota nad složkou. **Připraví a otevře. Uživatel ukládá, maže a odesílá.**  
Toto pravidlo je v kódu (whitelist tools), ne v promptu.

Klíč modelu žije jen v Supabase Edge Function (lekce OmniToca: žádný Gemini v Flutter assetu).

## 1. Endpoint

Jedna funkce `ai-assistant` (Deno).

```json
{
  "purpose": "chat | extract_document | extract_folder_scan",
  "tenant_id": "uuid",
  "conversation_id": "uuid | null",
  "message": "string | null",
  "locale": "es",
  "current_route": "/clientes/…",
  "attachment_ids": ["uuid"]
}
```

Auth: JWT uživatele. Funkce ověří membership a `deleted_at IS NULL` tenantu. Support jen s živou impersonací.

Model nikdy nedostane service_role do promptu. Tools volá runtime funkce podle whitelistu níže; každé tool volání = audit `ai.tool`.

## 2. Povolené tools

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

Volá RPC z [search_spec.md](search_spec.md). Vrací id, jméno, skóre, matched_via. Žádný update.

### 2.2 `open_screen`

```json
{
  "name": "open_screen",
  "parameters": {
    "route": "string",
    "cliente_id": "uuid?",
    "inmueble_id": "uuid?",
    "expediente_id": "uuid?",
    "bloque_key": "string?"
  }
}
```

Runtime ověří, že ids patří tenantu. Odpověď klientovi: `{ "type": "navigate", "route": "/clientes/{id}/carpeta/luz" }`. Flutter GoRouter to otevře. AI **ne** fetchuje celou kartu do chatu zbytečně — na to je `get_cliente`.

Povolené routy: `/inbox`, `/clientes/:id`, `/clientes/:id/carpeta`, `/clientes/:id/carpeta/:bloque`, `/inmuebles/:id`, `/expedientes/:id`. Nic v Support app.

### 2.3 `get_cliente`

Read-only snapshot karty + bloky + díry. Pro kontext „co chybí“. PII jde do modelu — audit `ai.read.cliente`.

### 2.4 `prefill_form`

```json
{
  "name": "prefill_form",
  "parameters": {
    "target": "cliente | inmueble | bloque | expediente",
    "id": "uuid?",
    "bloque_key": "string?",
    "fields": { "type": "object" },
    "enable_blocks": { "type": "array", "items": { "type": "string" } }
  }
}
```

Výsledek do UI: `{ "type": "prefill", "draft_id": "uuid", "fields": … }`.  
**Žádný INSERT/UPDATE v DB.** Draft žije v `ai_drafts` (TTL 24 h, soft-delete). Gestor vidí diff a klikne Guardar.

`enable_blocks` jen navrhne zapnutí (`agua`, `luz`, …). Guardar zapíše `bloque` + audit `bloque.enabled` jako akci uživatele, ne AI.

### 2.5 `extract_document`

Vstup: `attachment_id` v Storage. Vision/OCR → strukturovaný JSON podle cíle (`dni_nie`, `escritura`, `contrato_luz`, `folder_scan`).

Výstup vždy končí jako `prefill` draft, ne jako uložený klient. Gestor na desce klikne Guardar → `documentos.extracted` + pole bloku. Pak `ai_get_cliente` umí říct, kdy končí pas.

Příklad extract NIE:

```json
{
  "kind": "nie",
  "value": "Y123456E",
  "checksum": "valid",
  "nombre": "…",
  "confidence": 0.92
}
```

Maskované OCR (`Y123**6E`) se předá search, ne „oprava“ na plné číslo bez kandidáta.

### 2.6 `draft_message`

```json
{
  "name": "draft_message",
  "parameters": {
    "cliente_id": "uuid",
    "template_key": "falta_documento | faltan_datos | recordatorio | vencido",
    "bloque_key": "string?",
    "body_override": "string?"
  }
}
```

Vytvoří `mensajes.status = draft` **nebo** jen vrátí text do UI (preferovat zápis draftu, ať to gestor jen odešle). `sent_at` zůstane null. Tool `send_message` **neexistuje**.

Při odeslání člověkem: do kanálu jde překlad (`clientes.locale`), originál v `cuerpo`. AI ten krok nesmí spustit.

### 2.7 `search_document_text`

Read-only fulltext v `documentos.body_text` (RPC stejného jména). Limit 20, tenant RLS. Prázdný přepis ≠ „ve smlouvě to není“. `open_screen` na `/clientes/{id}/carpeta/{bloque}`. Žádný pgvector.

## 3. Zakázané tools (nesmí být v schématu)

- `save_*`, `update_*`, `insert_*`, `upsert_*`
- `delete_*`, `soft_delete_*`
- `send_message`, `send_email`, `send_whatsapp`
- `execute_sql`
- `impersonate`
- cokoliv na jiný tenant

Pokud model „chce uložit“, runtime odpoví: navrhnout `prefill_form` a říct uživateli, ať klikne Guardar.

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

Side-effects:

| Event | Klient |
| --- | --- |
| `navigate` | `context.go(route)` |
| `prefill` | otevři formulář, vyplň, badge „Propuesta IA“ |
| `draft_message` | otevři editor zprávy |

Guardar / Eliminar / Enviar jsou běžné use-casy mimo AI.
