import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  amountString,
  bookEstadoFromCreate,
  extractAeatUrl,
  extractEstadoRaw,
  extractUuid,
  f2MaxCents,
  isoToDmy,
  json,
  madridTodayDmy,
  madridTodayIso,
  qrToStored,
  sifConfig,
  str,
  taxLinesFromFactura,
} from "../_shared/sif_verifacti.ts";

/**
 * Koncept vydané → Verifacti create. Flutter sem nestrká klíč ani XML.
 * Po 200 je kniha pendiente; emitida až po sif-status (AEAT).
 */

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return json(200, { ok: true }, req);
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
      "id, tenant_id, direccion, estado, serie, numero, fecha, concepto, " +
        "destinatario_nombre, destinatario_nif, tipo_factura, lineas, " +
        "base_cents, iva_cents, iva_bps, total_cents, sif_external_id, " +
        "sif_status, sif_fecha_expedicion",
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
  const existingId = str(factura.sif_external_id);
  if (existingId) {
    return json(200, {
      ok: true,
      sif_external_id: existingId,
      sif_status: str(factura.sif_status) || factura.estado,
      book_estado: factura.estado,
    });
  }

  const { data: settings, error: setErr } = await userClient
    .from("tenant_settings")
    .select("emisor_nif, emisor_nombre, factura_serie, display_name")
    .eq("tenant_id", tenantId)
    .maybeSingle();
  if (setErr) return json(500, { ok: false, error: setErr.message });
  const emisorNif = `${settings?.emisor_nif ?? ""}`.trim().toUpperCase();
  if (!emisorNif) {
    return json(400, { ok: false, error: "emisor_nif_required" });
  }

  const serie = `${factura.serie ?? settings?.factura_serie ?? "A"}`.trim();
  const numero = `${factura.numero ?? ""}`.trim();
  const fechaOperacionIso = `${factura.fecha ?? ""}`.trim();
  if (!numero || !fechaOperacionIso) {
    return json(400, { ok: false, error: "numero_fecha_required" });
  }
  if (`${serie}${numero}`.length > 60) {
    return json(400, { ok: false, error: "serie_numero_too_long" });
  }

  const destinatarioNif = `${factura.destinatario_nif ?? ""}`.trim().toUpperCase();
  const destinatarioNombre = `${factura.destinatario_nombre ?? ""}`.trim();
  const tipoFactura = `${factura.tipo_factura ?? "F1"}`.trim().toUpperCase() || "F1";
  const isF2 = tipoFactura === "F2";
  if (!isF2 && (!destinatarioNif || !destinatarioNombre)) {
    return json(400, { ok: false, error: "destinatario_required" });
  }
  if (isF2 && num(factura.total_cents) > f2MaxCents) {
    return json(400, { ok: false, error: "f2_over_limit" });
  }

  const { vendor, apiUrl, apiKey } = sifConfig();
  if (!apiUrl || !apiKey) {
    return json(501, { ok: false, error: "sif_not_configured" });
  }
  if (vendor !== "verifacti") {
    return json(400, { ok: false, error: "unsupported_vendor" });
  }

  const fechaExpedicionDmy = madridTodayDmy();
  const fechaExpedicionIso = madridTodayIso();
  const fechaOperacionDmy = isoToDmy(fechaOperacionIso);
  const lineas = taxLinesFromFactura(factura as Record<string, unknown>);
  if (lineas.length === 0) {
    return json(400, { ok: false, error: "lineas_required" });
  }
  const payload: Record<string, unknown> = {
    serie,
    numero,
    fecha_expedicion: fechaExpedicionDmy,
    fecha_operacion: fechaOperacionDmy,
    tipo_factura: isF2 ? "F2" : "F1",
    descripcion: `${factura.concepto ?? ""}`.trim() || "Servicios",
    lineas,
    importe_total: amountString(num(factura.total_cents)),
  };
  if (destinatarioNif) payload.nif = destinatarioNif;
  if (destinatarioNombre) payload.nombre = destinatarioNombre;

  const res = await fetch(`${apiUrl}/verifactu/create`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      "Idempotency-Key": facturaId,
    },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  let parsed: Record<string, unknown> = {};
  try {
    parsed = text ? JSON.parse(text) as Record<string, unknown> : {};
  } catch {
    parsed = { raw: text.slice(0, 2000) };
  }

  if (res.status === 409) {
    return json(409, { ok: false, error: "sif_in_flight" });
  }

  const externalId = extractUuid(parsed);
  const rawEstado = extractEstadoRaw(parsed);
  const qr = qrToStored(
    parsed.qr ?? parsed.qr_image ?? parsed.sif_qr_url,
  );
  const aeatUrl = extractAeatUrl(parsed);
  const ok = res.ok;
  const bookEstado = bookEstadoFromCreate(ok, rawEstado);

  await userClient.from("facturas").update({
    estado: bookEstado,
    sif_provider: vendor,
    sif_external_id: externalId || null,
    sif_status: rawEstado || (ok ? "Pendiente" : "error"),
    sif_qr_url: qr,
    sif_aeat_url: aeatUrl,
    sif_fecha_expedicion: ok ? fechaExpedicionIso : null,
    sif_error: ok ? null : (str(parsed.error) || text.slice(0, 500)),
  }).eq("id", facturaId).eq("tenant_id", tenantId);

  if (!ok) {
    return json(502, {
      ok: false,
      error: res.status === 422 ? "sif_idempotency_conflict" : "sif_rejected",
      sif_status: rawEstado || "error",
      book_estado: bookEstado,
    });
  }
  return json(200, {
    ok: true,
    sif_external_id: externalId,
    sif_status: rawEstado || "Pendiente",
    book_estado: bookEstado,
    sif_qr_url: qr,
    sif_aeat_url: aeatUrl,
  });
});

function num(v: unknown): number {
  if (typeof v === "number") return v;
  return parseInt(`${v ?? 0}`, 10) || 0;
}
function supabaseUrl(): string {
  return Deno.env.get("SUPABASE_URL") ?? "";
}
function supabaseAnonKey(): string {
  return Deno.env.get("SUPABASE_ANON_KEY") ?? "";
}
