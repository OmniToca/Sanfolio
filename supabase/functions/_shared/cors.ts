/**
 * CORS allowlist — žádný `*`. Prod: sanfolio.app (+ www).
 * Extra originy přes CORS_ALLOWED_ORIGINS (čárkou). Localhost jen mimo produkci.
 */

const DEFAULT_ALLOWED = [
  "https://sanfolio.app",
  "https://www.sanfolio.app",
];

export function corsHeaders(req?: Request): Record<string, string> {
  const origin = (req?.headers.get("Origin") ?? "").trim();
  const extra = (Deno.env.get("CORS_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const support = (Deno.env.get("SUPPORT_APP_URL") ?? "").trim().replace(/\/$/, "");
  const allowed = new Set([
    ...DEFAULT_ALLOWED,
    ...extra,
    ...(support ? [support] : []),
  ]);
  // Dev: Flutter web na localhost.
  if (
    origin.startsWith("http://localhost:") ||
    origin.startsWith("http://127.0.0.1:")
  ) {
    allowed.add(origin);
  }
  const allowOrigin = allowed.has(origin) ? origin : DEFAULT_ALLOWED[0];
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Vary": "Origin",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, x-posta-secret, x-webhook-secret",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}
