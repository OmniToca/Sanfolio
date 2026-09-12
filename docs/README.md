# Dokumentace Gestoría OS

Pořadí čtení pro další vývoj. Tyto soubory jsou smlouva produktu. Kód se k nim musí chovat jako k migracím: změna chování = změna dokumentu ve stejném PR.

## Závazná pravidla (přečíst vždy)

1. Základ je **papírová složka**, ne obecný CRM a ne a3.
2. Tužka = zapnutý **blok**. Vypnutý blok se nehlídá a nechybí.
3. AI **hledá, otevírá, předvyplňuje**. Ukládá / maže / odesílá jen člověk.
4. Mazání je **100 % soft-delete**. Audit je **append-only**, včetně otevření karty.
5. MVP = složka koupě v prohlížeči. Výpočet daně, WhatsApp API a portál klienta **nejsou** první verze. Policie / magistrát / závěť: moduly u Jarky zapnuté, desky až po papíru.

## Soubory

| # | Soubor | Hotovo když |
| --- | --- | --- |
| 1 | [product_bible.md](product_bible.md) | Entity a hranice rozsahu jsou jednoznačné |
| 2 | [folder_template.md](folder_template.md) | Každý titulek z tisku má stav, pole a dokumenty |
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

Impuestos v katalogu: **IBI/SUMA**, **modelo 210**, **renta/IRPF**. V MVP jen plazo + checklist, ne výpočet daně.
