// The people this mail service has sent to, for the app's recipient suggestions: every To and Cc
// address of recent outgoing mail, with how often and when it was last used. Bcc recipients are
// not kept with sent copies, so they never show up here.

import { parseJsonArray } from "./store";
import type { Address } from "./types";
import { normalizeEmail } from "./util";

/** Outgoing messages read, newest first: bounds the rows each call reads. */
export const SCAN_MESSAGES = 2000;
export const MAX_CONTACTS = 500;

export interface Contact {
  address: string;
  /** The display name last sent to, if any. */
  name: string | null;
  /** Outgoing messages it was a recipient of. */
  count: number;
  lastSent: string;
}

interface Row {
  to_json: string;
  cc_json: string;
  date: string;
}

/** Most often first, then most recent. */
export async function listContacts(db: D1Database): Promise<Contact[]> {
  const { results } = await db
    .prepare("SELECT to_json, cc_json, date FROM messages WHERE direction = 'out' ORDER BY date DESC LIMIT ?")
    .bind(SCAN_MESSAGES)
    .all<Row>();
  const byAddress = new Map<string, Contact>();
  for (const row of results) {
    const seen = new Set<string>();
    for (const a of [...parseJsonArray<Address>(row.to_json), ...parseJsonArray<Address>(row.cc_json)]) {
      if (typeof a?.address !== "string" || !a.address.includes("@")) continue;
      const address = normalizeEmail(a.address);
      const name = typeof a.name === "string" && a.name.trim() ? a.name.trim() : null;
      const known = byAddress.get(address);
      if (known) {
        // Once per message. Rows come newest first: keep the latest name, else an older one.
        if (!seen.has(address)) known.count++;
        known.name ??= name;
      } else {
        byAddress.set(address, { address, name, count: 1, lastSent: row.date });
      }
      seen.add(address);
    }
  }
  return [...byAddress.values()]
    .sort((a, b) => b.count - a.count || b.lastSent.localeCompare(a.lastSent))
    .slice(0, MAX_CONTACTS);
}
