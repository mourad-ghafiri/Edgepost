// email() handler: Email Routing delivers each message here
// (https://developers.cloudflare.com/email-service/api/route-emails/email-handler/).

import PostalMime, { type Address as PmAddress, type Email } from "postal-mime";
import {
  attKey,
  bodyKey,
  findThreadId,
  getConfig,
  insertMessage,
  rawKey,
  type NewAttachment,
  type NewMessage,
} from "./store";
import type { Address, Env } from "./types";
import { ulid } from "./ulid";
import {
  belongsToDomains,
  bodyText,
  domainOf,
  makeSnippet,
  normalizeEmail,
  parseMessageIds,
  participantsText,
  toIsoOrNull,
} from "./util";

function flattenAddresses(list: PmAddress[] | PmAddress | undefined): Address[] {
  if (!list) return [];
  const items = Array.isArray(list) ? list : [list];
  const out: Address[] = [];
  for (const item of items) {
    if (item.group) {
      for (const m of item.group) if (m.address) out.push({ name: m.name || null, address: m.address });
    } else if (item.address) {
      out.push({ name: item.name || null, address: item.address });
    }
  }
  return out;
}

function headerValue(parsed: Email | null, fallback: Headers, name: string): string | null {
  const lower = name.toLowerCase();
  const fromParsed = parsed?.headers.find((h) => h.key === lower)?.value;
  const value = fromParsed ?? fallback.get(name);
  return value && value.trim() ? value.trim() : null;
}

function contentIdOf(value: string | undefined): string | null {
  if (!value) return null;
  const inner = value.trim().replace(/^<+/, "").replace(/>+$/, "").trim();
  return inner || null;
}

function attachmentBytes(content: ArrayBuffer | Uint8Array | string): Uint8Array {
  if (typeof content === "string") return new TextEncoder().encode(content);
  return content instanceof Uint8Array ? content : new Uint8Array(content);
}

export async function handleInbound(message: ForwardableEmailMessage, env: Env, _ctx?: ExecutionContext): Promise<void> {
  const config = await getConfig(env.DB);

  // 1. Size gate.
  if (message.rawSize > config.maxInboundBytes) {
    message.setReject("Message too large");
    return;
  }

  // 2. Recipient gate.
  const mailbox = normalizeEmail(message.to);
  if (config.domains.length > 0 && !belongsToDomains(mailbox, config.domains)) {
    message.setReject("Unknown recipient");
    return;
  }

  // 3. Read the stream once, store the raw message, then parse the same bytes.
  const raw = await new Response(message.raw).arrayBuffer();
  const id = ulid();
  await env.MAIL.put(rawKey(id), raw, { httpMetadata: { contentType: "message/rfc822" } });

  let parsed: Email | null = null;
  try {
    parsed = await PostalMime.parse(raw);
  } catch (err) {
    console.error("postal-mime could not parse message", id, err);
  }

  const receivedAt = new Date().toISOString();
  const fromList = flattenAddresses(parsed?.from);
  const from: Address = fromList[0] ?? { name: null, address: message.from };
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

  // 4. Thread: In-Reply-To first, then References from the most recent backwards.
  const candidates = [...new Set([...(inReplyTo ? [inReplyTo] : []), ...[...references].reverse()])];
  const threadId = (await findThreadId(env.DB, candidates)) ?? id;

  // 5. Bodies and attachments to R2, then the D1 rows.
  await env.MAIL.put(bodyKey(id), JSON.stringify({ text, html }), {
    httpMetadata: { contentType: "application/json; charset=utf-8" },
  });
  const attachments: NewAttachment[] = [];
  const parts = parsed?.attachments ?? [];
  for (let n = 0; n < parts.length; n++) {
    const part = parts[n]!;
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
      inline: contentId !== null && (part.disposition === "inline" || part.related === true),
    });
  }

  const record: NewMessage = {
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
    listUnsubscribe: headerValue(parsed, message.headers, "List-Unsubscribe"),
  };
  await insertMessage(env.DB, record, attachments, {
    participants: participantsText(from, to, cc),
    body: bodyText(text, html),
  });

  // 6. Optional copy to a verified destination; never blocks storage.
  const forwardTo = config.forwardCopies[mailbox];
  if (forwardTo) {
    try {
      await message.forward(forwardTo);
    } catch (err) {
      console.error(`Forward copy of ${id} to ${forwardTo} failed`, err);
    }
  }
}
