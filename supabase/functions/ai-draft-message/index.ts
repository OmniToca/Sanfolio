import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

/**
 * Copilot nachystá mensajes.draft ze děr složky. sent_at zůstane null.
 * Tool send_message neexistuje — odesílá gestor.
 */

const TEMPLATES: Record<string, { asunto: string; cuerpo: string }> = {
  falta_documento: {
    asunto: "Documentación pendiente — {{inmueble}}",
    cuerpo:
      "Hola {{nombre}},\n\nPara seguir con su expediente nos falta: {{documento}} ({{bloque}}).\nPuede responder a este correo con una foto nítida o un PDF.\n\nGracias,\n{{despacho}}",
  },
  faltan_datos: {
    asunto: "Datos pendientes — {{bloque}}",
    cuerpo:
      "Hola {{nombre}},\n\nNecesitamos completar {{bloque}}. En concreto: {{campos_faltantes}}.\n\nGracias,\n{{despacho}}",
  },
  recordatorio: {
    asunto: "Recordatorio: {{bloque}} — {{fecha}}",
    cuerpo:
      "Hola {{nombre}},\n\nLe recordamos el plazo de {{bloque}} con fecha {{fecha}}\n(inmueble: {{inmueble}}).\n\nSi ya lo tiene resuelto, ignore este mensaje o envíenos el justificante.\n\n{{despacho}}",
  },
  vencido: {
    asunto: "Plazo vencido — {{bloque}}",
    cuerpo:
      "Hola {{nombre}},\n\nEl plazo de {{bloque}} ({{fecha}}) ya ha vencido. Contacte con nosotros\nlo antes posible para evitar recargos.\n\n{{despacho}}",
  },
};

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
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
    cliente_id?: unknown;
    template_key?: unknown;
    bloque_key?: unknown;
    body_override?: unknown;
  };
  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  const clienteId = typeof body.cliente_id === "string" ? body.cliente_id.trim() : "";
  if (!tenantId || !clienteId) {
    return json(400, { ok: false, error: "tenant_id and cliente_id required" });
  }

  const { data: allowed } = await userClient.rpc("can_access_tenant", {
    _tenant_id: tenantId,
  });
  if (allowed !== true) return json(403, { ok: false, error: "forbidden" });

  const { data: snap, error: snapErr } = await userClient.rpc("ai_get_cliente", {
    p_cliente_id: clienteId,
  });
  if (snapErr || !snap) {
    return json(404, { ok: false, error: snapErr?.message ?? "not_found" });
  }

  const cliente = (snap as { cliente?: Record<string, unknown> }).cliente ?? {};
  const holes = (snap as { holes?: Array<Record<string, unknown>> }).holes ?? [];
  if (`${cliente.tenant_id ?? ""}` !== tenantId) {
    return json(403, { ok: false, error: "tenant mismatch" });
  }

  const requestedTpl = typeof body.template_key === "string"
    ? body.template_key.trim()
    : "";
  const requestedBloque = typeof body.bloque_key === "string"
    ? body.bloque_key.trim()
    : "";
  const hole = holes.find((h) =>
    requestedBloque ? `${h.bloque_key ?? ""}` === requestedBloque : true
  ) ?? holes[0];
  if (!hole && !requestedTpl) {
    return json(409, { ok: false, error: "no_holes" });
  }

  const status = `${hole?.status ?? ""}`;
  const templateKey = TEMPLATES[requestedTpl]
    ? requestedTpl
    : status === "missing_document"
    ? "falta_documento"
    : status === "missing_data"
    ? "faltan_datos"
    : "recordatorio";
  const tpl = TEMPLATES[templateKey];
  const bloqueKey = requestedBloque || `${hole?.bloque_key ?? "carpeta"}`;

  const { data: settings } = await userClient
    .from("tenant_settings")
    .select("display_name")
    .eq("tenant_id", tenantId)
    .maybeSingle();
  const { data: tenant } = await userClient
    .from("tenants")
    .select("name")
    .eq("id", tenantId)
    .maybeSingle();
  const despacho = `${settings?.display_name ?? ""}`.trim() ||
    `${tenant?.name ?? ""}`.trim() ||
    "despacho";
  const nombre = `${cliente.nombre ?? ""}`.trim() || "cliente";
  const override = typeof body.body_override === "string"
    ? body.body_override.trim()
    : "";

  const vars: Record<string, string> = {
    nombre,
    despacho,
    bloque: bloqueKey,
    documento: bloqueKey,
    inmueble: "—",
    fecha: "—",
    campos_faltantes: "—",
  };
  const asunto = fill(tpl.asunto, vars);
  const cuerpo = override || fill(tpl.cuerpo, vars);

  const { data: msg, error: insErr } = await userClient
    .from("mensajes")
    .insert({
      tenant_id: tenantId,
      cliente_id: clienteId,
      bloque_id: hole?.bloque_id ?? null,
      template_key: templateKey,
      canal: "email",
      asunto,
      cuerpo,
      locale_original: "es",
      status: "draft",
      sent_at: null,
      created_by: userData.user.id,
    })
    .select("id")
    .single();
  if (insErr || !msg) {
    return json(500, { ok: false, error: insErr?.message ?? "draft insert failed" });
  }

  const admin = createClient(supabaseUrl(), serviceRoleKey(), {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  await admin.from("audit_logs").insert({
    tenant_id: tenantId,
    actor_id: userData.user.id,
    action: "ai.tool",
    entity_table: "mensajes",
    entity_id: msg.id,
    after: { tool: "draft_message", template_key: templateKey, sent: false },
  });

  return json(200, {
    ok: true,
    mensaje_id: msg.id,
    template_key: templateKey,
    bloque_key: bloqueKey,
    asunto,
    cuerpo,
  });
});

function fill(source: string, vars: Record<string, string>): string {
  let out = source;
  for (const [k, v] of Object.entries(vars)) {
    out = out.replaceAll(`{{${k}}}`, v);
  }
  return out.replace(/\{\{[a-z_]+\}\}/g, "—");
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
) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}
