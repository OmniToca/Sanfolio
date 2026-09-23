# Plán: dokumenty, přepis, asistent kanceláře

Smlouva z rozhovoru 12. 9. 2026. Kód se k tomuto souboru chová jako k migraci: změna pořadí nebo rozsahu = změna tohoto souboru ve stejném PR.

**Cíl:** složka zůstane papír. Originál je sken. Přepis (pole + text) je to, čemu věří hledání a asistent. Chat umí odpovídat na otázky **kanceláře** (dodavatel, konce smluv), ne jen otevřené karty. Vektory až na hledání věty, která na desce záměrně není.

**Není v tomto plánu:** OneDrive / SharePoint, PDF uložené jako JPG, WhatsApp API, klientská zóna, renta/303/AEAT XML, JSON page-builder.

Vzory z LeoDejvIT bereme **ingest dlouhého PDF** (originál + text stránek + index na pozadí). Nepřenášíme globální knihovnu norem, offline cache ani pgvector v první vlně.

---

## Tři vrstvy dokumentu (vždy)

Jeden řádek `documentos` = jedna věc ve složce.

| Vrstva | Co | Kdo věří |
| --- | --- | --- |
| Originál | Soubor jak přišel (PDF nebo fotka) | Úřad, notář, gestor |
| Přepis | `extracted` (pole po Guardar) + později `body_text` | Hledání, asistent, inbox, lhůty |
| Pracovní kopie | Dočasný rastr stránky jen uvnitř `extract-document` | Nikdo. Po extracti zmizí |

AI navrhne. Gestor uloží. Řádek v DB se nemaže natvrdo. Blob ve Storage až při vysypání koše.

Průkaz (1 strana) → pole JSON, rastr jen v paměti serveru.  
Escritura / smlouva → PDF beze změny + hlavička polí + plný text se značkami stran.

---

## Jak postupujeme

Jedna fáze = jeden sloučitelný kus na `main` (commit / PR), pak ověření na [sanfolio-os.netlify.app](https://sanfolio-os.netlify.app). Další fázi nezačínáme, dokud předchozí drží na webu.

1. Před kódem: tento soubor + `slovnik_modulu.md` + `database_schema.md`.
2. SQL a změna chování = stejný PR jako `docs/`.
3. Brána: `cd apps/gestoria && flutter test` (nebo analyze) bez červených.
4. i18n `cs/en/es/de/fr`. Žádný hardcoded UI text.
5. AI pořád jen search / open / prefill / extract. Žádný save / delete / send.
6. Peníze cents, ID UUID, čas UTC / termíny `date` Madrid.
7. Po nasazení Edge Function ověřit extract i chat na kartě Petra, ne jen screenshot.

Rozhodnutí, která už platí a neotevíráme je znovu:

- Soft-delete řádků, append-only audit.
- Jedna cesta souboru, ne `card/` i `ai/`.
- Office-wide otázky = SQL nad poli desky a `plazos`, ne embedding.
- Vektory až fáze F (věta napříč smlouvami).
- Koš nemaže originál tichým křížkem.

---

## Stav teď (neplánovat znovu)

Hotovo A–G v kódu (2026-09-13): jedna cesta nahrání, přepis|originál, `body_text`, koš, office-wide RPC, otevřený blok, extract na pozadí (pending `ai_drafts`). F = Postgres fulltext v `body_text`, bez pgvector. Edge timeout u obřího PDF (~60 s) zůstává — waitUntil drží isolate, ne UI. Escritura: extract páruje kupujícího s kartou (ne první compareciente / prodávající). Spoluvlastníci (cuota, 210) = [roadmap_titulares.md](roadmap_titulares.md), ne `client_contacts`.

---

## Fáze A — Jedna cesta, stejná pole

**Proč první:** bez toho každou další vrstvu stavíme na duplicitách a rozbitých klíčích.

- Nahrání karty i desky i extract z chatu → `{tenant}/{cliente}/{uuid}_{název}`.
- Sjednotit klíče bloků s DB (`proveedor` / `compania` / `fecha_vencimiento` vs. i18n `fields.*`) tak, aby Guardar, `recompute_bloque_status` a pozdější RPC četly totéž.
- Žádné mazání existujících blobů v této fázi (jen přestat vyrábět nové dvojice).

Hotovo když: nový NIE na kartě = jeden objekt ve Storage; pole luz/seguro po Guardar sedí na bloku i v `extracted`.

---

## Fáze B — Obrazovka přepis | originál

**Proč:** asistent a ty máte věřit řádku v DB, ne žlutému pruhu.

- Na kartě i na desce: dokument otevře **přepis** (uložená pole), vedle **originál** (signed URL).
- Žlutý návrh zůstane jen než klikneš Uložit návrh.
- Prázdný přepis = „ještě neuloženo“, ne tichá prázdnota.

Hotovo když: u Petra jde otevřít NIE jako pole + soubor, bez druhého nahrání.

---

## Fáze C — Dlouhé PDF jako v Leo (bez vektorů)

**Proč:** escritura není občanka.

- `extract-document`: u PDF nejdřív textová vrstva (stránky `--- Strana n/N ---`), vision jen když text nestačí nebo je to průkaz.
- Návrh obsahuje pole **a** `body_text`. Guardar zapíše obojí (`extracted` + sloupec / klíč v JSONB — rozhodnout v migraci, zapsat do `database_schema.md`).
- Extract na pozadí: HTTP vrátí pending draft hned; LLM doběhne přes `EdgeRuntime.waitUntil`. UI se neodblokuje až po minutě. Bez waitUntil isolát může extract useknout (~60 s u obřího PDF).
- Rastr JPEG **neukládat** do bucketu.

Hotovo když: nahrání vícestránkového PDF uloží originál + po Guardar čitelný text; chat u otevřené karty umí „je v této smlouvě …“ z přepisu, ne z binárky.

---

## Fáze D — Koš uvolní místo

**Proč:** řádek = audit; gigabajty = blob.

- Schovat = `deleted_at` (obnova možná).
- Vysypat koš (owner, potvrzení) = smazat objekt ve Storage. Řádek, audit a přepis zůstanou.
- U `copia_escritura` / daňových papírů varování, že originál nejde obnovit.
- Volitelně později: grace 30 dní. Ne v prvním PR této fáze, pokud stačí ruční vysypání.

Hotovo když: schovaný testovací sken zmizí z bucketu až po vysypání; karta vysypaný řádek neschovává (přepis + audit zůstanou). Koš na kartě bere i papíry schované ze složky (`bloque_id`).

---

## Fáze E — Asistent kanceláře (SQL, ne RAG)

**Proč:** „kolik máme u Iberdrola“ / „komu končí seguro za 3 měsíce“ / „které escritura od tohoto notáře“.

Nejdřív Edge `ai-assistant` podle [ai_contract.md](ai_contract.md) (whitelist tools, audit `ai.tool`, žádný zápis). Pak **nové read-only tools** (názvy pracovní):

| Tool | Otázka | Zdroj |
| --- | --- | --- |
| `query_suministro` | kdo má elektřinu/vodu/plyn od společnosti X | `bloques.fields` u `luz` / `agua` / `gaz` |
| `query_plazos` | komu končí pojištění / alarm / poder v intervalu | `plazos` + `seguro_warn_days` stejná logika jako inbox |
| `query_escritura` | které smlouvy mají tohoto notáře, právníka, catastral nebo stranu | blok `escritura` + `documentos.extracted` |

Pravidla:

- Filtr vždy `tenant_id` + `deleted_at IS NULL`. Limit (např. 20) + počet celkem. Žádný `execute_sql`.
- Odpověď = jména + odkaz `open_screen`. Model nedostane všechny složky do promptu.
- Prázdné pole ≠ „nemáme Iberdrola“. Říct, že na desce to není vyplněné.
- Pole `despacho` / zdroj papíru jen když notář nestačí — malý katalog, ne vektor.

Hotovo když: na Netlify, bez otevřené karty, chat vypíše klienty s končícím seguro a umí otevřít jejich desku. Nic neuloží.

---

## Fáze G — Otevřený blok = šanon papírů

**Proč:** deska jsou dva listy (identita). Patnáct faktur za vodu tam nepatří. Únik (229 €, pak 2 966 €) je vidět jen ve stohu dokladů, ne v poli CUPS. Žádná tabulka `invoice_lines` — jeden `documentos` = jeden papír.

- Route `/clientes/:id/carpeta/:bloqueKey` (query `exp` jako deska).
- Na deskách: klient zůstane tužkou; ostatní zapnuté bloky jsou **kryt** (chip, 1–3 pole, počet dokladů) a otevřou šanon.
- Uvnitř: stejná tužka identity + přiložit + papíry řazené od nejnovější. Faktura ukáže období od–do a částku. Přehled stohu sečte kladné faktury (dobropis ne). Identita (CUPS, smlouva) se na papíře neopakuje.
- Guardar z faktury povýší na desku jen klíče šablony (company, CUPS, contrato…), ne `amount` / `periodFrom`.
- AI navigate: `/clientes/{id}/carpeta/luz`.
- **Není v G:** výkyv vs. medián, portál klienta, scrap Hidraqua, srovnání tarifů.

Hotovo když: klik na Vodu u Petra otevře šanon; deska zůstane tenká; `facturas-5.pdf` je `factura_agua` a po Guardar sedí číslo smlouvy na desce, částka na dokladu.

---

## Fáze F — Hledání věty (fulltext, bez vektorů)

Hotovo v kódu (2026-09-13): GIN + RPC `search_document_text`, tool v `ai-assistant`. Prázdný přepis ≠ „ve smlouvě to není“.

1. Fulltext v Postgres (`body_text`, tenant RLS) — „arras“, „cláusula“.
2. pgvector `documento_chunks` (Leo-style kousky, vždy `tenant_id`) — lidská otázka („má kauci?“) bez přesného slova. Hybrid v `ai-assistant`. Stejné kousky bere extract jako vzory kanceláře (`similar_placed_papers`): další sken se učí z už zařazených papírů, ne z dotrénovaného modelu.

Hotovo když: „ve které smlouvě je arras / kauci?“ vrátí klienta + citaci + otevře šanon.

---

## Pořadí závislostí

```
A (cesta + klíče)
 └─ B (přepis | originál)
     └─ C (text PDF)
         ├─ D (koš Storage)     ← může jít souběžně s E, ne před A
         ├─ E (chat kanceláře)  ← potřebuje A; C jen pro otázky z textu
         ├─ G (otevřený blok / stoh faktur) ← po A; extract polí faktury
         └─ F (fulltext / vektory) ← jen po C a až je přepis smluv
```

E lze začít, jakmile A sjednotí pole — pojištění a dodavatel nečekají na OCR smluv.

---

## Ověření u design partnera

Po E, na reálných (nebo anonymizovaných) složkách Jarky:

- 1× luz s vyplněnou společností → počet sedí.
- 1× seguro s datem → inbox i chat stejní lidé.
- 1× escritura PDF → přepis + originál, chat necituje vymyšlenou doložku.

Když pole na desce nejsou, neopravujeme to vektorem — vyplní se tužkou.
