import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  extractAeatUrl,
  extractEstadoRaw,
  extractUuid,
  fetchVerifactiStatus,
  isoToDmy,
  json,
  mapBookEstado,
  qrToStored,
  sifConfig,
  str,
  unwrapRecord,
} from "../_shared/sif_verifacti.ts";

/**
 * Ověření vydané u Verifacti (GET /verifactu/status). Flutter jen klikne.
 * emitida až když AEAT přijme; pendiente jinak. AI tuhle funkci nevolá.
 */

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return json(200, { ok: true });
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
    factura_id?: unknown;
  };
  const tenantId = typeof body.tenant_id === "string" ? body.tenant_id.trim() : "";
  const facturaId = typeof body.factura_id === "string"
    ? body.factura_id.trim()
    : "";
  if (!tenantId || !facturaId) {
    return json(400, { ok: false, error: "tenant_id, factura_id required" });
  }

  const { data: allowed, error: accessErr } = await userClient.rpc(
    "can_access_tenant",
    { _tenant_id: tenantId },
  );
  if (accessErr) return json(500, { ok: false, error: accessErr.message });
  if (allowed !== true) return json(403, { ok: false, error: "forbidden" });

  const { data: factura, error: factErr } = await userClient
    .from("facturas")
    .select(
      "id, tenant_id, direccion, estado, serie, numero, fecha, " +
        "sif_external_id, sif_status, sif_fecha_expedicion",
    )
    .eq("id", facturaId)
    .eq("tenant_id", tenantId)
    .is("deleted_at", null)
    .maybeSingle();
  if (factErr) return json(500, { ok: false, error: factErr.message });
  if (!factura) return json(404, { ok: false, error: "factura_missing" });
  if (factura.direccion !== "emitida") {
    return json(400, { ok: false, error: "not_issued" });
  }
  if (factura.estado === "anulada") {
    return json(409, { ok: false, error: "anulada" });
  }

  const uuid = str(factura.sif_external_id);
  const fechaExpIso = str(factura.sif_fecha_expedicion) || str(factura.fecha);
  if (!uuid && (!str(factura.numero) || !fechaExpIso)) {
    return json(400, { ok: false, error: "not_submitted" });
  }

  const { vendor, apiUrl, apiKey } = sifConfig();
  if (!apiUrl || !apiKey) {
    return json(501, { ok: false, error: "sif_not_configured" });
  }
  if (vendor !== "verifacti") {
    return json(400, { ok: false, error: "unsupported_vendor" });
  }

  const result = await fetchVerifactiStatus({
    apiUrl,
    apiKey,
    uuid: uuid || null,
    serie: str(factura.serie),
    numero: str(factura.numero),
    fechaExpedicionDmy: fechaExpIso.includes("-") && fechaExpIso.length === 10 &&
        fechaExpIso[4] === "-"
      ? isoToDmy(fechaExpIso)
      : fechaExpIso,
  });

  const rawEstado = extractEstadoRaw(result.parsed) || str(result.parsed.error);
  const mapped = mapBookEstado(rawEstado);
  const bookEstado = mapped ??
    (result.http >= 200 && result.http < 300 ? "pendiente" : "error");
  const newUuid = extractUuid(result.parsed) || uuid || null;

  if (result.http >= 200 && result.http < 300) {
    const rec = unwrapRecord(result.parsed);
    const qr = qrToStored(rec.qr ?? rec.qr_image ?? rec.sif_qr_url);
    const aeatUrl = extractAeatUrl(result.parsed);
    await userClient.from("facturas").update({
      estado: bookEstado,
      sif_provider: vendor,
      sif_external_id: newUuid,
      sif_status: rawEstado || bookEstado,
      ...(qr ? { sif_qr_url: qr } : {}),
      ...(aeatUrl ? { sif_aeat_url: aeatUrl } : {}),
      sif_error: bookEstado === "error"
        ? (str(result.parsed.error) || result.text.slice(0, 500) || rawEstado)
        : null,
    }).eq("id", facturaId).eq("tenant_id", tenantId);

    return json(200, {
      ok: true,
      sif_external_id: newUuid,
      sif_status: rawEstado || bookEstado,
      book_estado: bookEstado,
      sif_qr_url: qr,
      sif_aeat_url: aeatUrl,
    });
  }

  await userClient.from("facturas").update({
    sif_status: rawEstado || "error",
    sif_error: str(result.parsed.error) || result.text.slice(0, 500),
  }).eq("id", facturaId).eq("tenant_id", tenantId);

  return json(502, {
    ok: false,
    error: "sif_status_failed",
    sif_status: rawEstado || "error",
    book_estado: factura.estado,
  });
});

function supabaseUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}
function supabaseAnonKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}
