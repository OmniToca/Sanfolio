# Sanfolio (Gestoría OS)

Provozní systém španělské kanceláře. Evidence klienta a služeb, doklady, termíny, výzvy, kniha faktur, příchozí pošta. Stavíme jednu aplikaci pro jednu kancelář i pro deset; nabízet dál až když je produkt dost dobrý. Fronta (AEAT, banka, portál, …) je [seznam vývoje](docs/vyvoj.md), ne čekání na druhého zákazníka. První kancelář je Gestorie Jarka — ověření, ne strop.

**Teď:** staff app kanceláře (inbox, složka, Pošta, kniha faktur, AI přepis) + Support s převtělením. Hosted Supabase (EU) + `config.json`.

## Spuštění

1. Zkopíruj [`config.example.json`](config.example.json) → `config.json` (je v gitignore).
2. `supabase link` + `supabase db push` (migrace `0001`–`0060`).
3. Deploy Edge Functions podle potřeby: `create-office` a `invite-staff` (secret `GESTORIA_BASE_URL=https://sanfolio.app`, nikdy localhost), `extract-document`, `ai-assistant`, `ai-draft-message`, `translate-message`, `plazo-reminders`, `posta-inbound`, `send-client-message`, `sif-emit`, `sif-status`.
4. Auth → Redirect URLs: kancelář i Support (Netlify + `localhost:5555` / `5556`).
5. Zaregistruj se na Support, v SQL: `UPDATE profiles SET is_support = true WHERE email = '…';`

> **Cursor Cloud Agent:** prostředí spouští [`tool/cloud_agent_install.sh`](tool/cloud_agent_install.sh) — nainstaluje Flutter stable, stáhne balíčky všech projektů a založí `config.json` z příkladu, aby prošel `flutter analyze` / `flutter test`. Skript je idempotentní; jde spustit i ručně.

## Nasazení (GitHub → Netlify)

`config.json` v gitu není. Netlify si Flutter nainstaluje v buildu a klíče bere z Environment.

1. **Add new project** → Import from Git → `OmniToca/Sanfolio`.
2. Build z root `netlify.toml` (kancelář). Support později: druhé project, Base directory `apps/support`.
3. Environment variables: `SUPABASE_URL`, `SUPABASE_ANON_KEY`. Adresy webů Netlify doplní samo (`$URL`). Až bude Support na vlastní URL, nastav `SUPPORT_APP_URL`.
4. Po prvním deploji: Supabase Auth → Redirect URLs včetně `https://sanfolio.app/reset-password` a `https://sanfolio.app/reset-password/**` (dočasně i `https://sanfolio-os.netlify.app/…`). Site URL = `https://sanfolio.app`.

### Vlastní doména (Webglobe → Netlify + pošta)

`sanfolio.app` je web kanceláře. `sanfolio.com` jen přesměruje. Příchozí pošta **20 kanceláří** sdílí subdoménu `inbound.sanfolio.app` — každá má `p{8hex}@inbound.sanfolio.app`, ne vlastní mailbox.

V Netlify: Domain management → Add `sanfolio.app` + `www.sanfolio.app`. Env `GESTORIA_BASE_URL=https://sanfolio.app`. Edge secret stejná URL.

DNS u Webglobe (Netlify už má `sanfolio.app` + `www`):

| Host | Typ | Cíl |
| --- | --- | --- |
| `@` (`sanfolio.app`) | ALIAS / ANAME | `apex-loadbalancer.netlify.com` |
| `@` (když Webglobe ALIAS neumí) | A | `75.2.60.5` |
| `www` | CNAME | `sanfolio-os.netlify.app` |
| `@` na `sanfolio.com` | URL redirect | `https://sanfolio.app` |
| `inbound` | MX 10 | hodnota z Resend (typicky `inbound-smtp.resend.com`) — **jen host `inbound`**, ne `@` |
| `@` | TXT SPF / DKIM | Resend, až budeme posílat z `posta@sanfolio.app` |

Bez MX na `inbound` Pošta zůstane prázdná. Bez ověřené From adresy v Resendu výzva otevře Gmail.

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
| [docs/rano_v_kancelari.md](docs/rano_v_kancelari.md) | Jedna strana pro staff |

Stack: Flutter web + Supabase. Online-only, bez nativní appky.
