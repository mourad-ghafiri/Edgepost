import type { Address } from "./types";

const EMAIL_RE = /^[^\s@<>()",;:\\[\]]+@[^\s@<>()",;:\\[\]]+\.[^\s@<>()",;:\\[\]]+$/;
const DOMAIN_RE = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;

export function isEmail(value: string): boolean {
  return value.length <= 320 && EMAIL_RE.test(value);
}

export function isDomain(value: string): boolean {
  return DOMAIN_RE.test(value);
}

export function normalizeEmail(value: string): string {
  return value.trim().toLowerCase();
}

export function domainOf(address: string): string {
  const at = address.lastIndexOf("@");
  return at >= 0 ? address.slice(at + 1).toLowerCase() : "";
}

/** True when the address's domain is one of `domains` or a subdomain of one. */
export function belongsToDomains(address: string, domains: readonly string[]): boolean {
  const domain = domainOf(address);
  if (!domain) return false;
  return domains.some((d) => domain === d || domain.endsWith(`.${d}`));
}

/** Every `<...>` token in a Message-ID style header, in order. Falls back to whitespace tokens. */
export function parseMessageIds(value: string | null | undefined): string[] {
  if (!value) return [];
  const bracketed = value.match(/<[^<>\s]+>/g);
  if (bracketed && bracketed.length > 0) return bracketed;
  return value
    .split(/[\s,]+/)
    .map((t) => t.trim())
    .filter((t) => t.length > 0 && t.includes("@"))
    .map((t) => `<${t.replace(/^<|>$/g, "")}>`);
}

/** Normalises a Message-ID to the `<...>` form; null for empty input. */
export function normalizeMessageId(value: string | null | undefined): string | null {
  const raw = (value ?? "").trim();
  if (!raw) return null;
  const inner = raw.replace(/^<+/, "").replace(/>+$/, "").trim();
  return inner ? `<${inner}>` : null;
}

const ENTITIES: Record<string, string> = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " ",
};

function decodeEntities(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, entity: string) => {
    const lower = entity.toLowerCase();
    if (lower.startsWith("#x")) return safeCodePoint(Number.parseInt(lower.slice(2), 16)) ?? whole;
    if (lower.startsWith("#")) return safeCodePoint(Number.parseInt(lower.slice(1), 10)) ?? whole;
    return ENTITIES[lower] ?? whole;
  });
}

function safeCodePoint(cp: number): string | null {
  if (!Number.isFinite(cp) || cp < 0 || cp > 0x10ffff) return null;
  try {
    return String.fromCodePoint(cp);
  } catch {
    return null;
  }
}

/** Rough HTML to text for snippets and the search index (never rendered). */
export function htmlToText(html: string): string {
  return decodeEntities(
    html
      .replace(/<(script|style|head|title)\b[\s\S]*?<\/\1\s*>/gi, " ")
      .replace(/<!--[\s\S]*?-->/g, " ")
      .replace(/<(br|\/p|\/div|\/li|\/tr|\/h[1-6])\b[^>]*>/gi, "\n")
      .replace(/<[^>]+>/g, " "),
  );
}

export function bodyText(text: string | null | undefined, html: string | null | undefined): string {
  if (text && text.trim()) return text;
  if (html && html.trim()) return htmlToText(html);
  return "";
}

/** First ~160 characters of the text body (or HTML converted to text), whitespace collapsed. */
export function makeSnippet(text: string | null | undefined, html: string | null | undefined): string {
  const collapsed = bodyText(text, html).replace(/\s+/g, " ").trim();
  const chars = Array.from(collapsed);
  return chars.length > 160 ? chars.slice(0, 160).join("").trimEnd() : collapsed;
}

export function truncateChars(value: string, max: number): string {
  return value.length > max ? value.slice(0, max) : value;
}

export function participantsText(from: Address, ...lists: Address[][]): string {
  const all = [from, ...lists.flat()];
  return all.map((a) => `${a.name ?? ""} ${a.address}`.trim()).join(" ");
}

export function utf8Length(value: string | null | undefined): number {
  return value ? new TextEncoder().encode(value).byteLength : 0;
}

export function toIsoOrNull(value: string | null | undefined): string | null {
  if (!value) return null;
  const t = Date.parse(value);
  return Number.isFinite(t) ? new Date(t).toISOString() : null;
}

export function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
