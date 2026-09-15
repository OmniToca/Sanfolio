# Motor termínů a chybějících dokumentů

Po naplnění složky systém **šilhá dopředu**: inbox ráno, návrh výzvy klientovi, odesílá gestor.

## 1. Co inbox ukazuje

Řazení: `overdue` → `due_today` → `due_soon` → `missing_document` → `missing_data` → `provision_alert` → `stale_expediente`.

| Druh | Zdroj |
| --- | --- |
| Termín | `plazos.due_on` + stav bloku ≠ `off` |
| Díra dokumentu | blok `missing_document` |
| Díra dat | blok `missing_data` |
| Záloha | `saldo <= 0` a spis otevřený, nebo spis `hecho` a `facturado = 0` |
| Zastaralý spis | `en_curso` bez `updated_at` novějšího než N dní (`tenant_settings.stale_expediente_days`, default 14, 0 = vypnuto) |

Každý řádek inboxu: klient, inmueble, bloque/expediente, due_on, akce (`abrir`, `borrador_mensaje`).

## 2. Odvozená pravidla (MVP)

Časy v zóně **Europe/Madrid**. `due_on` je `date` (ne timestamp), ať nerrozbije DST.

| `kind` | Spouštěč | `due_on` | Offset |
| --- | --- | --- | --- |
| `plusvalia_plazo` | blok `plusvalia` zapnut + `escritura_fecha` | fecha + `tenant_settings.plusvalia_days` | `plazo_offsets.plusvalia_plazo` |
| `ibi_anual` | blok `suma` zapnut + `periodo` rok | `tenant_settings.ibi_due_month` + `ibi_due_day` (NULL = bez plazos, žádné 1. 11.) | `ibi_warn_days` |
| `seguro_renovacion` | `fecha_vencimiento` | to datum | `seguro_warn_days` |
| `alarma_renovacion` | `fecha_vencimiento` | to datum | `alarma_warn_days` |
| `poder_caducidad` | `fecha_caducidad` | to datum | `poder_warn_days` |
| `nie_caducidad` | `nie_caducidad` | to datum | `plazo_offsets.nie_caducidad` |
| `cita_nie` | `fecha_cita` | to datum | `plazo_offsets.cita_nie` |
| `cita_tramite` | `fields.appointment` u policia / ayuntamiento / testament | to datum, když stav `cita` | žádný hardcoded offset |
| `modelo_210` | periodicidad + periodo | z `tenant_settings` (čtvrtletně i ročně) | `plazo_offsets.modelo_210` |
| `renta` | ejercicio | z `tenant_settings` (v dotazníku prázdné) | `plazo_offsets.renta` |

Žádné dny v kódu. Defaulty v SQL (`plusvalia_days = 30`, warn 60) jsou start; Gestorie Jarka je mění v Nastavení.

Přepočet: trigger na změně zdrojového pole smaže jen `source = derived` a `status != done` stejného `kind` a vloží nový plazo. Ruční plazo (`source = manual`, RPC `add_manual_plazo`) se netýká. Odklad `snooze_until` (RPC `snooze_plazo`) řádek schová z inboxu a cronu, `due_on` nemění.

`presentado_at` / blok `done` → plazo `completed_at = now()`, zmizí z inboxu.

## 3. Připomínky nejsou spam

Tabulka `plazo_reminders` (`plazo_id`, `offset_days`, `fired_at`). Cron denně 07:00 Madrid (`run_plazo_reminders`, pg_cron 05:00+06:00 UTC s hradlem na hodinu 7, nebo Edge Function `plazo-reminders`):

1. Najdi živé plazos s `due_on - offset IN (today)` a ještě `fired_at IS NULL`.
2. Vytvoř `mensajes` status `draft` (ne `sent`).
3. Označ reminder fired.
4. Řádek inboxu existuje nezávisle na zprávě.

Když klientovi chybí e-mail i telefon, draft se nevytvoří; inbox zůstane s příznakem `sin_canal`.

Opakované denní „po splatnosti“: jeden draft typu `overdue` na plazo, dokud gestor neodešle nebo neskryje (`snooze_until`).

## 4. Chybějící dokumenty

Nejsou plazo. Jsou to bloky ve `missing_document` / `missing_data`.

Cron **nevytváří** nový draft každý den. Draft „faltan documentos“ vznikne:

- když blok poprvé spadne do `missing_document` / `missing_data`, nebo
- když gestor v inboxu klikne „Pedir al cliente“.

Po kliknutí **Pedir al cliente**: `last_requested_at` + `mensajes` status `draft`. Gestor odesílá z compose. AI nesmí odeslat. Další Pedir až po `tenant_settings.nudge_interval_days` (default 7). Klient bez e-mailu i telefonu = `sin_canal`, draft nevznikne.

## 5. Šablony ES (MVP)

Proměnné: `{{nombre}}`, `{{bloque}}`, `{{documento}}`, `{{fecha}}`, `{{despacho}}`, `{{inmueble}}`.

Gestor vidí náhled, smí text upravit, pak Odeslat. AI smí navrhnout úpravu přes `draft_message`, ne odeslat.

### 5.1 Falta documento

Asunto: `Documentación pendiente — {{inmueble}}`

```
Hola {{nombre}},

Para seguir con su expediente nos falta: {{documento}} ({{bloque}}).
Puede responder a este correo con una foto nítida o un PDF.

Gracias,
{{despacho}}
```

### 5.2 Faltan datos

Asunto: `Datos pendientes — {{bloque}}`

```
Hola {{nombre}},

Necesitamos completar {{bloque}}. En concreto: {{campos_faltantes}}.

Gracias,
{{despacho}}
```

### 5.3 Recordatorio plazo

Asunto: `Recordatorio: {{bloque}} — {{fecha}}`

```
Hola {{nombre}},

Le recordamos el plazo de {{bloque}} con fecha {{fecha}}
(inmueble: {{inmueble}}).

Si ya lo tiene resuelto, ignore este mensaje o envíenos el justificante.

{{despacho}}
```

### 5.4 Vencido

Asunto: `Plazo vencido — {{bloque}}`

```
Hola {{nombre}},

El plazo de {{bloque}} ({{fecha}}) ya ha vencido. Contacte con nosotros
lo antes posible para evitar recargos.

{{despacho}}
```

### 5.5 Poder / seguro / NIE caducidad

Stejné tělo jako 5.3 s konkrétním `{{bloque}}`.

## 6. Odeslání

MVP: Edge Function `send_client_message` (Resend nebo SMTP). Volá ji **jen** authenticated gestor po kliknutí, ne cron, ne AI. Do doby, než existuje, compose otvírá `mailto:` a do `Reply-To` dává plus-adresu složky (`posta_accounts.ingest_local+{cliente_id}@…`), aby odpověď s PDF spadla do `/posta` na stejného klienta.

`tenant_settings.send_translated_outbound = true` (Gestorie Jarka): do e-mailu / WhatsApp jde **překlad** v `clientes.locale`. Originál (`mensajes.cuerpo` + `locale_original`) zůstane ve spisu a později v klientské zóně vedle překladu. Překlad se uloží jednou do `mensajes.translations`.

Gestor píše španělsky; překlad do jazyka klienta běží při odeslání.

Log: `mensajes` + `audit_logs` action `message.sent`. Soft-delete zprávy ji schová, audit zůstane.

Tlačítko **Copiar para WhatsApp** dá do schránky **odesílané** tělo (překlad). To je oficiální MVP kanál č. 2 bez API. Kanály, když chybí papír: WhatsApp, e-mail, telefon, osobně.

## 7. Co motor nesmí

- Sám odeslat e-mail nebo WhatsApp
- Smazat plazo
- Měnit blok na `off`
- Podávat daň (210 / renta) — 210 se spočítá na desce, podání AEAT ne; renta zatím datum + checklist
