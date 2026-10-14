// The schema is applied once per isolate, so re-applying it to a database that already has the
// tables and data must change nothing.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { applySchema } from "../src/schema";
import { callJson, deliver, fakeEmail, makeEnv, setConfig } from "./helpers";
import { simpleMessage } from "./fixtures";

describe("schema", () => {
  it("is a no-op on a database that already has the tables", async () => {
    await setConfig({ domains: ["acme.test"], trashRetentionDays: 9 });
    await deliver(simpleMessage({ messageId: "<keep@x.example>", body: "zebra" }), {
      from: "old@x.example",
      to: "contact@acme.test",
    });
    const email = fakeEmail();
    await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: { from: { name: null, address: "contact@acme.test" }, to: [{ name: null, address: "old@x.example" }], subject: "Re", text: "ok" },
    });
    const snapshot = async () =>
      (
        await env.DB.batch([
          env.DB.prepare("SELECT COUNT(*) AS n FROM messages"),
          env.DB.prepare("SELECT COUNT(*) AS n FROM messages_fts"),
          env.DB.prepare("SELECT COUNT(*) AS n FROM send_log"),
          env.DB.prepare("SELECT COUNT(*) AS n FROM config"),
          env.DB.prepare("SELECT value AS n FROM meta WHERE key = 'change_seq'"),
        ])
      ).map((r: any) => r.results[0].n);
    const before = await snapshot();
    expect(before.slice(0, 4)).toEqual([2, 2, 1, 2]);

    await applySchema(env.DB);
    await applySchema(env.DB);

    expect(await snapshot()).toEqual(before);
    expect((await callJson("GET", "/v1/messages?q=zebra")).body.messages).toHaveLength(1);
    expect((await callJson("GET", "/v1/config")).body).toMatchObject({ trashRetentionDays: 9, sendUsage: { used: 1 } });
  });
});
