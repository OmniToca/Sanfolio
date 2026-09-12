# Gestoría OS

Digitální složka pro španělskou gestoría. Zdroj pravdy je papírová deska z design-partner kanceláře (Costa Blanca / Alicante): tužkou se zapíná, co kancelář za klienta opravdu dělá. Po naplnění systém hlídá termíny a chybějící dokumenty.

**Teď:** Auth + Support + převtělení. Napoj hosted Supabase (EU) a `config.json`.

## Spuštění (až máš projekt)

1. Zkopíruj [`config.example.json`](config.example.json) → `config.json` (je v gitignore).
2. `supabase link` + `supabase db push` (`0001`–`0004`).
3. Deploy Edge Function `create-office` (secret `GESTORIA_BASE_URL`).
4. Auth → Redirect URLs: kancelář i Support (Netlify + `localhost:5555` / `5556`).
5. Zaregistruj se na Support, v SQL: `UPDATE profiles SET is_support = true WHERE email = '…';`

```bash
# kancelář
cd apps/gestoria && flutter run -d chrome --web-port=5555 --dart-define-from-file=../../config.json

# support
cd apps/support && flutter run -d chrome --web-port=5556 --dart-define-from-file=../../config.json
```

| Dokument | Účel |
| --- | --- |
| [docs/README.md](docs/README.md) | Mapa dokumentace |
| [docs/product_bible.md](docs/product_bible.md) | Entity, role, non-goals |
| [docs/folder_template.md](docs/folder_template.md) | Tužka → stavy bloků |
| [docs/search_spec.md](docs/search_spec.md) | NIE/DNI matcher včetně masek |
| [docs/deadline_engine.md](docs/deadline_engine.md) | Termíny + výzvy klientovi |
| [docs/ai_contract.md](docs/ai_contract.md) | AI tools, zákaz save/delete/send |
| [docs/tenancy_audit.md](docs/tenancy_audit.md) | Portály, RLS, soft-delete, GDPR |
| [docs/mvp_screens.md](docs/mvp_screens.md) | Obrazovky MVP |
| [docs/design_partner_sanon.md](docs/design_partner_sanon.md) | Partner a co je potvrzené |
| [docs/partner/](docs/partner/README.md) | Dotazník + **odpovědi Gestorie Jarka** |

Stack (až se bude stavět): Flutter web + Supabase. Online-only, bez nativní appky.
