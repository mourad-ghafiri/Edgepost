// Per-domain branding: the signature and logo the app puts at the end of mail sent from a domain.
// The signature is plain text (the app renders it); the logo is a PNG kept in R2 and attached
// inline (Content-ID) to outgoing mail on request, so it shows without loading remote images.

import { badRequest, HttpError } from "./http";
import type { Env, MailConfig } from "./types";

export const MAX_SIGNATURE_CHARS = 2000;
/** The app scales logos to 480×96 (2× their shown size), well under this. */
export const MAX_LOGO_BYTES = 256 * 1024;
const MAX_LOGO_SIDE = 2000;
/** The Content-ID of the logo in outgoing mail (`<img src="cid:logo@edgepost">`). */
export const BRAND_LOGO_CID = "logo@edgepost";
export const LOGO_TYPE = "image/png";

export const logoKey = (domain: string): string => `brand/${domain}/logo`;

export interface BrandLogo {
  type: string;
  size: number;
  width: number;
  height: number;
  updatedAt: string;
}

export interface Brand {
  domain: string;
  signature: string;
  logo: BrandLogo | null;
}

interface BrandRow {
  domain: string;
  signature: string;
  logo_type: string | null;
  logo_size: number | null;
  logo_width: number | null;
  logo_height: number | null;
  updated_at: string;
}

function rowToBrand(domain: string, row: BrandRow | null): Brand {
  if (!row) return { domain, signature: "", logo: null };
  const logo =
    row.logo_type && row.logo_size !== null && row.logo_width !== null && row.logo_height !== null
      ? { type: row.logo_type, size: row.logo_size, width: row.logo_width, height: row.logo_height, updatedAt: row.updated_at }
      : null;
  return { domain, signature: row.signature, logo };
}

/** A domain the mail service handles, lower-cased; anything else is 404. */
export function requireDomain(config: MailConfig, value: string): string {
  const domain = value.trim().toLowerCase();
  if (!config.domains.includes(domain)) {
    throw new HttpError(404, "domain_not_configured", `${domain} is not one of this mail service's domains`);
  }
  return domain;
}

async function getRow(db: D1Database, domain: string): Promise<BrandRow | null> {
  return db.prepare("SELECT * FROM brands WHERE domain = ?").bind(domain).first<BrandRow>();
}

export async function getBrand(db: D1Database, domain: string): Promise<Brand> {
  return rowToBrand(domain, await getRow(db, domain));
}

/** Every configured domain's brand, in config order (blank when never set). */
export async function listBrands(db: D1Database, config: MailConfig): Promise<Brand[]> {
  const { results } = await db.prepare("SELECT * FROM brands").all<BrandRow>();
  const byDomain = new Map(results.map((r) => [r.domain, r]));
  return config.domains.map((d) => rowToBrand(d, byDomain.get(d) ?? null));
}

export function parseSignature(body: unknown): string {
  if (typeof body !== "object" || body === null || typeof (body as { signature?: unknown }).signature !== "string") {
    throw badRequest("signature must be a string");
  }
  const signature = ((body as { signature: string }).signature).replace(/\r\n?/g, "\n").trim();
  if (signature.length > MAX_SIGNATURE_CHARS) {
    throw badRequest(`signature must be at most ${MAX_SIGNATURE_CHARS} characters`, "signature_too_long");
  }
  return signature;
}

export async function putSignature(db: D1Database, domain: string, signature: string): Promise<Brand> {
  await db
    .prepare(
      `INSERT INTO brands (domain, signature, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(domain) DO UPDATE SET signature = excluded.signature, updated_at = excluded.updated_at`,
    )
    .bind(domain, signature, new Date().toISOString())
    .run();
  return getBrand(db, domain);
}

/** Width and height from a PNG's IHDR chunk, or null when the bytes are not a PNG. */
export function pngSize(bytes: Uint8Array): { width: number; height: number } | null {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.byteLength < 24 || signature.some((b, i) => bytes[i] !== b)) return null;
  // IHDR is the first chunk: length (4), "IHDR" (4), width (4), height (4).
  if (String.fromCharCode(...bytes.subarray(12, 16)) !== "IHDR") return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { width: view.getUint32(16), height: view.getUint32(20) };
}

export async function putLogo(env: Env, domain: string, bytes: Uint8Array): Promise<Brand> {
  if (bytes.byteLength === 0) throw badRequest("The logo is empty", "invalid_logo");
  if (bytes.byteLength > MAX_LOGO_BYTES) {
    throw new HttpError(413, "logo_too_large", `The logo must be at most ${MAX_LOGO_BYTES} bytes`, {
      size: bytes.byteLength,
      limit: MAX_LOGO_BYTES,
    });
  }
  const size = pngSize(bytes);
  if (!size) throw badRequest("The logo must be a PNG image", "invalid_logo");
  if (size.width < 1 || size.height < 1 || size.width > MAX_LOGO_SIDE || size.height > MAX_LOGO_SIDE) {
    throw badRequest(`The logo must be between 1 and ${MAX_LOGO_SIDE} pixels on each side`, "invalid_logo");
  }
  await env.MAIL.put(logoKey(domain), bytes, { httpMetadata: { contentType: LOGO_TYPE } });
  await env.DB.prepare(
    `INSERT INTO brands (domain, signature, logo_type, logo_size, logo_width, logo_height, updated_at)
     VALUES (?, '', ?, ?, ?, ?, ?)
     ON CONFLICT(domain) DO UPDATE SET logo_type = excluded.logo_type, logo_size = excluded.logo_size,
       logo_width = excluded.logo_width, logo_height = excluded.logo_height, updated_at = excluded.updated_at`,
  )
    .bind(domain, LOGO_TYPE, bytes.byteLength, size.width, size.height, new Date().toISOString())
    .run();
  return getBrand(env.DB, domain);
}

export async function deleteLogo(env: Env, domain: string): Promise<Brand> {
  await env.MAIL.delete(logoKey(domain));
  await env.DB.prepare(
    `UPDATE brands SET logo_type = NULL, logo_size = NULL, logo_width = NULL, logo_height = NULL, updated_at = ?
     WHERE domain = ?`,
  )
    .bind(new Date().toISOString(), domain)
    .run();
  return getBrand(env.DB, domain);
}

/** The domain's logo bytes, or null when it has none. */
export async function getLogo(env: Env, domain: string): Promise<Uint8Array | null> {
  const brand = await getBrand(env.DB, domain);
  if (!brand.logo) return null;
  const obj = await env.MAIL.get(logoKey(domain));
  return obj ? new Uint8Array(await obj.arrayBuffer()) : null;
}
