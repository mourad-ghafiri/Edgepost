var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/http.ts
var HttpError = class extends Error {
  constructor(status, code, message, extra = {}) {
    super(message);
    this.status = status;
    this.code = code;
    this.extra = extra;
    this.name = "HttpError";
  }
  status;
  code;
  extra;
  static {
    __name(this, "HttpError");
  }
};
var BASE_HEADERS = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff"
};
function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...BASE_HEADERS, ...headers }
  });
}
__name(json, "json");
function errorJson(status, code, message, extra = {}, headers = {}) {
  return json({ error: { code, message, ...extra } }, status, headers);
}
__name(errorJson, "errorJson");
function fromHttpError(err) {
  return errorJson(err.status, err.code, err.message, err.extra);
}
__name(fromHttpError, "fromHttpError");
var badRequest = /* @__PURE__ */ __name((message, code = "invalid_request") => new HttpError(400, code, message), "badRequest");
var notFound = /* @__PURE__ */ __name((message = "Not found") => new HttpError(404, "not_found", message), "notFound");
function withBaseHeaders(headers) {
  return { ...BASE_HEADERS, ...headers };
}
__name(withBaseHeaders, "withBaseHeaders");

// src/auth.ts
var encoder = new TextEncoder();
function isAuthorized(request, apiKey) {
  if (!apiKey) return false;
  const header = request.headers.get("Authorization") ?? "";
  const match2 = /^Bearer[ \t]+(\S+)[ \t]*$/i.exec(header);
  if (!match2) return false;
  const presented = encoder.encode(match2[1]);
  const secret = encoder.encode(apiKey);
  const lengthsMatch = presented.byteLength === secret.byteLength;
  return lengthsMatch ? crypto.subtle.timingSafeEqual(presented, secret) : !crypto.subtle.timingSafeEqual(presented, presented);
}
__name(isAuthorized, "isAuthorized");
function unauthorized() {
  return errorJson(401, "unauthorized", "Missing or invalid API key", {}, { "WWW-Authenticate": "Bearer" });
}
__name(unauthorized, "unauthorized");

// src/brand.ts
var MAX_SIGNATURE_CHARS = 2e3;
var MAX_LOGO_BYTES = 256 * 1024;
var MAX_LOGO_SIDE = 2e3;
var BRAND_LOGO_CID = "logo@edgepost";
var LOGO_TYPE = "image/png";
var logoKey = /* @__PURE__ */ __name((domain) => `brand/${domain}/logo`, "logoKey");
function rowToBrand(domain, row) {
  if (!row) return { domain, signature: "", logo: null };
  const logo = row.logo_type && row.logo_size !== null && row.logo_width !== null && row.logo_height !== null ? { type: row.logo_type, size: row.logo_size, width: row.logo_width, height: row.logo_height, updatedAt: row.updated_at } : null;
  return { domain, signature: row.signature, logo };
}
__name(rowToBrand, "rowToBrand");
function requireDomain(config, value) {
  const domain = value.trim().toLowerCase();
  if (!config.domains.includes(domain)) {
    throw new HttpError(404, "domain_not_configured", `${domain} is not one of this mail service's domains`);
  }
  return domain;
}
__name(requireDomain, "requireDomain");
async function getRow(db, domain) {
  return db.prepare("SELECT * FROM brands WHERE domain = ?").bind(domain).first();
}
__name(getRow, "getRow");
async function getBrand(db, domain) {
  return rowToBrand(domain, await getRow(db, domain));
}
__name(getBrand, "getBrand");
async function listBrands(db, config) {
  const { results } = await db.prepare("SELECT * FROM brands").all();
  const byDomain = new Map(results.map((r) => [r.domain, r]));
  return config.domains.map((d) => rowToBrand(d, byDomain.get(d) ?? null));
}
__name(listBrands, "listBrands");
function parseSignature(body) {
  if (typeof body !== "object" || body === null || typeof body.signature !== "string") {
    throw badRequest("signature must be a string");
  }
  const signature = body.signature.replace(/\r\n?/g, "\n").trim();
  if (signature.length > MAX_SIGNATURE_CHARS) {
    throw badRequest(`signature must be at most ${MAX_SIGNATURE_CHARS} characters`, "signature_too_long");
  }
  return signature;
}
__name(parseSignature, "parseSignature");
async function putSignature(db, domain, signature) {
  await db.prepare(
    `INSERT INTO brands (domain, signature, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(domain) DO UPDATE SET signature = excluded.signature, updated_at = excluded.updated_at`
  ).bind(domain, signature, (/* @__PURE__ */ new Date()).toISOString()).run();
  return getBrand(db, domain);
}
__name(putSignature, "putSignature");
function pngSize(bytes) {
  const signature = [137, 80, 78, 71, 13, 10, 26, 10];
  if (bytes.byteLength < 24 || signature.some((b, i) => bytes[i] !== b)) return null;
  if (String.fromCharCode(...bytes.subarray(12, 16)) !== "IHDR") return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  return { width: view.getUint32(16), height: view.getUint32(20) };
}
__name(pngSize, "pngSize");
async function putLogo(env, domain, bytes) {
  if (bytes.byteLength === 0) throw badRequest("The logo is empty", "invalid_logo");
  if (bytes.byteLength > MAX_LOGO_BYTES) {
    throw new HttpError(413, "logo_too_large", `The logo must be at most ${MAX_LOGO_BYTES} bytes`, {
      size: bytes.byteLength,
      limit: MAX_LOGO_BYTES
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
       logo_width = excluded.logo_width, logo_height = excluded.logo_height, updated_at = excluded.updated_at`
  ).bind(domain, LOGO_TYPE, bytes.byteLength, size.width, size.height, (/* @__PURE__ */ new Date()).toISOString()).run();
  return getBrand(env.DB, domain);
}
__name(putLogo, "putLogo");
async function deleteLogo(env, domain) {
  await env.MAIL.delete(logoKey(domain));
  await env.DB.prepare(
    `UPDATE brands SET logo_type = NULL, logo_size = NULL, logo_width = NULL, logo_height = NULL, updated_at = ?
     WHERE domain = ?`
  ).bind((/* @__PURE__ */ new Date()).toISOString(), domain).run();
  return getBrand(env.DB, domain);
}
__name(deleteLogo, "deleteLogo");
async function getLogo(env, domain) {
  const brand = await getBrand(env.DB, domain);
  if (!brand.logo) return null;
  const obj = await env.MAIL.get(logoKey(domain));
  return obj ? new Uint8Array(await obj.arrayBuffer()) : null;
}
__name(getLogo, "getLogo");

// src/budget.ts
var SEND_WINDOW_DAYS = 31;
var DAY_MS = 864e5;
var WINDOW_MS = SEND_WINDOW_DAYS * DAY_MS;
var SEND_LOG_RETENTION_DAYS = 40;
function sendUsageStatement(db, now = Date.now()) {
  return db.prepare("SELECT COALESCE(SUM(recipients), 0) AS used, MIN(ts) AS oldest FROM send_log WHERE ts > ?1").bind(now - WINDOW_MS);
}
__name(sendUsageStatement, "sendUsageStatement");
function sendUsageFromRow(row, limit) {
  const oldest = row?.oldest ?? null;
  return {
    used: Number(row?.used ?? 0),
    limit,
    windowDays: SEND_WINDOW_DAYS,
    resetsAt: oldest === null ? null : new Date(Number(oldest) + WINDOW_MS).toISOString()
  };
}
__name(sendUsageFromRow, "sendUsageFromRow");
async function getSendUsage(db, limit, now = Date.now()) {
  return sendUsageFromRow(await sendUsageStatement(db, now).first(), limit);
}
__name(getSendUsage, "getSendUsage");
async function reserveSend(db, recipients, limit, now = Date.now()) {
  const row = await db.prepare(
    `INSERT INTO send_log (ts, recipients)
      SELECT ?1, ?2
      WHERE (SELECT COALESCE(SUM(recipients), 0) FROM send_log WHERE ts > ?3) + ?2 <= ?4
      RETURNING rowid AS rid`
  ).bind(now, recipients, now - WINDOW_MS, limit).first();
  return row ? Number(row.rid) : null;
}
__name(reserveSend, "reserveSend");
async function releaseSend(db, rid) {
  await db.prepare("DELETE FROM send_log WHERE rowid = ?1").bind(rid).run();
}
__name(releaseSend, "releaseSend");
var SEND_DEDUPE_RETENTION_DAYS = 1;
async function pruneSendTables(db, now = Date.now()) {
  const results = await db.batch([
    db.prepare("DELETE FROM send_log WHERE ts < ?1").bind(now - SEND_LOG_RETENTION_DAYS * DAY_MS),
    db.prepare("DELETE FROM send_dedupe WHERE ts < ?1").bind(now - SEND_DEDUPE_RETENTION_DAYS * DAY_MS)
  ]);
  return results.reduce((n, r) => n + (r.meta.changes ?? 0), 0);
}
__name(pruneSendTables, "pruneSendTables");

// src/schema.ts
var SCHEMA = [
  "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
  `CREATE TABLE IF NOT EXISTS messages (
    rid INTEGER PRIMARY KEY,
    id TEXT NOT NULL UNIQUE,
    thread_id TEXT NOT NULL,
    folder TEXT NOT NULL CHECK (folder IN ('inbox','sent','archive','trash')),
    direction TEXT NOT NULL CHECK (direction IN ('in','out')),
    mailbox TEXT NOT NULL,
    domain TEXT NOT NULL,
    from_name TEXT,
    from_address TEXT NOT NULL,
    to_json TEXT NOT NULL DEFAULT '[]',
    cc_json TEXT NOT NULL DEFAULT '[]',
    reply_to_json TEXT NOT NULL DEFAULT '[]',
    subject TEXT NOT NULL DEFAULT '',
    snippet TEXT NOT NULL DEFAULT '',
    date TEXT NOT NULL,
    received_at TEXT NOT NULL,
    message_id TEXT,
    in_reply_to TEXT,
    references_json TEXT NOT NULL DEFAULT '[]',
    read INTEGER NOT NULL DEFAULT 0,
    starred INTEGER NOT NULL DEFAULT 0,
    has_attachments INTEGER NOT NULL DEFAULT 0,
    size INTEGER NOT NULL DEFAULT 0,
    list_unsubscribe TEXT,
    trashed_at TEXT,
    seq INTEGER NOT NULL
  )`,
  "CREATE INDEX IF NOT EXISTS messages_folder_id ON messages(folder, id)",
  "CREATE INDEX IF NOT EXISTS messages_mailbox_folder_id ON messages(mailbox, folder, id)",
  "CREATE INDEX IF NOT EXISTS messages_domain_folder_id ON messages(domain, folder, id)",
  "CREATE INDEX IF NOT EXISTS messages_thread_id ON messages(thread_id, id)",
  "CREATE INDEX IF NOT EXISTS messages_message_id ON messages(message_id)",
  "CREATE INDEX IF NOT EXISTS messages_seq ON messages(seq)",
  // GET /v1/contacts reads recent outgoing mail.
  "CREATE INDEX IF NOT EXISTS messages_direction_date ON messages(direction, date)",
  "CREATE INDEX IF NOT EXISTS messages_trashed ON messages(folder, trashed_at)",
  `CREATE TABLE IF NOT EXISTS attachments (
    id TEXT PRIMARY KEY,
    message_id TEXT NOT NULL,
    idx INTEGER NOT NULL,
    filename TEXT NOT NULL,
    mime_type TEXT NOT NULL,
    size INTEGER NOT NULL,
    content_id TEXT,
    inline INTEGER NOT NULL DEFAULT 0
  )`,
  "CREATE INDEX IF NOT EXISTS attachments_message ON attachments(message_id, idx)",
  `CREATE TABLE IF NOT EXISTS tombstones (
    id TEXT PRIMARY KEY,
    seq INTEGER NOT NULL,
    deleted_at TEXT NOT NULL
  )`,
  "CREATE INDEX IF NOT EXISTS tombstones_seq ON tombstones(seq)",
  "CREATE TABLE IF NOT EXISTS config (key TEXT PRIMARY KEY, value TEXT NOT NULL)",
  `CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    subject, participants, body, tokenize = 'unicode61 remove_diacritics 2'
  )`,
  // One row per counted send: epoch ms and recipient count (to + cc + bcc).
  "CREATE TABLE IF NOT EXISTS send_log (ts INTEGER NOT NULL, recipients INTEGER NOT NULL)",
  "CREATE INDEX IF NOT EXISTS send_log_ts ON send_log(ts)",
  // POST /v1/send idempotency: response is NULL while the send is in progress.
  "CREATE TABLE IF NOT EXISTS send_dedupe (client_id TEXT PRIMARY KEY, ts INTEGER NOT NULL, response TEXT)",
  "CREATE INDEX IF NOT EXISTS send_dedupe_ts ON send_dedupe(ts)",
  // Per-domain branding (src/brand.ts); the logo bytes live in R2 at brand/<domain>/logo.
  `CREATE TABLE IF NOT EXISTS brands (
    domain TEXT PRIMARY KEY,
    signature TEXT NOT NULL DEFAULT '',
    logo_type TEXT,
    logo_size INTEGER,
    logo_width INTEGER,
    logo_height INTEGER,
    updated_at TEXT NOT NULL
  )`,
  "INSERT OR IGNORE INTO meta (key, value) VALUES ('change_seq', '0')"
];
var BUMP_SEQ_SQL = "UPDATE meta SET value = CAST(value AS INTEGER) + 1 WHERE key = 'change_seq'";
var CURRENT_SEQ_SQL = "(SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'change_seq')";
var ready = null;
function ensureSchema(db) {
  if (!ready) {
    ready = applySchema(db).catch((err) => {
      ready = null;
      throw err;
    });
  }
  return ready;
}
__name(ensureSchema, "ensureSchema");
async function applySchema(db) {
  await db.batch(SCHEMA.map((sql) => db.prepare(sql)));
}
__name(applySchema, "applySchema");

// src/types.ts
var FOLDERS = ["inbox", "sent", "archive", "trash"];
var MIB = 1024 * 1024;
var DEFAULT_CONFIG = Object.freeze({
  domains: [],
  forwardCopies: {},
  maxInboundBytes: 25 * MIB,
  trashRetentionDays: 30,
  monthlySendLimit: 3e3
});
var MAX_MONTHLY_SEND_LIMIT = 1e5;

// src/util.ts
var EMAIL_RE = /^[^\s@<>()",;:\\[\]]+@[^\s@<>()",;:\\[\]]+\.[^\s@<>()",;:\\[\]]+$/;
var DOMAIN_RE = /^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
function isEmail(value) {
  return value.length <= 320 && EMAIL_RE.test(value);
}
__name(isEmail, "isEmail");
function isDomain(value) {
  return DOMAIN_RE.test(value);
}
__name(isDomain, "isDomain");
function normalizeEmail(value) {
  return value.trim().toLowerCase();
}
__name(normalizeEmail, "normalizeEmail");
function domainOf(address) {
  const at = address.lastIndexOf("@");
  return at >= 0 ? address.slice(at + 1).toLowerCase() : "";
}
__name(domainOf, "domainOf");
function belongsToDomains(address, domains) {
  const domain = domainOf(address);
  if (!domain) return false;
  return domains.some((d) => domain === d || domain.endsWith(`.${d}`));
}
__name(belongsToDomains, "belongsToDomains");
function parseMessageIds(value) {
  if (!value) return [];
  const bracketed = value.match(/<[^<>\s]+>/g);
  if (bracketed && bracketed.length > 0) return bracketed;
  return value.split(/[\s,]+/).map((t) => t.trim()).filter((t) => t.length > 0 && t.includes("@")).map((t) => `<${t.replace(/^<|>$/g, "")}>`);
}
__name(parseMessageIds, "parseMessageIds");
function normalizeMessageId(value) {
  const raw = (value ?? "").trim();
  if (!raw) return null;
  const inner = raw.replace(/^<+/, "").replace(/>+$/, "").trim();
  return inner ? `<${inner}>` : null;
}
__name(normalizeMessageId, "normalizeMessageId");
var ENTITIES = {
  amp: "&",
  lt: "<",
  gt: ">",
  quot: '"',
  apos: "'",
  nbsp: " "
};
function decodeEntities(text) {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, entity) => {
    const lower = entity.toLowerCase();
    if (lower.startsWith("#x")) return safeCodePoint(Number.parseInt(lower.slice(2), 16)) ?? whole;
    if (lower.startsWith("#")) return safeCodePoint(Number.parseInt(lower.slice(1), 10)) ?? whole;
    return ENTITIES[lower] ?? whole;
  });
}
__name(decodeEntities, "decodeEntities");
function safeCodePoint(cp) {
  if (!Number.isFinite(cp) || cp < 0 || cp > 1114111) return null;
  try {
    return String.fromCodePoint(cp);
  } catch {
    return null;
  }
}
__name(safeCodePoint, "safeCodePoint");
function htmlToText(html) {
  return decodeEntities(
    html.replace(/<(script|style|head|title)\b[\s\S]*?<\/\1\s*>/gi, " ").replace(/<!--[\s\S]*?-->/g, " ").replace(/<(br|\/p|\/div|\/li|\/tr|\/h[1-6])\b[^>]*>/gi, "\n").replace(/<[^>]+>/g, " ")
  );
}
__name(htmlToText, "htmlToText");
function bodyText(text, html) {
  if (text && text.trim()) return text;
  if (html && html.trim()) return htmlToText(html);
  return "";
}
__name(bodyText, "bodyText");
function makeSnippet(text, html) {
  const collapsed = bodyText(text, html).replace(/\s+/g, " ").trim();
  const chars = Array.from(collapsed);
  return chars.length > 160 ? chars.slice(0, 160).join("").trimEnd() : collapsed;
}
__name(makeSnippet, "makeSnippet");
function truncateChars(value, max) {
  return value.length > max ? value.slice(0, max) : value;
}
__name(truncateChars, "truncateChars");
function participantsText(from, ...lists) {
  const all = [from, ...lists.flat()];
  return all.map((a) => `${a.name ?? ""} ${a.address}`.trim()).join(" ");
}
__name(participantsText, "participantsText");
function utf8Length(value) {
  return value ? new TextEncoder().encode(value).byteLength : 0;
}
__name(utf8Length, "utf8Length");
function toIsoOrNull(value) {
  if (!value) return null;
  const t = Date.parse(value);
  return Number.isFinite(t) ? new Date(t).toISOString() : null;
}
__name(toIsoOrNull, "toIsoOrNull");
function isPlainObject(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
__name(isPlainObject, "isPlainObject");

// src/store.ts
var rawKey = /* @__PURE__ */ __name((id) => `raw/${id}.eml`, "rawKey");
var bodyKey = /* @__PURE__ */ __name((id) => `body/${id}.json`, "bodyKey");
var attKey = /* @__PURE__ */ __name((id, n) => `att/${id}/${n}`, "attKey");
var FTS_BODY_MAX = 32e3;
var CONFIG_SQL = "SELECT key, value FROM config";
async function getConfig(db) {
  const { results } = await db.prepare(CONFIG_SQL).all();
  return configFromRows(results);
}
__name(getConfig, "getConfig");
function configFromRows(results) {
  const cfg = {
    domains: [...DEFAULT_CONFIG.domains],
    forwardCopies: { ...DEFAULT_CONFIG.forwardCopies },
    maxInboundBytes: DEFAULT_CONFIG.maxInboundBytes,
    trashRetentionDays: DEFAULT_CONFIG.trashRetentionDays,
    monthlySendLimit: DEFAULT_CONFIG.monthlySendLimit
  };
  for (const row of results) {
    let value;
    try {
      value = JSON.parse(row.value);
    } catch {
      continue;
    }
    switch (row.key) {
      case "domains":
        if (Array.isArray(value)) cfg.domains = value.filter((d) => typeof d === "string");
        break;
      case "forwardCopies":
        if (isPlainObject(value)) {
          cfg.forwardCopies = Object.fromEntries(
            Object.entries(value).filter((e) => typeof e[1] === "string")
          );
        }
        break;
      case "maxInboundBytes":
        if (typeof value === "number" && value > 0) cfg.maxInboundBytes = value;
        break;
      case "trashRetentionDays":
        if (typeof value === "number" && value > 0) cfg.trashRetentionDays = value;
        break;
      case "monthlySendLimit":
        if (typeof value === "number" && Number.isInteger(value) && value >= 0) cfg.monthlySendLimit = value;
        break;
    }
  }
  return cfg;
}
__name(configFromRows, "configFromRows");
var invalidConfig = /* @__PURE__ */ __name((message) => new HttpError(400, "invalid_config", message), "invalidConfig");
function validateConfigPatch(body) {
  if (!isPlainObject(body)) throw invalidConfig("Body must be a JSON object");
  const patch = {};
  if (body.domains !== void 0) {
    if (!Array.isArray(body.domains) || body.domains.some((d) => typeof d !== "string")) {
      throw invalidConfig("domains must be an array of strings");
    }
    const domains = [...new Set(body.domains.map((d) => d.trim().toLowerCase().replace(/\.$/, "")))];
    const bad = domains.find((d) => !isDomain(d));
    if (bad !== void 0) throw invalidConfig(`Invalid domain: ${bad}`);
    patch.domains = domains;
  }
  if (body.forwardCopies !== void 0) {
    if (!isPlainObject(body.forwardCopies)) throw invalidConfig("forwardCopies must be an object");
    const copies = {};
    for (const [mailbox, dest] of Object.entries(body.forwardCopies)) {
      if (dest === null || dest === "") continue;
      const key = normalizeEmail(mailbox);
      if (!isEmail(key)) throw invalidConfig(`Invalid mailbox in forwardCopies: ${mailbox}`);
      if (typeof dest !== "string" || !isEmail(dest.trim())) {
        throw invalidConfig(`Invalid forward destination for ${mailbox}`);
      }
      copies[key] = dest.trim();
    }
    patch.forwardCopies = copies;
  }
  if (body.maxInboundBytes !== void 0) {
    const v = body.maxInboundBytes;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 2 ** 31) {
      throw invalidConfig("maxInboundBytes must be a positive integer");
    }
    patch.maxInboundBytes = v;
  }
  if (body.trashRetentionDays !== void 0) {
    const v = body.trashRetentionDays;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 3650) {
      throw invalidConfig("trashRetentionDays must be an integer between 1 and 3650");
    }
    patch.trashRetentionDays = v;
  }
  if (body.monthlySendLimit !== void 0) {
    const v = body.monthlySendLimit;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > MAX_MONTHLY_SEND_LIMIT) {
      throw invalidConfig(`monthlySendLimit must be an integer between 0 and ${MAX_MONTHLY_SEND_LIMIT}`);
    }
    patch.monthlySendLimit = v;
  }
  return patch;
}
__name(validateConfigPatch, "validateConfigPatch");
async function putConfig(db, patch) {
  const statements = Object.entries(patch).map(
    ([key, value]) => db.prepare("INSERT INTO config (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value").bind(key, JSON.stringify(value))
  );
  if (statements.length > 0) await db.batch(statements);
  return getConfig(db);
}
__name(putConfig, "putConfig");
function parseJsonArray(value) {
  try {
    const parsed = JSON.parse(value);
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}
__name(parseJsonArray, "parseJsonArray");
function rowToSummary(row) {
  return {
    id: row.id,
    threadId: row.thread_id,
    folder: row.folder,
    direction: row.direction,
    mailbox: row.mailbox,
    domain: row.domain,
    from: { name: row.from_name, address: row.from_address },
    to: parseJsonArray(row.to_json),
    cc: parseJsonArray(row.cc_json),
    replyTo: parseJsonArray(row.reply_to_json),
    subject: row.subject,
    snippet: row.snippet,
    date: row.date,
    receivedAt: row.received_at,
    messageId: row.message_id,
    inReplyTo: row.in_reply_to,
    references: parseJsonArray(row.references_json),
    read: row.read === 1,
    starred: row.starred === 1,
    hasAttachments: row.has_attachments === 1,
    size: row.size
  };
}
__name(rowToSummary, "rowToSummary");
function rowToAttachment(row) {
  return {
    id: row.id,
    filename: row.filename,
    mimeType: row.mime_type,
    size: row.size,
    contentId: row.content_id,
    inline: row.inline === 1
  };
}
__name(rowToAttachment, "rowToAttachment");
function recordToSummary(rec, starred = false) {
  return {
    id: rec.id,
    threadId: rec.threadId,
    folder: rec.folder,
    direction: rec.direction,
    mailbox: rec.mailbox,
    domain: rec.domain,
    from: rec.from,
    to: rec.to,
    cc: rec.cc,
    replyTo: rec.replyTo,
    subject: rec.subject,
    snippet: rec.snippet,
    date: rec.date,
    receivedAt: rec.receivedAt,
    messageId: rec.messageId,
    inReplyTo: rec.inReplyTo,
    references: rec.references,
    read: rec.read,
    starred,
    hasAttachments: rec.hasAttachments,
    size: rec.size
  };
}
__name(recordToSummary, "recordToSummary");
var attachmentId = /* @__PURE__ */ __name((messageId, idx) => `${messageId}.${idx}`, "attachmentId");
async function insertMessage(db, msg, attachments, search) {
  const statements = [db.prepare(BUMP_SEQ_SQL)];
  statements.push(
    db.prepare(
      `INSERT INTO messages (id, thread_id, folder, direction, mailbox, domain, from_name, from_address,
          to_json, cc_json, reply_to_json, subject, snippet, date, received_at, message_id, in_reply_to,
          references_json, read, starred, has_attachments, size, list_unsubscribe, trashed_at, seq)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, 0, ?20, ?21, ?22,
          NULL, ${CURRENT_SEQ_SQL})`
    ).bind(
      msg.id,
      msg.threadId,
      msg.folder,
      msg.direction,
      msg.mailbox,
      msg.domain,
      msg.from.name,
      msg.from.address,
      JSON.stringify(msg.to),
      JSON.stringify(msg.cc),
      JSON.stringify(msg.replyTo),
      msg.subject,
      msg.snippet,
      msg.date,
      msg.receivedAt,
      msg.messageId,
      msg.inReplyTo,
      JSON.stringify(msg.references),
      msg.read ? 1 : 0,
      msg.hasAttachments ? 1 : 0,
      msg.size,
      msg.listUnsubscribe
    )
  );
  for (const att of attachments) {
    statements.push(
      db.prepare(
        `INSERT INTO attachments (id, message_id, idx, filename, mime_type, size, content_id, inline)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`
      ).bind(
        attachmentId(msg.id, att.idx),
        msg.id,
        att.idx,
        att.filename,
        att.mimeType,
        att.size,
        att.contentId,
        att.inline ? 1 : 0
      )
    );
  }
  statements.push(
    db.prepare(
      `INSERT INTO messages_fts (rowid, subject, participants, body)
        VALUES ((SELECT rid FROM messages WHERE id = ?1), ?2, ?3, ?4)`
    ).bind(msg.id, msg.subject, search.participants, truncateChars(search.body, FTS_BODY_MAX))
  );
  await db.batch(statements);
}
__name(insertMessage, "insertMessage");
async function updateMessages(db, ids, patch) {
  if (ids.length === 0) return 0;
  const now = (/* @__PURE__ */ new Date()).toISOString();
  const results = await db.batch([
    db.prepare(BUMP_SEQ_SQL),
    db.prepare(
      `UPDATE messages SET
          read = COALESCE(?1, read),
          starred = COALESCE(?2, starred),
          folder = COALESCE(?3, folder),
          trashed_at = CASE WHEN ?3 IS NULL THEN trashed_at
                            WHEN ?3 = 'trash' THEN COALESCE(trashed_at, ?4)
                            ELSE NULL END,
          seq = ${CURRENT_SEQ_SQL}
        WHERE id IN (SELECT value FROM json_each(?5))`
    ).bind(
      patch.read === void 0 ? null : patch.read ? 1 : 0,
      patch.starred === void 0 ? null : patch.starred ? 1 : 0,
      patch.folder ?? null,
      now,
      JSON.stringify(ids)
    )
  ]);
  return results[1]?.meta.changes ?? 0;
}
__name(updateMessages, "updateMessages");
async function purgeMessages(env, ids) {
  if (ids.length === 0) return [];
  const idsJson = JSON.stringify(ids);
  const [existing, atts] = await env.DB.batch([
    env.DB.prepare("SELECT id FROM messages WHERE id IN (SELECT value FROM json_each(?1))").bind(idsJson),
    env.DB.prepare(
      "SELECT message_id, idx FROM attachments WHERE message_id IN (SELECT value FROM json_each(?1))"
    ).bind(idsJson)
  ]);
  const found = (existing?.results ?? []).map((r) => r.id);
  if (found.length === 0) return [];
  const keys = [];
  for (const id of found) keys.push(rawKey(id), bodyKey(id));
  for (const a of atts?.results ?? []) {
    if (a.message_id !== void 0 && a.idx !== void 0) keys.push(attKey(a.message_id, a.idx));
  }
  for (let i = 0; i < keys.length; i += 1e3) {
    await env.MAIL.delete(keys.slice(i, i + 1e3));
  }
  const foundJson = JSON.stringify(found);
  const now = (/* @__PURE__ */ new Date()).toISOString();
  await env.DB.batch([
    env.DB.prepare(BUMP_SEQ_SQL),
    env.DB.prepare(
      `INSERT INTO tombstones (id, seq, deleted_at)
      SELECT value, ${CURRENT_SEQ_SQL}, ?2 FROM json_each(?1) WHERE true
      ON CONFLICT(id) DO UPDATE SET seq = excluded.seq, deleted_at = excluded.deleted_at`
    ).bind(foundJson, now),
    env.DB.prepare(
      "DELETE FROM messages_fts WHERE rowid IN (SELECT rid FROM messages WHERE id IN (SELECT value FROM json_each(?1)))"
    ).bind(foundJson),
    env.DB.prepare("DELETE FROM attachments WHERE message_id IN (SELECT value FROM json_each(?1))").bind(foundJson),
    env.DB.prepare("DELETE FROM messages WHERE id IN (SELECT value FROM json_each(?1))").bind(foundJson)
  ]);
  return found;
}
__name(purgeMessages, "purgeMessages");
async function getMessageRow(db, id) {
  return db.prepare("SELECT * FROM messages WHERE id = ?1").bind(id).first();
}
__name(getMessageRow, "getMessageRow");
async function requireMessageRow(db, id) {
  const row = await getMessageRow(db, id);
  if (!row) throw new HttpError(404, "not_found", `Message ${id} not found`);
  return row;
}
__name(requireMessageRow, "requireMessageRow");
async function getAttachmentRows(db, messageId) {
  const { results } = await db.prepare("SELECT * FROM attachments WHERE message_id = ?1 ORDER BY idx").bind(messageId).all();
  return results;
}
__name(getAttachmentRows, "getAttachmentRows");
async function getAttachmentRow(db, id) {
  return db.prepare("SELECT * FROM attachments WHERE id = ?1").bind(id).first();
}
__name(getAttachmentRow, "getAttachmentRow");
function ftsQuery(q) {
  const terms = q.normalize("NFKC").split(/\s+/).map((t) => t.replace(/"/g, "")).filter((t) => /[\p{L}\p{N}]/u.test(t)).slice(0, 16);
  if (terms.length === 0) return null;
  return terms.map((t) => `"${t}"*`).join(" AND ");
}
__name(ftsQuery, "ftsQuery");
async function listMessages(db, f) {
  const where = ["folder = ?"];
  const params = [f.folder];
  if (f.mailbox) {
    where.push("mailbox = ?");
    params.push(f.mailbox);
  }
  if (f.domain) {
    where.push("domain = ?");
    params.push(f.domain);
  }
  if (f.unread) where.push("read = 0");
  if (f.starred) where.push("starred = 1");
  if (f.cursor) {
    where.push("id < ?");
    params.push(f.cursor);
  }
  if (f.q !== void 0) {
    const match2 = ftsQuery(f.q);
    if (match2) {
      where.push("rid IN (SELECT rowid FROM messages_fts WHERE messages_fts MATCH ?)");
      params.push(match2);
    }
  }
  params.push(f.limit + 1);
  const sql = `SELECT * FROM messages WHERE ${where.join(" AND ")} ORDER BY id DESC LIMIT ?`;
  const { results } = await db.prepare(sql).bind(...params).all();
  const page = results.slice(0, f.limit);
  const nextCursor = results.length > f.limit ? page[page.length - 1]?.id ?? null : null;
  return { messages: page.map(rowToSummary), nextCursor };
}
__name(listMessages, "listMessages");
async function getThread(db, threadId) {
  const { results } = await db.prepare("SELECT * FROM messages WHERE thread_id = ?1 ORDER BY id ASC").bind(threadId).all();
  return results.map(rowToSummary);
}
__name(getThread, "getThread");
async function listMailboxes(db) {
  const { results } = await db.prepare(
    `SELECT mailbox AS address, MAX(domain) AS domain,
        SUM(CASE WHEN read = 0 AND folder = 'inbox' THEN 1 ELSE 0 END) AS unread,
        COUNT(*) AS total,
        MAX(received_at) AS lastAt
      FROM messages WHERE folder != 'trash'
      GROUP BY mailbox ORDER BY lastAt DESC, mailbox ASC`
  ).all();
  return results.map((r) => ({
    address: r.address,
    domain: r.domain,
    unread: Number(r.unread),
    total: Number(r.total),
    lastAt: r.lastAt
  }));
}
__name(listMailboxes, "listMailboxes");
async function findThreadId(db, candidates) {
  if (candidates.length === 0) return null;
  const { results } = await db.prepare(
    `SELECT message_id, thread_id FROM messages
      WHERE message_id IN (SELECT value FROM json_each(?1)) ORDER BY id ASC`
  ).bind(JSON.stringify(candidates)).all();
  const byMessageId = /* @__PURE__ */ new Map();
  for (const r of results) if (!byMessageId.has(r.message_id)) byMessageId.set(r.message_id, r.thread_id);
  for (const c of candidates) {
    const thread = byMessageId.get(c);
    if (thread) return thread;
  }
  return null;
}
__name(findThreadId, "findThreadId");
async function syncChanges(db, since, limit = 500) {
  const from = since ?? Number.MAX_SAFE_INTEGER;
  const [configRes, headRes, rowsRes, tombRes, usageRes, unreadRes] = await db.batch([
    db.prepare(CONFIG_SQL),
    db.prepare(`SELECT ${CURRENT_SEQ_SQL} AS seq`),
    db.prepare(`SELECT * FROM messages WHERE seq > ?1 AND seq <= ${CURRENT_SEQ_SQL} ORDER BY seq ASC, id ASC LIMIT ?2`).bind(from, limit + 1),
    db.prepare(`SELECT id, seq FROM tombstones WHERE seq > ?1 AND seq <= ${CURRENT_SEQ_SQL} ORDER BY seq ASC, id ASC`).bind(from),
    sendUsageStatement(db),
    db.prepare("SELECT COUNT(*) AS n FROM messages WHERE folder = 'inbox' AND read = 0")
  ]);
  const config = configFromRows(configRes?.results ?? []);
  const head = Number(headRes?.results[0]?.seq ?? 0);
  const results = rowsRes?.results ?? [];
  let rows = results;
  let upper = head;
  let hasMore = false;
  if (results.length > limit) {
    hasMore = true;
    const boundary2 = results[limit].seq;
    rows = results.filter((r) => r.seq < boundary2);
    if (rows.length === 0) {
      const all = await db.prepare("SELECT * FROM messages WHERE seq = ?1 ORDER BY id ASC").bind(boundary2).all();
      rows = all.results;
      upper = boundary2;
    } else {
      upper = boundary2 - 1;
    }
  }
  const deleted = (tombRes?.results ?? []).filter((t) => t.seq <= upper).map((t) => t.id);
  const total = Number(unreadRes?.results[0]?.n ?? 0);
  return {
    messages: rows.map(rowToSummary),
    deleted,
    cursor: String(since !== null && since < head ? upper : head),
    hasMore,
    sendUsage: sendUsageFromRow(usageRes?.results[0], config.monthlySendLimit),
    unread: { total }
  };
}
__name(syncChanges, "syncChanges");
async function purgeExpiredTrash(env, days, now = Date.now()) {
  const cutoff = new Date(now - days * 864e5).toISOString();
  let purged = 0;
  for (let round = 0; round < 10; round++) {
    const { results } = await env.DB.prepare(
      "SELECT id FROM messages WHERE folder = 'trash' AND trashed_at IS NOT NULL AND trashed_at < ?1 ORDER BY id LIMIT 200"
    ).bind(cutoff).all();
    if (results.length === 0) break;
    purged += (await purgeMessages(env, results.map((r) => r.id))).length;
    if (results.length < 200) break;
  }
  return purged;
}
__name(purgeExpiredTrash, "purgeExpiredTrash");

// src/contacts.ts
var SCAN_MESSAGES = 2e3;
var MAX_CONTACTS = 500;
async function listContacts(db) {
  const { results } = await db.prepare("SELECT to_json, cc_json, date FROM messages WHERE direction = 'out' ORDER BY date DESC LIMIT ?").bind(SCAN_MESSAGES).all();
  const byAddress = /* @__PURE__ */ new Map();
  for (const row of results) {
    const seen = /* @__PURE__ */ new Set();
    for (const a of [...parseJsonArray(row.to_json), ...parseJsonArray(row.cc_json)]) {
      if (typeof a?.address !== "string" || !a.address.includes("@")) continue;
      const address = normalizeEmail(a.address);
      const name = typeof a.name === "string" && a.name.trim() ? a.name.trim() : null;
      const known = byAddress.get(address);
      if (known) {
        if (!seen.has(address)) known.count++;
        known.name ??= name;
      } else {
        byAddress.set(address, { address, name, count: 1, lastSent: row.date });
      }
      seen.add(address);
    }
  }
  return [...byAddress.values()].sort((a, b) => b.count - a.count || b.lastSent.localeCompare(a.lastSent)).slice(0, MAX_CONTACTS);
}
__name(listContacts, "listContacts");

// src/mime.ts
var encoder2 = new TextEncoder();
function isPrintableAscii(value) {
  return /^[\x20-\x7e]*$/.test(value);
}
__name(isPrintableAscii, "isPrintableAscii");
function encodeWord(value) {
  if (isPrintableAscii(value)) return value;
  return `=?UTF-8?B?${encoder2.encode(value).toBase64()}?=`;
}
__name(encodeWord, "encodeWord");
function formatAddress(a) {
  if (!a.name) return a.address;
  const name = isPrintableAscii(a.name) ? `"${a.name.replace(/(["\\])/g, "\\$1")}"` : encodeWord(a.name);
  return `${name} <${a.address}>`;
}
__name(formatAddress, "formatAddress");
function wrap76(b64) {
  return b64.replace(/.{1,76}/g, "$&\r\n");
}
__name(wrap76, "wrap76");
function quoteParam(value) {
  return isPrintableAscii(value) ? `"${value.replace(/(["\\])/g, "\\$1")}"` : `"${encodeWord(value)}"`;
}
__name(quoteParam, "quoteParam");
function boundary() {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return `=_ek_${[...bytes].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}
__name(boundary, "boundary");
function textPart(contentType, value) {
  return `Content-Type: ${contentType}; charset=utf-8\r
Content-Transfer-Encoding: base64\r
\r
` + wrap76(encoder2.encode(value).toBase64());
}
__name(textPart, "textPart");
function attachmentPart(att) {
  const disposition = att.inline ? "inline" : "attachment";
  let headers = `Content-Type: ${att.mimeType}; name=${quoteParam(att.filename)}\r
Content-Disposition: ${disposition}; filename=${quoteParam(att.filename)}\r
Content-Transfer-Encoding: base64\r
`;
  if (att.contentId) headers += `Content-ID: <${att.contentId}>\r
`;
  return `${headers}\r
${wrap76(att.bytes.toBase64())}`;
}
__name(attachmentPart, "attachmentPart");
function multipart(subtype, parts) {
  const b = boundary();
  return `Content-Type: multipart/${subtype}; boundary="${b}"\r
\r
` + parts.map((p) => `--${b}\r
${p}\r
`).join("") + `--${b}--\r
`;
}
__name(multipart, "multipart");
function buildMime(input) {
  const headers = [
    `From: ${formatAddress(input.from)}`,
    `Date: ${input.date.toUTCString().replace("GMT", "+0000")}`,
    `Subject: ${encodeWord(input.subject)}`
  ];
  if (input.to.length) headers.push(`To: ${input.to.map(formatAddress).join(", ")}`);
  if (input.cc.length) headers.push(`Cc: ${input.cc.map(formatAddress).join(", ")}`);
  if (input.bcc.length) headers.push(`Bcc: ${input.bcc.map(formatAddress).join(", ")}`);
  if (input.replyTo) headers.push(`Reply-To: ${formatAddress(input.replyTo)}`);
  if (input.messageId) headers.push(`Message-ID: ${input.messageId}`);
  if (input.inReplyTo) headers.push(`In-Reply-To: ${input.inReplyTo}`);
  if (input.references.length) headers.push(`References: ${input.references.join(" ")}`);
  headers.push("MIME-Version: 1.0");
  const body = input.html ? multipart("alternative", [textPart("text/plain", input.text), textPart("text/html", input.html)]) : textPart("text/plain", input.text);
  const content = input.attachments.length > 0 ? multipart("mixed", [body, ...input.attachments.map(attachmentPart)]) : body;
  return encoder2.encode(`${headers.join("\r\n")}\r
${content}`);
}
__name(buildMime, "buildMime");

// src/ulid.ts
var ENCODING = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
var RANDOM_BYTES = 10;
var lastTime = -1;
var lastRandom = new Uint8Array(RANDOM_BYTES);
function encodeTime(time) {
  let out = "";
  let t = time;
  for (let i = 0; i < 10; i++) {
    const mod = t % 32;
    out = ENCODING.charAt(mod) + out;
    t = (t - mod) / 32;
  }
  return out;
}
__name(encodeTime, "encodeTime");
function encodeRandom(bytes) {
  let n = 0n;
  for (const b of bytes) n = n << 8n | BigInt(b);
  let out = "";
  for (let i = 0; i < 16; i++) {
    out = ENCODING.charAt(Number(n & 31n)) + out;
    n >>= 5n;
  }
  return out;
}
__name(encodeRandom, "encodeRandom");
function increment(bytes) {
  const next = bytes.slice();
  for (let i = next.length - 1; i >= 0; i--) {
    const v = next[i];
    if (v < 255) {
      next[i] = v + 1;
      return next;
    }
    next[i] = 0;
  }
  return null;
}
__name(increment, "increment");
function ulid(now = Date.now()) {
  let time = Math.max(0, Math.floor(now));
  let random = null;
  if (time <= lastTime) {
    time = lastTime;
    random = increment(lastRandom);
    if (random === null) {
      time = lastTime + 1;
    }
  }
  if (random === null) random = crypto.getRandomValues(new Uint8Array(RANDOM_BYTES));
  lastTime = time;
  lastRandom = random;
  return encodeTime(time) + encodeRandom(random);
}
__name(ulid, "ulid");

// src/send.ts
var MAX_OUTBOUND_BYTES = 5 * MIB;
var HEADERS_ESTIMATE_BYTES = 2048;
var ATTACHMENT_PART_HEADERS_BYTES = 300;
var BASE64_LINE_BREAK_FACTOR = 1.027;
var QUOTED_PRINTABLE_FACTOR = 1.03;
var DEDUPE_WINDOW_MS = 15 * 6e4;
var MAX_RECIPIENTS = 50;
var MAX_ATTACHMENTS = 32;
var REFERENCES_TAIL = 18;
var HEADER_VALUE_MAX_BYTES = 2048;
function parseAddress(value, field) {
  if (!isPlainObject(value) || typeof value.address !== "string") {
    throw badRequest(`${field} must be an address object {name, address}`);
  }
  const address = value.address.trim();
  if (!isEmail(address)) throw badRequest(`${field} has an invalid address: ${address}`);
  if (value.name !== void 0 && value.name !== null && typeof value.name !== "string") {
    throw badRequest(`${field}.name must be a string or null`);
  }
  const name = typeof value.name === "string" && value.name.trim() ? value.name.trim() : null;
  if (name !== null && /[\r\n]/.test(name)) throw badRequest(`${field}.name must not contain line breaks`);
  return { name, address };
}
__name(parseAddress, "parseAddress");
function parseAddressList(value, field, required) {
  if (value === void 0 || value === null) {
    if (required) throw badRequest(`${field} is required`);
    return [];
  }
  if (!Array.isArray(value)) throw badRequest(`${field} must be an array of addresses`);
  return value.map((v, i) => parseAddress(v, `${field}[${i}]`));
}
__name(parseAddressList, "parseAddressList");
function optionalString(value, field) {
  if (value === void 0 || value === null) return null;
  if (typeof value !== "string") throw badRequest(`${field} must be a string or null`);
  return value;
}
__name(optionalString, "optionalString");
function parseSendRequest(body) {
  if (!isPlainObject(body)) throw badRequest("Body must be a JSON object");
  const from = parseAddress(body.from, "from");
  const to = parseAddressList(body.to, "to", true);
  const cc = parseAddressList(body.cc, "cc", false);
  const bcc = parseAddressList(body.bcc, "bcc", false);
  const replyTo = body.replyTo === void 0 || body.replyTo === null ? null : parseAddress(body.replyTo, "replyTo");
  if (typeof body.subject !== "string") throw badRequest("subject must be a string");
  if (/[\r\n]/.test(body.subject)) throw badRequest("subject must not contain line breaks");
  if (typeof body.text !== "string") throw badRequest("text must be a string");
  const html = optionalString(body.html, "html");
  let attachments = [];
  if (body.attachments !== void 0 && body.attachments !== null) {
    if (!Array.isArray(body.attachments)) throw badRequest("attachments must be an array");
    attachments = body.attachments.map((a, i) => {
      if (!isPlainObject(a) || typeof a.filename !== "string" || typeof a.mimeType !== "string" || typeof a.contentBase64 !== "string") {
        throw badRequest(`attachments[${i}] must be {filename, mimeType, contentBase64}`);
      }
      return { filename: a.filename, mimeType: a.mimeType, contentBase64: a.contentBase64 };
    });
  }
  const inReplyTo = optionalString(body.inReplyTo, "inReplyTo");
  const forwardOf = optionalString(body.forwardOf, "forwardOf");
  if (body.includeOriginalAttachments !== void 0 && typeof body.includeOriginalAttachments !== "boolean") {
    throw badRequest("includeOriginalAttachments must be a boolean");
  }
  if (body.brandLogo !== void 0 && typeof body.brandLogo !== "boolean") {
    throw badRequest("brandLogo must be a boolean");
  }
  const clientMessageId = optionalString(body.clientMessageId, "clientMessageId");
  if (clientMessageId !== null && (clientMessageId.length < 8 || clientMessageId.length > 100)) {
    throw badRequest("clientMessageId must be 8 to 100 characters");
  }
  return {
    from,
    to,
    cc,
    bcc,
    replyTo,
    subject: body.subject,
    text: body.text,
    html,
    attachments,
    inReplyTo: inReplyTo || null,
    forwardOf: forwardOf || null,
    includeOriginalAttachments: body.includeOriginalAttachments === true,
    brandLogo: body.brandLogo === true,
    clientMessageId
  };
}
__name(parseSendRequest, "parseSendRequest");
function toBuilderAddress(a) {
  return a.name ? { email: a.address, name: a.name } : a.address;
}
__name(toBuilderAddress, "toBuilderAddress");
function buildReferences(parent) {
  const chain = [...parent.references];
  if (parent.messageId && chain[chain.length - 1] !== parent.messageId) chain.push(parent.messageId);
  let refs = chain.length > REFERENCES_TAIL + 1 ? [chain[0], ...chain.slice(-REFERENCES_TAIL)] : chain;
  while (refs.length > 1 && utf8Length(refs.join(" ")) > HEADER_VALUE_MAX_BYTES) {
    refs = refs.length > 2 ? [refs[0], ...refs.slice(2)] : refs.slice(1);
  }
  return refs;
}
__name(buildReferences, "buildReferences");
function encodedAttachmentSize(bytes) {
  return Math.ceil(4 * Math.ceil(bytes / 3) * BASE64_LINE_BREAK_FACTOR) + ATTACHMENT_PART_HEADERS_BYTES;
}
__name(encodedAttachmentSize, "encodedAttachmentSize");
function estimateMessageSize(text, html, attachmentBytes2) {
  let total = HEADERS_ESTIMATE_BYTES;
  total += Math.ceil(utf8Length(text) * QUOTED_PRINTABLE_FACTOR);
  total += Math.ceil(utf8Length(html) * QUOTED_PRINTABLE_FACTOR);
  for (const n of attachmentBytes2) total += encodedAttachmentSize(n);
  return total;
}
__name(estimateMessageSize, "estimateMessageSize");
function mapSendErrorCode(providerCode) {
  switch (providerCode) {
    case "E_VALIDATION_ERROR":
    case "E_FIELD_MISSING":
      return { status: 400, code: "invalid_message" };
    case "E_TOO_MANY_RECIPIENTS":
      return { status: 400, code: "too_many_recipients" };
    case "E_TOO_MANY_ATTACHMENTS":
    case "E_CONTENT_TOO_LARGE":
      return { status: 413, code: "content_too_large" };
    case "E_SENDER_NOT_VERIFIED":
    case "E_SENDER_DOMAIN_NOT_AVAILABLE":
      return { status: 403, code: "sender_domain_not_onboarded" };
    case "E_RECIPIENT_NOT_ALLOWED":
      return { status: 403, code: "recipient_not_allowed" };
    case "E_RECIPIENT_SUPPRESSED":
      return { status: 409, code: "recipient_suppressed" };
    case "E_RATE_LIMIT_EXCEEDED":
    case "E_DAILY_LIMIT_EXCEEDED":
      return { status: 429, code: "sending_limit" };
    default:
      if (providerCode?.startsWith("E_HEADER")) return { status: 400, code: "invalid_message" };
      return { status: 502, code: "delivery_failed" };
  }
}
__name(mapSendErrorCode, "mapSendErrorCode");
var BOUNDARY_REJECTIONS = /* @__PURE__ */ new Set([
  "E_VALIDATION_ERROR",
  "E_FIELD_MISSING",
  "E_TOO_MANY_RECIPIENTS",
  "E_TOO_MANY_ATTACHMENTS",
  "E_CONTENT_TOO_LARGE",
  "E_SENDER_NOT_VERIFIED",
  "E_SENDER_DOMAIN_NOT_AVAILABLE",
  "E_RECIPIENT_NOT_ALLOWED",
  "E_RECIPIENT_SUPPRESSED",
  "E_RATE_LIMIT_EXCEEDED",
  "E_DAILY_LIMIT_EXCEEDED"
]);
function isBoundaryRejection(providerCode) {
  if (!providerCode) return false;
  return BOUNDARY_REJECTIONS.has(providerCode) || providerCode.startsWith("E_HEADER");
}
__name(isBoundaryRejection, "isBoundaryRejection");
function providerCodeOf(err) {
  if (isPlainObject(err) || err instanceof Error) {
    const code = err.code;
    if (typeof code === "string" && /^E_[A-Z0-9_]+$/.test(code)) return code;
  }
  const message = err instanceof Error ? err.message : typeof err === "string" ? err : "";
  return /\bE_[A-Z0-9_]+\b/.exec(message)?.[0] ?? null;
}
__name(providerCodeOf, "providerCodeOf");
function sendError(err) {
  const providerCode = providerCodeOf(err);
  const { status, code } = mapSendErrorCode(providerCode);
  const message = err instanceof Error && err.message ? err.message : "Email Sending rejected the message";
  return new HttpError(status, code, message, providerCode ? { providerCode } : {});
}
__name(sendError, "sendError");
function attachmentContent(bytes) {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
}
__name(attachmentContent, "attachmentContent");
async function sendMessage(env, config, body) {
  const req = parseSendRequest(body);
  const clientId = req.clientMessageId;
  if (clientId) {
    const claim = await claimClientMessageId(env.DB, clientId);
    if (claim.kind === "duplicate") return { ...claim.result, duplicate: true };
    if (claim.kind === "in_progress") {
      throw new HttpError(409, "send_in_progress", `A send with clientMessageId ${clientId} is still in progress`);
    }
  }
  let result;
  try {
    result = await deliver(env, config, req);
  } catch (err) {
    if (clientId) {
      await releaseClientMessageId(env.DB, clientId).catch(
        (e) => console.error("Could not release clientMessageId", e)
      );
    }
    throw err;
  }
  if (clientId) {
    await completeClientMessageId(env.DB, clientId, result).catch(
      (e) => console.error("Could not record clientMessageId", e)
    );
  }
  return { ...result, duplicate: false };
}
__name(sendMessage, "sendMessage");
async function claimClientMessageId(db, clientId, now = Date.now()) {
  const [claim, existing] = await db.batch([
    db.prepare(
      `INSERT INTO send_dedupe (client_id, ts, response) VALUES (?1, ?2, NULL)
        ON CONFLICT(client_id) DO UPDATE SET ts = excluded.ts, response = NULL WHERE send_dedupe.ts <= ?3
        RETURNING client_id`
    ).bind(clientId, now, now - DEDUPE_WINDOW_MS),
    db.prepare("SELECT response FROM send_dedupe WHERE client_id = ?1").bind(clientId)
  ]);
  if ((claim?.results.length ?? 0) > 0) return { kind: "claimed" };
  const response = existing?.results[0]?.response;
  if (typeof response === "string") return { kind: "duplicate", result: JSON.parse(response) };
  return { kind: "in_progress" };
}
__name(claimClientMessageId, "claimClientMessageId");
async function completeClientMessageId(db, clientId, result) {
  await db.prepare("UPDATE send_dedupe SET response = ?2, ts = ?3 WHERE client_id = ?1").bind(clientId, JSON.stringify(result), Date.now()).run();
}
__name(completeClientMessageId, "completeClientMessageId");
async function releaseClientMessageId(db, clientId) {
  await db.prepare("DELETE FROM send_dedupe WHERE client_id = ?1 AND response IS NULL").bind(clientId).run();
}
__name(releaseClientMessageId, "releaseClientMessageId");
async function deliver(env, config, req) {
  if (!belongsToDomains(req.from.address, config.domains)) {
    throw new HttpError(403, "sender_not_allowed", `${req.from.address} is not on a configured domain`);
  }
  if (!env.EMAIL || typeof env.EMAIL.send !== "function") {
    throw new HttpError(503, "sending_not_configured", "The EMAIL (send_email) binding is not configured");
  }
  const recipients = req.to.length + req.cc.length + req.bcc.length;
  if (recipients === 0) throw badRequest("At least one recipient is required");
  if (recipients > MAX_RECIPIENTS) {
    throw new HttpError(400, "too_many_recipients", `At most ${MAX_RECIPIENTS} recipients per message`);
  }
  const attachments = req.attachments.map((a, i) => {
    let bytes;
    try {
      bytes = Uint8Array.fromBase64(a.contentBase64);
    } catch {
      throw badRequest(`attachments[${i}].contentBase64 is not valid base64`);
    }
    return {
      filename: a.filename.trim() || `attachment-${i + 1}`,
      mimeType: a.mimeType.trim() || "application/octet-stream",
      bytes,
      inline: false,
      contentId: null
    };
  });
  if (req.brandLogo) {
    const logo = await getLogo(env, domainOf(normalizeEmail(req.from.address)));
    if (!logo) throw badRequest("The sender's domain has no logo", "brand_logo_missing");
    attachments.push({ filename: "logo.png", mimeType: LOGO_TYPE, bytes: logo, inline: true, contentId: BRAND_LOGO_CID });
  }
  let parent = null;
  let references = [];
  let inReplyToHeader = null;
  if (req.inReplyTo) {
    parent = await requireMessageRow(env.DB, req.inReplyTo);
    const parentSummary = rowToSummary(parent);
    if (parentSummary.messageId) {
      inReplyToHeader = parentSummary.messageId;
      references = buildReferences(parentSummary);
    }
  }
  const sizes = /* @__PURE__ */ __name(() => attachments.map((a) => a.bytes.byteLength), "sizes");
  if (req.forwardOf) {
    const original = await requireMessageRow(env.DB, req.forwardOf);
    if (req.includeOriginalAttachments) {
      const rows = await getAttachmentRows(env.DB, original.id);
      const estimate2 = estimateMessageSize(req.text, req.html, [...sizes(), ...rows.map((r) => r.size)]);
      if (estimate2 > MAX_OUTBOUND_BYTES) throw tooLarge(estimate2);
      if (attachments.length + rows.length > MAX_ATTACHMENTS) throw tooManyAttachments();
      for (const row of rows) {
        const obj = await env.MAIL.get(attKey(original.id, row.idx));
        if (!obj) throw new HttpError(500, "internal_error", `Attachment ${row.id} of the original is missing`);
        const bytes = new Uint8Array(await obj.arrayBuffer());
        const inline = row.inline === 1 && row.content_id !== null;
        attachments.push({
          filename: row.filename,
          mimeType: row.mime_type,
          bytes,
          inline,
          contentId: inline ? row.content_id : null
        });
      }
    }
  }
  const estimate = estimateMessageSize(req.text, req.html, sizes());
  if (estimate > MAX_OUTBOUND_BYTES) throw tooLarge(estimate);
  if (attachments.length > MAX_ATTACHMENTS) throw tooManyAttachments();
  const headers = {};
  if (inReplyToHeader) headers["In-Reply-To"] = inReplyToHeader;
  if (references.length) headers["References"] = references.join(" ");
  const builder = {
    from: toBuilderAddress(req.from),
    subject: req.subject,
    text: req.text
  };
  if (req.to.length) builder.to = req.to.map(toBuilderAddress);
  if (req.cc.length) builder.cc = req.cc.map(toBuilderAddress);
  if (req.bcc.length) builder.bcc = req.bcc.map(toBuilderAddress);
  if (req.replyTo) builder.replyTo = toBuilderAddress(req.replyTo);
  if (req.html) builder.html = req.html;
  if (attachments.length) {
    builder.attachments = attachments.map((a) => {
      const content = attachmentContent(a.bytes);
      return a.inline && a.contentId ? { disposition: "inline", contentId: a.contentId, filename: a.filename, type: a.mimeType, content } : { disposition: "attachment", filename: a.filename, type: a.mimeType, content };
    });
  }
  if (Object.keys(headers).length) builder.headers = headers;
  const reservation = await reserveSend(env.DB, recipients, config.monthlySendLimit);
  if (reservation === null) {
    const usage = await getSendUsage(env.DB, config.monthlySendLimit);
    const message = usage.limit === 0 ? "Sending is disabled (monthlySendLimit is 0)" : `Monthly send limit reached: ${usage.used} of ${usage.limit} recipients used in the last ${usage.windowDays} days; this message has ${recipients}`;
    throw new HttpError(429, "monthly_send_limit", message, { usage });
  }
  let result;
  try {
    result = await env.EMAIL.send(builder);
  } catch (err) {
    if (isBoundaryRejection(providerCodeOf(err))) {
      await releaseSend(env.DB, reservation).catch(
        (releaseErr) => console.error("Could not release the send budget reservation", releaseErr)
      );
    }
    throw sendError(err);
  }
  const providerMessageId = typeof result?.messageId === "string" && result.messageId ? result.messageId : null;
  const messageId = normalizeMessageId(providerMessageId);
  const id = ulid();
  const now = /* @__PURE__ */ new Date();
  const mailbox = normalizeEmail(req.from.address);
  const record = {
    id,
    threadId: parent?.thread_id ?? id,
    folder: "sent",
    direction: "out",
    mailbox,
    domain: domainOf(mailbox),
    from: req.from,
    to: req.to,
    cc: req.cc,
    replyTo: req.replyTo ? [req.replyTo] : [],
    subject: req.subject,
    snippet: makeSnippet(req.text, req.html),
    date: now.toISOString(),
    receivedAt: now.toISOString(),
    messageId,
    inReplyTo: inReplyToHeader,
    references,
    read: true,
    hasAttachments: attachments.some((a) => !a.inline),
    size: 0,
    listUnsubscribe: null
  };
  try {
    const raw = buildMime({
      from: req.from,
      to: req.to,
      cc: req.cc,
      bcc: req.bcc,
      replyTo: req.replyTo,
      subject: req.subject,
      date: now,
      messageId,
      inReplyTo: inReplyToHeader,
      references,
      text: req.text,
      html: req.html,
      attachments
    });
    record.size = raw.byteLength;
    await env.MAIL.put(rawKey(id), raw, { httpMetadata: { contentType: "message/rfc822" } });
    await env.MAIL.put(bodyKey(id), JSON.stringify({ text: req.text, html: req.html }), {
      httpMetadata: { contentType: "application/json; charset=utf-8" }
    });
    const attRows = [];
    for (let n = 0; n < attachments.length; n++) {
      const a = attachments[n];
      await env.MAIL.put(attKey(id, n), a.bytes, { httpMetadata: { contentType: a.mimeType } });
      attRows.push({
        idx: n,
        filename: a.filename,
        mimeType: a.mimeType,
        size: a.bytes.byteLength,
        contentId: a.contentId,
        inline: a.inline
      });
    }
    await insertMessage(env.DB, record, attRows, {
      participants: participantsText(req.from, req.to, req.cc),
      body: bodyText(req.text, req.html)
    });
  } catch (err) {
    console.error(`Sent message ${providerMessageId ?? "(no id)"} could not be stored`, err);
  }
  return { message: recordToSummary(record), providerMessageId };
}
__name(deliver, "deliver");
function tooLarge(size) {
  return new HttpError(
    413,
    "content_too_large",
    `The message would be about ${size} bytes as sent; Email Sending allows ${MAX_OUTBOUND_BYTES} including attachments`,
    { size, limit: MAX_OUTBOUND_BYTES }
  );
}
__name(tooLarge, "tooLarge");
function tooManyAttachments() {
  return new HttpError(413, "content_too_large", `At most ${MAX_ATTACHMENTS} attachments per message`);
}
__name(tooManyAttachments, "tooManyAttachments");

// src/version.ts
var WORKER_VERSION = "1.0.0";

// src/api.ts
var DEFAULT_LIMIT = 50;
var MAX_LIMIT = 100;
var ROUTES = [
  { pattern: ["v1", "health"], methods: { GET: health } },
  { pattern: ["v1", "config"], methods: { GET: getConfigRoute, PUT: putConfigRoute } },
  { pattern: ["v1", "mailboxes"], methods: { GET: mailboxes } },
  { pattern: ["v1", "messages"], methods: { GET: listRoute } },
  { pattern: ["v1", "messages", null], methods: { GET: detailRoute, PATCH: patchRoute, DELETE: deleteRoute } },
  { pattern: ["v1", "threads", null], methods: { GET: threadRoute } },
  { pattern: ["v1", "attachments", null], methods: { GET: attachmentRoute } },
  { pattern: ["v1", "sync"], methods: { GET: syncRoute } },
  { pattern: ["v1", "send"], methods: { POST: sendRoute } },
  { pattern: ["v1", "contacts"], methods: { GET: contactsRoute } },
  { pattern: ["v1", "brands"], methods: { GET: brandsRoute } },
  { pattern: ["v1", "brands", null], methods: { PUT: putBrandRoute } },
  { pattern: ["v1", "brands", null, "logo"], methods: { GET: getLogoRoute, PUT: putLogoRoute, DELETE: deleteLogoRoute } }
];
function match(route, parts) {
  if (route.pattern.length !== parts.length) return null;
  const params = [];
  for (let i = 0; i < parts.length; i++) {
    const expected = route.pattern[i];
    const actual = parts[i];
    if (expected === null) params.push(actual);
    else if (expected !== actual) return null;
  }
  return params;
}
__name(match, "match");
async function handleFetch(request, env) {
  if (!isAuthorized(request, env.MAIL_API_KEY)) return unauthorized();
  try {
    await ensureSchema(env.DB);
    const url = new URL(request.url);
    let parts;
    try {
      parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);
    } catch {
      throw notFound();
    }
    const candidates = ROUTES.map((route) => ({ route, params: match(route, parts) })).filter((c) => c.params !== null).sort((a, b) => a.params.length - b.params.length);
    if (candidates.length === 0) throw notFound();
    const method = request.method.toUpperCase();
    const hit = candidates.find((c) => c.route.methods[method]);
    if (!hit) {
      const allowed = [...new Set(candidates.flatMap((c) => Object.keys(c.route.methods)))].join(", ");
      return errorJson(405, "method_not_allowed", `${method} is not allowed here`, {}, { Allow: allowed });
    }
    return await hit.route.methods[method]({ request, env, url, params: hit.params });
  } catch (err) {
    if (err instanceof HttpError) return fromHttpError(err);
    console.error("Unhandled error", err);
    return errorJson(500, "internal_error", "Internal error");
  }
}
__name(handleFetch, "handleFetch");
async function readJson(request) {
  const text = await request.text();
  if (!text.trim()) throw badRequest("A JSON body is required", "invalid_json");
  try {
    return JSON.parse(text);
  } catch {
    throw badRequest("Body is not valid JSON", "invalid_json");
  }
}
__name(readJson, "readJson");
function parseFolder(value, field = "folder") {
  if (typeof value !== "string" || !FOLDERS.includes(value)) {
    throw badRequest(`${field} must be one of ${FOLDERS.join(", ")}`);
  }
  return value;
}
__name(parseFolder, "parseFolder");
function parseFlagPatch(body) {
  const patch = {};
  if (body.read !== void 0) {
    if (typeof body.read !== "boolean") throw badRequest("read must be a boolean");
    patch.read = body.read;
  }
  if (body.starred !== void 0) {
    if (typeof body.starred !== "boolean") throw badRequest("starred must be a boolean");
    patch.starred = body.starred;
  }
  if (body.folder !== void 0) patch.folder = parseFolder(body.folder);
  return patch;
}
__name(parseFlagPatch, "parseFlagPatch");
function parseLimit(value) {
  if (value === null || value === "") return DEFAULT_LIMIT;
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n) || n < 1) throw badRequest("limit must be a positive integer");
  return Math.min(n, MAX_LIMIT);
}
__name(parseLimit, "parseLimit");
function flag(value) {
  return value === "1";
}
__name(flag, "flag");
function contentDisposition(filename) {
  const ascii = filename.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  const encoded = encodeURIComponent(filename).replace(/['()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encoded}`;
}
__name(contentDisposition, "contentDisposition");
async function health({ env }) {
  const config = await getConfig(env.DB);
  return json({
    version: WORKER_VERSION,
    time: (/* @__PURE__ */ new Date()).toISOString(),
    domains: config.domains,
    sendingConfigured: typeof env.EMAIL?.send === "function",
    sendUsage: await getSendUsage(env.DB, config.monthlySendLimit)
  });
}
__name(health, "health");
async function configResponse(db, config) {
  return json({ ...config, sendUsage: await getSendUsage(db, config.monthlySendLimit) });
}
__name(configResponse, "configResponse");
async function getConfigRoute({ env }) {
  return configResponse(env.DB, await getConfig(env.DB));
}
__name(getConfigRoute, "getConfigRoute");
async function putConfigRoute({ request, env }) {
  const patch = validateConfigPatch(await readJson(request));
  return configResponse(env.DB, await putConfig(env.DB, patch));
}
__name(putConfigRoute, "putConfigRoute");
async function mailboxes({ env }) {
  return json({ mailboxes: await listMailboxes(env.DB) });
}
__name(mailboxes, "mailboxes");
async function listRoute({ env, url }) {
  const q = url.searchParams;
  const folder = q.has("folder") && q.get("folder") !== "" ? parseFolder(q.get("folder")) : "inbox";
  const result = await listMessages(env.DB, {
    folder,
    mailbox: q.get("mailbox") ? normalizeEmail(q.get("mailbox")) : void 0,
    domain: q.get("domain") ? q.get("domain").trim().toLowerCase() : void 0,
    q: q.get("q")?.trim() || void 0,
    unread: flag(q.get("unread")),
    starred: flag(q.get("starred")),
    cursor: q.get("cursor") || void 0,
    limit: parseLimit(q.get("limit"))
  });
  return json(result);
}
__name(listRoute, "listRoute");
async function threadRoute({ env, params }) {
  const messages = await getThread(env.DB, params[0]);
  if (messages.length === 0) throw notFound(`Thread ${params[0]} not found`);
  return json({ messages });
}
__name(threadRoute, "threadRoute");
async function detailRoute({ env, params }) {
  const row = await requireMessageRow(env.DB, params[0]);
  const [bodyObj, attRows] = await Promise.all([env.MAIL.get(bodyKey(row.id)), getAttachmentRows(env.DB, row.id)]);
  let text = null;
  let html = null;
  if (bodyObj) {
    try {
      const body = await bodyObj.json();
      text = typeof body.text === "string" ? body.text : null;
      html = typeof body.html === "string" ? body.html : null;
    } catch (err) {
      console.error(`Body of ${row.id} is unreadable`, err);
    }
  }
  const detail = {
    ...rowToSummary(row),
    text,
    html,
    attachments: attRows.map(rowToAttachment),
    listUnsubscribe: row.list_unsubscribe
  };
  return json(detail);
}
__name(detailRoute, "detailRoute");
async function attachmentRoute({ env, params }) {
  const row = await getAttachmentRow(env.DB, params[0]);
  if (!row) throw notFound(`Attachment ${params[0]} not found`);
  const obj = await env.MAIL.get(attKey(row.message_id, row.idx));
  if (!obj) throw notFound(`Attachment ${row.id} content not found`);
  return new Response(obj.body, {
    headers: withBaseHeaders({
      "Content-Type": row.mime_type || "application/octet-stream",
      "Content-Length": String(obj.size),
      "Content-Disposition": contentDisposition(row.filename),
      "Content-Security-Policy": "sandbox"
    })
  });
}
__name(attachmentRoute, "attachmentRoute");
async function patchRoute({ request, env, params }) {
  const body = await readJson(request);
  if (!isPlainObject(body)) throw badRequest("Body must be a JSON object");
  const patch = parseFlagPatch(body);
  const row = await requireMessageRow(env.DB, params[0]);
  if (Object.keys(patch).length > 0) await updateMessages(env.DB, [row.id], patch);
  return json(rowToSummary(await requireMessageRow(env.DB, row.id)));
}
__name(patchRoute, "patchRoute");
async function deleteRoute({ env, params }) {
  const row = await requireMessageRow(env.DB, params[0]);
  if (row.folder !== "trash") {
    await updateMessages(env.DB, [row.id], { folder: "trash" });
    return json({ result: "trashed" });
  }
  await purgeMessages(env, [row.id]);
  return json({ result: "purged" });
}
__name(deleteRoute, "deleteRoute");
async function syncRoute({ env, url }) {
  const sinceParam = url.searchParams.get("since");
  let since = null;
  if (sinceParam !== null && sinceParam !== "") {
    if (!/^\d{1,15}$/.test(sinceParam)) throw badRequest("since is not a valid cursor", "invalid_cursor");
    since = Number(sinceParam);
  }
  return json(await syncChanges(env.DB, since));
}
__name(syncRoute, "syncRoute");
async function sendRoute({ request, env }) {
  const body = await readJson(request);
  const config = await getConfig(env.DB);
  return json(await sendMessage(env, config, body));
}
__name(sendRoute, "sendRoute");
async function contactsRoute({ env }) {
  return json({ contacts: await listContacts(env.DB) });
}
__name(contactsRoute, "contactsRoute");
async function brandsRoute({ env }) {
  return json({ brands: await listBrands(env.DB, await getConfig(env.DB)) });
}
__name(brandsRoute, "brandsRoute");
async function putBrandRoute({ request, env, params }) {
  const domain = requireDomain(await getConfig(env.DB), params[0]);
  return json(await putSignature(env.DB, domain, parseSignature(await readJson(request))));
}
__name(putBrandRoute, "putBrandRoute");
async function getLogoRoute({ env, params }) {
  const domain = requireDomain(await getConfig(env.DB), params[0]);
  const bytes = await getLogo(env, domain);
  if (!bytes) throw notFound(`${domain} has no logo`);
  return new Response(bytes, {
    headers: withBaseHeaders({
      "Content-Type": LOGO_TYPE,
      "Content-Length": String(bytes.byteLength),
      "Content-Security-Policy": "sandbox"
    })
  });
}
__name(getLogoRoute, "getLogoRoute");
async function putLogoRoute({ request, env, params }) {
  const domain = requireDomain(await getConfig(env.DB), params[0]);
  if ((request.headers.get("Content-Type") ?? "").split(";")[0].trim().toLowerCase() !== LOGO_TYPE) {
    throw badRequest(`The logo must be sent as ${LOGO_TYPE}`, "invalid_logo");
  }
  return json(await putLogo(env, domain, new Uint8Array(await request.arrayBuffer())));
}
__name(putLogoRoute, "putLogoRoute");
async function deleteLogoRoute({ env, params }) {
  const domain = requireDomain(await getConfig(env.DB), params[0]);
  return json(await deleteLogo(env, domain));
}
__name(deleteLogoRoute, "deleteLogoRoute");

// node_modules/postal-mime/dist/esm/decode-strings.js
var textEncoder = new TextEncoder();
var isWsp = /* @__PURE__ */ __name((c) => c === 32 || c === 9, "isWsp");
var base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
var base64Lookup = new Uint8Array(256);
for (let i = 0; i < base64Chars.length; i++) {
  base64Lookup[base64Chars.charCodeAt(i)] = i;
}
function decodeBase64(base64) {
  let len = base64.length;
  while (len > 0 && base64.charAt(len - 1) === "=") {
    len--;
  }
  if (len % 4 === 1) {
    len--;
  }
  const remainder = len % 4;
  const bufferLength = Math.floor(len / 4) * 3 + (remainder ? remainder - 1 : 0);
  const arrayBuffer = new ArrayBuffer(bufferLength);
  const bytes = new Uint8Array(arrayBuffer);
  let p = 0;
  for (let i = 0; i < len; i += 4) {
    let encoded1 = base64Lookup[base64.charCodeAt(i)];
    let encoded2 = base64Lookup[base64.charCodeAt(i + 1)];
    let encoded3 = base64Lookup[base64.charCodeAt(i + 2)];
    let encoded4 = base64Lookup[base64.charCodeAt(i + 3)];
    bytes[p++] = encoded1 << 2 | encoded2 >> 4;
    if (p < bufferLength) {
      bytes[p++] = (encoded2 & 15) << 4 | encoded3 >> 2;
    }
    if (p < bufferLength) {
      bytes[p++] = (encoded3 & 3) << 6 | encoded4 & 63;
    }
  }
  return arrayBuffer;
}
__name(decodeBase64, "decodeBase64");
var charsetAliases = /* @__PURE__ */ new Map([
  // Hebrew. The logical and explicit ordering variants share the iso-8859-8 index.
  ["iso88598i", "iso-8859-8"],
  ["iso88598e", "iso-8859-8"],
  // Japanese. WHATWG shift_jis is the Windows-31J index, so cp932 text decodes
  // identically, including the NEC and IBM extension rows.
  ["shiftjis", "shift_jis"],
  ["windows31j", "shift_jis"],
  ["mskanji", "shift_jis"],
  ["eucjp", "euc-jp"],
  // ISO-2022-JP, including the -1 / -2 supersets. Escape sequences outside plain
  // ISO-2022-JP (JIS X 0212, the non-Japanese G2 sets, and the SO/SI katakana shifts
  // cp50222 uses) decode to replacement characters, but the Japanese text around them
  // still comes out right.
  ["iso2022jp", "iso-2022-jp"],
  ["iso2022jp1", "iso-2022-jp"],
  ["iso2022jp2", "iso-2022-jp"],
  ["junet", "iso-2022-jp"],
  // Korean. The WHATWG euc-kr index is the extended cp949 / UHC index.
  ["euckr", "euc-kr"],
  ["uhc", "euc-kr"],
  // Thai.
  ["tis620", "windows-874"]
]);
var codePageAliases = /* @__PURE__ */ new Map([
  ["932", "shift_jis"],
  ["936", "gbk"],
  ["949", "euc-kr"],
  ["950", "big5"],
  ["874", "windows-874"],
  // Microsoft's EUC-JP and ISO-2022-JP variants. euc-jp and iso-2022-jp cover
  // everything they can express.
  ["51932", "euc-jp"],
  ["50220", "iso-2022-jp"],
  ["50221", "iso-2022-jp"],
  ["50222", "iso-2022-jp"]
]);
var codePagePattern = /^(?:cp|windows|ms|ibm)(\d+)$/;
function normalizeCharset(charset) {
  return charset.replace(/^(?:x-ms-|x-|cs)/, "").replace(/[\s._-]+/g, "");
}
__name(normalizeCharset, "normalizeCharset");
var ENCODING_LABELS = new Set([
  // UTF-8
  "unicode-1-1-utf-8 unicode11utf8 unicode20utf8 utf-8 utf8 x-unicode20utf8",
  // IBM866
  "866 cp866 csibm866 ibm866",
  // ISO-8859-2
  "csisolatin2 iso-8859-2 iso-ir-101 iso8859-2 iso88592 iso_8859-2 iso_8859-2:1987 l2 latin2",
  // ISO-8859-3
  "csisolatin3 iso-8859-3 iso-ir-109 iso8859-3 iso88593 iso_8859-3 iso_8859-3:1988 l3 latin3",
  // ISO-8859-4
  "csisolatin4 iso-8859-4 iso-ir-110 iso8859-4 iso88594 iso_8859-4 iso_8859-4:1988 l4 latin4",
  // ISO-8859-5
  "csisolatincyrillic cyrillic iso-8859-5 iso-ir-144 iso8859-5 iso88595 iso_8859-5 iso_8859-5:1988",
  // ISO-8859-6
  "arabic asmo-708 csiso88596e csiso88596i csisolatinarabic ecma-114 iso-8859-6 iso-8859-6-e",
  "iso-8859-6-i iso-ir-127 iso8859-6 iso88596 iso_8859-6 iso_8859-6:1987",
  // ISO-8859-7
  "csisolatingreek ecma-118 elot_928 greek greek8 iso-8859-7 iso-ir-126 iso8859-7 iso88597 iso_8859-7",
  "iso_8859-7:1987 sun_eu_greek",
  // ISO-8859-8
  "csiso88598e csisolatinhebrew hebrew iso-8859-8 iso-8859-8-e iso-ir-138 iso8859-8 iso88598 iso_8859-8",
  "iso_8859-8:1988 visual",
  // ISO-8859-8-I
  "csiso88598i iso-8859-8-i logical",
  // ISO-8859-10
  "csisolatin6 iso-8859-10 iso-ir-157 iso8859-10 iso885910 l6 latin6",
  // ISO-8859-13
  "iso-8859-13 iso8859-13 iso885913",
  // ISO-8859-14
  "iso-8859-14 iso8859-14 iso885914",
  // ISO-8859-15
  "csisolatin9 iso-8859-15 iso8859-15 iso885915 iso_8859-15 l9",
  // ISO-8859-16
  "iso-8859-16",
  // KOI8-R
  "cskoi8r koi koi8 koi8-r koi8_r",
  // KOI8-U
  "koi8-ru koi8-u",
  // macintosh
  "csmacintosh mac macintosh x-mac-roman",
  // windows-874
  "dos-874 iso-8859-11 iso8859-11 iso885911 tis-620 windows-874",
  // windows-1250
  "cp1250 windows-1250 x-cp1250",
  // windows-1251
  "cp1251 windows-1251 x-cp1251",
  // windows-1252
  "ansi_x3.4-1968 ascii cp1252 cp819 csisolatin1 ibm819 iso-8859-1 iso-ir-100 iso8859-1 iso88591",
  "iso_8859-1 iso_8859-1:1987 l1 latin1 us-ascii windows-1252 x-cp1252",
  // windows-1253
  "cp1253 windows-1253 x-cp1253",
  // windows-1254
  "cp1254 csisolatin5 iso-8859-9 iso-ir-148 iso8859-9 iso88599 iso_8859-9 iso_8859-9:1989 l5 latin5",
  "windows-1254 x-cp1254",
  // windows-1255
  "cp1255 windows-1255 x-cp1255",
  // windows-1256
  "cp1256 windows-1256 x-cp1256",
  // windows-1257
  "cp1257 windows-1257 x-cp1257",
  // windows-1258
  "cp1258 windows-1258 x-cp1258",
  // x-mac-cyrillic
  "x-mac-cyrillic x-mac-ukrainian",
  // GBK
  "chinese csgb2312 csiso58gb231280 gb2312 gb_2312 gb_2312-80 gbk iso-ir-58 x-gbk",
  // gb18030
  "gb18030",
  // Big5
  "big5 big5-hkscs cn-big5 csbig5 x-x-big5",
  // EUC-JP
  "cseucpkdfmtjapanese euc-jp x-euc-jp",
  // ISO-2022-JP
  "csiso2022jp iso-2022-jp",
  // Shift_JIS
  "csshiftjis ms932 ms_kanji shift-jis shift_jis sjis windows-31j x-sjis",
  // EUC-KR
  "cseuckr csksc56011987 euc-kr iso-ir-149 korean ks_c_5601-1987 ks_c_5601-1989 ksc5601 ksc_5601",
  "windows-949",
  // replacement
  "csiso2022kr hz-gb-2312 iso-2022-cn iso-2022-cn-ext iso-2022-kr replacement",
  // UTF-16BE
  "unicodefffe utf-16be",
  // UTF-16LE
  "csunicode iso-10646-ucs-2 ucs-2 unicode unicodefeff utf-16 utf-16le",
  // x-user-defined
  "x-user-defined"
].join(" ").split(" "));
var decoders = /* @__PURE__ */ new Map();
function tryDecoder(charset) {
  if (!ENCODING_LABELS.has(charset)) {
    return null;
  }
  let decoder = decoders.get(charset);
  if (decoder === void 0) {
    decoder = null;
    try {
      decoder = new TextDecoder(charset);
    } catch {
    }
    decoders.set(charset, decoder);
  }
  return decoder;
}
__name(tryDecoder, "tryDecoder");
var utf8Decoder = new TextDecoder();
function findDecoder(charset) {
  charset = (charset || "utf8").trim().toLowerCase();
  const decoder = tryDecoder(charset);
  if (decoder) {
    return decoder;
  }
  const normalized = normalizeCharset(charset);
  const codePage = normalized.match(codePagePattern);
  const alias = codePage && codePageAliases.get(codePage[1]) || charsetAliases.get(normalized) || normalized;
  return tryDecoder(alias);
}
__name(findDecoder, "findDecoder");
function getDecoder(charset) {
  return findDecoder(charset) || tryDecoder("windows-1252") || utf8Decoder;
}
__name(getDecoder, "getDecoder");
function isUtf8(bytes) {
  for (let i = 0; i < bytes.length; ) {
    const lead = bytes[i];
    if (lead < 128) {
      i++;
      continue;
    }
    let count;
    if (lead >= 194 && lead <= 223) {
      count = 1;
    } else if (lead >= 224 && lead <= 239) {
      count = 2;
    } else if (lead >= 240 && lead <= 244) {
      count = 3;
    } else {
      return false;
    }
    if (i + count >= bytes.length) {
      return false;
    }
    const second = bytes[i + 1];
    const min = lead === 224 ? 160 : lead === 240 ? 144 : 128;
    const max = lead === 237 ? 159 : lead === 244 ? 143 : 191;
    if (second < min || second > max) {
      return false;
    }
    for (let k = 2; k <= count; k++) {
      if ((bytes[i + k] & 192) !== 128) {
        return false;
      }
    }
    i += count + 1;
  }
  return true;
}
__name(isUtf8, "isUtf8");
function decodeUtf8OrWindows1252(bytes, utf8 = utf8Decoder) {
  const view = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  return isUtf8(view) ? utf8.decode(view) : getDecoder("windows-1252").decode(view);
}
__name(decodeUtf8OrWindows1252, "decodeUtf8OrWindows1252");
function decodeCharset(bytes, charset) {
  const decoder = findDecoder(charset);
  return decoder ? decoder.decode(bytes) : decodeUtf8OrWindows1252(bytes);
}
__name(decodeCharset, "decodeCharset");
var META_PRESCAN_BYTES = 1024;
var CHARSET_ATTRIBUTE = /charset\s*=\s*["']?\s*([^\s"';>]+)/;
var UTF16_ENCODINGS = /* @__PURE__ */ new Set(["utf-16le", "utf-16be"]);
function sniffHtmlCharset(bytes) {
  const head = utf8Decoder.decode(bytes.subarray(0, META_PRESCAN_BYTES)).toLowerCase();
  let pos = 0;
  while ((pos = head.indexOf("<meta", pos)) >= 0) {
    let end = head.indexOf(">", pos);
    if (end < 0) {
      end = head.length;
    }
    const match2 = CHARSET_ATTRIBUTE.exec(head.slice(pos, end));
    if (match2) {
      return match2[1];
    }
    pos = end;
  }
  return null;
}
__name(sniffHtmlCharset, "sniffHtmlCharset");
function decodeText(bytes, charset, html) {
  const view = new Uint8Array(bytes);
  if (charset) {
    return decodeCharset(view, charset);
  }
  const sniffed = html ? sniffHtmlCharset(view) : null;
  const decoder = sniffed ? findDecoder(sniffed) : null;
  if (!decoder || UTF16_ENCODINGS.has(decoder.encoding)) {
    return decodeUtf8OrWindows1252(view);
  }
  return (decoder.encoding === "x-user-defined" ? getDecoder("windows-1252") : decoder).decode(view);
}
__name(decodeText, "decodeText");
async function blobToArrayBuffer(blob) {
  if ("arrayBuffer" in blob) {
    return await blob.arrayBuffer();
  }
  const fr = new FileReader();
  return new Promise((resolve, reject) => {
    fr.onload = () => {
      resolve(fr.result);
    };
    fr.onerror = () => {
      reject(fr.error);
    };
    fr.readAsArrayBuffer(blob);
  });
}
__name(blobToArrayBuffer, "blobToArrayBuffer");
function hexNibble(c) {
  if (c >= 48 && c <= 57) {
    return c - 48;
  }
  if (c >= 97 && c <= 102) {
    return c - 97 + 10;
  }
  if (c >= 65 && c <= 70) {
    return c - 65 + 10;
  }
  return -1;
}
__name(hexNibble, "hexNibble");
function foldLineBreaks(str) {
  return str.replace(/[\r\n]+/g, " ");
}
__name(foldLineBreaks, "foldLineBreaks");
function decodeWord(charset, encoding, str) {
  let splitPos = charset.indexOf("*");
  if (splitPos >= 0) {
    charset = charset.slice(0, splitPos);
  }
  encoding = encoding.toUpperCase();
  let byteStr;
  if (encoding === "Q") {
    str = str.replace(/=\s+([0-9a-fA-F])/g, "=$1").replace(/[_\s]/g, " ");
    let buf = textEncoder.encode(str);
    let encodedBytes = [];
    for (let i = 0, len = buf.length; i < len; i++) {
      let c = buf[i];
      if (i <= len - 2 && c === 61) {
        let high = hexNibble(buf[i + 1]);
        let low = hexNibble(buf[i + 2]);
        if (high >= 0 && low >= 0) {
          encodedBytes.push(high << 4 | low);
          i += 2;
          continue;
        }
      }
      encodedBytes.push(c);
    }
    byteStr = new ArrayBuffer(encodedBytes.length);
    let dataView = new DataView(byteStr);
    for (let i = 0, len = encodedBytes.length; i < len; i++) {
      dataView.setUint8(i, encodedBytes[i]);
    }
  } else if (encoding === "B") {
    byteStr = decodeBase64(str.replace(/[^a-zA-Z0-9\+\/=]+/g, ""));
  } else {
    byteStr = textEncoder.encode(str);
  }
  return foldLineBreaks(decodeCharset(byteStr, charset));
}
__name(decodeWord, "decodeWord");
var ENCODED_WORD_PATTERN = "=\\?([^?\\s]+)\\?([QqBb])\\?([^?]*)\\?=";
var ENCODED_WORD_REGEX = new RegExp(ENCODED_WORD_PATTERN, "g");
var WORD_SEPARATOR_REGEX = /^[ \t\r\n]+$/;
var ENCODED_WORDS_ONLY_REGEX = new RegExp(`^(?:${ENCODED_WORD_PATTERN}\\s*)+$`);
function isEncodedWordsOnly(str) {
  return ENCODED_WORDS_ONLY_REGEX.test(str);
}
__name(isEncodedWordsOnly, "isEncodedWordsOnly");
function splitEncodedWords(str) {
  const tokens = [];
  ENCODED_WORD_REGEX.lastIndex = 0;
  let pos = 0;
  let match2;
  while (match2 = ENCODED_WORD_REGEX.exec(str)) {
    if (match2.index > pos) {
      tokens.push({ text: str.substring(pos, match2.index) });
    }
    tokens.push({ charset: match2[1], encoding: match2[2], encodedText: match2[3] });
    pos = match2.index + match2[0].length;
  }
  if (pos < str.length) {
    tokens.push({ text: str.substring(pos) });
  }
  return tokens;
}
__name(splitEncodedWords, "splitEncodedWords");
function canJoinWords(left, right) {
  const encoding = left.encoding.toUpperCase();
  if (left.charset !== right.charset || encoding !== right.encoding.toUpperCase()) {
    return false;
  }
  if (encoding === "B") {
    return left.encodedText.length % 4 === 0 && !/=$/.test(left.encodedText);
  }
  return true;
}
__name(canJoinWords, "canJoinWords");
function renderTokens(tokens, joinWords) {
  let result = "";
  let pending = null;
  for (let i = 0; i < tokens.length; i++) {
    const token = tokens[i];
    if (token.text !== void 0) {
      const nextToken = tokens[i + 1];
      if (pending && nextToken && nextToken.text === void 0 && WORD_SEPARATOR_REGEX.test(token.text)) {
        continue;
      }
      if (pending) {
        result += decodeWord(pending.charset, pending.encoding, pending.encodedText);
        pending = null;
      }
      result += token.text;
      continue;
    }
    if (pending && joinWords && canJoinWords(pending, token)) {
      pending.encodedText += token.encodedText;
      continue;
    }
    if (pending) {
      result += decodeWord(pending.charset, pending.encoding, pending.encodedText);
    }
    pending = { charset: token.charset, encoding: token.encoding, encodedText: token.encodedText };
  }
  if (pending) {
    result += decodeWord(pending.charset, pending.encoding, pending.encodedText);
  }
  return result;
}
__name(renderTokens, "renderTokens");
function decodeWords(str) {
  const tokens = splitEncodedWords((str || "").toString());
  const result = renderTokens(tokens, true);
  return result.indexOf("\uFFFD") < 0 ? result : renderTokens(tokens, false);
}
__name(decodeWords, "decodeWords");
function decodeURIComponentWithCharset(encodedStr, charset) {
  charset = charset || "utf-8";
  let encodedBytes = [];
  for (let i = 0; i < encodedStr.length; i++) {
    let c = encodedStr.charAt(i);
    const high = c === "%" ? hexNibble(encodedStr.charCodeAt(i + 1)) : -1;
    const low = high >= 0 ? hexNibble(encodedStr.charCodeAt(i + 2)) : -1;
    if (low >= 0) {
      encodedBytes.push(high << 4 | low);
      i += 2;
    } else if (c.charCodeAt(0) > 126) {
      const bytes = textEncoder.encode(c);
      for (let j = 0; j < bytes.length; j++) {
        encodedBytes.push(bytes[j]);
      }
    } else {
      encodedBytes.push(c.charCodeAt(0));
    }
  }
  const byteStr = new ArrayBuffer(encodedBytes.length);
  const dataView = new DataView(byteStr);
  for (let i = 0, len = encodedBytes.length; i < len; i++) {
    dataView.setUint8(i, encodedBytes[i]);
  }
  return decodeCharset(byteStr, charset);
}
__name(decodeURIComponentWithCharset, "decodeURIComponentWithCharset");
function decodeParameterValueContinuations(header) {
  let paramKeys = /* @__PURE__ */ new Map();
  Object.keys(header.params).forEach((key) => {
    let match2 = key.match(/\*((\d+)\*?)?$/);
    if (!match2) {
      return;
    }
    let actualKey = key.slice(0, match2.index).toLowerCase();
    let nr = Number(match2[2]) || 0;
    let paramVal = paramKeys.get(actualKey);
    if (!paramVal) {
      paramVal = {
        charset: null,
        values: []
      };
      paramKeys.set(actualKey, paramVal);
    }
    let value = header.params[key];
    let encoded = match2[0].charAt(match2[0].length - 1) === "*";
    if (nr === 0 && encoded && (match2 = value.match(/^([^']*)'[^']*'(.*)$/))) {
      paramVal.charset = match2[1] || "utf-8";
      value = match2[2];
    }
    paramVal.values.push({ nr, value, encoded });
    delete header.params[key];
  });
  paramKeys.forEach((paramVal, key) => {
    if (Object.prototype.hasOwnProperty.call(header.params, key)) {
      return;
    }
    let result = "";
    let pending = "";
    for (let part of paramVal.values.sort((a, b) => a.nr - b.nr)) {
      if (part.encoded) {
        pending += part.value;
        continue;
      }
      if (pending) {
        result += decodeURIComponentWithCharset(pending, paramVal.charset);
        pending = "";
      }
      result += part.value;
    }
    if (pending) {
      result += decodeURIComponentWithCharset(pending, paramVal.charset);
    }
    header.params[key] = result;
  });
}
__name(decodeParameterValueContinuations, "decodeParameterValueContinuations");

// node_modules/postal-mime/dist/esm/pass-through-decoder.js
var PassThroughDecoder = class {
  static {
    __name(this, "PassThroughDecoder");
  }
  constructor() {
    this.chunks = [];
    this.runBuffer = null;
    this.runStart = 0;
    this.runEnd = 0;
    this.pendingLineBreak = null;
  }
  // Whether the bytes sit in the run's buffer right at the end of the run
  continuesRun(bytes) {
    return bytes.buffer === this.runBuffer && bytes.byteOffset === this.runEnd;
  }
  flushRun() {
    if (this.runBuffer && this.runEnd > this.runStart) {
      this.chunks.push(new Uint8Array(this.runBuffer, this.runStart, this.runEnd - this.runStart));
    }
    this.runBuffer = null;
  }
  update(line, lineBreak) {
    const pending = this.pendingLineBreak;
    if (pending && this.continuesRun(pending) && line.buffer === this.runBuffer && line.byteOffset === this.runEnd + pending.byteLength) {
      this.runEnd = line.byteOffset + line.byteLength;
    } else {
      this.flushRun();
      if (pending) {
        this.chunks.push(pending);
      }
      this.runBuffer = line.buffer;
      this.runStart = line.byteOffset;
      this.runEnd = line.byteOffset + line.byteLength;
    }
    this.pendingLineBreak = lineBreak;
  }
  // A part ended by the end of the message has no boundary to own its final line
  // break, so there it stays content
  finalize(boundaryEnded = false) {
    const pending = this.pendingLineBreak;
    if (!boundaryEnded && pending) {
      if (this.continuesRun(pending)) {
        this.runEnd += pending.byteLength;
      } else {
        this.flushRun();
        this.chunks.push(pending);
      }
    }
    this.flushRun();
    return blobToArrayBuffer(new Blob(this.chunks, { type: "application/octet-stream" }));
  }
};

// node_modules/postal-mime/dist/esm/base64-decoder.js
var Base64Decoder = class {
  static {
    __name(this, "Base64Decoder");
  }
  constructor(opts) {
    opts = opts || {};
    this.decoder = opts.decoder || new TextDecoder();
    this.maxChunkSize = 100 * 1024;
    this.chunks = [];
    this.remainder = "";
  }
  pushChunk(base64Str) {
    if (base64Str.length) {
      this.chunks.push(decodeBase64(base64Str));
    }
  }
  flushRemainder() {
    this.pushChunk(this.remainder);
    this.remainder = "";
  }
  update(buffer) {
    let str = this.decoder.decode(buffer).replace(/[^a-zA-Z0-9+/=]+/g, "");
    const units = str.split(/=+/);
    for (let i = 0; i < units.length; i++) {
      this.remainder += units[i];
      if (i < units.length - 1) {
        this.flushRemainder();
      }
    }
    if (this.remainder.length >= this.maxChunkSize) {
      const alignedLength = Math.floor(this.remainder.length / 4) * 4;
      this.pushChunk(this.remainder.substring(0, alignedLength));
      this.remainder = this.remainder.substring(alignedLength);
    }
  }
  finalize() {
    this.flushRemainder();
    return blobToArrayBuffer(new Blob(this.chunks, { type: "application/octet-stream" }));
  }
};

// node_modules/postal-mime/dist/esm/qp-decoder.js
var CHR_EQUALS = 61;
var QPDecoder = class {
  static {
    __name(this, "QPDecoder");
  }
  constructor() {
    this.maxChunkSize = 100 * 1024;
    this.buffer = new Uint8Array(this.maxChunkSize);
    this.bufferPos = 0;
    this.chunks = [];
    this.pendingLineBreak = null;
  }
  writeLineBreak() {
    if (this.pendingLineBreak) {
      this.writeBytes(this.pendingLineBreak, 0, this.pendingLineBreak.length);
    }
  }
  writeByte(byte) {
    if (this.bufferPos >= this.buffer.length) {
      this.flushBuffer();
    }
    this.buffer[this.bufferPos++] = byte;
  }
  // Literal text is the bulk of a typical body, so it is copied in runs rather than a
  // byte at a time
  writeBytes(line, start, end) {
    while (start < end) {
      if (this.bufferPos >= this.buffer.length) {
        this.flushBuffer();
      }
      const count = Math.min(end - start, this.buffer.length - this.bufferPos);
      this.buffer.set(line.subarray(start, start + count), this.bufferPos);
      this.bufferPos += count;
      start += count;
    }
  }
  flushBuffer() {
    if (this.bufferPos) {
      this.chunks.push(this.buffer.slice(0, this.bufferPos));
      this.bufferPos = 0;
    }
  }
  // Quoted-printable source is 7 bit by definition, so it is decoded byte by byte and
  // the result is handed on as bytes. Running the body charset over the encoded source
  // instead corrupted every part whose charset was not ASCII compatible: the same
  // content that decoded correctly in base64 came out as mojibake in quoted-printable.
  //
  // As in PassThroughDecoder, a hard line break is only written once the next line
  // arrives, so the CRLF that belongs to a following boundary is not decoded as content,
  // and the break written is the one the line came with.
  update(line, lineBreak) {
    this.writeLineBreak();
    let len = line.length;
    while (len > 0 && isWsp(line[len - 1])) {
      len--;
    }
    const softBreak = len > 0 && line[len - 1] === CHR_EQUALS;
    if (softBreak) {
      len--;
    }
    let literalStart = 0;
    for (let i = 0; i < len; i++) {
      if (line[i] !== CHR_EQUALS || i + 2 >= len) {
        continue;
      }
      const high = hexNibble(line[i + 1]);
      const low = hexNibble(line[i + 2]);
      if (high < 0 || low < 0) {
        continue;
      }
      this.writeBytes(line, literalStart, i);
      this.writeByte(high << 4 | low);
      i += 2;
      literalStart = i + 1;
    }
    this.writeBytes(line, literalStart, len);
    this.pendingLineBreak = softBreak ? null : lineBreak;
  }
  // see PassThroughDecoder.finalize
  finalize(boundaryEnded = false) {
    if (!boundaryEnded) {
      this.writeLineBreak();
    }
    this.flushBuffer();
    return blobToArrayBuffer(new Blob(this.chunks, { type: "application/octet-stream" }));
  }
};

// node_modules/postal-mime/dist/esm/mime-node.js
var headerDecoder = new TextDecoder("utf-8", { ignoreBOM: true });
var trimWsp = /* @__PURE__ */ __name((str) => {
  let start = 0;
  let end = str.length;
  while (start < end && isWsp(str.charCodeAt(start))) {
    start++;
  }
  while (end > start && isWsp(str.charCodeAt(end - 1))) {
    end--;
  }
  return str.slice(start, end);
}, "trimWsp");
var isBlankLine = /* @__PURE__ */ __name((line) => line.every(isWsp), "isBlankLine");
var FIELD_START = /^[!-9;-~]+[ \t]*:/;
var CONTENT_HEADERS = /* @__PURE__ */ new Set([
  "content-type",
  "content-transfer-encoding",
  "content-disposition",
  "content-id",
  "content-description"
]);
var MimeNode = class {
  static {
    __name(this, "MimeNode");
  }
  constructor(options) {
    this.options = options;
    this.postalMime = options.postalMime;
    this.postalMime.partCount++;
    if (this.postalMime.partCount > options.maxPartCount) {
      throw new Error(`Maximum MIME part count of ${options.maxPartCount} parts exceeded`);
    }
    this.childNodes = [];
    this.finalizedChildCount = 0;
    if (options.parentNode) {
      this.parentNode = options.parentNode;
      this.depth = this.parentNode.depth + 1;
      if (this.depth > options.maxNestingDepth) {
        throw new Error(`Maximum MIME nesting depth of ${options.maxNestingDepth} levels exceeded`);
      }
      options.parentNode.childNodes.push(this);
    } else {
      this.depth = 0;
    }
    this.state = "header";
    this.headerLines = [];
    this.lastLineBlank = false;
    const parentMultipartType = options.parentMultipartType || null;
    const defaultContentType = parentMultipartType === "digest" ? "message/rfc822" : "text/plain";
    this.contentType = {
      value: defaultContentType,
      parsed: { value: defaultContentType, params: {} },
      multipart: false
    };
    this.contentTransferEncoding = {
      value: "8bit",
      encoding: ""
    };
    this.contentDisposition = {
      value: "",
      parsed: { value: "", params: {} }
    };
    this.headers = [];
    this.rawHeaderLines = [];
    this.contentDecoder = null;
    this.content = null;
  }
  setupContentDecoder(transferEncoding) {
    if (/base64/i.test(transferEncoding)) {
      this.contentDecoder = new Base64Decoder();
    } else if (/quoted-printable/i.test(transferEncoding)) {
      this.contentDecoder = new QPDecoder();
    } else {
      this.contentDecoder = new PassThroughDecoder();
    }
  }
  // `boundaryEnded` tells that the part was ended by a multipart boundary, which owns
  // the line break after the last line of the part (RFC 2046 5.1.1)
  async finalize(boundaryEnded = false) {
    if (this.state === "finished") {
      return;
    }
    if (this.state === "header") {
      this.endHeaders();
    }
    let boundaries = this.postalMime.boundaries;
    for (let i = boundaries.length - 1; i >= 0; i--) {
      let boundary2 = boundaries[i];
      if (boundary2.node === this) {
        boundaries.splice(i, 1);
        break;
      }
    }
    await this.finalizeChildNodes(boundaryEnded);
    this.content = this.contentDecoder ? await this.contentDecoder.finalize(boundaryEnded) : null;
    this.contentDecoder = null;
    this.state = "finished";
  }
  async finalizeChildNodes(boundaryEnded = false) {
    while (this.finalizedChildCount < this.childNodes.length) {
      await this.childNodes[this.finalizedChildCount++].finalize(boundaryEnded);
    }
  }
  // Strip RFC 822 comments (parenthesized text) from structured header values.
  //
  // Inside an unquoted parameter value a parenthesis that continues the current token is
  // content, because `filename=Invoice(1).pdf` is a filename and not a token followed by
  // a comment, and deleting the parens silently renames the attachment.
  stripComments(str) {
    let result = "";
    let depth = 0;
    let escaped = false;
    let inQuote = false;
    let commentStart = -1;
    let inParameterValue = false;
    let endsWithWsp = false;
    const append = /* @__PURE__ */ __name((c) => {
      result += c;
      endsWithWsp = c === " " || c === "	";
    }, "append");
    const opensComment = /* @__PURE__ */ __name(() => !inParameterValue || !result.length || endsWithWsp, "opensComment");
    for (let i = 0; i < str.length; i++) {
      const chr = str.charAt(i);
      if (escaped) {
        if (depth === 0) {
          append(chr);
        }
        escaped = false;
        continue;
      }
      if (chr === "\\") {
        escaped = true;
        if (depth === 0) {
          append(chr);
        }
        continue;
      }
      if (chr === '"' && depth === 0) {
        inQuote = !inQuote;
        append(chr);
        continue;
      }
      if (!inQuote) {
        if (chr === "(" && opensComment()) {
          if (depth === 0) {
            commentStart = i;
          }
          depth++;
          continue;
        }
        if (chr === ")" && depth > 0) {
          depth--;
          continue;
        }
        if (depth === 0) {
          if (chr === "=") {
            inParameterValue = true;
          } else if (chr === ";") {
            inParameterValue = false;
          }
        }
      }
      if (depth === 0) {
        append(chr);
      }
    }
    if (depth === 0) {
      return result;
    }
    return str.indexOf(";", commentStart) < 0 ? result : str;
  }
  parseStructuredHeader(str) {
    str = this.stripComments(str);
    let response = {
      value: "",
      params: {}
    };
    let key = false;
    let value = "";
    let stage = "value";
    let pendingSpace = "";
    let quoteClosed = false;
    let quote = false;
    let escaped = false;
    let chr;
    const flushSpace = /* @__PURE__ */ __name(() => {
      if (value.length) {
        value += pendingSpace;
      }
      pendingSpace = "";
    }, "flushSpace");
    const addChr = /* @__PURE__ */ __name((c) => {
      flushSpace();
      value += c;
    }, "addChr");
    const takeValue = /* @__PURE__ */ __name(() => {
      const result = value;
      value = "";
      pendingSpace = "";
      quoteClosed = false;
      return result;
    }, "takeValue");
    const storeParam = /* @__PURE__ */ __name((name, result) => {
      if (name && !Object.prototype.hasOwnProperty.call(response.params, name)) {
        response.params[name] = result;
      }
    }, "storeParam");
    const storeValue = /* @__PURE__ */ __name(() => {
      const result = takeValue();
      if (key === false) {
        response.value = result;
      } else {
        storeParam(key, result);
      }
    }, "storeValue");
    const storeEmptyKey = /* @__PURE__ */ __name(() => {
      storeParam(takeValue().trim().toLowerCase(), "");
    }, "storeEmptyKey");
    for (let i = 0, len = str.length; i < len; i++) {
      chr = str.charAt(i);
      switch (stage) {
        case "key":
          if (chr === "=") {
            key = takeValue().trim().toLowerCase();
            stage = "value";
            break;
          }
          if (chr === ";") {
            storeEmptyKey();
            break;
          }
          value += chr;
          break;
        case "value":
          if (quoteClosed && chr !== ";") {
            escaped = false;
            break;
          }
          if (escaped) {
            addChr(chr);
          } else if (quote && chr === "\\") {
            escaped = true;
            continue;
          } else if (quote && chr === quote) {
            quote = false;
            quoteClosed = true;
          } else if (!quote && chr === '"') {
            quote = chr;
            flushSpace();
          } else if (!quote && chr === ";") {
            storeValue();
            stage = "key";
          } else if (!quote && (chr === " " || chr === "	")) {
            pendingSpace += chr;
          } else {
            addChr(chr);
          }
          escaped = false;
          break;
      }
    }
    if (stage === "value") {
      storeValue();
    } else {
      storeEmptyKey();
    }
    if (response.value) {
      response.value = response.value.toLowerCase();
    }
    decodeParameterValueContinuations(response);
    return response;
  }
  // Unfolds format=flowed text (RFC 3676 4.1). A line is read as its quote marks, one
  // space of stuffing and its content, in that order, and a line whose content ends in a
  // space is flowed: the next line of the same quote depth continues its paragraph. The
  // paragraph ends at a fixed line, at a change of quote depth and at the signature
  // separator, which is neither flowed nor fixed. Joining a quoted paragraph used to
  // leave the quote marks of the continuation lines inside the text, so a quoted reply
  // read `> one > two` instead of `> one two`.
  //
  // The quote marks and stuffing of the first line of a paragraph are kept as they were
  // written, so a fixed quoted line comes out exactly as it went in. An unquoted stuffed
  // line loses its stuffing, which is all the stuffing is for.
  decodeFlowedText(str, delSp) {
    const parts = [];
    let flowed = false;
    let depth = 0;
    const lines = str.split("\n");
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];
      let quoteDepth = 0;
      while (line.charCodeAt(quoteDepth) === 62) {
        quoteDepth++;
      }
      const contentStart = line.charCodeAt(quoteDepth) === 32 ? quoteDepth + 1 : quoteDepth;
      const content = line.slice(contentStart);
      const isSignature = content === "-- ";
      if (flowed && quoteDepth === depth && !isSignature) {
        if (delSp) {
          const last = parts[parts.length - 1];
          parts[parts.length - 1] = last.slice(0, -1);
        }
        parts.push(content);
      } else {
        if (i) {
          parts.push("\n");
        }
        parts.push(quoteDepth ? line : content);
      }
      flowed = !isSignature && content.endsWith(" ");
      depth = quoteDepth;
    }
    return parts.join("");
  }
  getTextContent() {
    if (!this.content) {
      return "";
    }
    let str = decodeText(this.content, this.contentType.parsed.params.charset, this.contentType.parsed.value === "text/html").replace(/\r\n/g, "\n");
    if (/^flowed$/i.test(this.contentType.parsed.params.format)) {
      str = this.decodeFlowedText(str, /^yes$/i.test(this.contentType.parsed.params.delsp));
    }
    return str;
  }
  processHeaders() {
    let foldedLines = [];
    for (let line of this.headerLines) {
      if (foldedLines.length && /^[ \t]/.test(line)) {
        foldedLines[foldedLines.length - 1].push(line);
      } else {
        foldedLines.push([line]);
      }
    }
    let seenContentHeaders = /* @__PURE__ */ new Set();
    for (let parts of foldedLines) {
      let rawLine = parts.join("\n");
      let sep = rawLine.indexOf(":");
      let rawKey2 = trimWsp(sep < 0 ? rawLine : rawLine.slice(0, sep));
      this.rawHeaderLines.push({
        key: rawKey2.toLowerCase(),
        line: rawLine
      });
      let unfoldedLine = parts.join("");
      sep = unfoldedLine.indexOf(":");
      let key = trimWsp(sep < 0 ? unfoldedLine : unfoldedLine.slice(0, sep));
      let value = sep < 0 ? "" : trimWsp(foldLineBreaks(unfoldedLine.slice(sep + 1)));
      this.headers.push({ key: key.toLowerCase(), originalKey: key, value });
      const lowerKey = key.toLowerCase();
      if (CONTENT_HEADERS.has(lowerKey) && !seenContentHeaders.has(lowerKey)) {
        seenContentHeaders.add(lowerKey);
        switch (lowerKey) {
          case "content-type":
            this.contentType.value = value;
            break;
          case "content-transfer-encoding":
            this.contentTransferEncoding.value = value;
            break;
          case "content-disposition":
            this.contentDisposition.value = value;
            break;
          case "content-id":
            this.contentId = value;
            break;
          case "content-description":
            this.contentDescription = value;
            break;
        }
      }
    }
    this.contentType.parsed = this.parseStructuredHeader(this.contentType.value);
    this.contentType.multipart = /^multipart\//i.test(this.contentType.parsed.value) ? this.contentType.parsed.value.slice(this.contentType.parsed.value.indexOf("/") + 1) : false;
    if (this.contentType.multipart && !this.contentType.parsed.params.boundary) {
      this.contentType.parsed.value = "text/plain";
      this.contentType.multipart = false;
    }
    if (this.contentType.multipart) {
      this.postalMime.boundaries.push({
        value: textEncoder.encode(this.contentType.parsed.params.boundary),
        node: this
      });
    }
    this.contentDisposition.parsed = this.parseStructuredHeader(this.contentDisposition.value);
    this.contentTransferEncoding.encoding = (this.stripComments(this.contentTransferEncoding.value).toLowerCase().match(/[\w-]+/) || [""])[0];
    this.setupContentDecoder(this.contentTransferEncoding.encoding);
  }
  // Ends the header section and sets up the body
  endHeaders() {
    this.state = "body";
    this.processHeaders();
  }
  // Returns true when the line was not consumed: the headers ended with the line before
  // it, and the parser has to read it again, since the boundary this part declares was
  // not known yet when the line was checked for one
  feed(line, lineBreak) {
    switch (this.state) {
      case "header": {
        if (!line.length) {
          this.endHeaders();
          return false;
        }
        this.postalMime.headerSize += line.length;
        if (this.postalMime.headerSize > this.options.maxHeadersSize) {
          let error = new Error(`Maximum header size of ${this.options.maxHeadersSize} bytes exceeded`);
          throw error;
        }
        const text = decodeUtf8OrWindows1252(line, headerDecoder);
        if (this.lastLineBlank && !isWsp(line[0]) && !FIELD_START.test(text)) {
          this.headerLines.pop();
          this.endHeaders();
          return true;
        }
        this.headerLines.push(text);
        this.lastLineBlank = isBlankLine(line);
        break;
      }
      case "body":
        if (this.contentDecoder) {
          this.contentDecoder.update(line, lineBreak);
        }
        break;
    }
    return false;
  }
};

// node_modules/postal-mime/dist/esm/html-entities.js
var htmlEntities = {
  "&AElig": "\xC6",
  "&AElig;": "\xC6",
  "&AMP": "&",
  "&AMP;": "&",
  "&Aacute": "\xC1",
  "&Aacute;": "\xC1",
  "&Abreve;": "\u0102",
  "&Acirc": "\xC2",
  "&Acirc;": "\xC2",
  "&Acy;": "\u0410",
  "&Afr;": "\u{1D504}",
  "&Agrave": "\xC0",
  "&Agrave;": "\xC0",
  "&Alpha;": "\u0391",
  "&Amacr;": "\u0100",
  "&And;": "\u2A53",
  "&Aogon;": "\u0104",
  "&Aopf;": "\u{1D538}",
  "&ApplyFunction;": "\u2061",
  "&Aring": "\xC5",
  "&Aring;": "\xC5",
  "&Ascr;": "\u{1D49C}",
  "&Assign;": "\u2254",
  "&Atilde": "\xC3",
  "&Atilde;": "\xC3",
  "&Auml": "\xC4",
  "&Auml;": "\xC4",
  "&Backslash;": "\u2216",
  "&Barv;": "\u2AE7",
  "&Barwed;": "\u2306",
  "&Bcy;": "\u0411",
  "&Because;": "\u2235",
  "&Bernoullis;": "\u212C",
  "&Beta;": "\u0392",
  "&Bfr;": "\u{1D505}",
  "&Bopf;": "\u{1D539}",
  "&Breve;": "\u02D8",
  "&Bscr;": "\u212C",
  "&Bumpeq;": "\u224E",
  "&CHcy;": "\u0427",
  "&COPY": "\xA9",
  "&COPY;": "\xA9",
  "&Cacute;": "\u0106",
  "&Cap;": "\u22D2",
  "&CapitalDifferentialD;": "\u2145",
  "&Cayleys;": "\u212D",
  "&Ccaron;": "\u010C",
  "&Ccedil": "\xC7",
  "&Ccedil;": "\xC7",
  "&Ccirc;": "\u0108",
  "&Cconint;": "\u2230",
  "&Cdot;": "\u010A",
  "&Cedilla;": "\xB8",
  "&CenterDot;": "\xB7",
  "&Cfr;": "\u212D",
  "&Chi;": "\u03A7",
  "&CircleDot;": "\u2299",
  "&CircleMinus;": "\u2296",
  "&CirclePlus;": "\u2295",
  "&CircleTimes;": "\u2297",
  "&ClockwiseContourIntegral;": "\u2232",
  "&CloseCurlyDoubleQuote;": "\u201D",
  "&CloseCurlyQuote;": "\u2019",
  "&Colon;": "\u2237",
  "&Colone;": "\u2A74",
  "&Congruent;": "\u2261",
  "&Conint;": "\u222F",
  "&ContourIntegral;": "\u222E",
  "&Copf;": "\u2102",
  "&Coproduct;": "\u2210",
  "&CounterClockwiseContourIntegral;": "\u2233",
  "&Cross;": "\u2A2F",
  "&Cscr;": "\u{1D49E}",
  "&Cup;": "\u22D3",
  "&CupCap;": "\u224D",
  "&DD;": "\u2145",
  "&DDotrahd;": "\u2911",
  "&DJcy;": "\u0402",
  "&DScy;": "\u0405",
  "&DZcy;": "\u040F",
  "&Dagger;": "\u2021",
  "&Darr;": "\u21A1",
  "&Dashv;": "\u2AE4",
  "&Dcaron;": "\u010E",
  "&Dcy;": "\u0414",
  "&Del;": "\u2207",
  "&Delta;": "\u0394",
  "&Dfr;": "\u{1D507}",
  "&DiacriticalAcute;": "\xB4",
  "&DiacriticalDot;": "\u02D9",
  "&DiacriticalDoubleAcute;": "\u02DD",
  "&DiacriticalGrave;": "`",
  "&DiacriticalTilde;": "\u02DC",
  "&Diamond;": "\u22C4",
  "&DifferentialD;": "\u2146",
  "&Dopf;": "\u{1D53B}",
  "&Dot;": "\xA8",
  "&DotDot;": "\u20DC",
  "&DotEqual;": "\u2250",
  "&DoubleContourIntegral;": "\u222F",
  "&DoubleDot;": "\xA8",
  "&DoubleDownArrow;": "\u21D3",
  "&DoubleLeftArrow;": "\u21D0",
  "&DoubleLeftRightArrow;": "\u21D4",
  "&DoubleLeftTee;": "\u2AE4",
  "&DoubleLongLeftArrow;": "\u27F8",
  "&DoubleLongLeftRightArrow;": "\u27FA",
  "&DoubleLongRightArrow;": "\u27F9",
  "&DoubleRightArrow;": "\u21D2",
  "&DoubleRightTee;": "\u22A8",
  "&DoubleUpArrow;": "\u21D1",
  "&DoubleUpDownArrow;": "\u21D5",
  "&DoubleVerticalBar;": "\u2225",
  "&DownArrow;": "\u2193",
  "&DownArrowBar;": "\u2913",
  "&DownArrowUpArrow;": "\u21F5",
  "&DownBreve;": "\u0311",
  "&DownLeftRightVector;": "\u2950",
  "&DownLeftTeeVector;": "\u295E",
  "&DownLeftVector;": "\u21BD",
  "&DownLeftVectorBar;": "\u2956",
  "&DownRightTeeVector;": "\u295F",
  "&DownRightVector;": "\u21C1",
  "&DownRightVectorBar;": "\u2957",
  "&DownTee;": "\u22A4",
  "&DownTeeArrow;": "\u21A7",
  "&Downarrow;": "\u21D3",
  "&Dscr;": "\u{1D49F}",
  "&Dstrok;": "\u0110",
  "&ENG;": "\u014A",
  "&ETH": "\xD0",
  "&ETH;": "\xD0",
  "&Eacute": "\xC9",
  "&Eacute;": "\xC9",
  "&Ecaron;": "\u011A",
  "&Ecirc": "\xCA",
  "&Ecirc;": "\xCA",
  "&Ecy;": "\u042D",
  "&Edot;": "\u0116",
  "&Efr;": "\u{1D508}",
  "&Egrave": "\xC8",
  "&Egrave;": "\xC8",
  "&Element;": "\u2208",
  "&Emacr;": "\u0112",
  "&EmptySmallSquare;": "\u25FB",
  "&EmptyVerySmallSquare;": "\u25AB",
  "&Eogon;": "\u0118",
  "&Eopf;": "\u{1D53C}",
  "&Epsilon;": "\u0395",
  "&Equal;": "\u2A75",
  "&EqualTilde;": "\u2242",
  "&Equilibrium;": "\u21CC",
  "&Escr;": "\u2130",
  "&Esim;": "\u2A73",
  "&Eta;": "\u0397",
  "&Euml": "\xCB",
  "&Euml;": "\xCB",
  "&Exists;": "\u2203",
  "&ExponentialE;": "\u2147",
  "&Fcy;": "\u0424",
  "&Ffr;": "\u{1D509}",
  "&FilledSmallSquare;": "\u25FC",
  "&FilledVerySmallSquare;": "\u25AA",
  "&Fopf;": "\u{1D53D}",
  "&ForAll;": "\u2200",
  "&Fouriertrf;": "\u2131",
  "&Fscr;": "\u2131",
  "&GJcy;": "\u0403",
  "&GT": ">",
  "&GT;": ">",
  "&Gamma;": "\u0393",
  "&Gammad;": "\u03DC",
  "&Gbreve;": "\u011E",
  "&Gcedil;": "\u0122",
  "&Gcirc;": "\u011C",
  "&Gcy;": "\u0413",
  "&Gdot;": "\u0120",
  "&Gfr;": "\u{1D50A}",
  "&Gg;": "\u22D9",
  "&Gopf;": "\u{1D53E}",
  "&GreaterEqual;": "\u2265",
  "&GreaterEqualLess;": "\u22DB",
  "&GreaterFullEqual;": "\u2267",
  "&GreaterGreater;": "\u2AA2",
  "&GreaterLess;": "\u2277",
  "&GreaterSlantEqual;": "\u2A7E",
  "&GreaterTilde;": "\u2273",
  "&Gscr;": "\u{1D4A2}",
  "&Gt;": "\u226B",
  "&HARDcy;": "\u042A",
  "&Hacek;": "\u02C7",
  "&Hat;": "^",
  "&Hcirc;": "\u0124",
  "&Hfr;": "\u210C",
  "&HilbertSpace;": "\u210B",
  "&Hopf;": "\u210D",
  "&HorizontalLine;": "\u2500",
  "&Hscr;": "\u210B",
  "&Hstrok;": "\u0126",
  "&HumpDownHump;": "\u224E",
  "&HumpEqual;": "\u224F",
  "&IEcy;": "\u0415",
  "&IJlig;": "\u0132",
  "&IOcy;": "\u0401",
  "&Iacute": "\xCD",
  "&Iacute;": "\xCD",
  "&Icirc": "\xCE",
  "&Icirc;": "\xCE",
  "&Icy;": "\u0418",
  "&Idot;": "\u0130",
  "&Ifr;": "\u2111",
  "&Igrave": "\xCC",
  "&Igrave;": "\xCC",
  "&Im;": "\u2111",
  "&Imacr;": "\u012A",
  "&ImaginaryI;": "\u2148",
  "&Implies;": "\u21D2",
  "&Int;": "\u222C",
  "&Integral;": "\u222B",
  "&Intersection;": "\u22C2",
  "&InvisibleComma;": "\u2063",
  "&InvisibleTimes;": "\u2062",
  "&Iogon;": "\u012E",
  "&Iopf;": "\u{1D540}",
  "&Iota;": "\u0399",
  "&Iscr;": "\u2110",
  "&Itilde;": "\u0128",
  "&Iukcy;": "\u0406",
  "&Iuml": "\xCF",
  "&Iuml;": "\xCF",
  "&Jcirc;": "\u0134",
  "&Jcy;": "\u0419",
  "&Jfr;": "\u{1D50D}",
  "&Jopf;": "\u{1D541}",
  "&Jscr;": "\u{1D4A5}",
  "&Jsercy;": "\u0408",
  "&Jukcy;": "\u0404",
  "&KHcy;": "\u0425",
  "&KJcy;": "\u040C",
  "&Kappa;": "\u039A",
  "&Kcedil;": "\u0136",
  "&Kcy;": "\u041A",
  "&Kfr;": "\u{1D50E}",
  "&Kopf;": "\u{1D542}",
  "&Kscr;": "\u{1D4A6}",
  "&LJcy;": "\u0409",
  "&LT": "<",
  "&LT;": "<",
  "&Lacute;": "\u0139",
  "&Lambda;": "\u039B",
  "&Lang;": "\u27EA",
  "&Laplacetrf;": "\u2112",
  "&Larr;": "\u219E",
  "&Lcaron;": "\u013D",
  "&Lcedil;": "\u013B",
  "&Lcy;": "\u041B",
  "&LeftAngleBracket;": "\u27E8",
  "&LeftArrow;": "\u2190",
  "&LeftArrowBar;": "\u21E4",
  "&LeftArrowRightArrow;": "\u21C6",
  "&LeftCeiling;": "\u2308",
  "&LeftDoubleBracket;": "\u27E6",
  "&LeftDownTeeVector;": "\u2961",
  "&LeftDownVector;": "\u21C3",
  "&LeftDownVectorBar;": "\u2959",
  "&LeftFloor;": "\u230A",
  "&LeftRightArrow;": "\u2194",
  "&LeftRightVector;": "\u294E",
  "&LeftTee;": "\u22A3",
  "&LeftTeeArrow;": "\u21A4",
  "&LeftTeeVector;": "\u295A",
  "&LeftTriangle;": "\u22B2",
  "&LeftTriangleBar;": "\u29CF",
  "&LeftTriangleEqual;": "\u22B4",
  "&LeftUpDownVector;": "\u2951",
  "&LeftUpTeeVector;": "\u2960",
  "&LeftUpVector;": "\u21BF",
  "&LeftUpVectorBar;": "\u2958",
  "&LeftVector;": "\u21BC",
  "&LeftVectorBar;": "\u2952",
  "&Leftarrow;": "\u21D0",
  "&Leftrightarrow;": "\u21D4",
  "&LessEqualGreater;": "\u22DA",
  "&LessFullEqual;": "\u2266",
  "&LessGreater;": "\u2276",
  "&LessLess;": "\u2AA1",
  "&LessSlantEqual;": "\u2A7D",
  "&LessTilde;": "\u2272",
  "&Lfr;": "\u{1D50F}",
  "&Ll;": "\u22D8",
  "&Lleftarrow;": "\u21DA",
  "&Lmidot;": "\u013F",
  "&LongLeftArrow;": "\u27F5",
  "&LongLeftRightArrow;": "\u27F7",
  "&LongRightArrow;": "\u27F6",
  "&Longleftarrow;": "\u27F8",
  "&Longleftrightarrow;": "\u27FA",
  "&Longrightarrow;": "\u27F9",
  "&Lopf;": "\u{1D543}",
  "&LowerLeftArrow;": "\u2199",
  "&LowerRightArrow;": "\u2198",
  "&Lscr;": "\u2112",
  "&Lsh;": "\u21B0",
  "&Lstrok;": "\u0141",
  "&Lt;": "\u226A",
  "&Map;": "\u2905",
  "&Mcy;": "\u041C",
  "&MediumSpace;": "\u205F",
  "&Mellintrf;": "\u2133",
  "&Mfr;": "\u{1D510}",
  "&MinusPlus;": "\u2213",
  "&Mopf;": "\u{1D544}",
  "&Mscr;": "\u2133",
  "&Mu;": "\u039C",
  "&NJcy;": "\u040A",
  "&Nacute;": "\u0143",
  "&Ncaron;": "\u0147",
  "&Ncedil;": "\u0145",
  "&Ncy;": "\u041D",
  "&NegativeMediumSpace;": "\u200B",
  "&NegativeThickSpace;": "\u200B",
  "&NegativeThinSpace;": "\u200B",
  "&NegativeVeryThinSpace;": "\u200B",
  "&NestedGreaterGreater;": "\u226B",
  "&NestedLessLess;": "\u226A",
  "&NewLine;": "\n",
  "&Nfr;": "\u{1D511}",
  "&NoBreak;": "\u2060",
  "&NonBreakingSpace;": "\xA0",
  "&Nopf;": "\u2115",
  "&Not;": "\u2AEC",
  "&NotCongruent;": "\u2262",
  "&NotCupCap;": "\u226D",
  "&NotDoubleVerticalBar;": "\u2226",
  "&NotElement;": "\u2209",
  "&NotEqual;": "\u2260",
  "&NotEqualTilde;": "\u2242\u0338",
  "&NotExists;": "\u2204",
  "&NotGreater;": "\u226F",
  "&NotGreaterEqual;": "\u2271",
  "&NotGreaterFullEqual;": "\u2267\u0338",
  "&NotGreaterGreater;": "\u226B\u0338",
  "&NotGreaterLess;": "\u2279",
  "&NotGreaterSlantEqual;": "\u2A7E\u0338",
  "&NotGreaterTilde;": "\u2275",
  "&NotHumpDownHump;": "\u224E\u0338",
  "&NotHumpEqual;": "\u224F\u0338",
  "&NotLeftTriangle;": "\u22EA",
  "&NotLeftTriangleBar;": "\u29CF\u0338",
  "&NotLeftTriangleEqual;": "\u22EC",
  "&NotLess;": "\u226E",
  "&NotLessEqual;": "\u2270",
  "&NotLessGreater;": "\u2278",
  "&NotLessLess;": "\u226A\u0338",
  "&NotLessSlantEqual;": "\u2A7D\u0338",
  "&NotLessTilde;": "\u2274",
  "&NotNestedGreaterGreater;": "\u2AA2\u0338",
  "&NotNestedLessLess;": "\u2AA1\u0338",
  "&NotPrecedes;": "\u2280",
  "&NotPrecedesEqual;": "\u2AAF\u0338",
  "&NotPrecedesSlantEqual;": "\u22E0",
  "&NotReverseElement;": "\u220C",
  "&NotRightTriangle;": "\u22EB",
  "&NotRightTriangleBar;": "\u29D0\u0338",
  "&NotRightTriangleEqual;": "\u22ED",
  "&NotSquareSubset;": "\u228F\u0338",
  "&NotSquareSubsetEqual;": "\u22E2",
  "&NotSquareSuperset;": "\u2290\u0338",
  "&NotSquareSupersetEqual;": "\u22E3",
  "&NotSubset;": "\u2282\u20D2",
  "&NotSubsetEqual;": "\u2288",
  "&NotSucceeds;": "\u2281",
  "&NotSucceedsEqual;": "\u2AB0\u0338",
  "&NotSucceedsSlantEqual;": "\u22E1",
  "&NotSucceedsTilde;": "\u227F\u0338",
  "&NotSuperset;": "\u2283\u20D2",
  "&NotSupersetEqual;": "\u2289",
  "&NotTilde;": "\u2241",
  "&NotTildeEqual;": "\u2244",
  "&NotTildeFullEqual;": "\u2247",
  "&NotTildeTilde;": "\u2249",
  "&NotVerticalBar;": "\u2224",
  "&Nscr;": "\u{1D4A9}",
  "&Ntilde": "\xD1",
  "&Ntilde;": "\xD1",
  "&Nu;": "\u039D",
  "&OElig;": "\u0152",
  "&Oacute": "\xD3",
  "&Oacute;": "\xD3",
  "&Ocirc": "\xD4",
  "&Ocirc;": "\xD4",
  "&Ocy;": "\u041E",
  "&Odblac;": "\u0150",
  "&Ofr;": "\u{1D512}",
  "&Ograve": "\xD2",
  "&Ograve;": "\xD2",
  "&Omacr;": "\u014C",
  "&Omega;": "\u03A9",
  "&Omicron;": "\u039F",
  "&Oopf;": "\u{1D546}",
  "&OpenCurlyDoubleQuote;": "\u201C",
  "&OpenCurlyQuote;": "\u2018",
  "&Or;": "\u2A54",
  "&Oscr;": "\u{1D4AA}",
  "&Oslash": "\xD8",
  "&Oslash;": "\xD8",
  "&Otilde": "\xD5",
  "&Otilde;": "\xD5",
  "&Otimes;": "\u2A37",
  "&Ouml": "\xD6",
  "&Ouml;": "\xD6",
  "&OverBar;": "\u203E",
  "&OverBrace;": "\u23DE",
  "&OverBracket;": "\u23B4",
  "&OverParenthesis;": "\u23DC",
  "&PartialD;": "\u2202",
  "&Pcy;": "\u041F",
  "&Pfr;": "\u{1D513}",
  "&Phi;": "\u03A6",
  "&Pi;": "\u03A0",
  "&PlusMinus;": "\xB1",
  "&Poincareplane;": "\u210C",
  "&Popf;": "\u2119",
  "&Pr;": "\u2ABB",
  "&Precedes;": "\u227A",
  "&PrecedesEqual;": "\u2AAF",
  "&PrecedesSlantEqual;": "\u227C",
  "&PrecedesTilde;": "\u227E",
  "&Prime;": "\u2033",
  "&Product;": "\u220F",
  "&Proportion;": "\u2237",
  "&Proportional;": "\u221D",
  "&Pscr;": "\u{1D4AB}",
  "&Psi;": "\u03A8",
  "&QUOT": '"',
  "&QUOT;": '"',
  "&Qfr;": "\u{1D514}",
  "&Qopf;": "\u211A",
  "&Qscr;": "\u{1D4AC}",
  "&RBarr;": "\u2910",
  "&REG": "\xAE",
  "&REG;": "\xAE",
  "&Racute;": "\u0154",
  "&Rang;": "\u27EB",
  "&Rarr;": "\u21A0",
  "&Rarrtl;": "\u2916",
  "&Rcaron;": "\u0158",
  "&Rcedil;": "\u0156",
  "&Rcy;": "\u0420",
  "&Re;": "\u211C",
  "&ReverseElement;": "\u220B",
  "&ReverseEquilibrium;": "\u21CB",
  "&ReverseUpEquilibrium;": "\u296F",
  "&Rfr;": "\u211C",
  "&Rho;": "\u03A1",
  "&RightAngleBracket;": "\u27E9",
  "&RightArrow;": "\u2192",
  "&RightArrowBar;": "\u21E5",
  "&RightArrowLeftArrow;": "\u21C4",
  "&RightCeiling;": "\u2309",
  "&RightDoubleBracket;": "\u27E7",
  "&RightDownTeeVector;": "\u295D",
  "&RightDownVector;": "\u21C2",
  "&RightDownVectorBar;": "\u2955",
  "&RightFloor;": "\u230B",
  "&RightTee;": "\u22A2",
  "&RightTeeArrow;": "\u21A6",
  "&RightTeeVector;": "\u295B",
  "&RightTriangle;": "\u22B3",
  "&RightTriangleBar;": "\u29D0",
  "&RightTriangleEqual;": "\u22B5",
  "&RightUpDownVector;": "\u294F",
  "&RightUpTeeVector;": "\u295C",
  "&RightUpVector;": "\u21BE",
  "&RightUpVectorBar;": "\u2954",
  "&RightVector;": "\u21C0",
  "&RightVectorBar;": "\u2953",
  "&Rightarrow;": "\u21D2",
  "&Ropf;": "\u211D",
  "&RoundImplies;": "\u2970",
  "&Rrightarrow;": "\u21DB",
  "&Rscr;": "\u211B",
  "&Rsh;": "\u21B1",
  "&RuleDelayed;": "\u29F4",
  "&SHCHcy;": "\u0429",
  "&SHcy;": "\u0428",
  "&SOFTcy;": "\u042C",
  "&Sacute;": "\u015A",
  "&Sc;": "\u2ABC",
  "&Scaron;": "\u0160",
  "&Scedil;": "\u015E",
  "&Scirc;": "\u015C",
  "&Scy;": "\u0421",
  "&Sfr;": "\u{1D516}",
  "&ShortDownArrow;": "\u2193",
  "&ShortLeftArrow;": "\u2190",
  "&ShortRightArrow;": "\u2192",
  "&ShortUpArrow;": "\u2191",
  "&Sigma;": "\u03A3",
  "&SmallCircle;": "\u2218",
  "&Sopf;": "\u{1D54A}",
  "&Sqrt;": "\u221A",
  "&Square;": "\u25A1",
  "&SquareIntersection;": "\u2293",
  "&SquareSubset;": "\u228F",
  "&SquareSubsetEqual;": "\u2291",
  "&SquareSuperset;": "\u2290",
  "&SquareSupersetEqual;": "\u2292",
  "&SquareUnion;": "\u2294",
  "&Sscr;": "\u{1D4AE}",
  "&Star;": "\u22C6",
  "&Sub;": "\u22D0",
  "&Subset;": "\u22D0",
  "&SubsetEqual;": "\u2286",
  "&Succeeds;": "\u227B",
  "&SucceedsEqual;": "\u2AB0",
  "&SucceedsSlantEqual;": "\u227D",
  "&SucceedsTilde;": "\u227F",
  "&SuchThat;": "\u220B",
  "&Sum;": "\u2211",
  "&Sup;": "\u22D1",
  "&Superset;": "\u2283",
  "&SupersetEqual;": "\u2287",
  "&Supset;": "\u22D1",
  "&THORN": "\xDE",
  "&THORN;": "\xDE",
  "&TRADE;": "\u2122",
  "&TSHcy;": "\u040B",
  "&TScy;": "\u0426",
  "&Tab;": "	",
  "&Tau;": "\u03A4",
  "&Tcaron;": "\u0164",
  "&Tcedil;": "\u0162",
  "&Tcy;": "\u0422",
  "&Tfr;": "\u{1D517}",
  "&Therefore;": "\u2234",
  "&Theta;": "\u0398",
  "&ThickSpace;": "\u205F\u200A",
  "&ThinSpace;": "\u2009",
  "&Tilde;": "\u223C",
  "&TildeEqual;": "\u2243",
  "&TildeFullEqual;": "\u2245",
  "&TildeTilde;": "\u2248",
  "&Topf;": "\u{1D54B}",
  "&TripleDot;": "\u20DB",
  "&Tscr;": "\u{1D4AF}",
  "&Tstrok;": "\u0166",
  "&Uacute": "\xDA",
  "&Uacute;": "\xDA",
  "&Uarr;": "\u219F",
  "&Uarrocir;": "\u2949",
  "&Ubrcy;": "\u040E",
  "&Ubreve;": "\u016C",
  "&Ucirc": "\xDB",
  "&Ucirc;": "\xDB",
  "&Ucy;": "\u0423",
  "&Udblac;": "\u0170",
  "&Ufr;": "\u{1D518}",
  "&Ugrave": "\xD9",
  "&Ugrave;": "\xD9",
  "&Umacr;": "\u016A",
  "&UnderBar;": "_",
  "&UnderBrace;": "\u23DF",
  "&UnderBracket;": "\u23B5",
  "&UnderParenthesis;": "\u23DD",
  "&Union;": "\u22C3",
  "&UnionPlus;": "\u228E",
  "&Uogon;": "\u0172",
  "&Uopf;": "\u{1D54C}",
  "&UpArrow;": "\u2191",
  "&UpArrowBar;": "\u2912",
  "&UpArrowDownArrow;": "\u21C5",
  "&UpDownArrow;": "\u2195",
  "&UpEquilibrium;": "\u296E",
  "&UpTee;": "\u22A5",
  "&UpTeeArrow;": "\u21A5",
  "&Uparrow;": "\u21D1",
  "&Updownarrow;": "\u21D5",
  "&UpperLeftArrow;": "\u2196",
  "&UpperRightArrow;": "\u2197",
  "&Upsi;": "\u03D2",
  "&Upsilon;": "\u03A5",
  "&Uring;": "\u016E",
  "&Uscr;": "\u{1D4B0}",
  "&Utilde;": "\u0168",
  "&Uuml": "\xDC",
  "&Uuml;": "\xDC",
  "&VDash;": "\u22AB",
  "&Vbar;": "\u2AEB",
  "&Vcy;": "\u0412",
  "&Vdash;": "\u22A9",
  "&Vdashl;": "\u2AE6",
  "&Vee;": "\u22C1",
  "&Verbar;": "\u2016",
  "&Vert;": "\u2016",
  "&VerticalBar;": "\u2223",
  "&VerticalLine;": "|",
  "&VerticalSeparator;": "\u2758",
  "&VerticalTilde;": "\u2240",
  "&VeryThinSpace;": "\u200A",
  "&Vfr;": "\u{1D519}",
  "&Vopf;": "\u{1D54D}",
  "&Vscr;": "\u{1D4B1}",
  "&Vvdash;": "\u22AA",
  "&Wcirc;": "\u0174",
  "&Wedge;": "\u22C0",
  "&Wfr;": "\u{1D51A}",
  "&Wopf;": "\u{1D54E}",
  "&Wscr;": "\u{1D4B2}",
  "&Xfr;": "\u{1D51B}",
  "&Xi;": "\u039E",
  "&Xopf;": "\u{1D54F}",
  "&Xscr;": "\u{1D4B3}",
  "&YAcy;": "\u042F",
  "&YIcy;": "\u0407",
  "&YUcy;": "\u042E",
  "&Yacute": "\xDD",
  "&Yacute;": "\xDD",
  "&Ycirc;": "\u0176",
  "&Ycy;": "\u042B",
  "&Yfr;": "\u{1D51C}",
  "&Yopf;": "\u{1D550}",
  "&Yscr;": "\u{1D4B4}",
  "&Yuml;": "\u0178",
  "&ZHcy;": "\u0416",
  "&Zacute;": "\u0179",
  "&Zcaron;": "\u017D",
  "&Zcy;": "\u0417",
  "&Zdot;": "\u017B",
  "&ZeroWidthSpace;": "\u200B",
  "&Zeta;": "\u0396",
  "&Zfr;": "\u2128",
  "&Zopf;": "\u2124",
  "&Zscr;": "\u{1D4B5}",
  "&aacute": "\xE1",
  "&aacute;": "\xE1",
  "&abreve;": "\u0103",
  "&ac;": "\u223E",
  "&acE;": "\u223E\u0333",
  "&acd;": "\u223F",
  "&acirc": "\xE2",
  "&acirc;": "\xE2",
  "&acute": "\xB4",
  "&acute;": "\xB4",
  "&acy;": "\u0430",
  "&aelig": "\xE6",
  "&aelig;": "\xE6",
  "&af;": "\u2061",
  "&afr;": "\u{1D51E}",
  "&agrave": "\xE0",
  "&agrave;": "\xE0",
  "&alefsym;": "\u2135",
  "&aleph;": "\u2135",
  "&alpha;": "\u03B1",
  "&amacr;": "\u0101",
  "&amalg;": "\u2A3F",
  "&amp": "&",
  "&amp;": "&",
  "&and;": "\u2227",
  "&andand;": "\u2A55",
  "&andd;": "\u2A5C",
  "&andslope;": "\u2A58",
  "&andv;": "\u2A5A",
  "&ang;": "\u2220",
  "&ange;": "\u29A4",
  "&angle;": "\u2220",
  "&angmsd;": "\u2221",
  "&angmsdaa;": "\u29A8",
  "&angmsdab;": "\u29A9",
  "&angmsdac;": "\u29AA",
  "&angmsdad;": "\u29AB",
  "&angmsdae;": "\u29AC",
  "&angmsdaf;": "\u29AD",
  "&angmsdag;": "\u29AE",
  "&angmsdah;": "\u29AF",
  "&angrt;": "\u221F",
  "&angrtvb;": "\u22BE",
  "&angrtvbd;": "\u299D",
  "&angsph;": "\u2222",
  "&angst;": "\xC5",
  "&angzarr;": "\u237C",
  "&aogon;": "\u0105",
  "&aopf;": "\u{1D552}",
  "&ap;": "\u2248",
  "&apE;": "\u2A70",
  "&apacir;": "\u2A6F",
  "&ape;": "\u224A",
  "&apid;": "\u224B",
  "&apos;": "'",
  "&approx;": "\u2248",
  "&approxeq;": "\u224A",
  "&aring": "\xE5",
  "&aring;": "\xE5",
  "&ascr;": "\u{1D4B6}",
  "&ast;": "*",
  "&asymp;": "\u2248",
  "&asympeq;": "\u224D",
  "&atilde": "\xE3",
  "&atilde;": "\xE3",
  "&auml": "\xE4",
  "&auml;": "\xE4",
  "&awconint;": "\u2233",
  "&awint;": "\u2A11",
  "&bNot;": "\u2AED",
  "&backcong;": "\u224C",
  "&backepsilon;": "\u03F6",
  "&backprime;": "\u2035",
  "&backsim;": "\u223D",
  "&backsimeq;": "\u22CD",
  "&barvee;": "\u22BD",
  "&barwed;": "\u2305",
  "&barwedge;": "\u2305",
  "&bbrk;": "\u23B5",
  "&bbrktbrk;": "\u23B6",
  "&bcong;": "\u224C",
  "&bcy;": "\u0431",
  "&bdquo;": "\u201E",
  "&becaus;": "\u2235",
  "&because;": "\u2235",
  "&bemptyv;": "\u29B0",
  "&bepsi;": "\u03F6",
  "&bernou;": "\u212C",
  "&beta;": "\u03B2",
  "&beth;": "\u2136",
  "&between;": "\u226C",
  "&bfr;": "\u{1D51F}",
  "&bigcap;": "\u22C2",
  "&bigcirc;": "\u25EF",
  "&bigcup;": "\u22C3",
  "&bigodot;": "\u2A00",
  "&bigoplus;": "\u2A01",
  "&bigotimes;": "\u2A02",
  "&bigsqcup;": "\u2A06",
  "&bigstar;": "\u2605",
  "&bigtriangledown;": "\u25BD",
  "&bigtriangleup;": "\u25B3",
  "&biguplus;": "\u2A04",
  "&bigvee;": "\u22C1",
  "&bigwedge;": "\u22C0",
  "&bkarow;": "\u290D",
  "&blacklozenge;": "\u29EB",
  "&blacksquare;": "\u25AA",
  "&blacktriangle;": "\u25B4",
  "&blacktriangledown;": "\u25BE",
  "&blacktriangleleft;": "\u25C2",
  "&blacktriangleright;": "\u25B8",
  "&blank;": "\u2423",
  "&blk12;": "\u2592",
  "&blk14;": "\u2591",
  "&blk34;": "\u2593",
  "&block;": "\u2588",
  "&bne;": "=\u20E5",
  "&bnequiv;": "\u2261\u20E5",
  "&bnot;": "\u2310",
  "&bopf;": "\u{1D553}",
  "&bot;": "\u22A5",
  "&bottom;": "\u22A5",
  "&bowtie;": "\u22C8",
  "&boxDL;": "\u2557",
  "&boxDR;": "\u2554",
  "&boxDl;": "\u2556",
  "&boxDr;": "\u2553",
  "&boxH;": "\u2550",
  "&boxHD;": "\u2566",
  "&boxHU;": "\u2569",
  "&boxHd;": "\u2564",
  "&boxHu;": "\u2567",
  "&boxUL;": "\u255D",
  "&boxUR;": "\u255A",
  "&boxUl;": "\u255C",
  "&boxUr;": "\u2559",
  "&boxV;": "\u2551",
  "&boxVH;": "\u256C",
  "&boxVL;": "\u2563",
  "&boxVR;": "\u2560",
  "&boxVh;": "\u256B",
  "&boxVl;": "\u2562",
  "&boxVr;": "\u255F",
  "&boxbox;": "\u29C9",
  "&boxdL;": "\u2555",
  "&boxdR;": "\u2552",
  "&boxdl;": "\u2510",
  "&boxdr;": "\u250C",
  "&boxh;": "\u2500",
  "&boxhD;": "\u2565",
  "&boxhU;": "\u2568",
  "&boxhd;": "\u252C",
  "&boxhu;": "\u2534",
  "&boxminus;": "\u229F",
  "&boxplus;": "\u229E",
  "&boxtimes;": "\u22A0",
  "&boxuL;": "\u255B",
  "&boxuR;": "\u2558",
  "&boxul;": "\u2518",
  "&boxur;": "\u2514",
  "&boxv;": "\u2502",
  "&boxvH;": "\u256A",
  "&boxvL;": "\u2561",
  "&boxvR;": "\u255E",
  "&boxvh;": "\u253C",
  "&boxvl;": "\u2524",
  "&boxvr;": "\u251C",
  "&bprime;": "\u2035",
  "&breve;": "\u02D8",
  "&brvbar": "\xA6",
  "&brvbar;": "\xA6",
  "&bscr;": "\u{1D4B7}",
  "&bsemi;": "\u204F",
  "&bsim;": "\u223D",
  "&bsime;": "\u22CD",
  "&bsol;": "\\",
  "&bsolb;": "\u29C5",
  "&bsolhsub;": "\u27C8",
  "&bull;": "\u2022",
  "&bullet;": "\u2022",
  "&bump;": "\u224E",
  "&bumpE;": "\u2AAE",
  "&bumpe;": "\u224F",
  "&bumpeq;": "\u224F",
  "&cacute;": "\u0107",
  "&cap;": "\u2229",
  "&capand;": "\u2A44",
  "&capbrcup;": "\u2A49",
  "&capcap;": "\u2A4B",
  "&capcup;": "\u2A47",
  "&capdot;": "\u2A40",
  "&caps;": "\u2229\uFE00",
  "&caret;": "\u2041",
  "&caron;": "\u02C7",
  "&ccaps;": "\u2A4D",
  "&ccaron;": "\u010D",
  "&ccedil": "\xE7",
  "&ccedil;": "\xE7",
  "&ccirc;": "\u0109",
  "&ccups;": "\u2A4C",
  "&ccupssm;": "\u2A50",
  "&cdot;": "\u010B",
  "&cedil": "\xB8",
  "&cedil;": "\xB8",
  "&cemptyv;": "\u29B2",
  "&cent": "\xA2",
  "&cent;": "\xA2",
  "&centerdot;": "\xB7",
  "&cfr;": "\u{1D520}",
  "&chcy;": "\u0447",
  "&check;": "\u2713",
  "&checkmark;": "\u2713",
  "&chi;": "\u03C7",
  "&cir;": "\u25CB",
  "&cirE;": "\u29C3",
  "&circ;": "\u02C6",
  "&circeq;": "\u2257",
  "&circlearrowleft;": "\u21BA",
  "&circlearrowright;": "\u21BB",
  "&circledR;": "\xAE",
  "&circledS;": "\u24C8",
  "&circledast;": "\u229B",
  "&circledcirc;": "\u229A",
  "&circleddash;": "\u229D",
  "&cire;": "\u2257",
  "&cirfnint;": "\u2A10",
  "&cirmid;": "\u2AEF",
  "&cirscir;": "\u29C2",
  "&clubs;": "\u2663",
  "&clubsuit;": "\u2663",
  "&colon;": ":",
  "&colone;": "\u2254",
  "&coloneq;": "\u2254",
  "&comma;": ",",
  "&commat;": "@",
  "&comp;": "\u2201",
  "&compfn;": "\u2218",
  "&complement;": "\u2201",
  "&complexes;": "\u2102",
  "&cong;": "\u2245",
  "&congdot;": "\u2A6D",
  "&conint;": "\u222E",
  "&copf;": "\u{1D554}",
  "&coprod;": "\u2210",
  "&copy": "\xA9",
  "&copy;": "\xA9",
  "&copysr;": "\u2117",
  "&crarr;": "\u21B5",
  "&cross;": "\u2717",
  "&cscr;": "\u{1D4B8}",
  "&csub;": "\u2ACF",
  "&csube;": "\u2AD1",
  "&csup;": "\u2AD0",
  "&csupe;": "\u2AD2",
  "&ctdot;": "\u22EF",
  "&cudarrl;": "\u2938",
  "&cudarrr;": "\u2935",
  "&cuepr;": "\u22DE",
  "&cuesc;": "\u22DF",
  "&cularr;": "\u21B6",
  "&cularrp;": "\u293D",
  "&cup;": "\u222A",
  "&cupbrcap;": "\u2A48",
  "&cupcap;": "\u2A46",
  "&cupcup;": "\u2A4A",
  "&cupdot;": "\u228D",
  "&cupor;": "\u2A45",
  "&cups;": "\u222A\uFE00",
  "&curarr;": "\u21B7",
  "&curarrm;": "\u293C",
  "&curlyeqprec;": "\u22DE",
  "&curlyeqsucc;": "\u22DF",
  "&curlyvee;": "\u22CE",
  "&curlywedge;": "\u22CF",
  "&curren": "\xA4",
  "&curren;": "\xA4",
  "&curvearrowleft;": "\u21B6",
  "&curvearrowright;": "\u21B7",
  "&cuvee;": "\u22CE",
  "&cuwed;": "\u22CF",
  "&cwconint;": "\u2232",
  "&cwint;": "\u2231",
  "&cylcty;": "\u232D",
  "&dArr;": "\u21D3",
  "&dHar;": "\u2965",
  "&dagger;": "\u2020",
  "&daleth;": "\u2138",
  "&darr;": "\u2193",
  "&dash;": "\u2010",
  "&dashv;": "\u22A3",
  "&dbkarow;": "\u290F",
  "&dblac;": "\u02DD",
  "&dcaron;": "\u010F",
  "&dcy;": "\u0434",
  "&dd;": "\u2146",
  "&ddagger;": "\u2021",
  "&ddarr;": "\u21CA",
  "&ddotseq;": "\u2A77",
  "&deg": "\xB0",
  "&deg;": "\xB0",
  "&delta;": "\u03B4",
  "&demptyv;": "\u29B1",
  "&dfisht;": "\u297F",
  "&dfr;": "\u{1D521}",
  "&dharl;": "\u21C3",
  "&dharr;": "\u21C2",
  "&diam;": "\u22C4",
  "&diamond;": "\u22C4",
  "&diamondsuit;": "\u2666",
  "&diams;": "\u2666",
  "&die;": "\xA8",
  "&digamma;": "\u03DD",
  "&disin;": "\u22F2",
  "&div;": "\xF7",
  "&divide": "\xF7",
  "&divide;": "\xF7",
  "&divideontimes;": "\u22C7",
  "&divonx;": "\u22C7",
  "&djcy;": "\u0452",
  "&dlcorn;": "\u231E",
  "&dlcrop;": "\u230D",
  "&dollar;": "$",
  "&dopf;": "\u{1D555}",
  "&dot;": "\u02D9",
  "&doteq;": "\u2250",
  "&doteqdot;": "\u2251",
  "&dotminus;": "\u2238",
  "&dotplus;": "\u2214",
  "&dotsquare;": "\u22A1",
  "&doublebarwedge;": "\u2306",
  "&downarrow;": "\u2193",
  "&downdownarrows;": "\u21CA",
  "&downharpoonleft;": "\u21C3",
  "&downharpoonright;": "\u21C2",
  "&drbkarow;": "\u2910",
  "&drcorn;": "\u231F",
  "&drcrop;": "\u230C",
  "&dscr;": "\u{1D4B9}",
  "&dscy;": "\u0455",
  "&dsol;": "\u29F6",
  "&dstrok;": "\u0111",
  "&dtdot;": "\u22F1",
  "&dtri;": "\u25BF",
  "&dtrif;": "\u25BE",
  "&duarr;": "\u21F5",
  "&duhar;": "\u296F",
  "&dwangle;": "\u29A6",
  "&dzcy;": "\u045F",
  "&dzigrarr;": "\u27FF",
  "&eDDot;": "\u2A77",
  "&eDot;": "\u2251",
  "&eacute": "\xE9",
  "&eacute;": "\xE9",
  "&easter;": "\u2A6E",
  "&ecaron;": "\u011B",
  "&ecir;": "\u2256",
  "&ecirc": "\xEA",
  "&ecirc;": "\xEA",
  "&ecolon;": "\u2255",
  "&ecy;": "\u044D",
  "&edot;": "\u0117",
  "&ee;": "\u2147",
  "&efDot;": "\u2252",
  "&efr;": "\u{1D522}",
  "&eg;": "\u2A9A",
  "&egrave": "\xE8",
  "&egrave;": "\xE8",
  "&egs;": "\u2A96",
  "&egsdot;": "\u2A98",
  "&el;": "\u2A99",
  "&elinters;": "\u23E7",
  "&ell;": "\u2113",
  "&els;": "\u2A95",
  "&elsdot;": "\u2A97",
  "&emacr;": "\u0113",
  "&empty;": "\u2205",
  "&emptyset;": "\u2205",
  "&emptyv;": "\u2205",
  "&emsp13;": "\u2004",
  "&emsp14;": "\u2005",
  "&emsp;": "\u2003",
  "&eng;": "\u014B",
  "&ensp;": "\u2002",
  "&eogon;": "\u0119",
  "&eopf;": "\u{1D556}",
  "&epar;": "\u22D5",
  "&eparsl;": "\u29E3",
  "&eplus;": "\u2A71",
  "&epsi;": "\u03B5",
  "&epsilon;": "\u03B5",
  "&epsiv;": "\u03F5",
  "&eqcirc;": "\u2256",
  "&eqcolon;": "\u2255",
  "&eqsim;": "\u2242",
  "&eqslantgtr;": "\u2A96",
  "&eqslantless;": "\u2A95",
  "&equals;": "=",
  "&equest;": "\u225F",
  "&equiv;": "\u2261",
  "&equivDD;": "\u2A78",
  "&eqvparsl;": "\u29E5",
  "&erDot;": "\u2253",
  "&erarr;": "\u2971",
  "&escr;": "\u212F",
  "&esdot;": "\u2250",
  "&esim;": "\u2242",
  "&eta;": "\u03B7",
  "&eth": "\xF0",
  "&eth;": "\xF0",
  "&euml": "\xEB",
  "&euml;": "\xEB",
  "&euro;": "\u20AC",
  "&excl;": "!",
  "&exist;": "\u2203",
  "&expectation;": "\u2130",
  "&exponentiale;": "\u2147",
  "&fallingdotseq;": "\u2252",
  "&fcy;": "\u0444",
  "&female;": "\u2640",
  "&ffilig;": "\uFB03",
  "&fflig;": "\uFB00",
  "&ffllig;": "\uFB04",
  "&ffr;": "\u{1D523}",
  "&filig;": "\uFB01",
  "&fjlig;": "fj",
  "&flat;": "\u266D",
  "&fllig;": "\uFB02",
  "&fltns;": "\u25B1",
  "&fnof;": "\u0192",
  "&fopf;": "\u{1D557}",
  "&forall;": "\u2200",
  "&fork;": "\u22D4",
  "&forkv;": "\u2AD9",
  "&fpartint;": "\u2A0D",
  "&frac12": "\xBD",
  "&frac12;": "\xBD",
  "&frac13;": "\u2153",
  "&frac14": "\xBC",
  "&frac14;": "\xBC",
  "&frac15;": "\u2155",
  "&frac16;": "\u2159",
  "&frac18;": "\u215B",
  "&frac23;": "\u2154",
  "&frac25;": "\u2156",
  "&frac34": "\xBE",
  "&frac34;": "\xBE",
  "&frac35;": "\u2157",
  "&frac38;": "\u215C",
  "&frac45;": "\u2158",
  "&frac56;": "\u215A",
  "&frac58;": "\u215D",
  "&frac78;": "\u215E",
  "&frasl;": "\u2044",
  "&frown;": "\u2322",
  "&fscr;": "\u{1D4BB}",
  "&gE;": "\u2267",
  "&gEl;": "\u2A8C",
  "&gacute;": "\u01F5",
  "&gamma;": "\u03B3",
  "&gammad;": "\u03DD",
  "&gap;": "\u2A86",
  "&gbreve;": "\u011F",
  "&gcirc;": "\u011D",
  "&gcy;": "\u0433",
  "&gdot;": "\u0121",
  "&ge;": "\u2265",
  "&gel;": "\u22DB",
  "&geq;": "\u2265",
  "&geqq;": "\u2267",
  "&geqslant;": "\u2A7E",
  "&ges;": "\u2A7E",
  "&gescc;": "\u2AA9",
  "&gesdot;": "\u2A80",
  "&gesdoto;": "\u2A82",
  "&gesdotol;": "\u2A84",
  "&gesl;": "\u22DB\uFE00",
  "&gesles;": "\u2A94",
  "&gfr;": "\u{1D524}",
  "&gg;": "\u226B",
  "&ggg;": "\u22D9",
  "&gimel;": "\u2137",
  "&gjcy;": "\u0453",
  "&gl;": "\u2277",
  "&glE;": "\u2A92",
  "&gla;": "\u2AA5",
  "&glj;": "\u2AA4",
  "&gnE;": "\u2269",
  "&gnap;": "\u2A8A",
  "&gnapprox;": "\u2A8A",
  "&gne;": "\u2A88",
  "&gneq;": "\u2A88",
  "&gneqq;": "\u2269",
  "&gnsim;": "\u22E7",
  "&gopf;": "\u{1D558}",
  "&grave;": "`",
  "&gscr;": "\u210A",
  "&gsim;": "\u2273",
  "&gsime;": "\u2A8E",
  "&gsiml;": "\u2A90",
  "&gt": ">",
  "&gt;": ">",
  "&gtcc;": "\u2AA7",
  "&gtcir;": "\u2A7A",
  "&gtdot;": "\u22D7",
  "&gtlPar;": "\u2995",
  "&gtquest;": "\u2A7C",
  "&gtrapprox;": "\u2A86",
  "&gtrarr;": "\u2978",
  "&gtrdot;": "\u22D7",
  "&gtreqless;": "\u22DB",
  "&gtreqqless;": "\u2A8C",
  "&gtrless;": "\u2277",
  "&gtrsim;": "\u2273",
  "&gvertneqq;": "\u2269\uFE00",
  "&gvnE;": "\u2269\uFE00",
  "&hArr;": "\u21D4",
  "&hairsp;": "\u200A",
  "&half;": "\xBD",
  "&hamilt;": "\u210B",
  "&hardcy;": "\u044A",
  "&harr;": "\u2194",
  "&harrcir;": "\u2948",
  "&harrw;": "\u21AD",
  "&hbar;": "\u210F",
  "&hcirc;": "\u0125",
  "&hearts;": "\u2665",
  "&heartsuit;": "\u2665",
  "&hellip;": "\u2026",
  "&hercon;": "\u22B9",
  "&hfr;": "\u{1D525}",
  "&hksearow;": "\u2925",
  "&hkswarow;": "\u2926",
  "&hoarr;": "\u21FF",
  "&homtht;": "\u223B",
  "&hookleftarrow;": "\u21A9",
  "&hookrightarrow;": "\u21AA",
  "&hopf;": "\u{1D559}",
  "&horbar;": "\u2015",
  "&hscr;": "\u{1D4BD}",
  "&hslash;": "\u210F",
  "&hstrok;": "\u0127",
  "&hybull;": "\u2043",
  "&hyphen;": "\u2010",
  "&iacute": "\xED",
  "&iacute;": "\xED",
  "&ic;": "\u2063",
  "&icirc": "\xEE",
  "&icirc;": "\xEE",
  "&icy;": "\u0438",
  "&iecy;": "\u0435",
  "&iexcl": "\xA1",
  "&iexcl;": "\xA1",
  "&iff;": "\u21D4",
  "&ifr;": "\u{1D526}",
  "&igrave": "\xEC",
  "&igrave;": "\xEC",
  "&ii;": "\u2148",
  "&iiiint;": "\u2A0C",
  "&iiint;": "\u222D",
  "&iinfin;": "\u29DC",
  "&iiota;": "\u2129",
  "&ijlig;": "\u0133",
  "&imacr;": "\u012B",
  "&image;": "\u2111",
  "&imagline;": "\u2110",
  "&imagpart;": "\u2111",
  "&imath;": "\u0131",
  "&imof;": "\u22B7",
  "&imped;": "\u01B5",
  "&in;": "\u2208",
  "&incare;": "\u2105",
  "&infin;": "\u221E",
  "&infintie;": "\u29DD",
  "&inodot;": "\u0131",
  "&int;": "\u222B",
  "&intcal;": "\u22BA",
  "&integers;": "\u2124",
  "&intercal;": "\u22BA",
  "&intlarhk;": "\u2A17",
  "&intprod;": "\u2A3C",
  "&iocy;": "\u0451",
  "&iogon;": "\u012F",
  "&iopf;": "\u{1D55A}",
  "&iota;": "\u03B9",
  "&iprod;": "\u2A3C",
  "&iquest": "\xBF",
  "&iquest;": "\xBF",
  "&iscr;": "\u{1D4BE}",
  "&isin;": "\u2208",
  "&isinE;": "\u22F9",
  "&isindot;": "\u22F5",
  "&isins;": "\u22F4",
  "&isinsv;": "\u22F3",
  "&isinv;": "\u2208",
  "&it;": "\u2062",
  "&itilde;": "\u0129",
  "&iukcy;": "\u0456",
  "&iuml": "\xEF",
  "&iuml;": "\xEF",
  "&jcirc;": "\u0135",
  "&jcy;": "\u0439",
  "&jfr;": "\u{1D527}",
  "&jmath;": "\u0237",
  "&jopf;": "\u{1D55B}",
  "&jscr;": "\u{1D4BF}",
  "&jsercy;": "\u0458",
  "&jukcy;": "\u0454",
  "&kappa;": "\u03BA",
  "&kappav;": "\u03F0",
  "&kcedil;": "\u0137",
  "&kcy;": "\u043A",
  "&kfr;": "\u{1D528}",
  "&kgreen;": "\u0138",
  "&khcy;": "\u0445",
  "&kjcy;": "\u045C",
  "&kopf;": "\u{1D55C}",
  "&kscr;": "\u{1D4C0}",
  "&lAarr;": "\u21DA",
  "&lArr;": "\u21D0",
  "&lAtail;": "\u291B",
  "&lBarr;": "\u290E",
  "&lE;": "\u2266",
  "&lEg;": "\u2A8B",
  "&lHar;": "\u2962",
  "&lacute;": "\u013A",
  "&laemptyv;": "\u29B4",
  "&lagran;": "\u2112",
  "&lambda;": "\u03BB",
  "&lang;": "\u27E8",
  "&langd;": "\u2991",
  "&langle;": "\u27E8",
  "&lap;": "\u2A85",
  "&laquo": "\xAB",
  "&laquo;": "\xAB",
  "&larr;": "\u2190",
  "&larrb;": "\u21E4",
  "&larrbfs;": "\u291F",
  "&larrfs;": "\u291D",
  "&larrhk;": "\u21A9",
  "&larrlp;": "\u21AB",
  "&larrpl;": "\u2939",
  "&larrsim;": "\u2973",
  "&larrtl;": "\u21A2",
  "&lat;": "\u2AAB",
  "&latail;": "\u2919",
  "&late;": "\u2AAD",
  "&lates;": "\u2AAD\uFE00",
  "&lbarr;": "\u290C",
  "&lbbrk;": "\u2772",
  "&lbrace;": "{",
  "&lbrack;": "[",
  "&lbrke;": "\u298B",
  "&lbrksld;": "\u298F",
  "&lbrkslu;": "\u298D",
  "&lcaron;": "\u013E",
  "&lcedil;": "\u013C",
  "&lceil;": "\u2308",
  "&lcub;": "{",
  "&lcy;": "\u043B",
  "&ldca;": "\u2936",
  "&ldquo;": "\u201C",
  "&ldquor;": "\u201E",
  "&ldrdhar;": "\u2967",
  "&ldrushar;": "\u294B",
  "&ldsh;": "\u21B2",
  "&le;": "\u2264",
  "&leftarrow;": "\u2190",
  "&leftarrowtail;": "\u21A2",
  "&leftharpoondown;": "\u21BD",
  "&leftharpoonup;": "\u21BC",
  "&leftleftarrows;": "\u21C7",
  "&leftrightarrow;": "\u2194",
  "&leftrightarrows;": "\u21C6",
  "&leftrightharpoons;": "\u21CB",
  "&leftrightsquigarrow;": "\u21AD",
  "&leftthreetimes;": "\u22CB",
  "&leg;": "\u22DA",
  "&leq;": "\u2264",
  "&leqq;": "\u2266",
  "&leqslant;": "\u2A7D",
  "&les;": "\u2A7D",
  "&lescc;": "\u2AA8",
  "&lesdot;": "\u2A7F",
  "&lesdoto;": "\u2A81",
  "&lesdotor;": "\u2A83",
  "&lesg;": "\u22DA\uFE00",
  "&lesges;": "\u2A93",
  "&lessapprox;": "\u2A85",
  "&lessdot;": "\u22D6",
  "&lesseqgtr;": "\u22DA",
  "&lesseqqgtr;": "\u2A8B",
  "&lessgtr;": "\u2276",
  "&lesssim;": "\u2272",
  "&lfisht;": "\u297C",
  "&lfloor;": "\u230A",
  "&lfr;": "\u{1D529}",
  "&lg;": "\u2276",
  "&lgE;": "\u2A91",
  "&lhard;": "\u21BD",
  "&lharu;": "\u21BC",
  "&lharul;": "\u296A",
  "&lhblk;": "\u2584",
  "&ljcy;": "\u0459",
  "&ll;": "\u226A",
  "&llarr;": "\u21C7",
  "&llcorner;": "\u231E",
  "&llhard;": "\u296B",
  "&lltri;": "\u25FA",
  "&lmidot;": "\u0140",
  "&lmoust;": "\u23B0",
  "&lmoustache;": "\u23B0",
  "&lnE;": "\u2268",
  "&lnap;": "\u2A89",
  "&lnapprox;": "\u2A89",
  "&lne;": "\u2A87",
  "&lneq;": "\u2A87",
  "&lneqq;": "\u2268",
  "&lnsim;": "\u22E6",
  "&loang;": "\u27EC",
  "&loarr;": "\u21FD",
  "&lobrk;": "\u27E6",
  "&longleftarrow;": "\u27F5",
  "&longleftrightarrow;": "\u27F7",
  "&longmapsto;": "\u27FC",
  "&longrightarrow;": "\u27F6",
  "&looparrowleft;": "\u21AB",
  "&looparrowright;": "\u21AC",
  "&lopar;": "\u2985",
  "&lopf;": "\u{1D55D}",
  "&loplus;": "\u2A2D",
  "&lotimes;": "\u2A34",
  "&lowast;": "\u2217",
  "&lowbar;": "_",
  "&loz;": "\u25CA",
  "&lozenge;": "\u25CA",
  "&lozf;": "\u29EB",
  "&lpar;": "(",
  "&lparlt;": "\u2993",
  "&lrarr;": "\u21C6",
  "&lrcorner;": "\u231F",
  "&lrhar;": "\u21CB",
  "&lrhard;": "\u296D",
  "&lrm;": "\u200E",
  "&lrtri;": "\u22BF",
  "&lsaquo;": "\u2039",
  "&lscr;": "\u{1D4C1}",
  "&lsh;": "\u21B0",
  "&lsim;": "\u2272",
  "&lsime;": "\u2A8D",
  "&lsimg;": "\u2A8F",
  "&lsqb;": "[",
  "&lsquo;": "\u2018",
  "&lsquor;": "\u201A",
  "&lstrok;": "\u0142",
  "&lt": "<",
  "&lt;": "<",
  "&ltcc;": "\u2AA6",
  "&ltcir;": "\u2A79",
  "&ltdot;": "\u22D6",
  "&lthree;": "\u22CB",
  "&ltimes;": "\u22C9",
  "&ltlarr;": "\u2976",
  "&ltquest;": "\u2A7B",
  "&ltrPar;": "\u2996",
  "&ltri;": "\u25C3",
  "&ltrie;": "\u22B4",
  "&ltrif;": "\u25C2",
  "&lurdshar;": "\u294A",
  "&luruhar;": "\u2966",
  "&lvertneqq;": "\u2268\uFE00",
  "&lvnE;": "\u2268\uFE00",
  "&mDDot;": "\u223A",
  "&macr": "\xAF",
  "&macr;": "\xAF",
  "&male;": "\u2642",
  "&malt;": "\u2720",
  "&maltese;": "\u2720",
  "&map;": "\u21A6",
  "&mapsto;": "\u21A6",
  "&mapstodown;": "\u21A7",
  "&mapstoleft;": "\u21A4",
  "&mapstoup;": "\u21A5",
  "&marker;": "\u25AE",
  "&mcomma;": "\u2A29",
  "&mcy;": "\u043C",
  "&mdash;": "\u2014",
  "&measuredangle;": "\u2221",
  "&mfr;": "\u{1D52A}",
  "&mho;": "\u2127",
  "&micro": "\xB5",
  "&micro;": "\xB5",
  "&mid;": "\u2223",
  "&midast;": "*",
  "&midcir;": "\u2AF0",
  "&middot": "\xB7",
  "&middot;": "\xB7",
  "&minus;": "\u2212",
  "&minusb;": "\u229F",
  "&minusd;": "\u2238",
  "&minusdu;": "\u2A2A",
  "&mlcp;": "\u2ADB",
  "&mldr;": "\u2026",
  "&mnplus;": "\u2213",
  "&models;": "\u22A7",
  "&mopf;": "\u{1D55E}",
  "&mp;": "\u2213",
  "&mscr;": "\u{1D4C2}",
  "&mstpos;": "\u223E",
  "&mu;": "\u03BC",
  "&multimap;": "\u22B8",
  "&mumap;": "\u22B8",
  "&nGg;": "\u22D9\u0338",
  "&nGt;": "\u226B\u20D2",
  "&nGtv;": "\u226B\u0338",
  "&nLeftarrow;": "\u21CD",
  "&nLeftrightarrow;": "\u21CE",
  "&nLl;": "\u22D8\u0338",
  "&nLt;": "\u226A\u20D2",
  "&nLtv;": "\u226A\u0338",
  "&nRightarrow;": "\u21CF",
  "&nVDash;": "\u22AF",
  "&nVdash;": "\u22AE",
  "&nabla;": "\u2207",
  "&nacute;": "\u0144",
  "&nang;": "\u2220\u20D2",
  "&nap;": "\u2249",
  "&napE;": "\u2A70\u0338",
  "&napid;": "\u224B\u0338",
  "&napos;": "\u0149",
  "&napprox;": "\u2249",
  "&natur;": "\u266E",
  "&natural;": "\u266E",
  "&naturals;": "\u2115",
  "&nbsp": "\xA0",
  "&nbsp;": "\xA0",
  "&nbump;": "\u224E\u0338",
  "&nbumpe;": "\u224F\u0338",
  "&ncap;": "\u2A43",
  "&ncaron;": "\u0148",
  "&ncedil;": "\u0146",
  "&ncong;": "\u2247",
  "&ncongdot;": "\u2A6D\u0338",
  "&ncup;": "\u2A42",
  "&ncy;": "\u043D",
  "&ndash;": "\u2013",
  "&ne;": "\u2260",
  "&neArr;": "\u21D7",
  "&nearhk;": "\u2924",
  "&nearr;": "\u2197",
  "&nearrow;": "\u2197",
  "&nedot;": "\u2250\u0338",
  "&nequiv;": "\u2262",
  "&nesear;": "\u2928",
  "&nesim;": "\u2242\u0338",
  "&nexist;": "\u2204",
  "&nexists;": "\u2204",
  "&nfr;": "\u{1D52B}",
  "&ngE;": "\u2267\u0338",
  "&nge;": "\u2271",
  "&ngeq;": "\u2271",
  "&ngeqq;": "\u2267\u0338",
  "&ngeqslant;": "\u2A7E\u0338",
  "&nges;": "\u2A7E\u0338",
  "&ngsim;": "\u2275",
  "&ngt;": "\u226F",
  "&ngtr;": "\u226F",
  "&nhArr;": "\u21CE",
  "&nharr;": "\u21AE",
  "&nhpar;": "\u2AF2",
  "&ni;": "\u220B",
  "&nis;": "\u22FC",
  "&nisd;": "\u22FA",
  "&niv;": "\u220B",
  "&njcy;": "\u045A",
  "&nlArr;": "\u21CD",
  "&nlE;": "\u2266\u0338",
  "&nlarr;": "\u219A",
  "&nldr;": "\u2025",
  "&nle;": "\u2270",
  "&nleftarrow;": "\u219A",
  "&nleftrightarrow;": "\u21AE",
  "&nleq;": "\u2270",
  "&nleqq;": "\u2266\u0338",
  "&nleqslant;": "\u2A7D\u0338",
  "&nles;": "\u2A7D\u0338",
  "&nless;": "\u226E",
  "&nlsim;": "\u2274",
  "&nlt;": "\u226E",
  "&nltri;": "\u22EA",
  "&nltrie;": "\u22EC",
  "&nmid;": "\u2224",
  "&nopf;": "\u{1D55F}",
  "&not": "\xAC",
  "&not;": "\xAC",
  "&notin;": "\u2209",
  "&notinE;": "\u22F9\u0338",
  "&notindot;": "\u22F5\u0338",
  "&notinva;": "\u2209",
  "&notinvb;": "\u22F7",
  "&notinvc;": "\u22F6",
  "&notni;": "\u220C",
  "&notniva;": "\u220C",
  "&notnivb;": "\u22FE",
  "&notnivc;": "\u22FD",
  "&npar;": "\u2226",
  "&nparallel;": "\u2226",
  "&nparsl;": "\u2AFD\u20E5",
  "&npart;": "\u2202\u0338",
  "&npolint;": "\u2A14",
  "&npr;": "\u2280",
  "&nprcue;": "\u22E0",
  "&npre;": "\u2AAF\u0338",
  "&nprec;": "\u2280",
  "&npreceq;": "\u2AAF\u0338",
  "&nrArr;": "\u21CF",
  "&nrarr;": "\u219B",
  "&nrarrc;": "\u2933\u0338",
  "&nrarrw;": "\u219D\u0338",
  "&nrightarrow;": "\u219B",
  "&nrtri;": "\u22EB",
  "&nrtrie;": "\u22ED",
  "&nsc;": "\u2281",
  "&nsccue;": "\u22E1",
  "&nsce;": "\u2AB0\u0338",
  "&nscr;": "\u{1D4C3}",
  "&nshortmid;": "\u2224",
  "&nshortparallel;": "\u2226",
  "&nsim;": "\u2241",
  "&nsime;": "\u2244",
  "&nsimeq;": "\u2244",
  "&nsmid;": "\u2224",
  "&nspar;": "\u2226",
  "&nsqsube;": "\u22E2",
  "&nsqsupe;": "\u22E3",
  "&nsub;": "\u2284",
  "&nsubE;": "\u2AC5\u0338",
  "&nsube;": "\u2288",
  "&nsubset;": "\u2282\u20D2",
  "&nsubseteq;": "\u2288",
  "&nsubseteqq;": "\u2AC5\u0338",
  "&nsucc;": "\u2281",
  "&nsucceq;": "\u2AB0\u0338",
  "&nsup;": "\u2285",
  "&nsupE;": "\u2AC6\u0338",
  "&nsupe;": "\u2289",
  "&nsupset;": "\u2283\u20D2",
  "&nsupseteq;": "\u2289",
  "&nsupseteqq;": "\u2AC6\u0338",
  "&ntgl;": "\u2279",
  "&ntilde": "\xF1",
  "&ntilde;": "\xF1",
  "&ntlg;": "\u2278",
  "&ntriangleleft;": "\u22EA",
  "&ntrianglelefteq;": "\u22EC",
  "&ntriangleright;": "\u22EB",
  "&ntrianglerighteq;": "\u22ED",
  "&nu;": "\u03BD",
  "&num;": "#",
  "&numero;": "\u2116",
  "&numsp;": "\u2007",
  "&nvDash;": "\u22AD",
  "&nvHarr;": "\u2904",
  "&nvap;": "\u224D\u20D2",
  "&nvdash;": "\u22AC",
  "&nvge;": "\u2265\u20D2",
  "&nvgt;": ">\u20D2",
  "&nvinfin;": "\u29DE",
  "&nvlArr;": "\u2902",
  "&nvle;": "\u2264\u20D2",
  "&nvlt;": "<\u20D2",
  "&nvltrie;": "\u22B4\u20D2",
  "&nvrArr;": "\u2903",
  "&nvrtrie;": "\u22B5\u20D2",
  "&nvsim;": "\u223C\u20D2",
  "&nwArr;": "\u21D6",
  "&nwarhk;": "\u2923",
  "&nwarr;": "\u2196",
  "&nwarrow;": "\u2196",
  "&nwnear;": "\u2927",
  "&oS;": "\u24C8",
  "&oacute": "\xF3",
  "&oacute;": "\xF3",
  "&oast;": "\u229B",
  "&ocir;": "\u229A",
  "&ocirc": "\xF4",
  "&ocirc;": "\xF4",
  "&ocy;": "\u043E",
  "&odash;": "\u229D",
  "&odblac;": "\u0151",
  "&odiv;": "\u2A38",
  "&odot;": "\u2299",
  "&odsold;": "\u29BC",
  "&oelig;": "\u0153",
  "&ofcir;": "\u29BF",
  "&ofr;": "\u{1D52C}",
  "&ogon;": "\u02DB",
  "&ograve": "\xF2",
  "&ograve;": "\xF2",
  "&ogt;": "\u29C1",
  "&ohbar;": "\u29B5",
  "&ohm;": "\u03A9",
  "&oint;": "\u222E",
  "&olarr;": "\u21BA",
  "&olcir;": "\u29BE",
  "&olcross;": "\u29BB",
  "&oline;": "\u203E",
  "&olt;": "\u29C0",
  "&omacr;": "\u014D",
  "&omega;": "\u03C9",
  "&omicron;": "\u03BF",
  "&omid;": "\u29B6",
  "&ominus;": "\u2296",
  "&oopf;": "\u{1D560}",
  "&opar;": "\u29B7",
  "&operp;": "\u29B9",
  "&oplus;": "\u2295",
  "&or;": "\u2228",
  "&orarr;": "\u21BB",
  "&ord;": "\u2A5D",
  "&order;": "\u2134",
  "&orderof;": "\u2134",
  "&ordf": "\xAA",
  "&ordf;": "\xAA",
  "&ordm": "\xBA",
  "&ordm;": "\xBA",
  "&origof;": "\u22B6",
  "&oror;": "\u2A56",
  "&orslope;": "\u2A57",
  "&orv;": "\u2A5B",
  "&oscr;": "\u2134",
  "&oslash": "\xF8",
  "&oslash;": "\xF8",
  "&osol;": "\u2298",
  "&otilde": "\xF5",
  "&otilde;": "\xF5",
  "&otimes;": "\u2297",
  "&otimesas;": "\u2A36",
  "&ouml": "\xF6",
  "&ouml;": "\xF6",
  "&ovbar;": "\u233D",
  "&par;": "\u2225",
  "&para": "\xB6",
  "&para;": "\xB6",
  "&parallel;": "\u2225",
  "&parsim;": "\u2AF3",
  "&parsl;": "\u2AFD",
  "&part;": "\u2202",
  "&pcy;": "\u043F",
  "&percnt;": "%",
  "&period;": ".",
  "&permil;": "\u2030",
  "&perp;": "\u22A5",
  "&pertenk;": "\u2031",
  "&pfr;": "\u{1D52D}",
  "&phi;": "\u03C6",
  "&phiv;": "\u03D5",
  "&phmmat;": "\u2133",
  "&phone;": "\u260E",
  "&pi;": "\u03C0",
  "&pitchfork;": "\u22D4",
  "&piv;": "\u03D6",
  "&planck;": "\u210F",
  "&planckh;": "\u210E",
  "&plankv;": "\u210F",
  "&plus;": "+",
  "&plusacir;": "\u2A23",
  "&plusb;": "\u229E",
  "&pluscir;": "\u2A22",
  "&plusdo;": "\u2214",
  "&plusdu;": "\u2A25",
  "&pluse;": "\u2A72",
  "&plusmn": "\xB1",
  "&plusmn;": "\xB1",
  "&plussim;": "\u2A26",
  "&plustwo;": "\u2A27",
  "&pm;": "\xB1",
  "&pointint;": "\u2A15",
  "&popf;": "\u{1D561}",
  "&pound": "\xA3",
  "&pound;": "\xA3",
  "&pr;": "\u227A",
  "&prE;": "\u2AB3",
  "&prap;": "\u2AB7",
  "&prcue;": "\u227C",
  "&pre;": "\u2AAF",
  "&prec;": "\u227A",
  "&precapprox;": "\u2AB7",
  "&preccurlyeq;": "\u227C",
  "&preceq;": "\u2AAF",
  "&precnapprox;": "\u2AB9",
  "&precneqq;": "\u2AB5",
  "&precnsim;": "\u22E8",
  "&precsim;": "\u227E",
  "&prime;": "\u2032",
  "&primes;": "\u2119",
  "&prnE;": "\u2AB5",
  "&prnap;": "\u2AB9",
  "&prnsim;": "\u22E8",
  "&prod;": "\u220F",
  "&profalar;": "\u232E",
  "&profline;": "\u2312",
  "&profsurf;": "\u2313",
  "&prop;": "\u221D",
  "&propto;": "\u221D",
  "&prsim;": "\u227E",
  "&prurel;": "\u22B0",
  "&pscr;": "\u{1D4C5}",
  "&psi;": "\u03C8",
  "&puncsp;": "\u2008",
  "&qfr;": "\u{1D52E}",
  "&qint;": "\u2A0C",
  "&qopf;": "\u{1D562}",
  "&qprime;": "\u2057",
  "&qscr;": "\u{1D4C6}",
  "&quaternions;": "\u210D",
  "&quatint;": "\u2A16",
  "&quest;": "?",
  "&questeq;": "\u225F",
  "&quot": '"',
  "&quot;": '"',
  "&rAarr;": "\u21DB",
  "&rArr;": "\u21D2",
  "&rAtail;": "\u291C",
  "&rBarr;": "\u290F",
  "&rHar;": "\u2964",
  "&race;": "\u223D\u0331",
  "&racute;": "\u0155",
  "&radic;": "\u221A",
  "&raemptyv;": "\u29B3",
  "&rang;": "\u27E9",
  "&rangd;": "\u2992",
  "&range;": "\u29A5",
  "&rangle;": "\u27E9",
  "&raquo": "\xBB",
  "&raquo;": "\xBB",
  "&rarr;": "\u2192",
  "&rarrap;": "\u2975",
  "&rarrb;": "\u21E5",
  "&rarrbfs;": "\u2920",
  "&rarrc;": "\u2933",
  "&rarrfs;": "\u291E",
  "&rarrhk;": "\u21AA",
  "&rarrlp;": "\u21AC",
  "&rarrpl;": "\u2945",
  "&rarrsim;": "\u2974",
  "&rarrtl;": "\u21A3",
  "&rarrw;": "\u219D",
  "&ratail;": "\u291A",
  "&ratio;": "\u2236",
  "&rationals;": "\u211A",
  "&rbarr;": "\u290D",
  "&rbbrk;": "\u2773",
  "&rbrace;": "}",
  "&rbrack;": "]",
  "&rbrke;": "\u298C",
  "&rbrksld;": "\u298E",
  "&rbrkslu;": "\u2990",
  "&rcaron;": "\u0159",
  "&rcedil;": "\u0157",
  "&rceil;": "\u2309",
  "&rcub;": "}",
  "&rcy;": "\u0440",
  "&rdca;": "\u2937",
  "&rdldhar;": "\u2969",
  "&rdquo;": "\u201D",
  "&rdquor;": "\u201D",
  "&rdsh;": "\u21B3",
  "&real;": "\u211C",
  "&realine;": "\u211B",
  "&realpart;": "\u211C",
  "&reals;": "\u211D",
  "&rect;": "\u25AD",
  "&reg": "\xAE",
  "&reg;": "\xAE",
  "&rfisht;": "\u297D",
  "&rfloor;": "\u230B",
  "&rfr;": "\u{1D52F}",
  "&rhard;": "\u21C1",
  "&rharu;": "\u21C0",
  "&rharul;": "\u296C",
  "&rho;": "\u03C1",
  "&rhov;": "\u03F1",
  "&rightarrow;": "\u2192",
  "&rightarrowtail;": "\u21A3",
  "&rightharpoondown;": "\u21C1",
  "&rightharpoonup;": "\u21C0",
  "&rightleftarrows;": "\u21C4",
  "&rightleftharpoons;": "\u21CC",
  "&rightrightarrows;": "\u21C9",
  "&rightsquigarrow;": "\u219D",
  "&rightthreetimes;": "\u22CC",
  "&ring;": "\u02DA",
  "&risingdotseq;": "\u2253",
  "&rlarr;": "\u21C4",
  "&rlhar;": "\u21CC",
  "&rlm;": "\u200F",
  "&rmoust;": "\u23B1",
  "&rmoustache;": "\u23B1",
  "&rnmid;": "\u2AEE",
  "&roang;": "\u27ED",
  "&roarr;": "\u21FE",
  "&robrk;": "\u27E7",
  "&ropar;": "\u2986",
  "&ropf;": "\u{1D563}",
  "&roplus;": "\u2A2E",
  "&rotimes;": "\u2A35",
  "&rpar;": ")",
  "&rpargt;": "\u2994",
  "&rppolint;": "\u2A12",
  "&rrarr;": "\u21C9",
  "&rsaquo;": "\u203A",
  "&rscr;": "\u{1D4C7}",
  "&rsh;": "\u21B1",
  "&rsqb;": "]",
  "&rsquo;": "\u2019",
  "&rsquor;": "\u2019",
  "&rthree;": "\u22CC",
  "&rtimes;": "\u22CA",
  "&rtri;": "\u25B9",
  "&rtrie;": "\u22B5",
  "&rtrif;": "\u25B8",
  "&rtriltri;": "\u29CE",
  "&ruluhar;": "\u2968",
  "&rx;": "\u211E",
  "&sacute;": "\u015B",
  "&sbquo;": "\u201A",
  "&sc;": "\u227B",
  "&scE;": "\u2AB4",
  "&scap;": "\u2AB8",
  "&scaron;": "\u0161",
  "&sccue;": "\u227D",
  "&sce;": "\u2AB0",
  "&scedil;": "\u015F",
  "&scirc;": "\u015D",
  "&scnE;": "\u2AB6",
  "&scnap;": "\u2ABA",
  "&scnsim;": "\u22E9",
  "&scpolint;": "\u2A13",
  "&scsim;": "\u227F",
  "&scy;": "\u0441",
  "&sdot;": "\u22C5",
  "&sdotb;": "\u22A1",
  "&sdote;": "\u2A66",
  "&seArr;": "\u21D8",
  "&searhk;": "\u2925",
  "&searr;": "\u2198",
  "&searrow;": "\u2198",
  "&sect": "\xA7",
  "&sect;": "\xA7",
  "&semi;": ";",
  "&seswar;": "\u2929",
  "&setminus;": "\u2216",
  "&setmn;": "\u2216",
  "&sext;": "\u2736",
  "&sfr;": "\u{1D530}",
  "&sfrown;": "\u2322",
  "&sharp;": "\u266F",
  "&shchcy;": "\u0449",
  "&shcy;": "\u0448",
  "&shortmid;": "\u2223",
  "&shortparallel;": "\u2225",
  "&shy": "\xAD",
  "&shy;": "\xAD",
  "&sigma;": "\u03C3",
  "&sigmaf;": "\u03C2",
  "&sigmav;": "\u03C2",
  "&sim;": "\u223C",
  "&simdot;": "\u2A6A",
  "&sime;": "\u2243",
  "&simeq;": "\u2243",
  "&simg;": "\u2A9E",
  "&simgE;": "\u2AA0",
  "&siml;": "\u2A9D",
  "&simlE;": "\u2A9F",
  "&simne;": "\u2246",
  "&simplus;": "\u2A24",
  "&simrarr;": "\u2972",
  "&slarr;": "\u2190",
  "&smallsetminus;": "\u2216",
  "&smashp;": "\u2A33",
  "&smeparsl;": "\u29E4",
  "&smid;": "\u2223",
  "&smile;": "\u2323",
  "&smt;": "\u2AAA",
  "&smte;": "\u2AAC",
  "&smtes;": "\u2AAC\uFE00",
  "&softcy;": "\u044C",
  "&sol;": "/",
  "&solb;": "\u29C4",
  "&solbar;": "\u233F",
  "&sopf;": "\u{1D564}",
  "&spades;": "\u2660",
  "&spadesuit;": "\u2660",
  "&spar;": "\u2225",
  "&sqcap;": "\u2293",
  "&sqcaps;": "\u2293\uFE00",
  "&sqcup;": "\u2294",
  "&sqcups;": "\u2294\uFE00",
  "&sqsub;": "\u228F",
  "&sqsube;": "\u2291",
  "&sqsubset;": "\u228F",
  "&sqsubseteq;": "\u2291",
  "&sqsup;": "\u2290",
  "&sqsupe;": "\u2292",
  "&sqsupset;": "\u2290",
  "&sqsupseteq;": "\u2292",
  "&squ;": "\u25A1",
  "&square;": "\u25A1",
  "&squarf;": "\u25AA",
  "&squf;": "\u25AA",
  "&srarr;": "\u2192",
  "&sscr;": "\u{1D4C8}",
  "&ssetmn;": "\u2216",
  "&ssmile;": "\u2323",
  "&sstarf;": "\u22C6",
  "&star;": "\u2606",
  "&starf;": "\u2605",
  "&straightepsilon;": "\u03F5",
  "&straightphi;": "\u03D5",
  "&strns;": "\xAF",
  "&sub;": "\u2282",
  "&subE;": "\u2AC5",
  "&subdot;": "\u2ABD",
  "&sube;": "\u2286",
  "&subedot;": "\u2AC3",
  "&submult;": "\u2AC1",
  "&subnE;": "\u2ACB",
  "&subne;": "\u228A",
  "&subplus;": "\u2ABF",
  "&subrarr;": "\u2979",
  "&subset;": "\u2282",
  "&subseteq;": "\u2286",
  "&subseteqq;": "\u2AC5",
  "&subsetneq;": "\u228A",
  "&subsetneqq;": "\u2ACB",
  "&subsim;": "\u2AC7",
  "&subsub;": "\u2AD5",
  "&subsup;": "\u2AD3",
  "&succ;": "\u227B",
  "&succapprox;": "\u2AB8",
  "&succcurlyeq;": "\u227D",
  "&succeq;": "\u2AB0",
  "&succnapprox;": "\u2ABA",
  "&succneqq;": "\u2AB6",
  "&succnsim;": "\u22E9",
  "&succsim;": "\u227F",
  "&sum;": "\u2211",
  "&sung;": "\u266A",
  "&sup1": "\xB9",
  "&sup1;": "\xB9",
  "&sup2": "\xB2",
  "&sup2;": "\xB2",
  "&sup3": "\xB3",
  "&sup3;": "\xB3",
  "&sup;": "\u2283",
  "&supE;": "\u2AC6",
  "&supdot;": "\u2ABE",
  "&supdsub;": "\u2AD8",
  "&supe;": "\u2287",
  "&supedot;": "\u2AC4",
  "&suphsol;": "\u27C9",
  "&suphsub;": "\u2AD7",
  "&suplarr;": "\u297B",
  "&supmult;": "\u2AC2",
  "&supnE;": "\u2ACC",
  "&supne;": "\u228B",
  "&supplus;": "\u2AC0",
  "&supset;": "\u2283",
  "&supseteq;": "\u2287",
  "&supseteqq;": "\u2AC6",
  "&supsetneq;": "\u228B",
  "&supsetneqq;": "\u2ACC",
  "&supsim;": "\u2AC8",
  "&supsub;": "\u2AD4",
  "&supsup;": "\u2AD6",
  "&swArr;": "\u21D9",
  "&swarhk;": "\u2926",
  "&swarr;": "\u2199",
  "&swarrow;": "\u2199",
  "&swnwar;": "\u292A",
  "&szlig": "\xDF",
  "&szlig;": "\xDF",
  "&target;": "\u2316",
  "&tau;": "\u03C4",
  "&tbrk;": "\u23B4",
  "&tcaron;": "\u0165",
  "&tcedil;": "\u0163",
  "&tcy;": "\u0442",
  "&tdot;": "\u20DB",
  "&telrec;": "\u2315",
  "&tfr;": "\u{1D531}",
  "&there4;": "\u2234",
  "&therefore;": "\u2234",
  "&theta;": "\u03B8",
  "&thetasym;": "\u03D1",
  "&thetav;": "\u03D1",
  "&thickapprox;": "\u2248",
  "&thicksim;": "\u223C",
  "&thinsp;": "\u2009",
  "&thkap;": "\u2248",
  "&thksim;": "\u223C",
  "&thorn": "\xFE",
  "&thorn;": "\xFE",
  "&tilde;": "\u02DC",
  "&times": "\xD7",
  "&times;": "\xD7",
  "&timesb;": "\u22A0",
  "&timesbar;": "\u2A31",
  "&timesd;": "\u2A30",
  "&tint;": "\u222D",
  "&toea;": "\u2928",
  "&top;": "\u22A4",
  "&topbot;": "\u2336",
  "&topcir;": "\u2AF1",
  "&topf;": "\u{1D565}",
  "&topfork;": "\u2ADA",
  "&tosa;": "\u2929",
  "&tprime;": "\u2034",
  "&trade;": "\u2122",
  "&triangle;": "\u25B5",
  "&triangledown;": "\u25BF",
  "&triangleleft;": "\u25C3",
  "&trianglelefteq;": "\u22B4",
  "&triangleq;": "\u225C",
  "&triangleright;": "\u25B9",
  "&trianglerighteq;": "\u22B5",
  "&tridot;": "\u25EC",
  "&trie;": "\u225C",
  "&triminus;": "\u2A3A",
  "&triplus;": "\u2A39",
  "&trisb;": "\u29CD",
  "&tritime;": "\u2A3B",
  "&trpezium;": "\u23E2",
  "&tscr;": "\u{1D4C9}",
  "&tscy;": "\u0446",
  "&tshcy;": "\u045B",
  "&tstrok;": "\u0167",
  "&twixt;": "\u226C",
  "&twoheadleftarrow;": "\u219E",
  "&twoheadrightarrow;": "\u21A0",
  "&uArr;": "\u21D1",
  "&uHar;": "\u2963",
  "&uacute": "\xFA",
  "&uacute;": "\xFA",
  "&uarr;": "\u2191",
  "&ubrcy;": "\u045E",
  "&ubreve;": "\u016D",
  "&ucirc": "\xFB",
  "&ucirc;": "\xFB",
  "&ucy;": "\u0443",
  "&udarr;": "\u21C5",
  "&udblac;": "\u0171",
  "&udhar;": "\u296E",
  "&ufisht;": "\u297E",
  "&ufr;": "\u{1D532}",
  "&ugrave": "\xF9",
  "&ugrave;": "\xF9",
  "&uharl;": "\u21BF",
  "&uharr;": "\u21BE",
  "&uhblk;": "\u2580",
  "&ulcorn;": "\u231C",
  "&ulcorner;": "\u231C",
  "&ulcrop;": "\u230F",
  "&ultri;": "\u25F8",
  "&umacr;": "\u016B",
  "&uml": "\xA8",
  "&uml;": "\xA8",
  "&uogon;": "\u0173",
  "&uopf;": "\u{1D566}",
  "&uparrow;": "\u2191",
  "&updownarrow;": "\u2195",
  "&upharpoonleft;": "\u21BF",
  "&upharpoonright;": "\u21BE",
  "&uplus;": "\u228E",
  "&upsi;": "\u03C5",
  "&upsih;": "\u03D2",
  "&upsilon;": "\u03C5",
  "&upuparrows;": "\u21C8",
  "&urcorn;": "\u231D",
  "&urcorner;": "\u231D",
  "&urcrop;": "\u230E",
  "&uring;": "\u016F",
  "&urtri;": "\u25F9",
  "&uscr;": "\u{1D4CA}",
  "&utdot;": "\u22F0",
  "&utilde;": "\u0169",
  "&utri;": "\u25B5",
  "&utrif;": "\u25B4",
  "&uuarr;": "\u21C8",
  "&uuml": "\xFC",
  "&uuml;": "\xFC",
  "&uwangle;": "\u29A7",
  "&vArr;": "\u21D5",
  "&vBar;": "\u2AE8",
  "&vBarv;": "\u2AE9",
  "&vDash;": "\u22A8",
  "&vangrt;": "\u299C",
  "&varepsilon;": "\u03F5",
  "&varkappa;": "\u03F0",
  "&varnothing;": "\u2205",
  "&varphi;": "\u03D5",
  "&varpi;": "\u03D6",
  "&varpropto;": "\u221D",
  "&varr;": "\u2195",
  "&varrho;": "\u03F1",
  "&varsigma;": "\u03C2",
  "&varsubsetneq;": "\u228A\uFE00",
  "&varsubsetneqq;": "\u2ACB\uFE00",
  "&varsupsetneq;": "\u228B\uFE00",
  "&varsupsetneqq;": "\u2ACC\uFE00",
  "&vartheta;": "\u03D1",
  "&vartriangleleft;": "\u22B2",
  "&vartriangleright;": "\u22B3",
  "&vcy;": "\u0432",
  "&vdash;": "\u22A2",
  "&vee;": "\u2228",
  "&veebar;": "\u22BB",
  "&veeeq;": "\u225A",
  "&vellip;": "\u22EE",
  "&verbar;": "|",
  "&vert;": "|",
  "&vfr;": "\u{1D533}",
  "&vltri;": "\u22B2",
  "&vnsub;": "\u2282\u20D2",
  "&vnsup;": "\u2283\u20D2",
  "&vopf;": "\u{1D567}",
  "&vprop;": "\u221D",
  "&vrtri;": "\u22B3",
  "&vscr;": "\u{1D4CB}",
  "&vsubnE;": "\u2ACB\uFE00",
  "&vsubne;": "\u228A\uFE00",
  "&vsupnE;": "\u2ACC\uFE00",
  "&vsupne;": "\u228B\uFE00",
  "&vzigzag;": "\u299A",
  "&wcirc;": "\u0175",
  "&wedbar;": "\u2A5F",
  "&wedge;": "\u2227",
  "&wedgeq;": "\u2259",
  "&weierp;": "\u2118",
  "&wfr;": "\u{1D534}",
  "&wopf;": "\u{1D568}",
  "&wp;": "\u2118",
  "&wr;": "\u2240",
  "&wreath;": "\u2240",
  "&wscr;": "\u{1D4CC}",
  "&xcap;": "\u22C2",
  "&xcirc;": "\u25EF",
  "&xcup;": "\u22C3",
  "&xdtri;": "\u25BD",
  "&xfr;": "\u{1D535}",
  "&xhArr;": "\u27FA",
  "&xharr;": "\u27F7",
  "&xi;": "\u03BE",
  "&xlArr;": "\u27F8",
  "&xlarr;": "\u27F5",
  "&xmap;": "\u27FC",
  "&xnis;": "\u22FB",
  "&xodot;": "\u2A00",
  "&xopf;": "\u{1D569}",
  "&xoplus;": "\u2A01",
  "&xotime;": "\u2A02",
  "&xrArr;": "\u27F9",
  "&xrarr;": "\u27F6",
  "&xscr;": "\u{1D4CD}",
  "&xsqcup;": "\u2A06",
  "&xuplus;": "\u2A04",
  "&xutri;": "\u25B3",
  "&xvee;": "\u22C1",
  "&xwedge;": "\u22C0",
  "&yacute": "\xFD",
  "&yacute;": "\xFD",
  "&yacy;": "\u044F",
  "&ycirc;": "\u0177",
  "&ycy;": "\u044B",
  "&yen": "\xA5",
  "&yen;": "\xA5",
  "&yfr;": "\u{1D536}",
  "&yicy;": "\u0457",
  "&yopf;": "\u{1D56A}",
  "&yscr;": "\u{1D4CE}",
  "&yucy;": "\u044E",
  "&yuml": "\xFF",
  "&yuml;": "\xFF",
  "&zacute;": "\u017A",
  "&zcaron;": "\u017E",
  "&zcy;": "\u0437",
  "&zdot;": "\u017C",
  "&zeetrf;": "\u2128",
  "&zeta;": "\u03B6",
  "&zfr;": "\u{1D537}",
  "&zhcy;": "\u0436",
  "&zigrarr;": "\u21DD",
  "&zopf;": "\u{1D56B}",
  "&zscr;": "\u{1D4CF}",
  "&zwj;": "\u200D",
  "&zwnj;": "\u200C"
};

// node_modules/postal-mime/dist/esm/text-format.js
var C1_ENTITY_REPLACEMENTS = /* @__PURE__ */ new Map([
  [128, 8364],
  [130, 8218],
  [131, 402],
  [132, 8222],
  [133, 8230],
  [134, 8224],
  [135, 8225],
  [136, 710],
  [137, 8240],
  [138, 352],
  [139, 8249],
  [140, 338],
  [142, 381],
  [145, 8216],
  [146, 8217],
  [147, 8220],
  [148, 8221],
  [149, 8226],
  [150, 8211],
  [151, 8212],
  [152, 732],
  [153, 8482],
  [154, 353],
  [155, 8250],
  [156, 339],
  [158, 382],
  [159, 376]
]);
function decodeHTMLEntities(str) {
  return str.replace(/&(#\d+|#x[a-f0-9]+|[a-z]+\d*);?/gi, (match2, entity) => {
    if (typeof htmlEntities[match2] === "string") {
      return htmlEntities[match2];
    }
    if (entity.charAt(0) !== "#" || match2.charAt(match2.length - 1) !== ";") {
      return match2;
    }
    let codePoint;
    if (entity.charAt(1).toLowerCase() === "x") {
      codePoint = parseInt(entity.slice(2), 16);
    } else {
      codePoint = parseInt(entity.slice(1), 10);
    }
    let output = "";
    if (codePoint === 0 || codePoint >= 55296 && codePoint <= 57343 || codePoint > 1114111) {
      return "\uFFFD";
    }
    codePoint = C1_ENTITY_REPLACEMENTS.get(codePoint) ?? codePoint;
    if (codePoint > 65535) {
      codePoint -= 65536;
      output += String.fromCharCode(codePoint >>> 10 & 1023 | 55296);
      codePoint = 56320 | codePoint & 1023;
    }
    output += String.fromCharCode(codePoint);
    return output;
  });
}
__name(decodeHTMLEntities, "decodeHTMLEntities");
function escapeHtml(str) {
  return str.trim().replace(/[<>"'?&]/g, (c) => {
    let hex = c.charCodeAt(0).toString(16);
    if (hex.length < 2) {
      hex = "0" + hex;
    }
    return "&#x" + hex.toUpperCase() + ";";
  });
}
__name(escapeHtml, "escapeHtml");
function textToHtml(str) {
  let html = escapeHtml(str).replace(/\n/g, "<br />");
  return "<div>" + html + "</div>";
}
__name(textToHtml, "textToHtml");
var LINE_TERMINATOR = /[\n\r\u2028\u2029]/g;
function lastLineTerminator(str) {
  return Math.max(str.lastIndexOf("\n"), str.lastIndexOf("\r"), str.lastIndexOf("\u2028"), str.lastIndexOf("\u2029"));
}
__name(lastLineTerminator, "lastLineTerminator");
function createFinder(str, regex) {
  let searchedFrom = Infinity;
  let found = null;
  return (pos) => {
    if (pos < searchedFrom || found && pos > found.index) {
      regex.lastIndex = pos;
      found = regex.exec(str);
      searchedFrom = pos;
    }
    return found;
  };
}
__name(createFinder, "createFinder");
function replaceClosedTags(str, pattern, replacement) {
  const end = str.lastIndexOf(">") + 1;
  return str.slice(0, end).replace(pattern, replacement) + str.slice(end);
}
__name(replaceClosedTags, "replaceClosedTags");
function replaceTags(str, prefix, pattern, replacement) {
  const parts = [];
  let copied = 0;
  let searchFrom = 0;
  while (true) {
    prefix.lastIndex = searchFrom;
    const candidate = prefix.exec(str);
    if (!candidate) {
      break;
    }
    const start = candidate.index;
    const gt = str.indexOf(">", start);
    if (gt < 0) {
      break;
    }
    pattern.lastIndex = start;
    const match2 = pattern.exec(str);
    if (!match2) {
      searchFrom = gt + 1;
      continue;
    }
    parts.push(str.slice(copied, start), replacement(...match2));
    copied = searchFrom = start + match2[0].length;
  }
  parts.push(str.slice(copied));
  return parts.join("");
}
__name(replaceTags, "replaceTags");
function replaceBlocks(str, open, openToGt, close, closeToGt, replacement) {
  const nextGt = createFinder(str, />/g);
  const nextClose = createFinder(str, close);
  const nextLineEnd = createFinder(str, LINE_TERMINATOR);
  const parts = [];
  let copied = 0;
  let searchFrom = 0;
  while (true) {
    open.lastIndex = searchFrom;
    const opener = open.exec(str);
    if (!opener) {
      break;
    }
    const start = opener.index;
    searchFrom = start + 1;
    let from = start + opener[0].length;
    if (openToGt) {
      const gt = nextGt(from);
      if (!gt) {
        break;
      }
      from = gt.index + 1;
    }
    const closer = nextClose(from);
    if (!closer) {
      break;
    }
    const lineEnd = nextLineEnd(from);
    if (lineEnd && lineEnd.index < closer.index) {
      continue;
    }
    let end = closer.index + closer[0].length;
    if (closeToGt) {
      const gt = nextGt(end);
      if (!gt) {
        break;
      }
      end = gt.index + 1;
    }
    parts.push(str.slice(copied, start), replacement);
    copied = searchFrom = end;
  }
  parts.push(str.slice(copied));
  return parts.join("");
}
__name(replaceBlocks, "replaceBlocks");
function stripThroughLastTag(str, prefix) {
  const lineEnd = str.search(LINE_TERMINATOR);
  const limit = Math.min(lineEnd < 0 ? str.length : lineEnd, str.lastIndexOf(">"));
  let last = -1;
  prefix.lastIndex = 0;
  let match2;
  while ((match2 = prefix.exec(str)) && match2.index < limit) {
    last = match2.index;
  }
  return last < 0 ? str : str.slice(str.indexOf(">", last) + 1);
}
__name(stripThroughLastTag, "stripThroughLastTag");
function stripFromFirstTag(str, prefix) {
  const lineEnd = lastLineTerminator(str);
  prefix.lastIndex = lineEnd < 0 ? 0 : str.lastIndexOf(">", lineEnd) + 1;
  const match2 = prefix.exec(str);
  return match2 && match2.index < str.lastIndexOf(">") ? str.slice(0, match2.index) : str;
}
__name(stripFromFirstTag, "stripFromFirstTag");
function htmlToText2(str) {
  str = str.replace(/\r?\n/g, "");
  str = replaceBlocks(str, /<!--/g, false, /-->/g, false, " ");
  str = replaceClosedTags(str, /<br\b[^>]*>/gi, "\n");
  str = replaceClosedTags(str, /<\/?(p|div|table|tr|td|th)\b[^>]*>/gi, "\n\n");
  str = replaceBlocks(str, /<script\b/gi, true, /<\/script\b/gi, true, " ");
  str = stripThroughLastTag(str, /<body\b/gi);
  str = stripThroughLastTag(str, /<\/head\b/gi);
  str = stripThroughLastTag(str, /<!doctype\b/gi);
  str = stripFromFirstTag(str, /<\/body\b/gi);
  str = stripFromFirstTag(str, /<\/html\b/gi);
  str = replaceTags(str, /<a\b/gi, /<a\b[^>]*href\s*=\s*["']?([^\s"']+)[^>]*>/iy, (match2, href) => ` (${href}) `);
  str = replaceClosedTags(str, /<\/?(span|em|i|strong|b|u|a)\b[^>]*>/gi, "");
  str = replaceTags(str, /<li\b/gi, /<li\b[^>]*>[\n\u0001\s]*/iy, () => "* ");
  str = replaceClosedTags(str, /<hr\b[^>]*>/g, "\n-------------\n");
  str = replaceClosedTags(str, /<[^>]*>/g, " ");
  str = str.replace(/\u0001/g, "\n").replace(/[ \t]+/g, " ").replace(/^\s+$/gm, "").replace(/\n\n+/g, "\n\n").replace(/^\n+/, "\n").replace(/\n+$/, "\n");
  str = decodeHTMLEntities(str);
  return str;
}
__name(htmlToText2, "htmlToText");
function formatDate(date) {
  if (typeof Intl === "undefined") {
    return date;
  }
  const parsed = new Date(date);
  if (isNaN(parsed.getTime())) {
    return date;
  }
  return new Intl.DateTimeFormat("default", {
    year: "numeric",
    month: "numeric",
    day: "numeric",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
    hour12: false
  }).format(parsed);
}
__name(formatDate, "formatDate");
function formatTextAddress(address) {
  return (address.name ? [address.name, `<${address.address}>`] : [address.address]).join(" ");
}
__name(formatTextAddress, "formatTextAddress");
function formatTextAddresses(addresses) {
  let parts = [];
  let processAddress = /* @__PURE__ */ __name((address, partCounter) => {
    if (partCounter) {
      parts.push(", ");
    }
    if (address.group) {
      let groupStart = `${address.name}:`;
      let groupEnd = `;`;
      parts.push(groupStart);
      address.group.forEach(processAddress);
      parts.push(groupEnd);
    } else {
      parts.push(formatTextAddress(address));
    }
  }, "processAddress");
  addresses.forEach(processAddress);
  return parts.join("");
}
__name(formatTextAddresses, "formatTextAddresses");
function formatHtmlAddress(address) {
  return `<a href="mailto:${escapeHtml(address.address)}" class="postal-email-address">${escapeHtml(address.name || `<${address.address}>`)}</a>`;
}
__name(formatHtmlAddress, "formatHtmlAddress");
function formatHtmlAddresses(addresses) {
  let parts = [];
  let processAddress = /* @__PURE__ */ __name((address, partCounter) => {
    if (partCounter) {
      parts.push('<span class="postal-email-address-separator">, </span>');
    }
    if (address.group) {
      let groupStart = `<span class="postal-email-address-group">${escapeHtml(address.name)}:</span>`;
      let groupEnd = `<span class="postal-email-address-group">;</span>`;
      parts.push(groupStart);
      address.group.forEach(processAddress);
      parts.push(groupEnd);
    } else {
      parts.push(formatHtmlAddress(address));
    }
  }, "processAddress");
  addresses.forEach(processAddress);
  return parts.join(" ");
}
__name(formatHtmlAddresses, "formatHtmlAddresses");
function foldLines(str, lineLength, afterSpace) {
  str = (str || "").toString();
  lineLength = lineLength || 76;
  let pos = 0, len = str.length, result = "", line, match2;
  while (pos < len) {
    line = str.slice(pos, pos + lineLength);
    if (line.length < lineLength) {
      result += line;
      break;
    }
    if (match2 = line.match(/^[^\n\r]*(\r?\n|\r)/)) {
      line = match2[0];
      result += line;
      pos += line.length;
      continue;
    } else if ((match2 = line.match(/(\s+)[^\s]*$/)) && match2[0].length - (afterSpace ? (match2[1] || "").length : 0) < line.length) {
      line = line.slice(0, line.length - (match2[0].length - (afterSpace ? (match2[1] || "").length : 0)));
    } else if (match2 = str.slice(pos + line.length).match(/^[^\s]+(\s*)/)) {
      line = line + match2[0].slice(0, match2[0].length - (!afterSpace ? (match2[1] || "").length : 0));
    }
    result += line;
    pos += line.length;
    if (pos < len) {
      result += "\r\n";
    }
  }
  return result;
}
__name(foldLines, "foldLines");
function formatTextHeader(message) {
  let rows = [];
  if (message.from) {
    rows.push({ key: "From", val: formatTextAddresses([message.from]) });
  }
  if (message.subject) {
    rows.push({ key: "Subject", val: message.subject });
  }
  if (message.date) {
    rows.push({ key: "Date", val: formatDate(message.date) });
  }
  if (message.to && message.to.length) {
    rows.push({ key: "To", val: formatTextAddresses(message.to) });
  }
  if (message.cc && message.cc.length) {
    rows.push({ key: "Cc", val: formatTextAddresses(message.cc) });
  }
  if (message.bcc && message.bcc.length) {
    rows.push({ key: "Bcc", val: formatTextAddresses(message.bcc) });
  }
  let maxKeyLength = rows.map((r) => r.key.length).reduce((acc, cur) => {
    return cur > acc ? cur : acc;
  }, 0);
  const lines = rows.flatMap((row) => {
    let sepLen = maxKeyLength - row.key.length;
    let prefix = `${row.key}: ${" ".repeat(sepLen)}`;
    let emptyPrefix = `${" ".repeat(row.key.length + 1)} ${" ".repeat(sepLen)}`;
    let foldedLines = foldLines(row.val, 80, true).split(/\r?\n/).map((line) => line.trim());
    return foldedLines.map((line, i) => `${i ? emptyPrefix : prefix}${line}`);
  });
  let maxLineLength = lines.map((r) => r.length).reduce((acc, cur) => {
    return cur > acc ? cur : acc;
  }, 0);
  let lineMarker = "-".repeat(maxLineLength);
  let template = `
${lineMarker}
${lines.join("\n")}
${lineMarker}
`;
  return template;
}
__name(formatTextHeader, "formatTextHeader");
function formatHtmlHeader(message) {
  let rows = [];
  if (message.from) {
    rows.push(
      // through the plural formatter, because `From:` may hold RFC 5322 group syntax
      // and a group has no address of its own
      `<div class="postal-email-header-key">From</div><div class="postal-email-header-value">${formatHtmlAddresses([message.from])}</div>`
    );
  }
  if (message.subject) {
    rows.push(`<div class="postal-email-header-key">Subject</div><div class="postal-email-header-value postal-email-header-subject">${escapeHtml(message.subject)}</div>`);
  }
  if (message.date) {
    rows.push(`<div class="postal-email-header-key">Date</div><div class="postal-email-header-value postal-email-header-date" data-date="${escapeHtml(message.date)}">${escapeHtml(formatDate(message.date))}</div>`);
  }
  if (message.to && message.to.length) {
    rows.push(`<div class="postal-email-header-key">To</div><div class="postal-email-header-value">${formatHtmlAddresses(message.to)}</div>`);
  }
  if (message.cc && message.cc.length) {
    rows.push(`<div class="postal-email-header-key">Cc</div><div class="postal-email-header-value">${formatHtmlAddresses(message.cc)}</div>`);
  }
  if (message.bcc && message.bcc.length) {
    rows.push(`<div class="postal-email-header-key">Bcc</div><div class="postal-email-header-value">${formatHtmlAddresses(message.bcc)}</div>`);
  }
  let template = `<div class="postal-email-header">${rows.length ? '<div class="postal-email-header-row">' : ""}${rows.join('</div>\n<div class="postal-email-header-row">')}${rows.length ? "</div>" : ""}</div>`;
  return template;
}
__name(formatHtmlHeader, "formatHtmlHeader");

// node_modules/postal-mime/dist/esm/address-parser.js
var HAS_WHITESPACE = /\s/;
var QUOTED_LOCAL_ADDR = /^("(?:[^"\\]|\\[\s\S])*"@\S+)(?:\s+([\s\S]+))?$/;
var ADDR_SPEC = /^[^@\s]+@[^@\s]+$/;
var LOOSE_ADDR_SPEC = /^[^@\s]+@\S+$/;
var LOOSE_TEXT_ADDR = /\s*\b[^@\s]+@[^\s]+\b\s*/y;
function quoteLocalPart(address) {
  const lastAt = address.lastIndexOf("@");
  if (lastAt < 0) {
    return address;
  }
  const user = address.substring(0, lastAt);
  if (/^[^\s"(),:;<>@[\\\]]+$/.test(user) || /^"(?:[^"\\]|\\[\s\S])*"$/.test(user)) {
    return address;
  }
  return '"' + user.replace(/["\\]/g, "\\$&") + '"@' + address.substring(lastAt + 1);
}
__name(quoteLocalPart, "quoteLocalPart");
function isSpaceCode(code) {
  return code === 32 || code >= 9 && code <= 13 || code === 160 || code === 5760 || code >= 8192 && code <= 8202 || code === 8232 || code === 8233 || code === 8239 || code === 8287 || code === 12288 || code === 65279;
}
__name(isSpaceCode, "isSpaceCode");
function isWordCode(code) {
  return code >= 48 && code <= 57 || code >= 65 && code <= 90 || code >= 97 && code <= 122 || code === 95;
}
__name(isWordCode, "isWordCode");
function isBoundary(text, at) {
  return isWordCode(text.charCodeAt(at - 1)) !== isWordCode(text.charCodeAt(at));
}
__name(isBoundary, "isBoundary");
function indexOfAt(text, from, to) {
  for (let i = from; i < to; i++) {
    if (text.charCodeAt(i) === 64) {
      return i;
    }
  }
  return -1;
}
__name(indexOfAt, "indexOfAt");
function looseAddressStart(text) {
  const len = text.length;
  let pos = 0;
  while (pos < len) {
    while (pos < len && isSpaceCode(text.charCodeAt(pos))) {
      pos++;
    }
    if (pos >= len) {
      break;
    }
    const runStart = pos;
    let runEnd = pos;
    while (runEnd < len && !isSpaceCode(text.charCodeAt(runEnd))) {
      runEnd++;
    }
    let at = indexOfAt(text, runStart, runEnd);
    if (at >= 0) {
      let lastBoundary = -1;
      for (let k = runEnd; k > runStart; k--) {
        if (isBoundary(text, k)) {
          lastBoundary = k;
          break;
        }
      }
      let atomStart = runStart;
      while (lastBoundary >= 0 && at >= 0) {
        if (at > atomStart && runEnd > at + 1 && lastBoundary > at + 1) {
          for (let start = atomStart; start < at; start++) {
            if (isBoundary(text, start)) {
              if (start > runStart) {
                return start;
              }
              let padded = runStart;
              while (padded > 0 && isSpaceCode(text.charCodeAt(padded - 1))) {
                padded--;
              }
              return padded;
            }
          }
        }
        atomStart = at + 1;
        at = indexOfAt(text, atomStart, runEnd);
      }
    }
    pos = runEnd;
  }
  return -1;
}
__name(looseAddressStart, "looseAddressStart");
function recoverAddrSpec(address, text) {
  if (!HAS_WHITESPACE.test(address)) {
    return { address, text };
  }
  let rest;
  const quoted = address.match(QUOTED_LOCAL_ADDR);
  if (quoted) {
    if (!quoted[2]) {
      return { address, text };
    }
    address = quoted[1];
    rest = [quoted[2]];
  } else {
    if (address.indexOf('"') >= 0) {
      return { address, text };
    }
    const parts = address.split(/\s+/);
    let addrIndex = parts.findIndex((part) => ADDR_SPEC.test(part));
    if (addrIndex < 0) {
      addrIndex = parts.findIndex((part) => LOOSE_ADDR_SPEC.test(part));
    }
    if (addrIndex < 0) {
      return { address, text };
    }
    address = parts.splice(addrIndex, 1)[0];
    rest = parts;
  }
  return {
    address,
    text: [text, ...rest].filter((part) => part).join(" ")
  };
}
__name(recoverAddrSpec, "recoverAddrSpec");
function stripAddressComments(address) {
  const comments = [];
  let result = "";
  let comment = "";
  let depth = 0;
  let closer = "";
  let lastChar = "";
  for (let i = 0, len = address.length; i < len; i++) {
    const chr = address.charAt(i);
    if (depth) {
      if (chr === "\\" && i < len - 1) {
        comment += address.charAt(++i);
      } else if (chr === "(") {
        depth++;
        comment += chr;
      } else if (chr === ")" && !--depth) {
        comments.push(comment.trim());
        comment = "";
        if (lastChar !== "@" && address.charAt(i + 1) !== "@") {
          result += " ";
          lastChar = " ";
        }
      } else {
        comment += chr;
      }
      continue;
    }
    if (closer) {
      if (chr === "\\" && closer === '"' && i < len - 1) {
        result += chr + address.charAt(++i);
        lastChar = address.charAt(i);
        continue;
      }
      if (chr === closer) {
        closer = "";
      }
    } else if (chr === '"') {
      closer = '"';
    } else if (chr === "[") {
      closer = "]";
    } else if (chr === "(") {
      depth = 1;
      continue;
    }
    result += chr;
    lastChar = chr;
  }
  if (depth) {
    comments.push(comment.trim());
  }
  return { address: result.trim(), comments: comments.filter((text) => text) };
}
__name(stripAddressComments, "stripAddressComments");
function hasAngleAddress(text) {
  let start = -1;
  let at = -1;
  for (let i = 0; i < text.length; i++) {
    const chr = text.charAt(i);
    if (chr === "<") {
      start = i + 1;
      at = -1;
    } else if (chr === ">") {
      if (at >= 0 && at < i - 1) {
        return true;
      }
      start = -1;
      at = -1;
    } else if (chr === "@" && start >= 0 && at < 0 && i > start) {
      at = i;
    }
  }
  return false;
}
__name(hasAngleAddress, "hasAngleAddress");
function _handleAddress(tokens, depth) {
  let isGroup = false;
  let state = "text";
  let addresses = [];
  let data = {
    address: [],
    comment: [],
    group: [],
    text: [],
    textWasQuoted: []
    // Track which text tokens came from inside quotes
  };
  let i;
  let len;
  let insideQuotes = false;
  const lastChars = { address: "", comment: "", group: "", text: "" };
  for (i = 0, len = tokens.length; i < len; i++) {
    let token = tokens[i];
    let prevToken = i ? tokens[i - 1] : null;
    if (token.type === "operator") {
      switch (token.value) {
        case "<":
          state = "address";
          insideQuotes = false;
          break;
        case "(":
          state = "comment";
          insideQuotes = false;
          break;
        case ":":
          state = "group";
          isGroup = true;
          insideQuotes = false;
          break;
        case '"':
          insideQuotes = !insideQuotes;
          state = "text";
          break;
        default:
          state = "text";
          insideQuotes = false;
          break;
      }
    } else if (token.value) {
      const prevPrevToken = i > 1 ? tokens[i - 2] : null;
      const opensAfterEmptyQuotedString = prevToken?.type === "operator" && prevToken.value === '"' && !!prevToken.noBreak && prevPrevToken?.type === "operator" && prevPrevToken.value === '"';
      if (state === "address") {
        token.value = token.value.replace(/^[^<]*<\s*/, "");
      }
      const joins = prevToken && prevToken.noBreak && data[state].length && (prevToken.value !== ")" || lastChars[state] === "@" || token.value.charAt(0) === "@");
      if (joins) {
        data[state][data[state].length - 1] += token.value;
        if (state === "text" && insideQuotes) {
          data.textWasQuoted[data.textWasQuoted.length - 1] = true;
        }
      } else {
        data[state].push(token.value);
        if (state === "text") {
          data.textWasQuoted.push(insideQuotes || opensAfterEmptyQuotedString);
        }
      }
      lastChars[state] = token.value.charAt(token.value.length - 1);
    }
  }
  if (!data.text.length && data.comment.length) {
    data.text = data.comment;
    data.comment = [];
  }
  if (isGroup) {
    const text = data.text.join(" ");
    let groupMembers = [];
    if (data.group.length) {
      let parsedGroup = parseAddressList2(data.group.join(","), depth + 1);
      parsedGroup.forEach((member) => {
        if (member.group) {
          for (const nestedMember of member.group) {
            groupMembers.push(nestedMember);
          }
        } else {
          groupMembers.push(member);
        }
      });
    }
    addresses.push({
      name: decodeWords(text),
      group: groupMembers
    });
  } else {
    const addressComments = [];
    const addressParts = [];
    for (const part of data.address) {
      if (part.indexOf("(") < 0) {
        addressParts.push(part);
        continue;
      }
      const stripped = stripAddressComments(part);
      for (const comment of stripped.comments) {
        addressComments.push(comment);
      }
      if (stripped.address) {
        addressParts.push(stripped.address);
      }
    }
    data.address = addressParts;
    if (!data.address.length && data.text.length) {
      for (i = data.text.length - 1; i >= 0; i--) {
        if (!data.textWasQuoted[i] && ADDR_SPEC.test(data.text[i])) {
          data.address = data.text.splice(i, 1);
          data.textWasQuoted.splice(i, 1);
          break;
        }
      }
      if (!data.address.length) {
        for (i = data.text.length - 1; i >= 0; i--) {
          if (!data.textWasQuoted[i]) {
            const part = data.text[i];
            const start = looseAddressStart(part);
            if (start >= 0) {
              LOOSE_TEXT_ADDR.lastIndex = start;
              const match2 = LOOSE_TEXT_ADDR.exec(part);
              if (match2) {
                data.address = [match2[0].trim()];
                data.text[i] = (part.slice(0, start) + " " + part.slice(start + match2[0].length)).trim();
                break;
              }
            }
            data.text[i] = part.trim();
          }
        }
      }
    }
    if (!data.text.length && data.comment.length) {
      data.text = data.comment;
      data.comment = [];
    }
    if (data.address.length > 1) {
      data.text = data.text.concat(data.address.splice(1));
    }
    const addressFromQuotedText = !data.address.length && data.textWasQuoted.some((wasQuoted) => wasQuoted);
    let text = data.text.join(" ");
    let addressValue = data.address.join(" ");
    if (!addressValue && isEncodedWordsOnly(text.trim())) {
      const decodedText = decodeWords(text);
      if (!addressFromQuotedText && hasAngleAddress(decodedText)) {
        const parsedSubAddresses = parseAddressList2(decodedText, depth + 1);
        if (parsedSubAddresses.length) {
          return parsedSubAddresses;
        }
      }
      return [{ address: "", name: decodedText }];
    }
    if (addressFromQuotedText && text.indexOf("@") >= 0) {
      addressValue = quoteLocalPart(text);
      text = "";
    }
    ({ address: addressValue, text } = recoverAddrSpec(addressValue, text));
    if (!text && addressComments.length) {
      text = addressComments.join(" ");
    }
    const rawName = text || addressValue || "";
    const address = {
      address: addressValue || text || "",
      name: decodeWords(rawName)
    };
    if (address.address === rawName || address.address === address.name) {
      if (address.address.match(/@/)) {
        address.name = "";
      } else {
        address.address = "";
      }
    }
    addresses.push(address);
  }
  return addresses;
}
__name(_handleAddress, "_handleAddress");
var Tokenizer = class {
  static {
    __name(this, "Tokenizer");
  }
  /**
   * @param str Address field string
   */
  constructor(str) {
    this.str = (str || "").toString();
    this.operatorCurrent = "";
    this.operatorExpecting = "";
    this.node = null;
    this.escaped = false;
    this.inDomainLiteral = false;
    this.afterAt = false;
    this.list = [];
    this.operators = {
      '"': '"',
      "(": ")",
      "<": ">",
      ",": "",
      ":": ";",
      // Semicolons are not a legal delimiter per the RFC2822 grammar other
      // than for terminating a group, but they are also not valid for any
      // other use in this context.  Given that some mail clients have
      // historically allowed the semicolon as a delimiter equivalent to the
      // comma in their UI, it makes sense to treat them the same as a comma
      // when used outside of a group.
      ";": ""
    };
  }
  /**
   * Tokenizes the original input string
   *
   * @return An array of operator|text tokens
   */
  tokenize() {
    let list = [];
    for (let i = 0, len = this.str.length; i < len; i++) {
      let chr = this.str.charAt(i);
      let nextChr = i < len - 1 ? this.str.charAt(i + 1) : null;
      this.checkChar(chr, nextChr);
    }
    this.list.forEach((node) => {
      node.value = (node.value || "").toString().trim();
      if (node.value) {
        list.push(node);
      }
    });
    return list;
  }
  /**
   * Checks if a character is an operator or text and acts accordingly
   *
   * @param chr Character from the address field
   * @param nextChr The character that follows, or null at the end of the field
   */
  checkChar(chr, nextChr) {
    if (!this.escaped && !this.operatorExpecting) {
      if (!this.inDomainLiteral && chr === "[" && this.afterAt) {
        this.inDomainLiteral = true;
      } else if (this.inDomainLiteral && (chr === "]" || chr === "," || chr === ";")) {
        this.inDomainLiteral = false;
      }
    }
    if (this.escaped) {
    } else if (chr === this.operatorExpecting) {
      this.node = {
        type: "operator",
        value: chr
      };
      if (nextChr && ![" ", "	", "\r", "\n", ",", ";"].includes(nextChr)) {
        this.node.noBreak = true;
      }
      this.list.push(this.node);
      this.node = null;
      if (chr !== ")") {
        this.afterAt = false;
      }
      this.operatorExpecting = "";
      this.escaped = false;
      return;
    } else if (!this.operatorExpecting && !(this.inDomainLiteral && chr === ":") && chr in this.operators) {
      this.node = {
        type: "operator",
        value: chr
      };
      this.list.push(this.node);
      this.node = null;
      if (chr !== "(") {
        this.afterAt = false;
      }
      this.operatorExpecting = this.operators[chr];
      this.escaped = false;
      return;
    } else if ((this.operatorExpecting === '"' || this.operatorExpecting === ")") && chr === "\\") {
      this.escaped = true;
      return;
    }
    if (!this.node) {
      this.node = {
        type: "text",
        value: ""
      };
      this.list.push(this.node);
    }
    if (chr === "\n") {
      chr = " ";
    }
    if (chr.charCodeAt(0) >= 33 || [" ", "	"].includes(chr)) {
      this.node.value += chr;
      if (!this.operatorExpecting && chr !== " " && chr !== "	") {
        this.afterAt = chr === "@";
      }
    }
    this.escaped = false;
  }
};
var MAX_NESTED_GROUP_DEPTH = 50;
function parseAddressList2(str, depth) {
  if (depth > MAX_NESTED_GROUP_DEPTH) {
    return [];
  }
  let tokenizer = new Tokenizer(str);
  let tokens = tokenizer.tokenize();
  let addresses = [];
  let address = [];
  const parsedAddresses = [];
  tokens.forEach((token) => {
    if (token.type === "operator" && (token.value === "," || token.value === ";")) {
      if (address.length) {
        addresses.push(address);
      }
      address = [];
    } else {
      address.push(token);
    }
  });
  if (address.length) {
    addresses.push(address);
  }
  for (const tokens2 of addresses) {
    for (const address2 of _handleAddress(tokens2, depth)) {
      parsedAddresses.push(address2);
    }
  }
  const mergedAddresses = [];
  for (let i = parsedAddresses.length - 1; i >= 0; i--) {
    const current = parsedAddresses[i];
    const next = mergedAddresses.length ? mergedAddresses[mergedAddresses.length - 1] : null;
    if (next && current.address === "" && current.name && !current.group && next.address && next.name) {
      next.name = current.name + ", " + next.name;
    } else {
      mergedAddresses.push(current);
    }
  }
  return mergedAddresses.reverse();
}
__name(parseAddressList2, "parseAddressList");
function addressParser(str, options) {
  const parsedAddresses = parseAddressList2(str, 0);
  if (options && options.flatten) {
    let addresses = [];
    let walkAddressList = /* @__PURE__ */ __name((list) => {
      list.forEach((address) => {
        if (address.group) {
          return walkAddressList(address.group);
        } else {
          addresses.push(address);
        }
      });
    }, "walkAddressList");
    walkAddressList(parsedAddresses);
    return addresses;
  }
  return parsedAddresses;
}
__name(addressParser, "addressParser");
var address_parser_default = addressParser;

// node_modules/postal-mime/dist/esm/base64-encoder.js
function base64ArrayBuffer(arrayBuffer) {
  let base64 = "";
  const encodings = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  const bytes = new Uint8Array(arrayBuffer);
  const byteLength = bytes.byteLength;
  const byteRemainder = byteLength % 3;
  const mainLength = byteLength - byteRemainder;
  let a, b, c, d;
  let chunk;
  for (let i = 0; i < mainLength; i = i + 3) {
    chunk = bytes[i] << 16 | bytes[i + 1] << 8 | bytes[i + 2];
    a = (chunk & 16515072) >> 18;
    b = (chunk & 258048) >> 12;
    c = (chunk & 4032) >> 6;
    d = chunk & 63;
    base64 += encodings[a] + encodings[b] + encodings[c] + encodings[d];
  }
  if (byteRemainder === 1) {
    chunk = bytes[mainLength];
    a = (chunk & 252) >> 2;
    b = (chunk & 3) << 4;
    base64 += encodings[a] + encodings[b] + "==";
  } else if (byteRemainder === 2) {
    chunk = bytes[mainLength] << 8 | bytes[mainLength + 1];
    a = (chunk & 64512) >> 10;
    b = (chunk & 1008) >> 4;
    c = (chunk & 15) << 2;
    base64 += encodings[a] + encodings[b] + encodings[c] + "=";
  }
  return base64;
}
__name(base64ArrayBuffer, "base64ArrayBuffer");

// node_modules/postal-mime/dist/esm/postal-mime.js
function isReadableStream(value) {
  return !!value && typeof value.getReader === "function";
}
__name(isReadableStream, "isReadableStream");
function isBlob(value) {
  return value instanceof Blob || Object.prototype.toString.call(value) === "[object Blob]";
}
__name(isBlob, "isBlob");
function renderEntry(textEntry, textType, convert) {
  if (textEntry.type === "subMessage") {
    return textType === "html" ? formatHtmlHeader(textEntry.value) : formatTextHeader(textEntry.value);
  }
  if (!convert) {
    return textEntry.value;
  }
  return textType === "html" ? textToHtml(textEntry.value) : htmlToText2(textEntry.value);
}
__name(renderEntry, "renderEntry");
var LINE_FEED = new Uint8Array([10]);
var MAX_NESTING_DEPTH = 256;
var MAX_HEADERS_SIZE = 2 * 1024 * 1024;
var MAX_PART_COUNT = 1e4;
var MAX_RFC822_NESTING_DEPTH = 10;
function parseLimitOption(value, defaultValue, name) {
  if (value === void 0 || value === null) {
    return defaultValue;
  }
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new TypeError(`${name} must be a non-negative integer`);
  }
  return value;
}
__name(parseLimitOption, "parseLimitOption");
var PostalMime = class _PostalMime {
  static {
    __name(this, "PostalMime");
  }
  /**
   * Parses a raw email message
   *
   * @param buf Raw email message
   * @param options Parser options
   * @returns The parsed email
   */
  // async so that an invalid option rejects the returned promise instead of throwing
  // synchronously, which would escape a `.catch()` chain
  static async parse(buf, options) {
    const parser = new _PostalMime(options);
    return parser.parse(buf);
  }
  constructor(options) {
    this.options = options || {};
    this.mimeOptions = {
      maxNestingDepth: parseLimitOption(this.options.maxNestingDepth, MAX_NESTING_DEPTH, "maxNestingDepth"),
      maxHeadersSize: parseLimitOption(this.options.maxHeadersSize, MAX_HEADERS_SIZE, "maxHeadersSize"),
      maxPartCount: parseLimitOption(this.options.maxPartCount, MAX_PART_COUNT, "maxPartCount")
    };
    this.maxRfc822NestingDepth = parseLimitOption(this.options.maxRfc822NestingDepth, MAX_RFC822_NESTING_DEPTH, "maxRfc822NestingDepth");
    this.rfc822NestingDepth = 0;
    this.headerSize = 0;
    this.partCount = 0;
    this.root = this.currentNode = new MimeNode({
      postalMime: this,
      ...this.mimeOptions
    });
    this.boundaries = [];
    this.textContent = {};
    this.textMap = /* @__PURE__ */ new Map();
    this.textTypes = /* @__PURE__ */ new Set();
    this.attachments = [];
    this.forceRfc822Attachments = false;
    this.attachmentEncoding = (this.options.attachmentEncoding || "").toString().replace(/[-_\s]/g, "").trim().toLowerCase() || "arraybuffer";
    this.started = false;
  }
  /** @internal */
  async finalize() {
    await this.root.finalize();
  }
  /** @internal */
  async processLine(line, lineBreak, isFinal) {
    let boundaries = this.boundaries;
    if (boundaries.length && line.length > 2 && line[0] === 45 && line[1] === 45) {
      for (let i = boundaries.length - 1; i >= 0; i--) {
        let boundary2 = boundaries[i];
        if (line.length < boundary2.value.length + 2) {
          continue;
        }
        let boundaryMatches = true;
        for (let j = 0; j < boundary2.value.length; j++) {
          if (line[j + 2] !== boundary2.value[j]) {
            boundaryMatches = false;
            break;
          }
        }
        if (!boundaryMatches) {
          continue;
        }
        let boundaryEnd = boundary2.value.length + 2;
        let isTerminator = false;
        if (line.length >= boundary2.value.length + 4 && line[boundary2.value.length + 2] === 45 && line[boundary2.value.length + 3] === 45) {
          isTerminator = true;
          boundaryEnd = boundary2.value.length + 4;
        }
        let hasValidTrailing = true;
        for (let j = boundaryEnd; j < line.length; j++) {
          if (!isWsp(line[j])) {
            hasValidTrailing = false;
            break;
          }
        }
        if (!hasValidTrailing) {
          continue;
        }
        if (isTerminator) {
          await boundary2.node.finalize(true);
          this.currentNode = boundary2.node.parentNode || this.root;
        } else {
          await boundary2.node.finalizeChildNodes(true);
          this.currentNode = new MimeNode({
            postalMime: this,
            parentNode: boundary2.node,
            parentMultipartType: boundary2.node.contentType.multipart,
            ...this.mimeOptions
          });
        }
        if (isFinal) {
          return this.finalize();
        }
        return;
      }
    }
    if (this.currentNode.feed(line, lineBreak)) {
      return this.processLine(line, lineBreak, isFinal);
    }
    if (isFinal) {
      return this.finalize();
    }
  }
  // Reads the next line without its line break. The break itself, the exact bytes between
  // the line and the next one, is returned alongside, because the body decoders write it
  // back out: a part has to keep the line endings it was sent with, see PassThroughDecoder.
  /** @internal */
  readLine() {
    let startPos = this.readPos;
    let endPos = this.readPos;
    while (this.readPos < this.av.length) {
      const c = this.av[this.readPos++];
      if (c !== 13 && c !== 10) {
        endPos = this.readPos;
      }
      if (c === 10) {
        return {
          bytes: new Uint8Array(this.buf, startPos, endPos - startPos),
          lineBreak: this.av.subarray(endPos, this.readPos),
          done: this.readPos >= this.av.length
        };
      }
    }
    return {
      bytes: new Uint8Array(this.buf, startPos, endPos - startPos),
      lineBreak: LINE_FEED,
      done: this.readPos >= this.av.length
    };
  }
  // Records a text part or a nested message under the node that selects it
  /** @internal */
  addTextEntry(selector, textType, item) {
    let textEntry = this.textMap.get(selector);
    if (!textEntry) {
      textEntry = {};
      this.textMap.set(selector, textEntry);
    }
    const entries = textEntry[textType] || [];
    textEntry[textType] = entries;
    entries.push(item);
    this.textTypes.add(textType);
  }
  // Sorts every leaf of the tree into text content, nested messages and attachments.
  // `alternative` is the closest enclosing multipart/alternative, if any: its text parts
  // are collected under the alternative itself, so that the body is assembled from one
  // representation of it rather than from every one. `related` tells whether the part
  // sits inside a multipart/related, where a Content-ID makes it an inline resource
  /** @internal */
  async collectNode(node, alternative, related) {
    if (!node.contentType.multipart) {
      const inlineRfc822 = this.isInlineMessageRfc822(node);
      const rfc822DepthExceeded = inlineRfc822 && this.rfc822NestingDepth >= this.maxRfc822NestingDepth;
      if (inlineRfc822 && !rfc822DepthExceeded) {
        await this.collectSubMessage(node);
      } else if (this.isInlineTextNode(node)) {
        const textType = node.contentType.parsed.value === "text/html" ? "html" : "plain";
        this.addTextEntry(alternative || node, textType, { type: "text", value: node.getTextContent() });
      } else if (node.content) {
        this.collectAttachment(node, node.content, related, rfc822DepthExceeded);
      }
    } else if (node.contentType.multipart === "alternative") {
      alternative = node;
    } else if (node.contentType.multipart === "related") {
      related = true;
    }
    for (let childNode of node.childNodes) {
      await this.collectNode(childNode, alternative, related);
    }
  }
  // Parses an inline message/rfc822 part with a nested parser and takes over its text
  // parts and attachments
  /** @internal */
  async collectSubMessage(node) {
    const subParser = new _PostalMime({
      // Only the limits are inherited. Options that decide how a part
      // is classified stay with the parser that was configured.
      ...this.mimeOptions,
      maxRfc822NestingDepth: this.maxRfc822NestingDepth,
      // attachments are encoded by the parent parser, keep raw buffers here
      attachmentEncoding: "arraybuffer"
    });
    subParser.rfc822NestingDepth = this.rfc822NestingDepth + 1;
    const subMessage = node.subMessage = await subParser.parse(node.content || new ArrayBuffer(0));
    if (subMessage.text || !subMessage.html) {
      this.addTextEntry(node, "plain", { type: "subMessage", value: subMessage });
    }
    if (subMessage.html) {
      this.addTextEntry(node, "html", { type: "subMessage", value: subMessage });
    }
    subParser.textMap.forEach((subTextEntry, subTextNode) => {
      this.textMap.set(subTextNode, subTextEntry);
    });
    for (let attachment of subMessage.attachments) {
      this.attachments.push(attachment);
    }
  }
  /** @internal */
  collectAttachment(node, content, related, rfc822DepthExceeded) {
    const filename = node.contentDisposition.parsed.params.filename || node.contentType.parsed.params.name || null;
    const attachment = {
      // An RFC 2231 filename is percent decoded without folding, since the same decoder
      // produces the boundary, so the fold happens here, see foldLineBreaks
      filename: filename ? decodeWords(foldLineBreaks(filename)) : null,
      mimeType: node.contentType.parsed.value,
      disposition: node.contentDisposition.parsed.value || null
    };
    if (related && node.contentId && !rfc822DepthExceeded) {
      attachment.related = true;
    }
    if (rfc822DepthExceeded) {
      attachment.rfc822DepthExceeded = true;
    }
    if (node.contentDescription) {
      attachment.description = decodeWords(node.contentDescription);
    }
    if (node.contentId) {
      attachment.contentId = node.contentId;
    }
    switch (node.contentType.parsed.value) {
      // Special handling for calendar events
      case "text/calendar":
      case "application/ics": {
        if (node.contentType.parsed.params.method) {
          attachment.method = node.contentType.parsed.params.method.toString().toUpperCase().trim();
        }
        const decodedText = node.getTextContent();
        let end = decodedText.length;
        while (end > 0 && decodedText.charCodeAt(end - 1) === 10) {
          end--;
        }
        attachment.content = textEncoder.encode(decodedText.slice(0, end) + "\n");
        break;
      }
      // Regular attachments
      default:
        attachment.content = content;
    }
    this.attachments.push(attachment);
  }
  // Joins the collected text parts into the plain and html bodies
  /** @internal */
  renderTextContent() {
    const textContent = {};
    this.textMap.forEach((mapEntry) => {
      this.textTypes.forEach((textType) => {
        const output = textContent[textType] || [];
        textContent[textType] = output;
        const ownEntries = mapEntry[textType];
        const entries = ownEntries || mapEntry[textType === "html" ? "plain" : "html"] || [];
        for (const textEntry of entries) {
          output.push(renderEntry(textEntry, textType, !ownEntries));
        }
      });
    });
    Object.keys(textContent).forEach((textType) => {
      this.textContent[textType] = textContent[textType].join("\n");
    });
  }
  /** @internal */
  isInlineTextNode(node) {
    if (node.contentDisposition.parsed.value === "attachment") {
      return false;
    }
    switch (node.contentType.parsed.value) {
      case "text/html":
      case "text/plain":
        return true;
      case "text/calendar":
      case "text/csv":
      default:
        return false;
    }
  }
  /** @internal */
  isInlineMessageRfc822(node) {
    if (this.forceRfc822Attachments || node.contentType.parsed.value !== "message/rfc822") {
      return false;
    }
    let disposition = node.contentDisposition.parsed.value || (this.options.rfc822Attachments ? "attachment" : "inline");
    return disposition === "inline";
  }
  // A delivery status or feedback report carries the offending message as a part. It is
  // evidence rather than content, so it is not inlined into the body of the report
  /** @internal */
  hasReportParts() {
    let found = false;
    let walk = /* @__PURE__ */ __name((node) => {
      if (!node.contentType.multipart) {
        if (["message/delivery-status", "message/feedback-report"].includes(node.contentType.parsed.value)) {
          found = true;
        }
      }
      for (let childNode of node.childNodes) {
        walk(childNode);
      }
    }, "walk");
    walk(this.root);
    return found;
  }
  /** @internal */
  async resolveStream(stream) {
    let chunkLen = 0;
    let chunks = [];
    const reader = stream.getReader();
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      chunks.push(value);
      chunkLen += value.length;
    }
    const result = new Uint8Array(chunkLen);
    let chunkPointer = 0;
    for (let chunk of chunks) {
      result.set(chunk, chunkPointer);
      chunkPointer += chunk.length;
    }
    return result;
  }
  /** @internal */
  async resolveInput(buf) {
    let input = buf;
    if (isReadableStream(input)) {
      input = await this.resolveStream(input);
    }
    input = input || new ArrayBuffer(0);
    if (typeof input === "string") {
      input = textEncoder.encode(input);
    }
    if (isBlob(input)) {
      input = await blobToArrayBuffer(input);
    }
    if (ArrayBuffer.isView(input)) {
      return input.buffer.slice(input.byteOffset, input.byteOffset + input.byteLength);
    }
    return input;
  }
  // Properties are added in the order the output has always had them, so the required
  // ones are filled in below rather than in the literal
  /** @internal */
  buildMessage() {
    const headers = this.root.headers;
    const message = {
      headers: headers.map((entry) => ({
        key: entry.key,
        originalKey: entry.originalKey,
        value: entry.value
      }))
    };
    for (const key of ["from", "sender"]) {
      const addressHeader = headers.find((line) => line.key === key);
      if (addressHeader && addressHeader.value) {
        const addresses = address_parser_default(addressHeader.value);
        if (addresses && addresses.length) {
          message[key] = addresses[0];
        }
      }
    }
    for (const [key, camelKey] of [
      ["delivered-to", "deliveredTo"],
      ["return-path", "returnPath"]
    ]) {
      const addressHeader = headers.find((line) => line.key === key);
      if (addressHeader && addressHeader.value) {
        const addresses = address_parser_default(addressHeader.value);
        if (addresses && addresses.length && addresses[0].address) {
          message[camelKey] = addresses[0].address;
        }
      }
    }
    for (const [key, camelKey] of [
      ["to", "to"],
      ["cc", "cc"],
      ["bcc", "bcc"],
      ["reply-to", "replyTo"]
    ]) {
      const addresses = [];
      for (const entry of headers) {
        if (entry.key === key && entry.value) {
          for (const address of address_parser_default(entry.value)) {
            addresses.push(address);
          }
        }
      }
      if (addresses.length) {
        message[camelKey] = addresses;
      }
    }
    for (const [key, camelKey] of [
      ["subject", "subject"],
      ["message-id", "messageId"],
      ["in-reply-to", "inReplyTo"],
      ["references", "references"]
    ]) {
      const header = headers.find((line) => line.key === key);
      if (header && header.value) {
        message[camelKey] = decodeWords(header.value);
      }
    }
    let dateHeader = headers.find((line) => line.key === "date");
    if (dateHeader) {
      let date = new Date(dateHeader.value);
      message.date = date.toString() === "Invalid Date" ? dateHeader.value : date.toISOString();
    }
    if (this.textContent.html) {
      message.html = this.textContent.html;
    }
    if (this.textContent.plain) {
      message.text = this.textContent.plain;
    }
    message.attachments = this.attachments;
    message.headerLines = this.root.rawHeaderLines.slice();
    return message;
  }
  // Every attachment holds binary content at this point, since nested parsers are
  // created with the arraybuffer encoding. The string check narrows the public content
  // type rather than handling a reachable case
  /** @internal */
  encodeAttachments() {
    switch (this.attachmentEncoding) {
      case "arraybuffer":
        break;
      case "base64":
        for (let attachment of this.attachments) {
          if (attachment.content && typeof attachment.content !== "string") {
            attachment.content = base64ArrayBuffer(attachment.content);
            attachment.encoding = "base64";
          }
        }
        break;
      case "utf8": {
        let attachmentDecoder = new TextDecoder("utf8");
        for (let attachment of this.attachments) {
          if (attachment.content && typeof attachment.content !== "string") {
            attachment.content = attachmentDecoder.decode(attachment.content);
            attachment.encoding = "utf8";
          }
        }
        break;
      }
      default:
        throw new Error("Unknown attachment encoding");
    }
  }
  /**
   * Parses a raw email message. A parser instance can be used once
   *
   * @param buf Raw email message
   * @returns The parsed email
   */
  async parse(buf) {
    if (this.started) {
      throw new Error("Can not reuse parser, create a new PostalMime object");
    }
    this.started = true;
    this.buf = await this.resolveInput(buf);
    this.av = new Uint8Array(this.buf);
    this.readPos = 0;
    while (this.readPos < this.av.length) {
      const line = this.readLine();
      await this.processLine(line.bytes, line.lineBreak, line.done);
    }
    this.forceRfc822Attachments = Boolean(this.options.forceRfc822Attachments) || this.hasReportParts();
    await this.collectNode(this.root, false, false);
    this.renderTextContent();
    const message = this.buildMessage();
    this.encodeAttachments();
    return message;
  }
};

// src/inbound.ts
function flattenAddresses(list) {
  if (!list) return [];
  const items = Array.isArray(list) ? list : [list];
  const out = [];
  for (const item of items) {
    if (item.group) {
      for (const m of item.group) if (m.address) out.push({ name: m.name || null, address: m.address });
    } else if (item.address) {
      out.push({ name: item.name || null, address: item.address });
    }
  }
  return out;
}
__name(flattenAddresses, "flattenAddresses");
function headerValue(parsed, fallback, name) {
  const lower = name.toLowerCase();
  const fromParsed = parsed?.headers.find((h) => h.key === lower)?.value;
  const value = fromParsed ?? fallback.get(name);
  return value && value.trim() ? value.trim() : null;
}
__name(headerValue, "headerValue");
function contentIdOf(value) {
  if (!value) return null;
  const inner = value.trim().replace(/^<+/, "").replace(/>+$/, "").trim();
  return inner || null;
}
__name(contentIdOf, "contentIdOf");
function attachmentBytes(content) {
  if (typeof content === "string") return new TextEncoder().encode(content);
  return content instanceof Uint8Array ? content : new Uint8Array(content);
}
__name(attachmentBytes, "attachmentBytes");
async function handleInbound(message, env, _ctx) {
  const config = await getConfig(env.DB);
  if (message.rawSize > config.maxInboundBytes) {
    message.setReject("Message too large");
    return;
  }
  const mailbox = normalizeEmail(message.to);
  if (config.domains.length > 0 && !belongsToDomains(mailbox, config.domains)) {
    message.setReject("Unknown recipient");
    return;
  }
  const raw = await new Response(message.raw).arrayBuffer();
  const id = ulid();
  await env.MAIL.put(rawKey(id), raw, { httpMetadata: { contentType: "message/rfc822" } });
  let parsed = null;
  try {
    parsed = await PostalMime.parse(raw);
  } catch (err) {
    console.error("postal-mime could not parse message", id, err);
  }
  const receivedAt = (/* @__PURE__ */ new Date()).toISOString();
  const fromList = flattenAddresses(parsed?.from);
  const from = fromList[0] ?? { name: null, address: message.from };
  const to = flattenAddresses(parsed?.to);
  const cc = flattenAddresses(parsed?.cc);
  const replyTo = flattenAddresses(parsed?.replyTo);
  const subject = parsed?.subject ?? message.headers.get("Subject") ?? "";
  const messageIdHeader = parsed?.messageId ?? message.headers.get("Message-ID");
  const messageId = parseMessageIds(messageIdHeader)[0] ?? null;
  const inReplyTo = parseMessageIds(parsed?.inReplyTo ?? message.headers.get("In-Reply-To"))[0] ?? null;
  const references = parseMessageIds(parsed?.references ?? message.headers.get("References"));
  const date = toIsoOrNull(parsed?.date ?? message.headers.get("Date")) ?? receivedAt;
  const text = parsed?.text ?? null;
  const html = parsed?.html ?? null;
  const candidates = [.../* @__PURE__ */ new Set([...inReplyTo ? [inReplyTo] : [], ...[...references].reverse()])];
  const threadId = await findThreadId(env.DB, candidates) ?? id;
  await env.MAIL.put(bodyKey(id), JSON.stringify({ text, html }), {
    httpMetadata: { contentType: "application/json; charset=utf-8" }
  });
  const attachments = [];
  const parts = parsed?.attachments ?? [];
  for (let n = 0; n < parts.length; n++) {
    const part = parts[n];
    const bytes = attachmentBytes(part.content);
    const mimeType = part.mimeType || "application/octet-stream";
    const contentId = contentIdOf(part.contentId);
    await env.MAIL.put(attKey(id, n), bytes, { httpMetadata: { contentType: mimeType } });
    attachments.push({
      idx: n,
      filename: part.filename?.trim() || `attachment-${n + 1}`,
      mimeType,
      size: bytes.byteLength,
      contentId,
      // Inline only when the HTML can reference it (cid:); clients such as Apple Mail mark real
      // attachments "inline" without a Content-ID.
      inline: contentId !== null && (part.disposition === "inline" || part.related === true)
    });
  }
  const record = {
    id,
    threadId,
    folder: "inbox",
    direction: "in",
    mailbox,
    domain: domainOf(mailbox),
    from,
    to,
    cc,
    replyTo,
    subject,
    snippet: makeSnippet(text, html),
    date,
    receivedAt,
    messageId,
    inReplyTo,
    references,
    read: false,
    hasAttachments: attachments.some((a) => !a.inline),
    size: message.rawSize || raw.byteLength,
    listUnsubscribe: headerValue(parsed, message.headers, "List-Unsubscribe")
  };
  await insertMessage(env.DB, record, attachments, {
    participants: participantsText(from, to, cc),
    body: bodyText(text, html)
  });
  const forwardTo = config.forwardCopies[mailbox];
  if (forwardTo) {
    try {
      await message.forward(forwardTo);
    } catch (err) {
      console.error(`Forward copy of ${id} to ${forwardTo} failed`, err);
    }
  }
}
__name(handleInbound, "handleInbound");

// src/index.ts
var index_default = {
  /** Checks the API key, applies the schema, then routes (see api.ts). */
  async fetch(request, env, _ctx) {
    return handleFetch(request, env);
  },
  async email(message, env, ctx) {
    await ensureSchema(env.DB);
    await handleInbound(message, env, ctx);
  },
  /**
   * Daily cron (set by the app): purge trash older than trashRetentionDays, prune send_log rows
   * older than 40 days and send_dedupe rows older than 1 day. D1 round-trips: schema 1 + config 1
   * + prune 1 + trash at most 30,
   * inside the Free plan's 50 per invocation (https://developers.cloudflare.com/d1/platform/limits/).
   */
  async scheduled(controller, env, _ctx) {
    await ensureSchema(env.DB);
    const now = controller.scheduledTime || Date.now();
    const config = await getConfig(env.DB);
    const pruned = await pruneSendTables(env.DB, now);
    const purged = await purgeExpiredTrash(env, config.trashRetentionDays, now);
    if (purged > 0 || pruned > 0) console.log(`Purged ${purged} trashed message(s), ${pruned} send log/dedupe row(s)`);
  }
};
export {
  index_default as default
};
