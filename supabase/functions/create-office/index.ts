import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

/**
 * Support zakládá kancelář: tenant + settings + moduly + invite owner.
 * Flutter INSERT do tenants nesmí — jen tahle funkce (service_role).
 */

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const DEFAULT_MODULES = [
  "carpeta_inmueble",
  "impuestos",
  "nie_poder",
  "messaging",
  "ai_copilot",
  "facturacion",
  "policia",
  "ayuntamiento",
  "testament",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonError(405, "Method not allowed");
  }

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.toLowerCase().startsWith("bearer ")) {
      return jsonError(401, "Missing Authorization");
    }

    const userClient = createClient(supabaseUrl(), supabaseAnonKey(), {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: supportOk, error: supportErr } = await userClient.rpc(
      "auth_is_support_user",
    );
    if (supportErr) return jsonError(500, supportErr.message);
    if (supportOk !== true) return jsonError(403, "Support only");

    const body = await req.json() as {
      name?: unknown;
      owner_email?: unknown;
      display_name?: unknown;
    };
    const name = typeof body.name === "string" ? body.name.trim() : "";
    const ownerEmail = typeof body.owner_email === "string"
      ? body.owner_email.trim().toLowerCase()
      : "";
    const displayName = typeof body.display_name === "string"
      ? body.display_name.trim()
      : name;
    if (!name) return jsonError(400, "name required");
    if (!ownerEmail || !ownerEmail.includes("@")) {
      return jsonError(400, "owner_email required");
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
      return jsonError(500, tenantErr?.message ?? "tenant insert failed");
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
    });
    if (settingsErr) {
      return jsonError(500, settingsErr.message);
    }

    const moduleRows = DEFAULT_MODULES.map((key) => ({
      tenant_id: tenantId,
      module_key: key,
      status: "active",
    }));
    const { error: modErr } = await admin
      .from("organization_modules")
      .insert(moduleRows);
    if (modErr) return jsonError(500, modErr.message);

    const gestoriaBase = (Deno.env.get("GESTORIA_BASE_URL") ??
      "http://localhost:5555").replace(/\/$/, "");
    const redirectTo = `${gestoriaBase}/login`;

    const invited = await admin.auth.admin.inviteUserByEmail(ownerEmail, {
      redirectTo,
    });

    let userId = invited.data.user?.id;
    if (invited.error || !userId) {
      const { data: existing } = await admin
        .from("profiles")
        .select("id")
        .eq("email", ownerEmail)
        .maybeSingle();
      userId = existing?.id as string | undefined;
      if (!userId) {
        return jsonError(
          500,
          invited.error?.message ?? "invite failed and profile not found",
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
        if (pErr) return jsonError(500, pErr.message);
      } else {
        await new Promise((r) => setTimeout(r, 150));
      }
    }

    const { error: memErr } = await admin.from("tenant_members").insert({
      tenant_id: tenantId,
      profile_id: userId,
      role: "owner",
    });
    if (memErr) return jsonError(500, memErr.message);

    await admin.from("audit_logs").insert({
      tenant_id: tenantId,
      actor_id: (await userClient.auth.getUser()).data.user?.id,
      action: "tenant.create",
      entity_table: "tenants",
      entity_id: tenantId,
      after: { name, owner_email: ownerEmail },
    });

    return new Response(
      JSON.stringify({ ok: true, tenant_id: tenantId, owner_id: userId }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return jsonError(500, e instanceof Error ? e.message : String(e));
  }
});

function jsonError(status: number, error: string) {
  return new Response(JSON.stringify({ ok: false, error }), {
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
