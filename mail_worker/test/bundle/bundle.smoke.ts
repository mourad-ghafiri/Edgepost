import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
// The exact file the app uploads.
import bundled from "../../../assets/worker/edgepost-mail.js";
import manifest from "../../../assets/worker/manifest.json";
import { WORKER_VERSION } from "../../src/version";
import { inboundMessage } from "../helpers";
import { richMessage } from "../fixtures";

const worker = bundled as unknown as Required<Pick<ExportedHandler<Cloudflare.Env>, "fetch" | "email" | "scheduled">>;
const KEY = "test-key-7f3a9c1e5b2d8f4a6c0e9b7d";

async function api(method: string, path: string, body?: unknown): Promise<{ status: number; json: any }> {
  const req = new Request<unknown, IncomingRequestCfProperties>(`https://mail.example${path}`, {
    method,
    headers: { Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const ctx = createExecutionContext();
  const res = await worker.fetch(req, env, ctx);
  await waitOnExecutionContext(ctx);
  return { status: res.status, json: await res.json() };
}

describe("shipped bundle", () => {
  it("matches the manifest and serves the API, inbound mail, sending and cron", async () => {
    expect(manifest).toEqual({
      // The bundle is the current source.
      version: WORKER_VERSION,
      mainModule: "edgepost-mail.js",
      compatibilityDate: expect.stringMatching(/^\d{4}-\d{2}-\d{2}$/),
      compatibilityFlags: [],
    });
    const health = await api("GET", "/v1/health");
    expect(health.status).toBe(200);
    expect(health.json).toMatchObject({ version: manifest.version });
    expect((await api("PUT", "/v1/config", { domains: ["acme.test"] })).status).toBe(200);

    const inbound = inboundMessage(richMessage(), { from: "alice@sender.example", to: "support@acme.test" });
    const ctx = createExecutionContext();
    await worker.email(inbound.message, env, ctx);
    await waitOnExecutionContext(ctx);
    const list = await api("GET", "/v1/messages?q=pelican");
    expect(list.json.messages).toHaveLength(1);
    expect(list.json.messages[0].hasAttachments).toBe(true);

    const sent = await api("POST", "/v1/send", {
      from: { name: null, address: "support@acme.test" },
      to: [{ name: null, address: "alice@sender.example" }],
      subject: "Re: report",
      text: "Thanks",
      inReplyTo: list.json.messages[0].id,
    });
    expect(sent.status).toBe(200);
    expect(sent.json.message.threadId).toBe(list.json.messages[0].threadId);
    const after = await api("GET", "/v1/health");
    expect(after.json.sendUsage).toMatchObject({ used: 1, limit: 3000, windowDays: 31 });

    const cron = createScheduledController({ scheduledTime: Date.now(), cron: "0 3 * * *" });
    const ctx2 = createExecutionContext();
    await worker.scheduled(cron, env, ctx2);
    await waitOnExecutionContext(ctx2);
  });
});
