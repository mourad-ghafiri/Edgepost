// edgepost-mail: the mailbox Worker that Edgepost deploys into the user's own Cloudflare
// account. Contract: mail_worker/API.md.

import { handleFetch } from "./api";
import { pruneSendTables } from "./budget";
import { handleInbound } from "./inbound";
import { ensureSchema } from "./schema";
import { getConfig, purgeExpiredTrash } from "./store";
import type { Env } from "./types";

export default {
  /** Checks the API key, applies the schema, then routes (see api.ts). */
  async fetch(request, env, _ctx): Promise<Response> {
    return handleFetch(request, env);
  },

  async email(message, env, ctx): Promise<void> {
    await ensureSchema(env.DB);
    await handleInbound(message, env, ctx);
  },

  /**
   * Daily cron (set by the app): purge trash older than trashRetentionDays, prune send_log rows
   * older than 40 days and send_dedupe rows older than 1 day. D1 round-trips: schema 1 + config 1
   * + prune 1 + trash at most 30,
   * inside the Free plan's 50 per invocation (https://developers.cloudflare.com/d1/platform/limits/).
   */
  async scheduled(controller, env, _ctx): Promise<void> {
    await ensureSchema(env.DB);
    const now = controller.scheduledTime || Date.now();
    const config = await getConfig(env.DB);
    const pruned = await pruneSendTables(env.DB, now);
    const purged = await purgeExpiredTrash(env, config.trashRetentionDays, now);
    if (purged > 0 || pruned > 0) console.log(`Purged ${purged} trashed message(s), ${pruned} send log/dedupe row(s)`);
  },
} satisfies ExportedHandler<Env>;
