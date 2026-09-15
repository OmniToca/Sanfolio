# Moduly, nastavení, jazyky — jak se nezamotat

OmniToca měla vizi JSON layout engine a **úmyslně ji nestavěla**. FalcoNest nabobtnal, když se všechny domény míchaly do jedné obrazovky. Tady platí tři vrstvy flexibility. Vyšší vrstvu nestavíme, dokud nestačí nižší.

## 1. Co chceme za deset let

- Sanfolio používá **libovolná** španělská kancelář, ne jen první partner.
- Kancelář v CS / ES / EN…, klienti CS / EN / DE / FR / ES.
- Každý klient má jazyk komunikace. Zpráva má originál + překlad (e-mail, WhatsApp, později zóna).
- Každá kancelář má jiné lhůty a zapnuté **moduly** (evidence → trámites/podání → faktury/banka → účetnictví).
- Obrazovky jdou skládat sloty, ne jako Figma v runtime.

## 2. Tři vrstvy (jen postupně)

```
A  i18n + locale klienta          ← teď
B  moduly + FeatureGate + sloty   ← teď (registry)
C  pořadí widgetů ve slotu        ← tenant_settings.slot_order, až B žije
D  volný drag-drop layout         ← ZÁKAZ, dokud C nestačí (OmniToca backlog)
```

**Slot** je díra v shellu s pevným významem: `inbox.feed`, `cliente.tabs`, `carpeta.blocks`, `settings.section`.  
**Modul** do slotu přihlásí widget. Kancelář modul vypne → widget zmizí. Kancelář změní `slot_order` → jen pořadí, ne nový layout engine.

To je „skládání obrazovky“ na deset let bez CMS.

## 3. Jazyky

| Kdo | Pole | Slovník |
| --- | --- | --- |
| Staff (3 lidé, každý vlastní) | `profiles.locale` | UI JSON cs/en/es/de/fr |
| Klient | `clientes.locale` (`cs`/`en`/`de`/`fr`/`es`) | překlad zpráv, až portál i UI zóny |
| Úřad / papír | neměnit | NIE, escritura, plusvalía jako termíny |

Zpráva (Gestorie Jarka):

1. Gestor píše **španělsky** → `mensajes.cuerpo`, `locale_original`.
2. Odeslání (člověk klikne, ne AI) → Edge Function přeloží do `clientes.locale`, uloží `translations`.
3. E-mail / WhatsApp = **překlad** (`send_translated_outbound = true`). Originál zůstane ve spisu.
4. Klientská zóna (v2) = originál + překlad vedle sebe.

Překlad se **nepouští při každém otevření**. Uloží se jednou. Staff UI locale je **per člověk** (`profiles.locale`), ne jedno pro kancelář.

## 4. Nastavení kanceláře

Tabulka `tenant_settings` (1:1 tenant). Defaulty z `plazo_rules` / `bloque_templates`. Override JSON:

```json
{
  "display_name": "Gestorie Jarka",
  "send_translated_outbound": true,
  "allow_client_without_nie": true,
  "iban_required_for_debit_only": true,
  "plusvalia_days": 30,
  "ibi_warn_days": 60,
  "ibi_due_month": null,
  "ibi_due_day": null,
  "seguro_warn_days": 60,
  "alarma_warn_days": 60,
  "poder_warn_days": 60,
  "plazo_offsets": { "seguro_renovacion": [60, 30, 7] },
  "nudge_interval_days": 7,
  "slot_order": {
    "carpeta.blocks": ["escritura", "agua", "luz", "gaz", "comunidad", "suma"]
  }
}
```

`staff_locale` na tenantu je fallback. Každý z 3 lidí má vlastní `profiles.locale`.  
Jarka chce **přeskládat** bloky → vrstva C (`slot_order`) je v rozsahu, ne drag-drop layout (D).

Workflow kanceláře = zapnuté moduly + tyhle offsety + pořadí bloků. Ne BPMN editor.

## 5. Katalog modulů

| Klíč | MVP | Sloty |
| --- | --- | --- |
| `core` | vždy | shell, klienti, hledání, audit |
| `carpeta_inmueble` | ano | `carpeta.blocks` (papír) |
| `impuestos` | ano (jen plazo) | `cliente.tabs`, `inbox.feed` |
| `messaging` | ano (e-mail + copy WhatsApp + příchozí Pošta) | `inbox.feed`, `cliente.tabs`; nav `/posta` |
| `nie_poder` | ano jako bloky na desce | `carpeta.blocks` |
| `ai_copilot` | kostra | pravý panel (`AiPanel`) |
| `facturacion` | ano (kniha, ne SIF) | `cliente.tabs`, `settings.section`, nav `/facturacion`; vnitřní knihy Ventas/Compras v `facturacion_nav.dart` (ne další rail) |
| `client_portal` | ne | — |
| `policia` / `ayuntamiento` / `testament` | zapnuto u Jarky; tenký spis na `cliente.tabs` | `cliente.tabs` |

Widget modulu žije v `features/<modul>/presentation/widgets/` a registruje se v `core/modules/registry.dart`. Nový modul = nová složka + řádek v katalogu + licence. Nesahej do cizích `presentation/`.

## 6. Proč tohle přežije deset let

- Nová služba = nový modul do slotu, ne přepis inboxu.
- Nová kancelář v Německu = jiné `staff_locale` a `plazo_offsets`, ne fork.
- Klientská zóna čte už uložené `translations`, nestaví se druhý messenger.
- Až bude chtít někdo drag-drop, napojí se na existující registry ID. Do té doby ho nestavíme — to je přesně místo, kde se OmniToca a FalcoNest zamotaly.
