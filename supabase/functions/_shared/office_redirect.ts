/**
 * Kam má Auth poslat odkaz z invite / recovery.
 *
 * Hosted GoTrue odmítne redirect, který není v Allow listu. Localhost
 * fallback z config.json by na produkci účet vůbec nezaložil — kolega
 * pak v Auth Users není a UI jen řekne „pozvánku se nepodařilo odeslat“.
 */
export function officeInviteRedirect(): string {
  const fallback = "https://sanfolio.app";
  const raw = (Deno.env.get("GESTORIA_BASE_URL") ?? "").trim().replace(
    /\/$/,
    "",
  );
  let base = fallback;
  if (raw) {
    try {
      const host = new URL(raw).hostname.toLowerCase();
      if (host && host !== "localhost" && host !== "127.0.0.1") {
        base = raw;
      }
    } catch {
      base = fallback;
    }
  }
  return `${base}/reset-password`;
}
