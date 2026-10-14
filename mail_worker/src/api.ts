// fetch() handler: the HTTP API in API.md.

import { isAuthorized, unauthorized } from "./auth";
import { deleteLogo, getLogo, LOGO_TYPE, listBrands, parseSignature, putLogo, putSignature, requireDomain } from "./brand";
import { getSendUsage } from "./budget";
import { listContacts } from "./contacts";
import { badRequest, errorJson, fromHttpError, HttpError, json, notFound, withBaseHeaders } from "./http";
import { ensureSchema } from "./schema";
import { sendMessage } from "./send";
import {
  attKey,
  bodyKey,
  getAttachmentRow,
  getAttachmentRows,
  getConfig,
  getThread,
  listMailboxes,
  listMessages,
  purgeMessages,
  putConfig,
  requireMessageRow,
  rowToAttachment,
  rowToSummary,
  syncChanges,
  updateMessages,
  validateConfigPatch,
  type FlagPatch,
} from "./store";
import { FOLDERS, type Env, type Folder, type MailConfig, type MessageDetail } from "./types";
import { isPlainObject, normalizeEmail } from "./util";
import { WORKER_VERSION } from "./version";

const DEFAULT_LIMIT = 50;
const MAX_LIMIT = 100;

type Handler = (ctx: RouteContext) => Promise<Response>;

interface RouteContext {
  request: Request;
  env: Env;
  url: URL;
  params: string[];
}

interface Route {
  pattern: (string | null)[]; // null = path parameter
  methods: Partial<Record<string, Handler>>;
}

const ROUTES: Route[] = [
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
  { pattern: ["v1", "brands", null, "logo"], methods: { GET: getLogoRoute, PUT: putLogoRoute, DELETE: deleteLogoRoute } },
];

function match(route: Route, parts: string[]): string[] | null {
  if (route.pattern.length !== parts.length) return null;
  const params: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const expected = route.pattern[i];
    const actual = parts[i]!;
    if (expected === null) params.push(actual);
    else if (expected !== actual) return null;
  }
  return params;
}

export async function handleFetch(request: Request, env: Env): Promise<Response> {
  if (!isAuthorized(request, env.MAIL_API_KEY)) return unauthorized();
  try {
    await ensureSchema(env.DB);
    const url = new URL(request.url);
    let parts: string[];
    try {
      parts = url.pathname.split("/").filter(Boolean).map(decodeURIComponent);
    } catch {
      throw notFound();
    }
    // Static segments win over parameters.
    const candidates = ROUTES.map((route) => ({ route, params: match(route, parts) }))
      .filter((c): c is { route: Route; params: string[] } => c.params !== null)
      .sort((a, b) => a.params.length - b.params.length);
    if (candidates.length === 0) throw notFound();
    const method = request.method.toUpperCase();
    const hit = candidates.find((c) => c.route.methods[method]);
    if (!hit) {
      const allowed = [...new Set(candidates.flatMap((c) => Object.keys(c.route.methods)))].join(", ");
      return errorJson(405, "method_not_allowed", `${method} is not allowed here`, {}, { Allow: allowed });
    }
    return await hit.route.methods[method]!({ request, env, url, params: hit.params });
  } catch (err) {
    if (err instanceof HttpError) return fromHttpError(err);
    console.error("Unhandled error", err);
    return errorJson(500, "internal_error", "Internal error");
  }
}

// ---- helpers ----------------------------------------------------------------------------------

async function readJson(request: Request): Promise<unknown> {
  const text = await request.text();
  if (!text.trim()) throw badRequest("A JSON body is required", "invalid_json");
  try {
    return JSON.parse(text) as unknown;
  } catch {
    throw badRequest("Body is not valid JSON", "invalid_json");
  }
}

function parseFolder(value: unknown, field = "folder"): Folder {
  if (typeof value !== "string" || !(FOLDERS as readonly string[]).includes(value)) {
    throw badRequest(`${field} must be one of ${FOLDERS.join(", ")}`);
  }
  return value as Folder;
}

function parseFlagPatch(body: Record<string, unknown>): FlagPatch {
  const patch: FlagPatch = {};
  if (body.read !== undefined) {
    if (typeof body.read !== "boolean") throw badRequest("read must be a boolean");
    patch.read = body.read;
  }
  if (body.starred !== undefined) {
    if (typeof body.starred !== "boolean") throw badRequest("starred must be a boolean");
    patch.starred = body.starred;
  }
  if (body.folder !== undefined) patch.folder = parseFolder(body.folder);
  return patch;
}

function parseLimit(value: string | null): number {
  if (value === null || value === "") return DEFAULT_LIMIT;
  const n = Number.parseInt(value, 10);
  if (!Number.isFinite(n) || n < 1) throw badRequest("limit must be a positive integer");
  return Math.min(n, MAX_LIMIT);
}

function flag(value: string | null): boolean {
  return value === "1";
}

function contentDisposition(filename: string): string {
  const ascii = filename.replace(/[^\x20-\x7e]/g, "_").replace(/["\\]/g, "_");
  const encoded = encodeURIComponent(filename).replace(/['()*]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase()}`);
  return `attachment; filename="${ascii}"; filename*=UTF-8''${encoded}`;
}

// ---- routes -----------------------------------------------------------------------------------

async function health({ env }: RouteContext): Promise<Response> {
  const config = await getConfig(env.DB);
  return json({
    version: WORKER_VERSION,
    time: new Date().toISOString(),
    domains: config.domains,
    sendingConfigured: typeof env.EMAIL?.send === "function",
    sendUsage: await getSendUsage(env.DB, config.monthlySendLimit),
  });
}

async function configResponse(db: D1Database, config: MailConfig): Promise<Response> {
  return json({ ...config, sendUsage: await getSendUsage(db, config.monthlySendLimit) });
}

async function getConfigRoute({ env }: RouteContext): Promise<Response> {
  return configResponse(env.DB, await getConfig(env.DB));
}

async function putConfigRoute({ request, env }: RouteContext): Promise<Response> {
  const patch = validateConfigPatch(await readJson(request));
  return configResponse(env.DB, await putConfig(env.DB, patch));
}

async function mailboxes({ env }: RouteContext): Promise<Response> {
  return json({ mailboxes: await listMailboxes(env.DB) });
}

async function listRoute({ env, url }: RouteContext): Promise<Response> {
  const q = url.searchParams;
  const folder = q.has("folder") && q.get("folder") !== "" ? parseFolder(q.get("folder")) : "inbox";
  const result = await listMessages(env.DB, {
    folder,
    mailbox: q.get("mailbox") ? normalizeEmail(q.get("mailbox")!) : undefined,
    domain: q.get("domain") ? q.get("domain")!.trim().toLowerCase() : undefined,
    q: q.get("q")?.trim() || undefined,
    unread: flag(q.get("unread")),
    starred: flag(q.get("starred")),
    cursor: q.get("cursor") || undefined,
    limit: parseLimit(q.get("limit")),
  });
  return json(result);
}

async function threadRoute({ env, params }: RouteContext): Promise<Response> {
  const messages = await getThread(env.DB, params[0]!);
  if (messages.length === 0) throw notFound(`Thread ${params[0]} not found`);
  return json({ messages });
}

async function detailRoute({ env, params }: RouteContext): Promise<Response> {
  const row = await requireMessageRow(env.DB, params[0]!);
  const [bodyObj, attRows] = await Promise.all([env.MAIL.get(bodyKey(row.id)), getAttachmentRows(env.DB, row.id)]);
  let text: string | null = null;
  let html: string | null = null;
  if (bodyObj) {
    try {
      const body = (await bodyObj.json()) as { text?: unknown; html?: unknown };
      text = typeof body.text === "string" ? body.text : null;
      html = typeof body.html === "string" ? body.html : null;
    } catch (err) {
      console.error(`Body of ${row.id} is unreadable`, err);
    }
  }
  const detail: MessageDetail = {
    ...rowToSummary(row),
    text,
    html,
    attachments: attRows.map(rowToAttachment),
    listUnsubscribe: row.list_unsubscribe,
  };
  return json(detail);
}

async function attachmentRoute({ env, params }: RouteContext): Promise<Response> {
  const row = await getAttachmentRow(env.DB, params[0]!);
  if (!row) throw notFound(`Attachment ${params[0]} not found`);
  const obj = await env.MAIL.get(attKey(row.message_id, row.idx));
  if (!obj) throw notFound(`Attachment ${row.id} content not found`);
  return new Response(obj.body, {
    headers: withBaseHeaders({
      "Content-Type": row.mime_type || "application/octet-stream",
      "Content-Length": String(obj.size),
      "Content-Disposition": contentDisposition(row.filename),
      "Content-Security-Policy": "sandbox",
    }),
  });
}

async function patchRoute({ request, env, params }: RouteContext): Promise<Response> {
  const body = await readJson(request);
  if (!isPlainObject(body)) throw badRequest("Body must be a JSON object");
  const patch = parseFlagPatch(body);
  const row = await requireMessageRow(env.DB, params[0]!);
  if (Object.keys(patch).length > 0) await updateMessages(env.DB, [row.id], patch);
  return json(rowToSummary(await requireMessageRow(env.DB, row.id)));
}

async function deleteRoute({ env, params }: RouteContext): Promise<Response> {
  const row = await requireMessageRow(env.DB, params[0]!);
  if (row.folder !== "trash") {
    await updateMessages(env.DB, [row.id], { folder: "trash" });
    return json({ result: "trashed" });
  }
  await purgeMessages(env, [row.id]);
  return json({ result: "purged" });
}

async function syncRoute({ env, url }: RouteContext): Promise<Response> {
  const sinceParam = url.searchParams.get("since");
  let since: number | null = null;
  if (sinceParam !== null && sinceParam !== "") {
    if (!/^\d{1,15}$/.test(sinceParam)) throw badRequest("since is not a valid cursor", "invalid_cursor");
    since = Number(sinceParam);
  }
  return json(await syncChanges(env.DB, since));
}

async function sendRoute({ request, env }: RouteContext): Promise<Response> {
  const body = await readJson(request);
  const config = await getConfig(env.DB);
  return json(await sendMessage(env, config, body));
}

async function contactsRoute({ env }: RouteContext): Promise<Response> {
  return json({ contacts: await listContacts(env.DB) });
}

async function brandsRoute({ env }: RouteContext): Promise<Response> {
  return json({ brands: await listBrands(env.DB, await getConfig(env.DB)) });
}

async function putBrandRoute({ request, env, params }: RouteContext): Promise<Response> {
  const domain = requireDomain(await getConfig(env.DB), params[0]!);
  return json(await putSignature(env.DB, domain, parseSignature(await readJson(request))));
}

async function getLogoRoute({ env, params }: RouteContext): Promise<Response> {
  const domain = requireDomain(await getConfig(env.DB), params[0]!);
  const bytes = await getLogo(env, domain);
  if (!bytes) throw notFound(`${domain} has no logo`);
  return new Response(bytes, {
    headers: withBaseHeaders({
      "Content-Type": LOGO_TYPE,
      "Content-Length": String(bytes.byteLength),
      "Content-Security-Policy": "sandbox",
    }),
  });
}

async function putLogoRoute({ request, env, params }: RouteContext): Promise<Response> {
  const domain = requireDomain(await getConfig(env.DB), params[0]!);
  if ((request.headers.get("Content-Type") ?? "").split(";")[0]!.trim().toLowerCase() !== LOGO_TYPE) {
    throw badRequest(`The logo must be sent as ${LOGO_TYPE}`, "invalid_logo");
  }
  return json(await putLogo(env, domain, new Uint8Array(await request.arrayBuffer())));
}

async function deleteLogoRoute({ env, params }: RouteContext): Promise<Response> {
  const domain = requireDomain(await getConfig(env.DB), params[0]!);
  return json(await deleteLogo(env, domain));
}
