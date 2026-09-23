import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  findAuthUserId,
  inviteOrCreateAuthUser,
} from "../_shared/invite_user.ts";

/**
 * Owner zve gestor / asistente. Service role kvůli invite.
 * Flutter INSERT do tenant_members smí jen owner; tady se navíc posílá e-mail.
 * Strop počtu lidí není — omezení je, které karty a bloky člen vidí.
 */

const ALLOWED_ROLES = new Set(["gestor", "asistente"]);

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" }, req);
  }

  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.toLowerCase().startsWith("bearer ")) {
    return json(401, { ok: false, error: "Missing Authorization" }, req);
  }

  const userClient = createClient(supabaseUrl(), supabaseAnonKey(), {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json(401, { ok: false, error: "Unauthorized" }, req);
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
  if (!tenantId) {
    return json(400, { ok: false, error: "tenant_id required" }, req);
  }
  if (!email || !email.includes("@")) {
    return json(400, { ok: false, error: "email required" }, req);
  }
  if (!ALLOWED_ROLES.has(role)) {
    return json(400, {
      ok: false,
      error: "role must be gestor or asistente",
    }, req);
  }

  const { data: ownerOk, error: ownerErr } = await userClient.rpc(
    "is_tenant_owner",
    { _tenant_id: tenantId },
  );
  if (ownerErr) {
    return json(500, { ok: false, error: ownerErr.message }, req);
  }
  if (ownerOk !== true) {
    return json(403, { ok: false, error: "Owner only" }, req);
  }

  const admin = createClient(supabaseUrl(), serviceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Účet už v Auth existuje (Support, jiná kancelář) → jen membership, ne invite.
  let userId = await findAuthUserId(admin, email);
  const existing = Boolean(userId);
  let emailSent = false;
  if (!userId) {
    const invited = await inviteOrCreateAuthUser(admin, email);
    userId = invited.userId;
    emailSent = invited.emailSent;
    if (!userId) {
      return json(500, {
        ok: false,
        error: invited.error ?? "invite failed",
      }, req);
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
      if (pErr) {
        return json(500, { ok: false, error: pErr.message }, req);
      }
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
    return json(409, { ok: false, error: "already_member" }, req);
  }

  const { error: memErr } = await admin.from("tenant_members").insert({
    tenant_id: tenantId,
    profile_id: userId,
    role,
  });
  if (memErr) {
    return json(500, { ok: false, error: memErr.message }, req);
  }

  await admin.from("audit_logs").insert({
    tenant_id: tenantId,
    actor_id: userData.user.id,
    action: "staff.invite",
    entity_table: "tenant_members",
    entity_id: userId,
    after: { email, role },
  });

  return json(200, {
    ok: true,
    profile_id: userId,
    role,
    existing,
    email_sent: existing ? false : emailSent,
  }, req);
});

function json(
  status: number,
  body: Record<string, unknown>,
  req?: Request,
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
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
