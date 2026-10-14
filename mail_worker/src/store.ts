// D1 + R2 storage. R2 layout: raw/<id>.eml, body/<id>.json ({text, html}), att/<id>/<n>.

import { sendUsageFromRow, sendUsageStatement, type SendUsageRow } from "./budget";
import { BUMP_SEQ_SQL, CURRENT_SEQ_SQL } from "./schema";
import { HttpError } from "./http";
import {
  DEFAULT_CONFIG,
  MAX_MONTHLY_SEND_LIMIT,
  type Address,
  type Attachment,
  type Direction,
  type Env,
  type Folder,
  type MailConfig,
  type MessageSummary,
  type SendUsage,
} from "./types";
import { isDomain, isEmail, isPlainObject, normalizeEmail, truncateChars } from "./util";

export const rawKey = (id: string): string => `raw/${id}.eml`;
export const bodyKey = (id: string): string => `body/${id}.json`;
export const attKey = (id: string, n: number): string => `att/${id}/${n}`;

/** Max characters of body text kept in the full-text index per message. */
const FTS_BODY_MAX = 32_000;

// ---- config -----------------------------------------------------------------------------------

export const CONFIG_SQL = "SELECT key, value FROM config";

export async function getConfig(db: D1Database): Promise<MailConfig> {
  const { results } = await db.prepare(CONFIG_SQL).all<{ key: string; value: string }>();
  return configFromRows(results);
}

export function configFromRows(results: readonly { key: string; value: string }[]): MailConfig {
  const cfg: MailConfig = {
    domains: [...DEFAULT_CONFIG.domains],
    forwardCopies: { ...DEFAULT_CONFIG.forwardCopies },
    maxInboundBytes: DEFAULT_CONFIG.maxInboundBytes,
    trashRetentionDays: DEFAULT_CONFIG.trashRetentionDays,
    monthlySendLimit: DEFAULT_CONFIG.monthlySendLimit,
  };
  for (const row of results) {
    let value: unknown;
    try {
      value = JSON.parse(row.value);
    } catch {
      continue;
    }
    switch (row.key) {
      case "domains":
        if (Array.isArray(value)) cfg.domains = value.filter((d): d is string => typeof d === "string");
        break;
      case "forwardCopies":
        if (isPlainObject(value)) {
          cfg.forwardCopies = Object.fromEntries(
            Object.entries(value).filter((e): e is [string, string] => typeof e[1] === "string"),
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

const invalidConfig = (message: string): HttpError => new HttpError(400, "invalid_config", message);

/**
 * Validates a partial config and returns the normalised fields. Unknown and read-only keys
 * (such as sendUsage) are ignored.
 */
export function validateConfigPatch(body: unknown): Partial<MailConfig> {
  if (!isPlainObject(body)) throw invalidConfig("Body must be a JSON object");
  const patch: Partial<MailConfig> = {};
  if (body.domains !== undefined) {
    if (!Array.isArray(body.domains) || body.domains.some((d) => typeof d !== "string")) {
      throw invalidConfig("domains must be an array of strings");
    }
    const domains = [...new Set((body.domains as string[]).map((d) => d.trim().toLowerCase().replace(/\.$/, "")))];
    const bad = domains.find((d) => !isDomain(d));
    if (bad !== undefined) throw invalidConfig(`Invalid domain: ${bad}`);
    patch.domains = domains;
  }
  if (body.forwardCopies !== undefined) {
    if (!isPlainObject(body.forwardCopies)) throw invalidConfig("forwardCopies must be an object");
    const copies: Record<string, string> = {};
    for (const [mailbox, dest] of Object.entries(body.forwardCopies)) {
      if (dest === null || dest === "") continue; // null/"" clears an entry
      const key = normalizeEmail(mailbox);
      if (!isEmail(key)) throw invalidConfig(`Invalid mailbox in forwardCopies: ${mailbox}`);
      if (typeof dest !== "string" || !isEmail(dest.trim())) {
        throw invalidConfig(`Invalid forward destination for ${mailbox}`);
      }
      copies[key] = dest.trim();
    }
    patch.forwardCopies = copies;
  }
  if (body.maxInboundBytes !== undefined) {
    const v = body.maxInboundBytes;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 2 ** 31) {
      throw invalidConfig("maxInboundBytes must be a positive integer");
    }
    patch.maxInboundBytes = v;
  }
  if (body.trashRetentionDays !== undefined) {
    const v = body.trashRetentionDays;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > 3650) {
      throw invalidConfig("trashRetentionDays must be an integer between 1 and 3650");
    }
    patch.trashRetentionDays = v;
  }
  if (body.monthlySendLimit !== undefined) {
    const v = body.monthlySendLimit;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > MAX_MONTHLY_SEND_LIMIT) {
      throw invalidConfig(`monthlySendLimit must be an integer between 0 and ${MAX_MONTHLY_SEND_LIMIT}`);
    }
    patch.monthlySendLimit = v;
  }
  return patch;
}

export async function putConfig(db: D1Database, patch: Partial<MailConfig>): Promise<MailConfig> {
  const statements = Object.entries(patch).map(([key, value]) =>
    db
      .prepare("INSERT INTO config (key, value) VALUES (?1, ?2) ON CONFLICT(key) DO UPDATE SET value = excluded.value")
      .bind(key, JSON.stringify(value)),
  );
  if (statements.length > 0) await db.batch(statements);
  return getConfig(db);
}

// ---- rows -------------------------------------------------------------------------------------

export interface MessageRow {
  rid: number;
  id: string;
  thread_id: string;
  folder: Folder;
  direction: Direction;
  mailbox: string;
  domain: string;
  from_name: string | null;
  from_address: string;
  to_json: string;
  cc_json: string;
  reply_to_json: string;
  subject: string;
  snippet: string;
  date: string;
  received_at: string;
  message_id: string | null;
  in_reply_to: string | null;
  references_json: string;
  read: number;
  starred: number;
  has_attachments: number;
  size: number;
  list_unsubscribe: string | null;
  trashed_at: string | null;
  seq: number;
}

interface AttachmentRow {
  id: string;
  message_id: string;
  idx: number;
  filename: string;
  mime_type: string;
  size: number;
  content_id: string | null;
  inline: number;
}

export function parseJsonArray<T>(value: string): T[] {
  try {
    const parsed: unknown = JSON.parse(value);
    return Array.isArray(parsed) ? (parsed as T[]) : [];
  } catch {
    return [];
  }
}

export function rowToSummary(row: MessageRow): MessageSummary {
  return {
    id: row.id,
    threadId: row.thread_id,
    folder: row.folder,
    direction: row.direction,
    mailbox: row.mailbox,
    domain: row.domain,
    from: { name: row.from_name, address: row.from_address },
    to: parseJsonArray<Address>(row.to_json),
    cc: parseJsonArray<Address>(row.cc_json),
    replyTo: parseJsonArray<Address>(row.reply_to_json),
    subject: row.subject,
    snippet: row.snippet,
    date: row.date,
    receivedAt: row.received_at,
    messageId: row.message_id,
    inReplyTo: row.in_reply_to,
    references: parseJsonArray<string>(row.references_json),
    read: row.read === 1,
    starred: row.starred === 1,
    hasAttachments: row.has_attachments === 1,
    size: row.size,
  };
}

export function rowToAttachment(row: AttachmentRow): Attachment {
  return {
    id: row.id,
    filename: row.filename,
    mimeType: row.mime_type,
    size: row.size,
    contentId: row.content_id,
    inline: row.inline === 1,
  };
}

// ---- writes -----------------------------------------------------------------------------------

export interface NewMessage {
  id: string;
  threadId: string;
  folder: Folder;
  direction: Direction;
  mailbox: string;
  domain: string;
  from: Address;
  to: Address[];
  cc: Address[];
  replyTo: Address[];
  subject: string;
  snippet: string;
  date: string;
  receivedAt: string;
  messageId: string | null;
  inReplyTo: string | null;
  references: string[];
  read: boolean;
  hasAttachments: boolean;
  size: number;
  listUnsubscribe: string | null;
}

export interface NewAttachment {
  idx: number;
  filename: string;
  mimeType: string;
  size: number;
  contentId: string | null;
  inline: boolean;
}

export function recordToSummary(rec: NewMessage, starred = false): MessageSummary {
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
    size: rec.size,
  };
}

export const attachmentId = (messageId: string, idx: number): string => `${messageId}.${idx}`;

/** Inserts the message, its attachment rows and its FTS row, and bumps the change sequence, atomically. */
export async function insertMessage(
  db: D1Database,
  msg: NewMessage,
  attachments: NewAttachment[],
  search: { participants: string; body: string },
): Promise<void> {
  const statements: D1PreparedStatement[] = [db.prepare(BUMP_SEQ_SQL)];
  statements.push(
    db
      .prepare(
        `INSERT INTO messages (id, thread_id, folder, direction, mailbox, domain, from_name, from_address,
          to_json, cc_json, reply_to_json, subject, snippet, date, received_at, message_id, in_reply_to,
          references_json, read, starred, has_attachments, size, list_unsubscribe, trashed_at, seq)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, 0, ?20, ?21, ?22,
          NULL, ${CURRENT_SEQ_SQL})`,
      )
      .bind(
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
        msg.listUnsubscribe,
      ),
  );
  for (const att of attachments) {
    statements.push(
      db
        .prepare(
          `INSERT INTO attachments (id, message_id, idx, filename, mime_type, size, content_id, inline)
          VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)`,
        )
        .bind(
          attachmentId(msg.id, att.idx),
          msg.id,
          att.idx,
          att.filename,
          att.mimeType,
          att.size,
          att.contentId,
          att.inline ? 1 : 0,
        ),
    );
  }
  statements.push(
    db
      .prepare(
        `INSERT INTO messages_fts (rowid, subject, participants, body)
        VALUES ((SELECT rid FROM messages WHERE id = ?1), ?2, ?3, ?4)`,
      )
      .bind(msg.id, msg.subject, search.participants, truncateChars(search.body, FTS_BODY_MAX)),
  );
  await db.batch(statements);
}

export interface FlagPatch {
  read?: boolean;
  starred?: boolean;
  folder?: Folder;
}

/** Applies flags/folder to the given ids in one transaction. Returns the number of rows updated. */
export async function updateMessages(db: D1Database, ids: string[], patch: FlagPatch): Promise<number> {
  if (ids.length === 0) return 0;
  const now = new Date().toISOString();
  const results = await db.batch([
    db.prepare(BUMP_SEQ_SQL),
    db
      .prepare(
        `UPDATE messages SET
          read = COALESCE(?1, read),
          starred = COALESCE(?2, starred),
          folder = COALESCE(?3, folder),
          trashed_at = CASE WHEN ?3 IS NULL THEN trashed_at
                            WHEN ?3 = 'trash' THEN COALESCE(trashed_at, ?4)
                            ELSE NULL END,
          seq = ${CURRENT_SEQ_SQL}
        WHERE id IN (SELECT value FROM json_each(?5))`,
      )
      .bind(
        patch.read === undefined ? null : patch.read ? 1 : 0,
        patch.starred === undefined ? null : patch.starred ? 1 : 0,
        patch.folder ?? null,
        now,
        JSON.stringify(ids),
      ),
  ]);
  return results[1]?.meta.changes ?? 0;
}

/**
 * Permanently deletes messages: R2 objects first (so a failure leaves the row to retry), then the
 * D1 rows, FTS rows and attachment rows, recording a tombstone at a new change sequence.
 * Returns the ids that existed and were purged.
 */
export async function purgeMessages(env: Env, ids: string[]): Promise<string[]> {
  if (ids.length === 0) return [];
  const idsJson = JSON.stringify(ids);
  const [existing, atts] = await env.DB.batch<{ id: string; message_id?: string; idx?: number }>([
    env.DB.prepare("SELECT id FROM messages WHERE id IN (SELECT value FROM json_each(?1))").bind(idsJson),
    env.DB.prepare(
      "SELECT message_id, idx FROM attachments WHERE message_id IN (SELECT value FROM json_each(?1))",
    ).bind(idsJson),
  ]);
  const found = (existing?.results ?? []).map((r) => r.id);
  if (found.length === 0) return [];
  const keys: string[] = [];
  for (const id of found) keys.push(rawKey(id), bodyKey(id));
  for (const a of atts?.results ?? []) {
    if (a.message_id !== undefined && a.idx !== undefined) keys.push(attKey(a.message_id, a.idx));
  }
  for (let i = 0; i < keys.length; i += 1000) {
    await env.MAIL.delete(keys.slice(i, i + 1000));
  }
  const foundJson = JSON.stringify(found);
  const now = new Date().toISOString();
  await env.DB.batch([
    env.DB.prepare(BUMP_SEQ_SQL),
    env.DB.prepare(
      `INSERT INTO tombstones (id, seq, deleted_at)
      SELECT value, ${CURRENT_SEQ_SQL}, ?2 FROM json_each(?1) WHERE true
      ON CONFLICT(id) DO UPDATE SET seq = excluded.seq, deleted_at = excluded.deleted_at`,
    ).bind(foundJson, now),
    env.DB.prepare(
      "DELETE FROM messages_fts WHERE rowid IN (SELECT rid FROM messages WHERE id IN (SELECT value FROM json_each(?1)))",
    ).bind(foundJson),
    env.DB.prepare("DELETE FROM attachments WHERE message_id IN (SELECT value FROM json_each(?1))").bind(foundJson),
    env.DB.prepare("DELETE FROM messages WHERE id IN (SELECT value FROM json_each(?1))").bind(foundJson),
  ]);
  return found;
}

// ---- reads ------------------------------------------------------------------------------------

export async function getMessageRow(db: D1Database, id: string): Promise<MessageRow | null> {
  return db.prepare("SELECT * FROM messages WHERE id = ?1").bind(id).first<MessageRow>();
}

export async function requireMessageRow(db: D1Database, id: string): Promise<MessageRow> {
  const row = await getMessageRow(db, id);
  if (!row) throw new HttpError(404, "not_found", `Message ${id} not found`);
  return row;
}

export async function getAttachmentRows(db: D1Database, messageId: string): Promise<AttachmentRow[]> {
  const { results } = await db
    .prepare("SELECT * FROM attachments WHERE message_id = ?1 ORDER BY idx")
    .bind(messageId)
    .all<AttachmentRow>();
  return results;
}

export async function getAttachmentRow(db: D1Database, id: string): Promise<AttachmentRow | null> {
  return db.prepare("SELECT * FROM attachments WHERE id = ?1").bind(id).first<AttachmentRow>();
}

export interface ListFilters {
  folder: Folder;
  mailbox?: string;
  domain?: string;
  q?: string;
  unread?: boolean;
  starred?: boolean;
  cursor?: string;
  limit: number;
}

/** Builds an FTS5 MATCH expression from user input: every word becomes a quoted prefix term. */
export function ftsQuery(q: string): string | null {
  const terms = q
    .normalize("NFKC")
    .split(/\s+/)
    .map((t) => t.replace(/"/g, ""))
    .filter((t) => /[\p{L}\p{N}]/u.test(t))
    .slice(0, 16);
  if (terms.length === 0) return null;
  return terms.map((t) => `"${t}"*`).join(" AND ");
}

/** Newest first, keyset-paged on the time-sortable id. */
export async function listMessages(
  db: D1Database,
  f: ListFilters,
): Promise<{ messages: MessageSummary[]; nextCursor: string | null }> {
  const where: string[] = ["folder = ?"];
  const params: (string | number)[] = [f.folder];
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
  if (f.q !== undefined) {
    const match = ftsQuery(f.q);
    if (match) {
      where.push("rid IN (SELECT rowid FROM messages_fts WHERE messages_fts MATCH ?)");
      params.push(match);
    }
  }
  params.push(f.limit + 1);
  const sql = `SELECT * FROM messages WHERE ${where.join(" AND ")} ORDER BY id DESC LIMIT ?`;
  const { results } = await db
    .prepare(sql)
    .bind(...params)
    .all<MessageRow>();
  const page = results.slice(0, f.limit);
  const nextCursor = results.length > f.limit ? (page[page.length - 1]?.id ?? null) : null;
  return { messages: page.map(rowToSummary), nextCursor };
}

export async function getThread(db: D1Database, threadId: string): Promise<MessageSummary[]> {
  const { results } = await db
    .prepare("SELECT * FROM messages WHERE thread_id = ?1 ORDER BY id ASC")
    .bind(threadId)
    .all<MessageRow>();
  return results.map(rowToSummary);
}

export async function listMailboxes(
  db: D1Database,
): Promise<{ address: string; domain: string; unread: number; total: number; lastAt: string | null }[]> {
  const { results } = await db
    .prepare(
      `SELECT mailbox AS address, MAX(domain) AS domain,
        SUM(CASE WHEN read = 0 AND folder = 'inbox' THEN 1 ELSE 0 END) AS unread,
        COUNT(*) AS total,
        MAX(received_at) AS lastAt
      FROM messages WHERE folder != 'trash'
      GROUP BY mailbox ORDER BY lastAt DESC, mailbox ASC`,
    )
    .all<{ address: string; domain: string; unread: number; total: number; lastAt: string | null }>();
  return results.map((r) => ({
    address: r.address,
    domain: r.domain,
    unread: Number(r.unread),
    total: Number(r.total),
    lastAt: r.lastAt,
  }));
}

/** Finds the thread of the first candidate Message-ID (in priority order) that is stored. */
export async function findThreadId(db: D1Database, candidates: string[]): Promise<string | null> {
  if (candidates.length === 0) return null;
  const { results } = await db
    .prepare(
      `SELECT message_id, thread_id FROM messages
      WHERE message_id IN (SELECT value FROM json_each(?1)) ORDER BY id ASC`,
    )
    .bind(JSON.stringify(candidates))
    .all<{ message_id: string; thread_id: string }>();
  const byMessageId = new Map<string, string>();
  for (const r of results) if (!byMessageId.has(r.message_id)) byMessageId.set(r.message_id, r.thread_id);
  for (const c of candidates) {
    const thread = byMessageId.get(c);
    if (thread) return thread;
  }
  return null;
}

export interface SyncResult {
  messages: MessageSummary[];
  deleted: string[];
  cursor: string;
  hasMore: boolean;
  sendUsage: SendUsage;
  unread: { total: number };
}

/**
 * Changes after `since` (new messages, flag and folder moves) plus tombstones of purged ids, with
 * the send budget usage and inbox unread counts. All reads run in one D1 batch (one round-trip,
 * one consistent snapshot). Rows changed in one transaction share a sequence number, so a page
 * never splits a sequence; only a single transaction larger than the page needs a second read.
 */
export async function syncChanges(db: D1Database, since: number | null, limit = 500): Promise<SyncResult> {
  const from = since ?? Number.MAX_SAFE_INTEGER; // no since: cursor only
  const [configRes, headRes, rowsRes, tombRes, usageRes, unreadRes] = await db.batch<any>([
    db.prepare(CONFIG_SQL),
    db.prepare(`SELECT ${CURRENT_SEQ_SQL} AS seq`),
    db
      .prepare(`SELECT * FROM messages WHERE seq > ?1 AND seq <= ${CURRENT_SEQ_SQL} ORDER BY seq ASC, id ASC LIMIT ?2`)
      .bind(from, limit + 1),
    db
      .prepare(`SELECT id, seq FROM tombstones WHERE seq > ?1 AND seq <= ${CURRENT_SEQ_SQL} ORDER BY seq ASC, id ASC`)
      .bind(from),
    sendUsageStatement(db),
    db.prepare("SELECT COUNT(*) AS n FROM messages WHERE folder = 'inbox' AND read = 0"),
  ]);
  const config = configFromRows((configRes?.results ?? []) as { key: string; value: string }[]);
  const head = Number((headRes?.results[0] as { seq: number | null } | undefined)?.seq ?? 0);
  const results = (rowsRes?.results ?? []) as MessageRow[];

  let rows = results;
  let upper = head;
  let hasMore = false;
  if (results.length > limit) {
    hasMore = true;
    const boundary = results[limit]!.seq;
    rows = results.filter((r) => r.seq < boundary);
    if (rows.length === 0) {
      const all = await db.prepare("SELECT * FROM messages WHERE seq = ?1 ORDER BY id ASC").bind(boundary).all<MessageRow>();
      rows = all.results;
      upper = boundary;
    } else {
      upper = boundary - 1;
    }
  }
  const deleted = ((tombRes?.results ?? []) as { id: string; seq: number }[])
    .filter((t) => t.seq <= upper)
    .map((t) => t.id);

  const total = Number((unreadRes?.results[0] as { n: number } | undefined)?.n ?? 0);
  return {
    messages: rows.map(rowToSummary),
    deleted,
    cursor: String(since !== null && since < head ? upper : head),
    hasMore,
    sendUsage: sendUsageFromRow(usageRes?.results[0] as SendUsageRow | undefined, config.monthlySendLimit),
    unread: { total },
  };
}

/**
 * Purges trash older than `days`. Returns the number of purged messages. Bounded per run (each
 * round is 3 D1 calls) to stay well inside the Free plan's 50 D1 queries per invocation
 * (https://developers.cloudflare.com/d1/platform/limits/); the next daily run continues.
 */
export async function purgeExpiredTrash(env: Env, days: number, now = Date.now()): Promise<number> {
  const cutoff = new Date(now - days * 86_400_000).toISOString();
  let purged = 0;
  for (let round = 0; round < 10; round++) {
    const { results } = await env.DB.prepare(
      "SELECT id FROM messages WHERE folder = 'trash' AND trashed_at IS NOT NULL AND trashed_at < ?1 ORDER BY id LIMIT 200",
    )
      .bind(cutoff)
      .all<{ id: string }>();
    if (results.length === 0) break;
    purged += (await purgeMessages(env, results.map((r) => r.id))).length;
    if (results.length < 200) break;
  }
  return purged;
}
