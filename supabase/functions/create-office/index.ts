import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import {
  findAuthUserId,
  inviteOrCreateAuthUser,
} from "../_shared/invite_user.ts";

/**
 * Support zakládá kancelář: tenant + settings + zvolený balíček + invite owner.
 * Flutter INSERT do tenants nesmí.
 */

/** Fallback, když licence_plan_modules ještě není (stejné jako seed 0061). */
const PLAN_MODULES: Record<string, string[]> = {
  carpeta: ["carpeta_inmueble", "messaging"],
  despacho: [
    "carpeta_inmueble",
    "messaging",
    "impuestos",
    "nie_poder",
    "policia",
    "ayuntamiento",
    "testament",
    "ofertas",
    "ai_copilot",
  ],
  asesoria: [
    "carpeta_inmueble",
    "messaging",
    "impuestos",
    "nie_poder",
    "policia",
    "ayuntamiento",
    "testament",
    "ofertas",
    "ai_copilot",
    "facturacion",
  ],
};

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return jsonError(405, "Method not allowed", req);
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return jsonError(401, "Missing Authorization", req);
    }

    const userClient = createClient(supabaseUrl(), supabaseAnonKey(), {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: supportOk, error: supportErr } = await userClient.rpc(
      "auth_is_support_user",
    );
    if (supportErr) return jsonError(500, supportErr.message, req);
    if (supportOk !== true) return jsonError(403, "Support only", req);

    const body = await req.json() as {
      name?: unknown;
      owner_email?: unknown;
      display_name?: unknown;
      plan_key?: unknown;
    };
    const name = typeof body.name === "string" ? body.name.trim() : "";
    const ownerEmail = typeof body.owner_email === "string"
      ? body.owner_email.trim().toLowerCase()
      : "";
    const displayName = typeof body.display_name === "string"
      ? body.display_name.trim()
      : name;
    const rawPlan = typeof body.plan_key === "string"
      ? body.plan_key.trim()
      : "carpeta";
    const planKey = rawPlan in PLAN_MODULES ? rawPlan : "carpeta";
    if (!name) return jsonError(400, "name required", req);
    if (!ownerEmail || !ownerEmail.includes("@")) {
      return jsonError(400, "owner_email required", req);
    }

    const admin = createClient(supabaseUrl(), serviceRoleKey(), {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: tenant, error: tenantErr } = await admin
      .from("tenants")
      .insert({ name, locale: "cs", timezone: "Europe/Madrid" })
      .select("id")
      .single();
    if (tenantErr || !tenant) {
      return jsonError(500, tenantErr?.message ?? "tenant insert failed", req);
    }
    const tenantId = tenant.id as string;

    const { error: settingsErr } = await admin.from("tenant_settings").insert({
      tenant_id: tenantId,
      display_name: displayName || name,
      staff_locale: "cs",
      default_client_locale: "cs",
      send_translated_outbound: true,
      allow_client_without_nie: true,
      iban_required_for_debit_only: true,
      licence_plan_key: planKey,
    });
    if (settingsErr) {
      return jsonError(500, settingsErr.message, req);
    }

    let moduleKeys = PLAN_MODULES[planKey] ?? PLAN_MODULES.carpeta;
    const { data: planRows } = await admin
      .from("licence_plan_modules")
      .select("module_key")
      .eq("plan_key", planKey);
    if (Array.isArray(planRows) && planRows.length > 0) {
      moduleKeys = planRows
        .map((row) =>
          row && typeof row === "object"
            ? `${(row as { module_key?: unknown }).module_key ?? ""}`
            : ""
        )
        .filter((key) => key.length > 0);
    }
    const moduleRows = moduleKeys.map((key) => ({
      tenant_id: tenantId,
      module_key: key,
      status: "active",
    }));
    const { error: modErr } = await admin
      .from("organization_modules")
      .insert(moduleRows);
    if (modErr) return jsonError(500, modErr.message, req);

    let userId = await findAuthUserId(admin, ownerEmail);
    if (!userId) {
      const invited = await inviteOrCreateAuthUser(admin, ownerEmail);
      userId = invited.userId;
      if (!userId) {
        return jsonError(
          500,
          invited.error ?? "invite failed and profile not found",
        );
      }
    }

    // Trigger handle_new_user může přijít o milisekundu později.
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
          email: ownerEmail,
        });
        if (pErr) return jsonError(500, pErr.message, req);
      } else {
        await new Promise((r) => setTimeout(r, 150));
      }
    }

    const { error: memErr } = await admin.from("tenant_members").insert({
      tenant_id: tenantId,
      profile_id: userId,
      role: "owner",
    });
    if (memErr) return jsonError(500, memErr.message, req);

    await admin.from("audit_logs").insert({
      tenant_id: tenantId,
      actor_id: (await userClient.auth.getUser()).data.user?.id,
      action: "tenant.create",
      entity_table: "tenants",
      entity_id: tenantId,
      after: { name, owner_email: ownerEmail, plan_key: planKey },
    });

    return new Response(
      JSON.stringify({ ok: true, tenant_id: tenantId, owner_id: userId }),
      { headers: { ...cors, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return jsonError(500, e instanceof Error ? e.message : String(e), req);
  }
});

function jsonError(status: number, error: string, req?: Request) {
  return new Response(JSON.stringify({ ok: false, error }), {
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
