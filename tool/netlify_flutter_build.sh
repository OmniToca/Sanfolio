#!/usr/bin/env bash
# Netlify build. Tajemství jsou env vars, ne soubor v gitu.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?app path (apps/gestoria|apps/support)}"
cd "$ROOT/$APP"

: "${SUPABASE_URL:?Nastavte SUPABASE_URL v Netlify Environment}"
: "${SUPABASE_ANON_KEY:?Nastavte SUPABASE_ANON_KEY v Netlify Environment}"

# Netlify dá URL produkčního webu. V release nesmí zůstat localhost.
GESTORIA_BASE_URL="${GESTORIA_BASE_URL:-${URL:-}}"
SUPPORT_APP_URL="${SUPPORT_APP_URL:-${URL:-}}"
if [[ -z "$GESTORIA_BASE_URL" || "$GESTORIA_BASE_URL" == *"localhost"* ]]; then
  echo "GESTORIA_BASE_URL musí být veřejná HTTPS adresa (ne localhost)." >&2
  exit 1
fi
if [[ -z "$SUPPORT_APP_URL" || "$SUPPORT_APP_URL" == *"localhost"* ]]; then
  echo "SUPPORT_APP_URL musí být veřejná HTTPS adresa (ne localhost)." >&2
  exit 1
fi

CACHE="${NETLIFY_CACHE_DIR:-$HOME/.cache}/flutter-sdk"
if [[ ! -x "$CACHE/bin/flutter" ]]; then
  rm -rf "$CACHE"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$CACHE"
fi
export PATH="$CACHE/bin:$PATH"
flutter config --no-analytics --enable-web >/dev/null
flutter pub get

CONFIG="$(mktemp)"
trap 'rm -f "$CONFIG"' EXIT
cat >"$CONFIG" <<EOF
{
  "SUPABASE_URL": "$SUPABASE_URL",
  "SUPABASE_ANON_KEY": "$SUPABASE_ANON_KEY",
  "GESTORIA_BASE_URL": "$GESTORIA_BASE_URL",
  "SUPPORT_APP_URL": "$SUPPORT_APP_URL"
}
EOF

flutter build web --release --dart-define-from-file="$CONFIG"
