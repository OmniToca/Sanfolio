#!/usr/bin/env bash
# Bootstrap prostředí pro Cursor Cloud Agent (Sanfolio = Flutter web monorepo).
#
# PROČ existuje: DB-managed prostředí startuje bez Flutteru, jenže AGENTS.md
# vyžaduje, aby na konci úkolu prošel `flutter analyze` / `flutter test`. Bez
# nainstalovaného SDK a stažených balíčků to nejde. Skript je idempotentní —
# může běžet znovu při každém buildu prostředí i ručně.
#
# Používá stejný Flutter stable kanál jako Netlify build (tool/netlify_flutter_build.sh),
# aby se choval konzistentně mezi CI a vývojem.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log() { printf '\n=== %s ===\n' "$1"; }

# --- 1) Root FS. Předpřipravené snapshoty někdy přijdou nezvětšené (fs menší než
#        disk), pak se ~2 GB Flutteru nevejde. Zvětšení plného FS je no-op, takže
#        je bezpečné volat pokaždé. Selhání neblokuje (|| true) — když nejde, jen
#        se spolehneme na volné místo. ---
log "Zvětšuji root filesystem (pokud je co)"
ROOT_DEV="$(findmnt -no SOURCE / 2>/dev/null || true)"
if [ -n "${ROOT_DEV}" ]; then
  sudo resize2fs "${ROOT_DEV}" 2>/dev/null || echo "resize2fs přeskočen (není potřeba nebo bez oprávnění)"
fi
df -h / || true

# --- 2) Flutter SDK (stable). Instaluje se do $HOME/flutter a přidá se na PATH. ---
FLUTTER_DIR="${FLUTTER_HOME:-$HOME/flutter}"
if [ ! -x "${FLUTTER_DIR}/bin/flutter" ]; then
  log "Stahuji Flutter stable do ${FLUTTER_DIR}"
  rm -rf "${FLUTTER_DIR}"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "${FLUTTER_DIR}"
else
  log "Flutter už je v ${FLUTTER_DIR}, přeskakuji clone"
fi
export PATH="${FLUTTER_DIR}/bin:${PATH}"

# Flutter na PATH ve všech shellech (i neinteraktivních). /usr/local/bin je na PATH
# vždy; symlinky jsou spolehlivější než úprava .bashrc, kterou `bash -c` nečte.
# Launcher `flutter`/`dart` si přes readlink dohledá vlastní FLUTTER_ROOT, takže
# symlink funguje. .bashrc řádek necháváme jako pojistku pro interaktivní shell.
sudo ln -sf "${FLUTTER_DIR}/bin/flutter" /usr/local/bin/flutter 2>/dev/null || true
sudo ln -sf "${FLUTTER_DIR}/bin/dart" /usr/local/bin/dart 2>/dev/null || true
PROFILE_LINE='export PATH="$HOME/flutter/bin:$PATH"'
if ! grep -qF "${PROFILE_LINE}" "$HOME/.bashrc" 2>/dev/null; then
  echo "${PROFILE_LINE}" >> "$HOME/.bashrc"
fi

# Flutter clone běží pod jiným ownerem než git safe.directory čeká.
git config --global --add safe.directory "${FLUTTER_DIR}" || true

log "Konfiguruji Flutter (web, bez telemetrie)"
flutter config --no-analytics --enable-web >/dev/null
flutter precache --web

# --- 3) config.json pro lokální běh. V gitu není (secrets), takže ho složíme
#        z příkladu. Placeholder klíče stačí pro `analyze`/`test`; reálné hodnoty
#        doplní uživatel ručně nebo přes secrets. ---
if [ ! -f "${ROOT}/config.json" ]; then
  log "Vytvářím config.json z config.example.json (placeholder klíče)"
  cp "${ROOT}/config.example.json" "${ROOT}/config.json"
else
  log "config.json už existuje, nechávám být"
fi

# --- 4) Balíčky pro všechny pubspec projekty. Sdílený package napřed, ať path
#        dependency v appkách sedí. ---
for pkg in packages/gestoria_auth apps/gestoria apps/support; do
  log "flutter pub get: ${pkg}"
  ( cd "${ROOT}/${pkg}" && flutter pub get )
done

log "Verze nástrojů"
flutter --version

log "Hotovo — prostředí je připravené na flutter analyze / flutter test"
