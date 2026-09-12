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
| druhý kontakt | ne | `client_contacts` + `locale` (občas partner / překladatel) |

Plazo: žádné.  
Inbox: klient bez e-mailu i telefonu + existuje `missing_document` jinde → kanál `none` (nelze poslat, jen úkol kanceláři).

### 3.2 `escritura` — ESCRITURA

| Pole | Povinné | Poznámka |
| --- | --- | --- |
| `notario` | ne | **ověřit u šanonu** |
| `escritura_fecha` | ano pokud je zapnutá plusvalía | Spouštěč lhůty |
| `protocolo` | ne | |

Dokument: `copia_escritura` obvykle (Gestorie Jarka: většinou ve složce).  
`referencia_catastral` na inmueble: většinou.  
Plazo: žádné vlastní. Zapnutá plusvalía odvodí lhůtu z `escritura_fecha` + `tenant_settings.plusvalia_days`.

### 3.3 `agua` / `luz` / `gaz` / `comunidad`

Stejný tvar, jiný katalog dokumentu a volitelné pole sítě.

| Pole | Povinné | Agua | Luz / Gaz | Comunidad |
| --- | --- | --- | --- | --- |
| `proveedor` | ano | Compañía | Comercializadora | Administrador |
| `numero_cliente` | ano u vody | číslo klienta na smlouvě | — | — |
| `numero_contrato` | ano | Póliza | Contrato | Ref. comunidad / účet |
| `cups` | ano u luz/gaz | — | **CUPS** | — |
| `titular` | ano | Kdo je na smlouvě | dtto | dtto |
| `fecha_alta` | ne | Změna titulu | dtto | dtto |

| Blok | Povinné dokumenty |
| --- | --- |
| `agua` | `contrato_agua` + `factura_agua` |
| `luz` | `contrato_luz` + `factura_luz` |
| `gaz` | `contrato_gaz` + `factura_gaz` |
| `comunidad` | `certificado_comunidad` (správce, účet, papír) |

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
| `presentado_at` | ne |

Gestorie Jarka: **čtvrtletně i ročně**. Papíry = všechny povinné ke zpracování 210. Výpočet daně **ne**.  
Dokumenty: checklist typů (`escritura_o_nota_simple`, `recibo_ibi`, `certificado_catastral`, …).  
Plazo: z `tenant_settings` podle `periodicidad`.

### 4.2 `renta`

| Pole | Povinné |
| --- | --- |
| `ejercicio` | ano | rok |
| `presentado_at` | ne |

Dokument: `borrador_renta` ne povinný.  
Plazo: jen nastavitelné v `tenant_settings` (v dotazníku prázdné).

Výpočet daně, XML, AEAT = mimo rozsah. Blok je spis „sbíráme podklady a hlídáme datum“.

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

## 6. Další služby (Gestorie Jarka je dělá)

Moduly `policia`, `ayuntamiento`, `testament` jsou **zapnuté**. Samostatné desky přijdou po složce koupě — stroj stavů se nemění. Dva tištěné listy zatím nevědí, jestli platí i jinde; doplnit později.
