# Šablona složky (tužka → bloky)

Převod dvou tištěných listů a náčrtu služeb na stavy, pole a dokumenty.  
Hodnoty označené **ověřit u šanonu** jsou pracovní default; kancelář je může opravit bez změny stroje stavů.

## 1. Stroj stavů bloku

```
off ──(gestor zapne)──► missing_data
                          │
                          │ povinná pole vyplněna
                          ▼
                    missing_document ──(není povinný dokument)──► watching nebo done
                          │
                          │ povinný dokument nahrán
                          ▼
                    watching ──(žádný budoucí plazo)──► done
                          │
                          │ termín minulý
                          ▼
                    overdue (odvozený UI stav watching + due_on < today)
```

| Stav v DB | UI ES | Význam papíru |
| --- | --- | --- |
| `off` | No aplica | Tužka nebyla. Inbox ignoruje. |
| `missing_data` | Faltan datos | Zapnuto, prázdné povinné pole. |
| `missing_document` | Falta documento | Pole ok, chybí povinný sken. |
| `watching` | En seguimiento | Kompletní, existuje budoucí plazo. |
| `done` | Hecho | Kompletní, není co hlídat. |
| `overdue` | Vencido | Není uložený stav; počítá se z `watching` + `due_on`. |

Přechod `off` → zapnuto zapisuje audit `bloque.enabled`. Vypnutí zapisuje `bloque.disabled` a **nemaže** pole ani dokumenty (soft, zůstanou pro obnovení).

Odvození běží v Postgres funkci `recompute_bloque_status(bloque_id)` po UPDATE polí, INSERT dokumentu, změně plazo. Klient stav nepočítá.

## 2. Šablony expedientes vs. deska

Tištěné dva listy = výchozí šablona `compraventa` (koupě/prodej + napojení nemovitosti).  
Stejné bloky energií lze zapnout i u `suministros_seguros`, pokud kancelář řeší jen přepis.

Compraventa se **čte v čase**, i když je seznam bloků rovný. Před notářem: identita (`cliente_snapshot`, `nie_tramite`, `poder`), IBI (`suma`), dodávky, komunita, případně cédula / residencia až budou v katalogu. U notáře: `escritura`. Po: `plusvalia` (a 210 na tenkém spisu), přepis energií. Kontrola chybějícího papíru je stav bloku, ne druhá evidence. Proč: [product_bible.md](product_bible.md) (poučení z velkých despachos).

Tisk z desky (`folder.print`) je zpátky na ty dva listy: HTML A4 v prohlížeči, stejné časové pořadí. `tenant_settings.slot_order` řadí jen obrazovku, ne výtisk. PDF uloží gestor z dialogu tisku.

| Šablona | Bloky v pořadí papíru |
| --- | --- |
| `compraventa` | `cliente_snapshot`, `escritura`, `agua`, `luz`, `gaz`, `comunidad`, `suma`, `plusvalia`, `seguro`, `provision_factura`, `alarma`, `nie_tramite`, `poder` |
| `impuestos_ibi` | `suma` (+ checklist IBI) |
| `impuestos_210` | `modelo_210` |
| `impuestos_renta` | `renta` |
| `nie_tramite` | `nie_tramite` |
| `poder` | `poder` |

`cliente_snapshot` na desce není druhý klient: je to **zobrazení** povinných kontaktů na spisu. Data žijí na `clientes`. Blok je `done`, když klient má jméno; identifikátor (NIE/DNI/pas) **není** podmínka založení (Gestorie Jarka: první úkon může být „vyřídit NIE“). `missing_data` jen když zapnutý blok má prázdné povinné pole jinde, ne proto, že NIE chybí.

Pořadí bloků na desce je `tenant_settings.slot_order` (`carpeta.blocks`), ne pořadí v kódu.

## 3. Bloky z tisku

U každého bloku: povinná pole při stavu ≠ `off`, povinné typy dokumentů, plazo.

### 3.1 `cliente_snapshot` — CLIENTE

Tužka na papíře u CLIENTE = tento spis je aktivní zakázka. V systému se tím otevře expediente; karta klienta vznikne/přiřadí se.

| Pole (na klientovi) | Povinné | Dokument |
| --- | --- | --- |
| Jméno | ano | — |
| NIE/DNI/NIF | ne | Kancelář často začíná bez NIE. Masky z úřadu (`Y123**6E`) se ukládají. |
| email | ne, ale bez něj nejde odeslat e-mail | — |
| tel | ne | WhatsApp / telefon |
| direccion | ne | — |
| iban | ne | povinný **jen** když je inkaso |
| druhý kontakt | ne | `client_contacts` + `locale` (občas partner / překladatel). Spoluvlastník sem ne. |

Plazo: žádné.  
Inbox: klient bez e-mailu i telefonu + existuje `missing_document` jinde → kanál `none` (nelze poslat, jen úkol kanceláři).

### 3.2 `escritura` — ESCRITURA

| Pole | Povinné | Poznámka |
| --- | --- | --- |
| `notario` | ne | **ověřit u šanonu** |
| `escritura_fecha` | ano pokud je zapnutá plusvalía | Spouštěč lhůty |
| `protocolo` | ne | |

Dokument: `copia_escritura` obvykle (Gestorie Jarka: většinou ve složce).  
U notářské compraventy extract bere **všechny** prodávající a **všechny** skutečné kupující (zastoupení cónyuges, ne zmocněnce), cenu (`precio de esta compraventa`, ne valor de referencia ani hypotéku), catastral, parcelu, registro, právníka/despacho a notáře. Klient kanceláře je jen jeden z nich — ať jde 210 / plusvalía spočítat z papíru, ne z první strany PDF. Věta v 40stranové smlouvě = `search_document_text` (uložený `body_text`). Notář / Zenia / catastral napříč kanceláří = `query_escritura`.  
`referencia_catastral` na inmueble: většinou; po Guardar listiny se doplní z přepisu.  
Kupující/prodávající po Guardar (fáze T2+) jdou do `inmueble_titulares` (cuota, NIE), ne do `client_contacts`. Kupující s NIE dostane **kartu** (hledání, e-mail), ne druhou desku. Default stejný díl mezi kupujícími; gananciales se nehádají z českého režimu. Tužka na šanonu ESCRITURA opraví %. 210 čte `sharePercent` z titulare tohoto klienta — [roadmap_titulares.md](roadmap_titulares.md).  
Plazo: žádné vlastní. Zapnutá plusvalía odvodí lhůtu z `escritura_fecha` + `tenant_settings.plusvalia_days`.

### 3.3 `agua` / `luz` / `gaz` / `comunidad`

Stejný tvar, jiný katalog dokumentu a volitelné pole sítě.

| Pole | Povinné | Agua | Luz / Gaz | Comunidad |
| --- | --- | --- | --- | --- |
| `proveedor` | ano | Compañía | Comercializadora | Administrador |
| `numero_cliente` | ano u vody | číslo klienta (i z faktury) | — | — |
| `numero_contrato` | ne u dodávky | z faktury, když tam je | dtto | Ref. comunidad / účet |
| `cups` | ano u luz/gaz | — | **CUPS** (i z faktury) | — |
| `titular` | ano | Kdo platí / je na faktuře | dtto | dtto |
| `fecha_alta` | ne | Změna titulu | dtto | dtto |

| Blok | Povinné dokumenty | Režim |
| --- | --- | --- |
| `agua` | `contrato_agua` / `factura_agua` / `recibo_agua` | **stačí jeden** — kancelář často nemá smlouvu, identita je na faktuře |
| `luz` | `contrato_luz` / `factura_luz` | **stačí jeden** |
| `gaz` | `contrato_gaz` / `factura_gaz` | **stačí jeden** |
| `comunidad` | `certificado_comunidad` (správce, účet, papír) | všechny |

Přepis dokladu a tužka na desce se neslévají. Faktura má v `documentos.extracted` číslo, datum vystavení, období od–do, spotřebu, částku. Na blok jdou jen identita (compañía, contrato, CUPS / číslo klienta, titular). `fields.period` je rok IBI, ne období faktury. Stoh `/clientes/:id/carpeta/:bloque` ukáže součet kladných faktur, poslední období, **efektivní €/kWh (m³)** a hrubý roční odhad z poslední faktury s obdobím — ne OCR dump. Dobropis (zápor) do součtu ne. Vodu a komunitu kancelář nesrovnává s nabídkami (často jedna síť). Obecní voda ve Španělsku je skoro vždy **trimestral**; když OCR uloží jen jeden měsíc, roční odhad se počítá z 91 dní, ne z 28.

Modul `ofertas` na bloku `luz` / `gaz` ukáže „u vás teď ~X €/rok · nabídka Y ~Z €/rok“ z `office_offers`. Tlačítko Nachystat výzvu otevře compose; AI nic neodešle ani nepřepne smlouvu. Inbox `/preplatek` seřadí klienty, kteří z **uložených** faktur platí víc než tarif kanceláře. Inbox `/kampane` seřadí otevřené 210 bez podání a koupě s `escritura_fecha`, kde ještě běží plusvalía, díra na dodávce, nebo čerstvá koupě (90 dní) bez 210. Tam je i IBI/SUMA (chybí `recibo_ibi` nebo plazo v okně z Nastavení) a kampaň expirací (DNI / pas / poder / seguro, stejné okno jako chip na kartě). Hromadný Pedir nachystá drafty; odesílá gestor. Inbox `/kanal` seřadí karty, na které Pedir bez kanálu nedosáhne.

Plazo: v MVP žádné, pokud kancelář nedoplní datum obnovy. Stav po kompletnosti = `done`.

### 3.4 `suma` — SUMA / IBI

V Alicante: [Suma Gestión Tributaria](https://www.suma.es/). Není dodavatel energie.

| Pole | Povinné |
| --- | --- |
| `identificacion_suma` | ano | číslo z dopisu SUMA |
| `referencia_catastral` | většinou (na inmueble) |
| `numero_recibo` | ne |
| `domiciliado` | ano (bool, default false) |
| `periodo` | ano pokud `watching` — rok IBI |

Dokument: `recibo_ibi`.  
Plazo: `ibi_anual` — datum a dny upozornění **jen** z `tenant_settings` (žádné zadrátované 1. 11.).

Stejný blok používá expediente `impuestos_ibi`.

### 3.5 `plusvalia`

| Pole | Povinné |
| --- | --- |
| `organismo` | ne (SUMA vs. ayuntamiento) |
| `importe_cents` | ne |
| `presentado_at` | ne — vyplnění → `done` |

Dokument: `declaracion_plusvalia` povinný dokud není `presentado_at`.  
Plazo: `plusvalia_plazo` = `escritura_fecha` + `tenant_settings.plusvalia_days` (default 30, kancelář mění v Nastavení). Připomínky z `plazo_offsets`. Po `presentado_at` plazo `done`.

### 3.6 `seguro`

| Pole | Povinné |
| --- | --- |
| `compania` | ano |
| `numero_poliza` | ano |
| `fecha_vencimiento` | ano |

Dokument: `poliza_seguro`.  
Na dokladu po Guardar i `fields.amount` (prémie) a volitelně období krytí. Na desku jdou dál jen compañía / póliza / vencimiento. Modul `ofertas` srovná prémii s `office_offers.kind=seguro`.  
Plazo: `seguro_renovacion` = `fecha_vencimiento`. Offset z `tenant_settings.seguro_warn_days`.

### 3.7 `provision_factura` — PROVISION DE FONDOS Y FACTURA

| Pole | Povinné |
| --- | --- |
| `recibido_cents` | ne (0 = zatím nic) |
| `facturado_cents` | ne |

Dokumenty: `justificante_ingreso` pokud `recibido > 0`; `factura_honorarios` pokud `facturado > 0`.  
Plazo: žádné datum. Inbox pravidlo viz bible §11: práce hotová a `facturado = 0`, nebo `saldo <= 0` při otevřeném spisu.

### 3.8 `alarma`

Stejné jako seguro: `compania`, `numero_contrato`, `fecha_vencimiento`, dokument `contrato_alarma`. Offset z `tenant_settings.alarma_warn_days`.

### 3.9 `nie_tramite` — EXTRAS NIE

Samostatný úkol, ne jen pole NIE na kartě klienta.

| Pole | Povinné |
| --- | --- |
| `estado_tramite` | ano | `cita` \| `presentado` \| `resuelto` \| `rechazado` |
| `fecha_cita` | pokud stav `cita` |
| `nie_caducidad` | pokud už NIE existuje |

Dokument: `pasaporte`, `justificante_cita` podle stavu.  
Plazo: `cita_nie` z `fecha_cita`; `nie_caducidad` z data na kartě. Offsety z `tenant_settings.plazo_offsets`.

### 3.10 `poder` — EXTRAS PODER

| Pole | Povinné |
| --- | --- |
| `notario` | ne |
| `apoderado` | ano (kdo je zmocněnec — často kancelář) |
| `fecha_poder` | ne |
| `fecha_caducidad` | ano — konec platnosti **individuálně** (per poder / kancelář) |

Dokument: `copia_poder` povinný.  
Plazo: `poder_caducidad`. Offset z `tenant_settings.poder_warn_days`. Propadlý poder = `overdue` a varování, že kancelář nemá jednat za klienta.

## 4. Daňové bloky mimo tisk (náčrt Impuestos)

### 4.1 `modelo_210`

| Pole | Povinné |
| --- | --- |
| `periodicidad` | ano | `trimestral` \| `anual` |
| `periodo` | ano | např. `2026-Q1` |
| `incomeKind` | ano | `imputacion` (02) \| `alquiler` (01/35) \| `transmision` (28) |
| `taxResidency` | ano | `ue` (19 %) \| `other` (24 %; UK po Brexitu) |
| `presentado_at` | ne |
| `address` / `cadastral` / `sumaId` | ne | z navázaného `inmueble` |
| `sharePercent` | výpočet | z `inmueble_titulares.cuota_bps` tohoto klienta; prázdné = 100 |

Další pole podle druhu (jinak by se míchal nájem s imputací): valor catastral a sazba 1,1/2 %; nájemné a výdaje; cena prodeje a modelo 211. Peníze v centech. Formule `irnr-210-2026.1` v `modelo_210.dart`.

Gestor uloží číslo. Systém **nepodává** na AEAT. Za správnost kliknutí Uložit ručí člověk.

Inbox `/kampane` seřadí otevřené 210 **bez data podání**: období, termín, chybějící papíry. Nachystat výzvu otevře compose. Hromadný Pedir nachystá drafty najednou; odesílá gestor.

Dokumenty: povinné sloty (`escritura_o_nota_simple`, `recibo_ibi`, `certificado_catastral`); DNI volitelně. Spis se naváže na `inmuebles`.  
Plazo: z `tenant_settings` podle `periodicidad`.

Tenký spis **není** druhá tištěná carpeta. Na `/expedientes/:id` má desku úkonu: klient, nemovitost, pole, výpočet, checklist papírů.

### 4.2 `renta`

| Pole | Povinné |
| --- | --- |
| `ejercicio` | ano | rok |
| `presentado_at` | ne |

Dokument: `borrador_renta` / DNI nejsou povinné.  
Plazo: jen nastavitelné v `tenant_settings` (v dotazníku prázdné).

Výpočet renta / IRPF a XML AEAT = mimo rozsah. 210 na desce počítá IRNR; renta zatím hlídá datum.

## 5. Katalog dokumentů (MVP)

| `tipo` | ES popisek |
| --- | --- |
| `dni_nie` | DNI / NIE |
| `pasaporte` | Pasaporte |
| `copia_escritura` | Copia de la escritura |
| `contrato_agua` | Contrato de agua |
| `factura_agua` | Factura de agua |
| `recibo_agua` | Recibo de agua |
| `contrato_luz` | Contrato de luz |
| `factura_luz` | Factura de luz |
| `contrato_gaz` | Contrato de gas |
| `factura_gaz` | Factura de gas |
| `certificado_comunidad` | Certificado / recibo comunidad |
| `recibo_ibi` | Recibo IBI / SUMA |
| `declaracion_plusvalia` | Declaración plusvalía |
| `poliza_seguro` | Póliza de seguro |
| `contrato_alarma` | Contrato de alarma |
| `justificante_ingreso` | Justificante provisión |
| `factura_honorarios` | Factura de honorarios |
| `justificante_cita` | Justificante de cita |
| `copia_poder` | Copia del poder |
| `otro` | Otro |

Nový typ se přidává jen migrací katalogu, ne volným stringem v UI (kromě `otro` + `titulo_libre`).

## 5b. Stoh ze šanonu

Po založení klienta (a kdykoli ze složky) jde `/clientes/:id/stoh`. Soubory padají na `documentos` **bez** `bloque_id` (`{tenant}/{cliente}/stoh/…`). Extract s `classify` navrhne `proposed_bloque_key` + `proposed_tipo`. Guardar přiřadí blok, zapne ho když byl `off`, zapíše `extracted`. AI neukládá. Jeden soubor = jeden papír (PDF se nedělí). `/prepis` bere jen extract, který už blok má.

## 6. Další služby (Gestorie Jarka je dělá)

Moduly `policia`, `ayuntamiento`, `testament` jsou zapnuté. **Tenký spis** (jako NIE extras): stav úkonu + cita + papír. Ne dva tištěné listy — kancelář je zatím nemá.

| Šablona | Pole | Dokumenty | Plazo |
| --- | --- | --- | --- |
| `policia` | `tramiteStatus`, `appointment`, `authority`, `docNumber`, `notes` | `justificante_cita` (+ DNI volitelně) | `cita_tramite` když stav `cita` |
| `ayuntamiento` | totéž + navázání inmueble | `justificante_cita` (+ DNI volitelně) | totéž |
| `testament` | `tramiteStatus`, `appointment`, `notary`, `date`, `notes` + inmueble | `copia_escritura` nebo `justificante_cita` (`any`) | totéž |

Stroj stavů stejný. Žádný EX formulář. Daň se počítá jen na modelo 210, ne tady. Office-wide přehled cit dne je `/citas` (slot `inbox.feed`), ne nová ikona v railu.
