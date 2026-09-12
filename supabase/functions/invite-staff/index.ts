import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Owner zve 2. a 3. člověka (gestor / asistente). Service role kvůli invite.
 * Flutter INSERT do tenant_members smí jen owner; tady se navíc posílá e-mail.
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ALLOWED_ROLES = new Set(["gestor", "asistente"]);
const MAX_LIVE_MEMBERS = 3;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" });
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { ok: false, error: "Missing Authorization" });
  }

  const userClient = createClient(supabaseUrl(), supabaseAnonKey(), {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json(401, { ok: false, error: "Unauthorized" });
  }

  const body = await req.json() as {
    tenant_id?: unknown;
    email?: unknown;
    role?: unknown;
  };
  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  const email = typeof body.email === "string"
    ? body.email.trim().toLowerCase()
    : "";
  const role = typeof body.role === "string" ? body.role.trim() : "";
  if (!tenantId) return json(400, { ok: false, error: "tenant_id required" });
  if (!email || !email.includes("@")) {
    return json(400, { ok: false, error: "email required" });
  }
  if (!ALLOWED_ROLES.has(role)) {
    return json(400, { ok: false, error: "role must be gestor or asistente" });
  }

  const { data: ownerOk, error: ownerErr } = await userClient.rpc(
    "is_tenant_owner",
    { _tenant_id: tenantId },
  );
  if (ownerErr) return json(500, { ok: false, error: ownerErr.message });
  if (ownerOk !== true) return json(403, { ok: false, error: "Owner only" });

  const admin = createClient(supabaseUrl(), serviceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { count, error: countErr } = await admin
    .from("tenant_members")
    .select("id", { count: "exact", head: true })
    .eq("tenant_id", tenantId)
    .is("deleted_at", null);
  if (countErr) return json(500, { ok: false, error: countErr.message });
  if ((count ?? 0) >= MAX_LIVE_MEMBERS) {
    return json(409, { ok: false, error: "team_full" });
  }

  const gestoriaBase = (Deno.env.get("GESTORIA_BASE_URL") ??
    "http://localhost:5555").replace(/\/$/, "");
  const invited = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo: `${gestoriaBase}/login`,
  });

  let userId = invited.data.user?.id;
  if (invited.error || !userId) {
    const { data: existing } = await admin
      .from("profiles")
      .select("id")
      .eq("email", email)
      .maybeSingle();
    userId = existing?.id as string | undefined;
    if (!userId) {
      return json(500, {
        ok: false,
        error: invited.error?.message ?? "invite failed",
      });
    }
  }

  for (let i = 0; i < 8; i++) {
    const { data: profile } = await admin
      .from("profiles")
      .select("id")
      .eq("id", userId)
      .maybeSingle();
    if (profile) break;
    if (i === 7) {
      const { error: pErr } = await admin.from("profiles").insert({
        id: userId,
        email,
      });
      if (pErr) return json(500, { ok: false, error: pErr.message });
    } else {
      await new Promise((r) => setTimeout(r, 150));
    }
  }

  const { data: live } = await admin
    .from("tenant_members")
    .select("id, role")
    .eq("tenant_id", tenantId)
    .eq("profile_id", userId)
    .is("deleted_at", null)
    .maybeSingle();
  if (live) {
    return json(409, { ok: false, error: "already_member" });
  }

  const { error: memErr } = await admin.from("tenant_members").insert({
    tenant_id: tenantId,
    profile_id: userId,
    role,
  });
  if (memErr) return json(500, { ok: false, error: memErr.message });

  await admin.from("audit_logs").insert({
    tenant_id: tenantId,
    actor_id: userData.user.id,
    action: "staff.invite",
    entity_table: "tenant_members",
    entity_id: userId,
    after: { email, role },
  });

  return json(200, { ok: true, profile_id: userId, role });
});

function json(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function supabaseUrl() {
  const u = Deno.env.get("SUPABASE_URL");
  if (!u) throw new Error("SUPABASE_URL missing");
  return u;
}

function supabaseAnonKey() {
  const k = Deno.env.get("SUPABASE_ANON_KEY");
  if (!k) throw new Error("SUPABASE_ANON_KEY missing");
  return k;
}

function serviceRoleKey() {
  const k = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!k) throw new Error("SUPABASE_SERVICE_ROLE_KEY missing");
  return k;
}
