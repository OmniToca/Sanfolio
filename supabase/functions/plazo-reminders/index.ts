import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

/**
 * Ranní cron: nachystá draft mensajes. Nikdy neodesílá.
 * Auth: CRON_SECRET nebo service_role. AI / gestor sem nepatří.
 */

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json(405, { ok: false, error: "Method not allowed" });
  }

  const token = (req.headers.get("Authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  ).trim();
  const cronSecret = Deno.env.get("CRON_SECRET")?.trim() ?? "";
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() ?? "";
  const allowed = (cronSecret !== "" && token === cronSecret) ||
    (service !== "" && token === service);
  if (!allowed) {
    return json(401, { ok: false, error: "Unauthorized" });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    service,
  );
  const { data, error } = await admin.rpc("run_plazo_reminders", {
    p_force: true,
  });
  if (error) {
    return json(500, { ok: false, error: error.message });
  }
  return json(200, { ok: true, result: data });
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
