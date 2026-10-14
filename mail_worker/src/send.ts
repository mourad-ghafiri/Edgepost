// POST /v1/send via the Email Sending Workers binding:
// https://developers.cloudflare.com/email-service/api/send-emails/workers-api/
// Custom headers must be on the allowlist; In-Reply-To and References are, Message-ID is
// platform-controlled: https://developers.cloudflare.com/email-service/reference/headers/

import { BRAND_LOGO_CID, getLogo, LOGO_TYPE } from "./brand";
import { getSendUsage, releaseSend, reserveSend } from "./budget";
import { buildMime, type MimeAttachment } from "./mime";
import { badRequest, HttpError } from "./http";
import {
  attKey,
  bodyKey,
  getAttachmentRows,
  insertMessage,
  rawKey,
  recordToSummary,
  requireMessageRow,
  rowToSummary,
  type MessageRow,
  type NewAttachment,
  type NewMessage,
} from "./store";
import { MIB, type Address, type Env, type MailConfig, type MessageSummary } from "./types";
import { ulid } from "./ulid";
import {
  belongsToDomains,
  bodyText,
  domainOf,
  isEmail,
  isPlainObject,
  makeSnippet,
  normalizeEmail,
  normalizeMessageId,
  participantsText,
  utf8Length,
} from "./util";

/**
 * Email Sending per-message limits. The 5 MiB applies to the whole message as sent, attachments
 * included (https://developers.cloudflare.com/email-service/api/send-emails/workers-api/), so the
 * Worker checks an estimate of the encoded size, not the decoded bytes.
 */
export const MAX_OUTBOUND_BYTES = 5 * MIB;
/** Allowance for the message headers. */
const HEADERS_ESTIMATE_BYTES = 2048;
/** Allowance for each attachment's MIME part headers. */
const ATTACHMENT_PART_HEADERS_BYTES = 300;
/** base64 line breaks (CRLF every 76 characters). */
const BASE64_LINE_BREAK_FACTOR = 1.027;
/** Headroom for quoted-printable text and HTML bodies. */
const QUOTED_PRINTABLE_FACTOR = 1.03;
/** How long a successful send's clientMessageId deduplicates retries. */
export const DEDUPE_WINDOW_MS = 15 * 60_000;
export const MAX_RECIPIENTS = 50;
export const MAX_ATTACHMENTS = 32;
/** References trimming: keep the first entry and the last 18. */
const REFERENCES_TAIL = 18;
const HEADER_VALUE_MAX_BYTES = 2048;

export interface SendRequest {
  from: Address;
  to: Address[];
  cc: Address[];
  bcc: Address[];
  replyTo: Address | null;
  subject: string;
  text: string;
  html: string | null;
  attachments: { filename: string; mimeType: string; contentBase64: string }[];
  inReplyTo: string | null;
  forwardOf: string | null;
  includeOriginalAttachments: boolean;
  /** Attach the From domain's logo inline (Content-ID BRAND_LOGO_CID) for the HTML's signature. */
  brandLogo: boolean;
  clientMessageId: string | null;
}

// ---- validation -------------------------------------------------------------------------------

function parseAddress(value: unknown, field: string): Address {
  if (!isPlainObject(value) || typeof value.address !== "string") {
    throw badRequest(`${field} must be an address object {name, address}`);
  }
  const address = value.address.trim();
  if (!isEmail(address)) throw badRequest(`${field} has an invalid address: ${address}`);
  if (value.name !== undefined && value.name !== null && typeof value.name !== "string") {
    throw badRequest(`${field}.name must be a string or null`);
  }
  const name = typeof value.name === "string" && value.name.trim() ? value.name.trim() : null;
  if (name !== null && /[\r\n]/.test(name)) throw badRequest(`${field}.name must not contain line breaks`);
  return { name, address };
}

function parseAddressList(value: unknown, field: string, required: boolean): Address[] {
  if (value === undefined || value === null) {
    if (required) throw badRequest(`${field} is required`);
    return [];
  }
  if (!Array.isArray(value)) throw badRequest(`${field} must be an array of addresses`);
  return value.map((v, i) => parseAddress(v, `${field}[${i}]`));
}

function optionalString(value: unknown, field: string): string | null {
  if (value === undefined || value === null) return null;
  if (typeof value !== "string") throw badRequest(`${field} must be a string or null`);
  return value;
}

export function parseSendRequest(body: unknown): SendRequest {
  if (!isPlainObject(body)) throw badRequest("Body must be a JSON object");
  const from = parseAddress(body.from, "from");
  const to = parseAddressList(body.to, "to", true);
  const cc = parseAddressList(body.cc, "cc", false);
  const bcc = parseAddressList(body.bcc, "bcc", false);
  const replyTo = body.replyTo === undefined || body.replyTo === null ? null : parseAddress(body.replyTo, "replyTo");
  if (typeof body.subject !== "string") throw badRequest("subject must be a string");
  if (/[\r\n]/.test(body.subject)) throw badRequest("subject must not contain line breaks");
  if (typeof body.text !== "string") throw badRequest("text must be a string");
  const html = optionalString(body.html, "html");
  let attachments: SendRequest["attachments"] = [];
  if (body.attachments !== undefined && body.attachments !== null) {
    if (!Array.isArray(body.attachments)) throw badRequest("attachments must be an array");
    attachments = body.attachments.map((a: unknown, i: number) => {
      if (
        !isPlainObject(a) ||
        typeof a.filename !== "string" ||
        typeof a.mimeType !== "string" ||
        typeof a.contentBase64 !== "string"
      ) {
        throw badRequest(`attachments[${i}] must be {filename, mimeType, contentBase64}`);
      }
      return { filename: a.filename, mimeType: a.mimeType, contentBase64: a.contentBase64 };
    });
  }
  const inReplyTo = optionalString(body.inReplyTo, "inReplyTo");
  const forwardOf = optionalString(body.forwardOf, "forwardOf");
  if (body.includeOriginalAttachments !== undefined && typeof body.includeOriginalAttachments !== "boolean") {
    throw badRequest("includeOriginalAttachments must be a boolean");
  }
  if (body.brandLogo !== undefined && typeof body.brandLogo !== "boolean") {
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
    clientMessageId,
  };
}

// ---- helpers ----------------------------------------------------------------------------------

/** `{email, name}` when a display name is present, otherwise the bare address. */
function toBuilderAddress(a: Address): string | EmailAddress {
  return a.name ? { email: a.address, name: a.name } : a.address;
}

/** Parent References + parent Message-ID, trimmed to the first and the last 18 when long. */
export function buildReferences(parent: { references: string[]; messageId: string | null }): string[] {
  const chain = [...parent.references];
  if (parent.messageId && chain[chain.length - 1] !== parent.messageId) chain.push(parent.messageId);
  let refs = chain.length > REFERENCES_TAIL + 1 ? [chain[0]!, ...chain.slice(-REFERENCES_TAIL)] : chain;
  // Keep the header within Email Sending's 2,048-byte value limit, dropping the oldest after the first.
  while (refs.length > 1 && utf8Length(refs.join(" ")) > HEADER_VALUE_MAX_BYTES) {
    refs = refs.length > 2 ? [refs[0]!, ...refs.slice(2)] : refs.slice(1);
  }
  return refs;
}

/** Size of one attachment as sent: base64 with line breaks, plus its part headers. */
export function encodedAttachmentSize(bytes: number): number {
  return Math.ceil(4 * Math.ceil(bytes / 3) * BASE64_LINE_BREAK_FACTOR) + ATTACHMENT_PART_HEADERS_BYTES;
}

/** Estimated size of the message as sent by Email Sending. */
export function estimateMessageSize(text: string, html: string | null, attachmentBytes: readonly number[]): number {
  let total = HEADERS_ESTIMATE_BYTES;
  total += Math.ceil(utf8Length(text) * QUOTED_PRINTABLE_FACTOR);
  total += Math.ceil(utf8Length(html) * QUOTED_PRINTABLE_FACTOR);
  for (const n of attachmentBytes) total += encodedAttachmentSize(n);
  return total;
}

interface SendErrorMapping {
  status: number;
  code: string;
}

export function mapSendErrorCode(providerCode: string | null): SendErrorMapping {
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
      // E_HEADER_* and E_HEADERS_* (header allowlist/size errors) are message errors.
      if (providerCode?.startsWith("E_HEADER")) return { status: 400, code: "invalid_message" };
      return { status: 502, code: "delivery_failed" };
  }
}

/** Email Sending codes for messages rejected at the API boundary, which never count toward its quota. */
const BOUNDARY_REJECTIONS: ReadonlySet<string> = new Set([
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
  "E_DAILY_LIMIT_EXCEEDED",
]);

/** True only for documented boundary rejections, including every E_HEADER* code. */
export function isBoundaryRejection(providerCode: string | null): boolean {
  if (!providerCode) return false;
  return BOUNDARY_REJECTIONS.has(providerCode) || providerCode.startsWith("E_HEADER");
}

/** Reads `error.code` (documented shape), falling back to an `E_*` token in the message. */
export function providerCodeOf(err: unknown): string | null {
  if (isPlainObject(err) || err instanceof Error) {
    const code = (err as { code?: unknown }).code;
    if (typeof code === "string" && /^E_[A-Z0-9_]+$/.test(code)) return code;
  }
  const message = err instanceof Error ? err.message : typeof err === "string" ? err : "";
  return /\bE_[A-Z0-9_]+\b/.exec(message)?.[0] ?? null;
}

function sendError(err: unknown): HttpError {
  const providerCode = providerCodeOf(err);
  const { status, code } = mapSendErrorCode(providerCode);
  const message = err instanceof Error && err.message ? err.message : "Email Sending rejected the message";
  return new HttpError(status, code, message, providerCode ? { providerCode } : {});
}

// ---- handler ----------------------------------------------------------------------------------

/**
 * An attachment's content for Email Sending: its bytes, as an ArrayBuffer of exactly their length
 * (as the official file-upload example passes `await file.arrayBuffer()`,
 * https://developers.cloudflare.com/email-service/examples/email-sending/email-attachments/).
 * Never a base64 string: Cloudflare's own local binding writes a string content to the file as
 * it is, so a base64 string would reach the recipient as a file of base64 text. Never a view
 * either: it would carry its whole underlying buffer to anything that reads `.buffer`.
 */
export function attachmentContent(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

export interface SendResult {
  message: MessageSummary;
  providerMessageId: string | null;
}

/**
 * POST /v1/send. With a clientMessageId, a retry of a send that succeeded in the last 15 minutes
 * returns the stored result (`duplicate: true`) without sending or counting budget again; a retry
 * while the first attempt is still running gets 409 send_in_progress.
 */
export async function sendMessage(
  env: Env,
  config: MailConfig,
  body: unknown,
): Promise<SendResult & { duplicate: boolean }> {
  const req = parseSendRequest(body);
  const clientId = req.clientMessageId;
  if (clientId) {
    const claim = await claimClientMessageId(env.DB, clientId);
    if (claim.kind === "duplicate") return { ...claim.result, duplicate: true };
    if (claim.kind === "in_progress") {
      throw new HttpError(409, "send_in_progress", `A send with clientMessageId ${clientId} is still in progress`);
    }
  }
  let result: SendResult;
  try {
    result = await deliver(env, config, req);
  } catch (err) {
    if (clientId) {
      await releaseClientMessageId(env.DB, clientId).catch((e: unknown) =>
        console.error("Could not release clientMessageId", e),
      );
    }
    throw err;
  }
  if (clientId) {
    await completeClientMessageId(env.DB, clientId, result).catch((e: unknown) =>
      console.error("Could not record clientMessageId", e),
    );
  }
  return { ...result, duplicate: false };
}

type Claim = { kind: "claimed" } | { kind: "in_progress" } | { kind: "duplicate"; result: SendResult };

/** Claims the id (new, or older than the dedupe window) or reports the fresh row, in one round-trip. */
async function claimClientMessageId(db: D1Database, clientId: string, now = Date.now()): Promise<Claim> {
  const [claim, existing] = await db.batch<{ client_id?: string; response?: string | null }>([
    db
      .prepare(
        `INSERT INTO send_dedupe (client_id, ts, response) VALUES (?1, ?2, NULL)
        ON CONFLICT(client_id) DO UPDATE SET ts = excluded.ts, response = NULL WHERE send_dedupe.ts <= ?3
        RETURNING client_id`,
      )
      .bind(clientId, now, now - DEDUPE_WINDOW_MS),
    db.prepare("SELECT response FROM send_dedupe WHERE client_id = ?1").bind(clientId),
  ]);
  if ((claim?.results.length ?? 0) > 0) return { kind: "claimed" };
  const response = existing?.results[0]?.response;
  if (typeof response === "string") return { kind: "duplicate", result: JSON.parse(response) as SendResult };
  return { kind: "in_progress" };
}

async function completeClientMessageId(db: D1Database, clientId: string, result: SendResult): Promise<void> {
  await db
    .prepare("UPDATE send_dedupe SET response = ?2, ts = ?3 WHERE client_id = ?1")
    .bind(clientId, JSON.stringify(result), Date.now())
    .run();
}

async function releaseClientMessageId(db: D1Database, clientId: string): Promise<void> {
  await db.prepare("DELETE FROM send_dedupe WHERE client_id = ?1 AND response IS NULL").bind(clientId).run();
}

/** Validates, checks the budget, sends through Email Sending and stores the sent copy. */
async function deliver(env: Env, config: MailConfig, req: SendRequest): Promise<SendResult> {

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

  // Uploaded attachments.
  const attachments: MimeAttachment[] = req.attachments.map((a, i) => {
    let bytes: Uint8Array;
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
      contentId: null,
    };
  });

  // The From domain's logo, inline, for the signature in the HTML part.
  if (req.brandLogo) {
    const logo = await getLogo(env, domainOf(normalizeEmail(req.from.address)));
    if (!logo) throw badRequest("The sender's domain has no logo", "brand_logo_missing");
    attachments.push({ filename: "logo.png", mimeType: LOGO_TYPE, bytes: logo, inline: true, contentId: BRAND_LOGO_CID });
  }

  // Reply threading.
  let parent: MessageRow | null = null;
  let references: string[] = [];
  let inReplyToHeader: string | null = null;
  if (req.inReplyTo) {
    parent = await requireMessageRow(env.DB, req.inReplyTo);
    const parentSummary = rowToSummary(parent);
    if (parentSummary.messageId) {
      inReplyToHeader = parentSummary.messageId;
      references = buildReferences(parentSummary);
    }
  }

  // Forward with the original's attachments from R2.
  const sizes = (): number[] => attachments.map((a) => a.bytes.byteLength);
  if (req.forwardOf) {
    const original = await requireMessageRow(env.DB, req.forwardOf);
    if (req.includeOriginalAttachments) {
      const rows = await getAttachmentRows(env.DB, original.id);
      // Check with the stored sizes before reading any bytes from R2.
      const estimate = estimateMessageSize(req.text, req.html, [...sizes(), ...rows.map((r) => r.size)]);
      if (estimate > MAX_OUTBOUND_BYTES) throw tooLarge(estimate);
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
          contentId: inline ? row.content_id : null,
        });
      }
    }
  }
  const estimate = estimateMessageSize(req.text, req.html, sizes());
  if (estimate > MAX_OUTBOUND_BYTES) throw tooLarge(estimate);
  if (attachments.length > MAX_ATTACHMENTS) throw tooManyAttachments();

  // Builder per the Workers API reference.
  const headers: Record<string, string> = {};
  if (inReplyToHeader) headers["In-Reply-To"] = inReplyToHeader;
  if (references.length) headers["References"] = references.join(" ");
  const builder = {
    from: toBuilderAddress(req.from),
    subject: req.subject,
    text: req.text,
  } as EmailMessageBuilder;
  if (req.to.length) builder.to = req.to.map(toBuilderAddress);
  if (req.cc.length) builder.cc = req.cc.map(toBuilderAddress);
  if (req.bcc.length) builder.bcc = req.bcc.map(toBuilderAddress);
  if (req.replyTo) builder.replyTo = toBuilderAddress(req.replyTo);
  if (req.html) builder.html = req.html;
  if (attachments.length) {
    builder.attachments = attachments.map((a): EmailAttachment => {
      const content = attachmentContent(a.bytes);
      return a.inline && a.contentId
        ? { disposition: "inline", contentId: a.contentId, filename: a.filename, type: a.mimeType, content }
        : { disposition: "attachment", filename: a.filename, type: a.mimeType, content };
    });
  }
  if (Object.keys(headers).length) builder.headers = headers;

  // Send budget: reserve this send's recipients atomically, or refuse before calling Email Sending.
  const reservation = await reserveSend(env.DB, recipients, config.monthlySendLimit);
  if (reservation === null) {
    const usage = await getSendUsage(env.DB, config.monthlySendLimit);
    const message =
      usage.limit === 0
        ? "Sending is disabled (monthlySendLimit is 0)"
        : `Monthly send limit reached: ${usage.used} of ${usage.limit} recipients used in the last ` +
          `${usage.windowDays} days; this message has ${recipients}`;
    throw new HttpError(429, "monthly_send_limit", message, { usage });
  }

  let result: EmailSendResult;
  try {
    result = await env.EMAIL.send(builder);
  } catch (err) {
    // Only documented API-boundary rejections are rolled back. Anything else (delivery failure,
    // internal error, unknown or uncoded error, timeout) may have been accepted and billed, so it
    // stays counted (https://developers.cloudflare.com/email-service/platform/pricing/).
    if (isBoundaryRejection(providerCodeOf(err))) {
      await releaseSend(env.DB, reservation).catch((releaseErr: unknown) =>
        console.error("Could not release the send budget reservation", releaseErr),
      );
    }
    throw sendError(err);
  }
  const providerMessageId = typeof result?.messageId === "string" && result.messageId ? result.messageId : null;
  const messageId = normalizeMessageId(providerMessageId);

  // Sent copy.
  const id = ulid();
  const now = new Date();
  const mailbox = normalizeEmail(req.from.address);
  const record: NewMessage = {
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
    listUnsubscribe: null,
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
      attachments,
    });
    record.size = raw.byteLength;
    await env.MAIL.put(rawKey(id), raw, { httpMetadata: { contentType: "message/rfc822" } });
    await env.MAIL.put(bodyKey(id), JSON.stringify({ text: req.text, html: req.html }), {
      httpMetadata: { contentType: "application/json; charset=utf-8" },
    });
    const attRows: NewAttachment[] = [];
    for (let n = 0; n < attachments.length; n++) {
      const a = attachments[n]!;
      await env.MAIL.put(attKey(id, n), a.bytes, { httpMetadata: { contentType: a.mimeType } });
      attRows.push({
        idx: n,
        filename: a.filename,
        mimeType: a.mimeType,
        size: a.bytes.byteLength,
        contentId: a.contentId,
        inline: a.inline,
      });
    }
    await insertMessage(env.DB, record, attRows, {
      participants: participantsText(req.from, req.to, req.cc),
      body: bodyText(req.text, req.html),
    });
  } catch (err) {
    // The message was already sent: report success rather than inviting a duplicate send.
    console.error(`Sent message ${providerMessageId ?? "(no id)"} could not be stored`, err);
  }
  return { message: recordToSummary(record), providerMessageId };
}

function tooLarge(size: number): HttpError {
  return new HttpError(
    413,
    "content_too_large",
    `The message would be about ${size} bytes as sent; Email Sending allows ${MAX_OUTBOUND_BYTES} including attachments`,
    { size, limit: MAX_OUTBOUND_BYTES },
  );
}

function tooManyAttachments(): HttpError {
  return new HttpError(413, "content_too_large", `At most ${MAX_ATTACHMENTS} attachments per message`);
}
