import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

/**
 * M6: Support vytvoří jednorázový kód (create); kancelář ho vymění za refresh (redeem).
 * Raw refresh_token neputuje v URL — jen short-lived code v hash.
 * verify_jwt=false: redeem běží bez JWT na druhé origině.
 */

const CODE_TTL_MS = 2 * 60 * 1000;

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "method" }, req);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json() as Record<string, unknown>;
  } catch {
    return json(400, { ok: false, error: "json" }, req);
  }
  const action = str(body.action);

  if (action === "create") {
    return await createHandoff(req, body);
  }
  if (action === "redeem") {
    return await redeemHandoff(req, body);
  }
  return json(400, { ok: false, error: "action" }, req);
});

async function createHandoff(
  req: Request,
  body: Record<string, unknown>,
): Promise<Response> {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { ok: false, error: "unauthorized" }, req);
  }

  const userClient = createClient(supabaseUrl(), supabaseAnonKey(), {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json(401, { ok: false, error: "unauthorized" }, req);
  }

  const { data: isSupport } = await userClient.rpc("auth_is_support_user");
  if (isSupport !== true) {
    return json(403, { ok: false, error: "forbidden" }, req);
  }

  const sessionId = str(body.session_id);
  const refreshToken = str(body.refresh_token);
  if (!sessionId || !refreshToken) {
    return json(400, { ok: false, error: "payload" }, req);
  }

  const admin = createClient(supabaseUrl(), serviceRoleKey());
  const { data: session, error: sessErr } = await admin
    .from("support_view_sessions")
    .select("id, support_user_id, ended_at, expires_at")
    .eq("id", sessionId)
    .maybeSingle();
  if (sessErr) return json(500, { ok: false, error: sessErr.message }, req);
  if (
    !session ||
    session.support_user_id !== userData.user.id ||
    session.ended_at != null ||
    new Date(session.expires_at as string).getTime() <= Date.now()
  ) {
    return json(403, { ok: false, error: "session" }, req);
  }

  const code = randomCode();
  const codeHash = await sha256Hex(code);
  const expiresAt = new Date(Date.now() + CODE_TTL_MS).toISOString();

  // Starší nevyužité kódy stejné session zneplatní — jeden aktivní handoff.
  await admin
    .from("impersonation_handoffs")
    .update({ redeemed_at: new Date().toISOString() })
    .eq("session_id", sessionId)
    .is("redeemed_at", null);

  const { error: insErr } = await admin.from("impersonation_handoffs").insert({
    code_hash: codeHash,
    session_id: sessionId,
    support_user_id: userData.user.id,
    refresh_token: refreshToken,
    expires_at: expiresAt,
  });
  if (insErr) return json(500, { ok: false, error: insErr.message }, req);

  return json(200, { ok: true, code, expires_at: expiresAt }, req);
}

async function redeemHandoff(
  req: Request,
  body: Record<string, unknown>,
): Promise<Response> {
  const sessionId = str(body.session_id);
  const code = str(body.code);
  if (!sessionId || !code) {
    return json(400, { ok: false, error: "payload" }, req);
  }

  const admin = createClient(supabaseUrl(), serviceRoleKey());
  const codeHash = await sha256Hex(code);

  const { data: row, error } = await admin
    .from("impersonation_handoffs")
    .select("id, refresh_token, expires_at, redeemed_at, session_id")
    .eq("code_hash", codeHash)
    .eq("session_id", sessionId)
    .maybeSingle();
  if (error) return json(500, { ok: false, error: error.message }, req);
  if (!row || row.redeemed_at != null) {
    return json(404, { ok: false, error: "invalid" }, req);
  }
  if (new Date(row.expires_at as string).getTime() <= Date.now()) {
    return json(410, { ok: false, error: "expired" }, req);
  }

  const { data: claimed, error: claimErr } = await admin
    .from("impersonation_handoffs")
    .update({ redeemed_at: new Date().toISOString() })
    .eq("id", row.id)
    .is("redeemed_at", null)
    .select("id")
    .maybeSingle();
  if (claimErr) return json(500, { ok: false, error: claimErr.message }, req);
  if (!claimed) {
    return json(404, { ok: false, error: "invalid" }, req);
  }

  return json(200, {
    ok: true,
    refresh_token: row.refresh_token,
  }, req);
}

function randomCode(): string {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(value: string): Promise<string> {
  const data = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest), (b) =>
    b.toString(16).padStart(2, "0")
  ).join("");
}

function str(v: unknown): string {
  return typeof v === "string" ? v.trim() : "";
}

function supabaseUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}

function supabaseAnonKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}

function serviceRoleKey(): string {
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

function json(
  status: number,
  body: Record<string, unknown>,
  req?: Request,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}
