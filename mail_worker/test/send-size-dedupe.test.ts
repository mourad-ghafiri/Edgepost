import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { encodedAttachmentSize, estimateMessageSize, MAX_OUTBOUND_BYTES } from "../src/send";
import { base64, callJson, deliver, fakeEmail, makeEnv, patternBytes, resetStore, runScheduled, sendingError, setConfig } from "./helpers";

const LIMIT = 5 * 1024 * 1024;

function request(extra: Record<string, unknown> = {}) {
  return {
    from: { name: "Me", address: "contact@acme.test" },
    to: [{ name: null, address: "carol@outside.example" }],
    subject: "Files",
    text: "See attached.",
    ...extra,
  };
}

function attachment(bytes: Uint8Array, filename = "file.bin") {
  return { filename, mimeType: "application/octet-stream", contentBase64: base64(bytes) };
}

/** An inbound message carrying one attachment of `size` bytes. */
function messageWithAttachment(size: number): string {
  const b64 = base64(patternBytes(size, 5)).replace(/.{1,76}/g, "$&\r\n");
  return [
    "From: Carol <carol@outside.example>",
    "To: contact@acme.test",
    "Subject: Big file",
    "Message-ID: <big@outside.example>",
    "MIME-Version: 1.0",
    'Content-Type: multipart/mixed; boundary="b"',
    "",
    "--b",
    "Content-Type: text/plain; charset=utf-8",
    "",
    "Here it is.",
    "--b",
    'Content-Type: application/octet-stream; name="big.bin"',
    'Content-Disposition: attachment; filename="big.bin"',
    "Content-Transfer-Encoding: base64",
    "",
    b64 + "--b--",
    "",
  ].join("\r\n");
}

beforeEach(async () => {
  await resetStore();
  await env.DB.batch([env.DB.prepare("DELETE FROM send_log"), env.DB.prepare("DELETE FROM send_dedupe")]);
  await setConfig({ domains: ["acme.test"] });
});

describe("encoded size estimate", () => {
  it("counts base64 with line breaks, part headers, QP headroom and header allowance", () => {
    expect(MAX_OUTBOUND_BYTES).toBe(LIMIT);
    expect(encodedAttachmentSize(3)).toBe(Math.ceil(4 * 1.027) + 300);
    expect(encodedAttachmentSize(3_000_000)).toBe(Math.ceil(4_000_000 * 1.027) + 300);
    expect(estimateMessageSize("abc", "<p>é</p>", [3])).toBe(2048 + Math.ceil(3 * 1.03) + Math.ceil(9 * 1.03) + Math.ceil(4 * 1.027) + 300);
  });

  it("lets a ~3 MB attachment through", { timeout: 30_000 }, async () => {
    const email = fakeEmail();
    const bytes = patternBytes(3_000_000);
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request({ attachments: [attachment(bytes)] }) });
    expect(res.status).toBe(200);
    expect(email.calls).toHaveLength(1);
    // The binding gets the file's bytes, exactly.
    const content = email.calls[0]!.attachments![0]!.content as ArrayBuffer;
    expect(content.byteLength).toBe(bytes.byteLength);
    expect(new Uint8Array(content)).toEqual(bytes);
  });

  it("refuses a 4 MB attachment by the encoded estimate (413 with size and limit)", { timeout: 30_000 }, async () => {
    const email = fakeEmail();
    const bytes = patternBytes(4 * 1024 * 1024);
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request({ attachments: [attachment(bytes)] }) });
    expect(res.status).toBe(413);
    expect(res.body.error).toEqual({
      code: "content_too_large",
      message: expect.any(String),
      size: estimateMessageSize("See attached.", null, [bytes.byteLength]),
      limit: LIMIT,
    });
    expect(bytes.byteLength).toBeLessThan(LIMIT); // the old decoded-bytes check would have passed it
    expect(email.calls).toHaveLength(0);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM send_log").first("n")).toBe(0);
  });

  it("counts forwarded original attachments the same way", { timeout: 30_000 }, async () => {
    await deliver(messageWithAttachment(2_500_000), { from: "carol@outside.example", to: "contact@acme.test" });
    const original = (await callJson("GET", "/v1/messages")).body.messages[0];
    const extra = attachment(patternBytes(1_500_000), "extra.bin");
    const email = fakeEmail();
    const res = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: request({ forwardOf: original.id, includeOriginalAttachments: true, attachments: [extra] }),
    });
    expect(res.status).toBe(413);
    expect(res.body.error.size).toBe(estimateMessageSize("See attached.", null, [1_500_000, 2_500_000]));
    expect(email.calls).toHaveLength(0);
    // Decoded that is only 4,000,000 bytes; without the originals it fits.
    const plain = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: request({ forwardOf: original.id, attachments: [extra] }),
    });
    expect(plain.status).toBe(200);
    // The original alone forwards fine.
    const fwd = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: request({ forwardOf: original.id, includeOriginalAttachments: true }),
    });
    expect(fwd.status).toBe(200);
    expect((email.calls[1]!.attachments![0]!.content as ArrayBuffer).byteLength).toBe(2_500_000);
  });

  it("rejects invalid base64, including the URL-safe alphabet", async () => {
    const email = fakeEmail();
    for (const contentBase64 of ["%%%", "a-_b"]) {
      const res = await callJson("POST", "/v1/send", {
        env: makeEnv({ EMAIL: email.binding }),
        body: request({ attachments: [{ filename: "x", mimeType: "text/plain", contentBase64 }] }),
      });
      expect(res.status).toBe(400);
    }
    expect(email.calls).toHaveLength(0);
  });
});

describe("idempotent send (clientMessageId)", () => {
  it("returns the first result for a retry and does not send or count again", async () => {
    const email = fakeEmail();
    const body = request({ clientMessageId: "compose-7f3a-0001" });
    const first = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body });
    expect(first.status).toBe(200);
    expect(first.body.duplicate).toBe(false);
    const second = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body });
    expect(second.status).toBe(200);
    expect(second.body).toEqual({ ...first.body, duplicate: true });
    expect(email.calls).toHaveLength(1);
    expect((await callJson("GET", "/v1/config")).body.sendUsage.used).toBe(1);
    expect((await callJson("GET", "/v1/messages?folder=sent")).body.messages).toHaveLength(1);
    // A different id is a different send.
    const other = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request({ clientMessageId: "compose-7f3a-0002" }) });
    expect(other.body.duplicate).toBe(false);
    expect(email.calls).toHaveLength(2);
  });

  it("expires after 15 minutes", async () => {
    const email = fakeEmail();
    const body = request({ clientMessageId: "compose-expiring" });
    await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body });
    await env.DB.prepare("UPDATE send_dedupe SET ts = ?1").bind(Date.now() - 15 * 60_000 - 1000).run();
    const again = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body });
    expect(again.status).toBe(200);
    expect(again.body.duplicate).toBe(false);
    expect(email.calls).toHaveLength(2);
    expect((await callJson("GET", "/v1/config")).body.sendUsage.used).toBe(2);
  });

  it("answers 409 send_in_progress while the first attempt is running", async () => {
    await env.DB.prepare("INSERT INTO send_dedupe (client_id, ts, response) VALUES ('compose-inflight', ?1, NULL)").bind(Date.now()).run();
    const email = fakeEmail();
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request({ clientMessageId: "compose-inflight" }) });
    expect(res.status).toBe(409);
    expect(res.body.error.code).toBe("send_in_progress");
    expect(email.calls).toHaveLength(0);
  });

  it("frees the id when the send fails, so a retry really sends", async () => {
    const failing = fakeEmail(async () => {
      throw sendingError("E_RECIPIENT_NOT_ALLOWED");
    });
    const body = request({ clientMessageId: "compose-retry-after-error" });
    expect((await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: failing.binding }), body })).status).toBe(403);
    const ok = fakeEmail();
    const retry = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: ok.binding }), body });
    expect(retry.status).toBe(200);
    expect(retry.body.duplicate).toBe(false);
    expect(ok.calls).toHaveLength(1);
    // A pre-send refusal frees it too.
    const refused = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: ok.binding }),
      body: request({ clientMessageId: "compose-refused-0", from: { name: null, address: "x@evil.example" } }),
    });
    expect(refused.status).toBe(403);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM send_dedupe WHERE client_id = 'compose-refused-0'").first("n")).toBe(0);
  });

  it("validates clientMessageId", async () => {
    const email = fakeEmail();
    for (const clientMessageId of ["short", "x".repeat(101), 12345678]) {
      const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request({ clientMessageId }) });
      expect(res.status, String(clientMessageId)).toBe(400);
    }
    expect((await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request({ clientMessageId: "x".repeat(8) }) })).status).toBe(200);
    expect((await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request({ clientMessageId: "y".repeat(100) }) })).status).toBe(200);
  });

  it("scheduled() prunes ids older than 1 day", async () => {
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("INSERT INTO send_dedupe (client_id, ts, response) VALUES ('old-id-0001', ?1, '{}')").bind(now - 25 * 3_600_000),
      env.DB.prepare("INSERT INTO send_dedupe (client_id, ts, response) VALUES ('new-id-0001', ?1, '{}')").bind(now - 3_600_000),
    ]);
    await runScheduled(now);
    const { results } = await env.DB.prepare("SELECT client_id FROM send_dedupe").all<{ client_id: string }>();
    expect(results.map((r) => r.client_id)).toEqual(["new-id-0001"]);
  });
});

describe("GET /v1/sync extras", () => {
  it("returns sendUsage and inbox unread counts", async () => {
    await setConfig({ monthlySendLimit: 40 });
    for (const [to, subject] of [
      ["contact@acme.test", "a"],
      ["contact@acme.test", "b"],
      ["sales@acme.test", "c"],
      ["sales@acme.test", "d"],
    ]) {
      await deliver(`From: x@outside.example\r\nTo: ${to}\r\nSubject: ${subject}\r\n\r\nhi\r\n`, { from: "x@outside.example", to: to! });
    }
    const list = (await callJson("GET", "/v1/messages")).body.messages as any[];
    const d = list.find((m) => m.subject === "d");
    const c = list.find((m) => m.subject === "c");
    await callJson("PATCH", `/v1/messages/${d.id}`, { body: { read: true } });
    await callJson("PATCH", `/v1/messages/${c.id}`, { body: { folder: "archive" } }); // unread but not inbox
    const email = fakeEmail();
    await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request() });

    const latest = await callJson("GET", "/v1/sync");
    expect(latest.body).toMatchObject({
      messages: [],
      deleted: [],
      hasMore: false,
      unread: { total: 2 },
    });
    expect(latest.body.sendUsage).toEqual((await callJson("GET", "/v1/config")).body.sendUsage);
    expect(latest.body.sendUsage).toMatchObject({ used: 1, limit: 40, windowDays: 31 });

    const full = await callJson("GET", "/v1/sync?since=0");
    expect(full.body.messages).toHaveLength(5);
    expect(full.body.unread).toEqual({ total: 2 });
    expect(full.body.cursor).toBe(latest.body.cursor);
  });
});
