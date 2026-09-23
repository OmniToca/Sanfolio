/**
 * Formáty Verifacti a výklad stavu AEAT.
 * PROČ: create i ověření musí stejné datum a stejné Pendiente → emitida.
 */

import { corsHeaders } from "./cors.ts";

/** @deprecated použij corsHeaders(req); ponecháno jako alias bez Origin. */
export function sifCors(req?: Request): Record<string, string> {
  return corsHeaders(req);
}

export type BookEstado = "pendiente" | "emitida" | "error" | "anulada";

export function sifConfig(): { vendor: string; apiUrl: string; apiKey: string } {
  return {
    vendor: (Deno.env.get("SIF_VENDOR") ?? "verifacti").trim().toLowerCase(),
    apiUrl: (Deno.env.get("SIF_API_URL") ?? "").replace(/\/$/, ""),
    apiKey: Deno.env.get("SIF_API_KEY") ?? "",
  };
}

/** Dnešek v Europe/Madrid jako DD-MM-YYYY — fecha_expedicion u Verifacti. */
export function madridTodayDmy(): string {
  return formatDmy(new Date(), "Europe/Madrid");
}

export function madridTodayIso(): string {
  const dmy = madridTodayDmy();
  return dmyToIso(dmy) ?? dmy;
}

/** ISO DATE z Postgres → DD-MM-YYYY. */
export function isoToDmy(iso: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso.trim());
  if (!m) return iso.trim();
  return `${m[3]}-${m[2]}-${m[1]}`;
}

export function dmyToIso(dmy: string): string | null {
  const m = /^(\d{2})-(\d{2})-(\d{4})$/.exec(dmy.trim());
  if (!m) return null;
  return `${m[3]}-${m[2]}-${m[1]}`;
}

/** Částky jako ve Verifacti příkladech: "21", ne "21.00". */
export function amountString(cents: number): string {
  const n = Number.isFinite(cents) ? cents : 0;
  if (n % 100 === 0) return String(n / 100);
  return (n / 100).toFixed(2);
}

export function tipoImpositivo(ivaBps: number): string {
  const bps = ivaBps > 0 ? ivaBps : 0;
  if (bps % 100 === 0) return String(bps / 100);
  return (bps / 100).toFixed(2);
}

/** F2 zjednodušená — AEAT 3000 €. */
export const f2MaxCents = 300000;

export type TaxLine = {
  base_imponible: string;
  tipo_impositivo: string;
  cuota_repercutida: string;
};

/**
 * Obchodní `facturas.lineas` → Verifacti sazby (max 12).
 * Prázdné JSON padá na součty knihy (staré koncepty bez řádků).
 */
export function taxLinesFromFactura(factura: Record<string, unknown>): TaxLine[] {
  const grouped = new Map<number, { base: number; iva: number }>();
  const raw = factura.lineas;
  if (Array.isArray(raw) && raw.length > 0) {
    for (const item of raw) {
      const rec = asRecord(item);
      if (!rec) continue;
      const storedBase = rec.base_cents;
      const storedIva = rec.iva_cents;
      const ivaBps = ivaRateBps(rec.iva_bps);
      const qty = parseQty(rec.cantidad) ?? 1;
      const precio = num(rec.precio_cents);
      const descBps = Math.min(10000, Math.max(0, num(rec.descuento_bps)));
      const gross = Math.round(qty * precio);
      const base = storedBase === null || storedBase === undefined || str(storedBase) === ""
        ? Math.round((gross * (10000 - descBps)) / 10000)
        : num(storedBase);
      const iva = storedIva === null || storedIva === undefined || str(storedIva) === ""
        ? Math.round((base * ivaBps) / 10000)
        : num(storedIva);
      if (base === 0 && iva === 0) continue;
      const prev = grouped.get(ivaBps) ?? { base: 0, iva: 0 };
      grouped.set(ivaBps, { base: prev.base + base, iva: prev.iva + iva });
    }
  }
  if (grouped.size === 0) {
    const ivaBps = num(factura.iva_bps) || 2100;
    return [
      {
        base_imponible: amountString(num(factura.base_cents)),
        tipo_impositivo: tipoImpositivo(ivaBps),
        cuota_repercutida: amountString(num(factura.iva_cents)),
      },
    ];
  }
  return [...grouped.entries()]
    .sort((a, b) => b[0] - a[0])
    .slice(0, 12)
    .map(([bps, sums]) => ({
      base_imponible: amountString(sums.base),
      tipo_impositivo: tipoImpositivo(bps),
      cuota_repercutida: amountString(sums.iva),
    }));
}

function parseQty(v: unknown): number | null {
  const s = str(v).replace(/\s/g, "").replace(",", ".");
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

function ivaRateBps(v: unknown): number {
  if (v === null || v === undefined || str(v) === "") return 2100;
  return num(v);
}

function num(v: unknown): number {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  return parseInt(`${v ?? 0}`, 10) || 0;
}

export function qrToStored(raw: unknown): string | null {
  const s = str(raw);
  if (!s) return null;
  if (/^https?:\/\//i.test(s) || s.startsWith("data:")) return s;
  const compact = s.replace(/\s/g, "");
  if (compact.length < 32) return s;
  return `data:image/png;base64,${compact}`;
}

/** AEAT ValidarQR URL from create (`url`), never the PNG base64. */
export function extractAeatUrl(parsed: Record<string, unknown>): string | null {
  const rec = unwrapRecord(parsed);
  const u = str(rec.url);
  if (/^https?:\/\//i.test(u)) return u;
  return null;
}

export function asRecord(v: unknown): Record<string, unknown> | null {
  if (v && typeof v === "object" && !Array.isArray(v)) {
    return v as Record<string, unknown>;
  }
  return null;
}

export function unwrapRecord(parsed: Record<string, unknown>): Record<string, unknown> {
  const inner = asRecord(parsed.data) ?? asRecord(parsed.registro);
  return inner ?? parsed;
}

export function extractUuid(parsed: Record<string, unknown>): string {
  const rec = unwrapRecord(parsed);
  return str(rec.uuid ?? rec.id ?? rec.Id ?? rec.sif_external_id);
}

export function extractEstadoRaw(parsed: Record<string, unknown>): string {
  const rec = unwrapRecord(parsed);
  return str(
    rec.estado ?? rec.status ?? rec.Estado ?? rec.resultado ?? rec.aeat_estado,
  );
}

/**
 * Verifacti/AEAT text → kniha. Neznámé necháme pendiente a uložíme raw.
 */
export function mapBookEstado(raw: string): BookEstado | null {
  const s = raw
    .trim()
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{M}/gu, "");
  if (!s) return null;
  if (s.includes("anul")) return "anulada";
  if (
    s.includes("incorrect") ||
    s.includes("rechaz") ||
    s.includes("error") ||
    s.includes("deneg")
  ) {
    return "error";
  }
  if (s.includes("correct") || s.includes("acept") || s === "ok") {
    return "emitida";
  }
  if (
    s.includes("pend") ||
    s.includes("cola") ||
    s.includes("proces") ||
    s.includes("enviad")
  ) {
    return "pendiente";
  }
  return null;
}

export function bookEstadoFromCreate(httpOk: boolean, rawEstado: string): BookEstado {
  if (!httpOk) return "error";
  return mapBookEstado(rawEstado) ?? "pendiente";
}

export async function fetchVerifactiStatus(opts: {
  apiUrl: string;
  apiKey: string;
  uuid?: string | null;
  serie?: string;
  numero?: string;
  fechaExpedicionDmy?: string;
}): Promise<{ http: number; parsed: Record<string, unknown>; text: string }> {
  const headers = {
    Authorization: `Bearer ${opts.apiKey}`,
    "Content-Type": "application/json",
  };
  const uuid = (opts.uuid ?? "").trim();
  if (uuid) {
    const byQuery = await readJson(
      `${opts.apiUrl}/verifactu/status?uuid=${encodeURIComponent(uuid)}`,
      { headers },
    );
    if (usableStatus(byQuery.http)) return byQuery;
    const byPath = await readJson(
      `${opts.apiUrl}/verifactu/status/${encodeURIComponent(uuid)}`,
      { headers },
    );
    if (usableStatus(byPath.http)) return byPath;
  }
  const serie = opts.serie ?? "";
  const numero = opts.numero ?? "";
  const fecha = opts.fechaExpedicionDmy ?? "";
  if (!numero || !fecha) {
    return { http: 400, parsed: { error: "status_keys_missing" }, text: "" };
  }
  return await readJson(`${opts.apiUrl}/verifactu/status`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      serie,
      numero,
      fecha_expedicion: fecha,
    }),
  });
}

export function json(
  status: number,
  body: Record<string, unknown>,
  req?: Request,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), "Content-Type": "application/json" },
  });
}

export function str(v: unknown): string {
  return `${v ?? ""}`.trim();
}

function usableStatus(http: number): boolean {
  if (http === 401 || http === 403) return true;
  return http >= 200 && http < 300;
}

function formatDmy(at: Date, timeZone: string): string {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    day: "2-digit",
    month: "2-digit",
    year: "numeric",
  }).formatToParts(at);
  const bag: Record<string, string> = {};
  for (const p of parts) bag[p.type] = p.value;
  return `${bag.day}-${bag.month}-${bag.year}`;
}

async function readJson(
  url: string,
  init: RequestInit,
): Promise<{ http: number; parsed: Record<string, unknown>; text: string }> {
  const res = await fetch(url, init);
  const text = await res.text();
  let parsed: Record<string, unknown> = {};
  try {
    const v = text ? JSON.parse(text) : {};
    parsed = asRecord(v) ?? { raw: text.slice(0, 2000) };
  } catch {
    parsed = { raw: text.slice(0, 2000) };
  }
  return { http: res.status, parsed, text };
}
