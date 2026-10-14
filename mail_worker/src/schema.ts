// The D1 schema: one idempotent definition. Every statement is IF NOT EXISTS / OR IGNORE, so it is
// applied once per isolate before any handler runs and is a no-op on a database that already has
// these tables. The app never runs SQL.
//
// Full-text search uses an FTS5 virtual table. D1 lists the FTS5 module among its supported
// SQLite extensions (https://developers.cloudflare.com/d1/sql-api/sql-statements/). Rows are
// written and deleted explicitly by the Worker (no triggers); the FTS rowid is messages.rid, an
// INTEGER PRIMARY KEY alias, so it stays stable across VACUUM.

/** Every table, index and seed row. */
const SCHEMA: readonly string[] = [
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
  "INSERT OR IGNORE INTO meta (key, value) VALUES ('change_seq', '0')",
];

/** Increments the change sequence. Run in the same batch (transaction) as the change itself. */
export const BUMP_SEQ_SQL = "UPDATE meta SET value = CAST(value AS INTEGER) + 1 WHERE key = 'change_seq'";
/** Scalar subquery returning the current change sequence. */
export const CURRENT_SEQ_SQL = "(SELECT CAST(value AS INTEGER) FROM meta WHERE key = 'change_seq')";

let ready: Promise<void> | null = null;

/** Applies SCHEMA once per isolate; a failed attempt is retried on the next call. */
export function ensureSchema(db: D1Database): Promise<void> {
  if (!ready) {
    ready = applySchema(db).catch((err: unknown) => {
      ready = null;
      throw err;
    });
  }
  return ready;
}

/** Runs every SCHEMA statement in one transaction. Idempotent. */
export async function applySchema(db: D1Database): Promise<void> {
  await db.batch(SCHEMA.map((sql) => db.prepare(sql)));
}
