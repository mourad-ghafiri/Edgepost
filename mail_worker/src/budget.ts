// Send budget (API.md "Send budget"). Email Sending has no spending cap: Workers Paid
// includes 3,000 emails per month, then $0.35 per 1,000
// (https://developers.cloudflare.com/email-service/platform/pricing/). The Worker caps sends
// itself, counted in recipients (to + cc + bcc) over a rolling 31-day window.

import type { SendUsage } from "./types";

export const SEND_WINDOW_DAYS = 31;
const DAY_MS = 86_400_000;
const WINDOW_MS = SEND_WINDOW_DAYS * DAY_MS;
/** send_log rows older than this are pruned by scheduled(); always longer than the window. */
export const SEND_LOG_RETENTION_DAYS = 40;

export interface SendUsageRow {
  used: number;
  oldest: number | null;
}

/** The usage query as a statement, so callers can batch it with other reads. */
export function sendUsageStatement(db: D1Database, now = Date.now()): D1PreparedStatement {
  return db
    .prepare("SELECT COALESCE(SUM(recipients), 0) AS used, MIN(ts) AS oldest FROM send_log WHERE ts > ?1")
    .bind(now - WINDOW_MS);
}

export function sendUsageFromRow(row: SendUsageRow | null | undefined, limit: number): SendUsage {
  const oldest = row?.oldest ?? null;
  return {
    used: Number(row?.used ?? 0),
    limit,
    windowDays: SEND_WINDOW_DAYS,
    resetsAt: oldest === null ? null : new Date(Number(oldest) + WINDOW_MS).toISOString(),
  };
}

export async function getSendUsage(db: D1Database, limit: number, now = Date.now()): Promise<SendUsage> {
  return sendUsageFromRow(await sendUsageStatement(db, now).first<SendUsageRow>(), limit);
}

/**
 * Records `recipients` in one statement only if it fits under `limit`, so concurrent sends
 * cannot both pass the check. Returns the row id of the reservation, or null when refused.
 * The caller releases the reservation if Email Sending rejects the message, so only
 * successful sends stay counted.
 */
export async function reserveSend(
  db: D1Database,
  recipients: number,
  limit: number,
  now = Date.now(),
): Promise<number | null> {
  const row = await db
    .prepare(
      `INSERT INTO send_log (ts, recipients)
      SELECT ?1, ?2
      WHERE (SELECT COALESCE(SUM(recipients), 0) FROM send_log WHERE ts > ?3) + ?2 <= ?4
      RETURNING rowid AS rid`,
    )
    .bind(now, recipients, now - WINDOW_MS, limit)
    .first<{ rid: number }>();
  return row ? Number(row.rid) : null;
}

/** Removes a reservation whose send failed. */
export async function releaseSend(db: D1Database, rid: number): Promise<void> {
  await db.prepare("DELETE FROM send_log WHERE rowid = ?1").bind(rid).run();
}

/** send_dedupe rows (POST /v1/send clientMessageId) are kept this long. */
export const SEND_DEDUPE_RETENTION_DAYS = 1;

/**
 * Deletes send_log rows older than SEND_LOG_RETENTION_DAYS and send_dedupe rows older than
 * SEND_DEDUPE_RETENTION_DAYS in one D1 round-trip. Returns the number of rows deleted.
 */
export async function pruneSendTables(db: D1Database, now = Date.now()): Promise<number> {
  const results = await db.batch([
    db.prepare("DELETE FROM send_log WHERE ts < ?1").bind(now - SEND_LOG_RETENTION_DAYS * DAY_MS),
    db.prepare("DELETE FROM send_dedupe WHERE ts < ?1").bind(now - SEND_DEDUPE_RETENTION_DAYS * DAY_MS),
  ]);
  return results.reduce((n, r) => n + (r.meta.changes ?? 0), 0);
}
