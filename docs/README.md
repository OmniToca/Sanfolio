# Dokumentace Gestoría OS

Pořadí čtení pro další vývoj. Tyto soubory jsou smlouva produktu. Kód se k nim musí chovat jako k migracím: změna chování = změna dokumentu ve stejném PR.

## Závazná pravidla (přečíst vždy)

1. Základ je **složka klienta** (evidence + zapnuté služby), ne obecný CRM a ne a3 jako start. Koupě je balík papírů v čase, ne jen escritura.
2. Zapnutá služba = **blok**. Vypnutá se nehlídá a nechybí.
3. AI **hledá, otevírá, předvyplňuje**. Ukládá / maže / odesílá / podává jen člověk.
4. Mazání je **100 % soft-delete**. Audit je **append-only**, včetně otevření karty.
5. První deska = složka koupě + inbox v prohlížeči. Stavíme pro jednu kancelář i pro deset; Jarka je první, ne strop a ne důvod čekat. WhatsApp API, portál a podání AEAT jsou na [seznamu vývoje](vyvoj.md). Modelo 210 se počítá. Kniha faktur (`facturacion`) a příchozí Pošta jsou v kódu. Policie / magistrát / závěť: tenký spis, dokud kancelář nechce plnou desku.

## Soubory

| # | Soubor | Hotovo když |
| --- | --- | --- |
| 1 | [product_bible.md](product_bible.md) | Entity a hranice rozsahu jsou jednoznačné |
| 1a | [vyvoj.md](vyvoj.md) | Prioritní seznam: co teď, co ve frontě, jak se řadí nápady |
| 2 | [folder_template.md](folder_template.md) | Každá služba na desce má stav, pole a dokumenty |
| 3 | [search_spec.md](search_spec.md) | `Y123**6E` najde `Y123456E` |
| 4 | [deadline_engine.md](deadline_engine.md) | Inbox a šablony výzev mají pravidla |
| 5 | [ai_contract.md](ai_contract.md) | Seznam tools a zákaz zápisu je vymahatelný v kódu |
| 6 | [tenancy_audit.md](tenancy_audit.md) | Tři portály, RLS, legal hold |
| 7 | [mvp_screens.md](mvp_screens.md) | Ranní inbox + desky klienta/nemovitosti |
| 8 | [design_partner_sanon.md](design_partner_sanon.md) | Partner a checklist šanonu |
| 9 | [partner/](partner/README.md) | Dotazník + **odpovědi Gestorie Jarka** |
| 10 | [database_schema.md](database_schema.md) | Odkaz na SQL migraci |
| 11 | [modules_settings_i18n.md](modules_settings_i18n.md) | Moduly, sloty, jazyky — jak se nezamotat |
| 12 | [roadmap_dokumenty_ai.md](roadmap_dokumenty_ai.md) | Fáze A–G: přepis, PDF, koš, asistent, otevřený blok |
| 13 | [facturacion_verifactu.md](facturacion_verifactu.md) | Modul knihy vs. SIF adapter; due diligence API |
| 14 | [roadmap_facturacion.md](roadmap_facturacion.md) | Napojení Verifacti (`GET /verifactu/declaracion`, Emitir, Ověřit) |
| 15 | [audit_verifacti.md](audit_verifacti.md) | Mezery `sif-emit` vs. Verifacti docs; pořadí sandbox → produkce |
| 16 | [ai_context/slovnik_modulu.md](ai_context/slovnik_modulu.md) | Živý seznam modulů / RPC / providerů |
| 17 | [rano_v_kancelari.md](rano_v_kancelari.md) | Jedna strana pro staff: co kliknout ráno |

Impuestos v katalogu: **IBI/SUMA**, **modelo 210** (výpočet IRNR, ne podání AEAT), **renta/IRPF** (zatím plazo + checklist).
