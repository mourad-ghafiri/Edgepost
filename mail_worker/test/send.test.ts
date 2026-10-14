import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { buildReferences, mapSendErrorCode } from "../src/send";
import { rawKey } from "../src/store";
import {
  base64,
  call,
  callJson,
  deliver,
  fakeEmail,
  makeEnv,
  patternBytes,
  r2Keys,
  resetStore,
  sendingError,
  setConfig,
} from "./helpers";
import { PDF_BYTES, RICH_MESSAGE_ID, richMessage, simpleMessage } from "./fixtures";

const ME = { name: "Mourad", address: "contact@acme.test" };

function baseRequest(extra: Record<string, unknown> = {}) {
  return {
    from: ME,
    to: [{ name: "Carol", address: "carol@outside.example" }],
    subject: "Hi Carol",
    text: "Hello there",
    ...extra,
  };
}

beforeEach(async () => {
  await resetStore();
  await setConfig({ domains: ["acme.test"] });
});

describe("POST /v1/send", () => {
  it("passes the documented builder shape to EMAIL.send and stores the sent copy", async () => {
    const email = fakeEmail(async () => ({ messageId: "0102018f-abcd@email.cloudflare.example" }));
    const attachment = patternBytes(1234, 3);
    const res = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: baseRequest({
        cc: [{ name: null, address: "dave@outside.example" }],
        bcc: [{ name: "Erin", address: "erin@outside.example" }],
        replyTo: { name: null, address: "replies@acme.test" },
        html: "<p>Hello there</p>",
        attachments: [{ filename: "notes.bin", mimeType: "application/octet-stream", contentBase64: base64(attachment) }],
      }),
    });
    expect(res.status).toBe(200);
    expect(email.calls).toHaveLength(1);
    expect(email.calls[0]).toEqual({
      from: { email: "contact@acme.test", name: "Mourad" },
      to: [{ email: "carol@outside.example", name: "Carol" }],
      cc: ["dave@outside.example"],
      bcc: [{ email: "erin@outside.example", name: "Erin" }],
      replyTo: "replies@acme.test",
      subject: "Hi Carol",
      text: "Hello there",
      html: "<p>Hello there</p>",
      attachments: [
        { disposition: "attachment", filename: "notes.bin", type: "application/octet-stream", content: expect.any(ArrayBuffer) },
      ],
    });
    // The file's own bytes, not its base64 text.
    expect(new Uint8Array(email.calls[0]!.attachments![0]!.content as ArrayBuffer)).toEqual(attachment);
    expect(res.body.providerMessageId).toBe("0102018f-abcd@email.cloudflare.example");
    const sent = res.body.message;
    expect(sent).toMatchObject({
      folder: "sent",
      direction: "out",
      mailbox: "contact@acme.test",
      domain: "acme.test",
      from: ME,
      to: [{ name: "Carol", address: "carol@outside.example" }],
      cc: [{ name: null, address: "dave@outside.example" }],
      replyTo: [{ name: null, address: "replies@acme.test" }],
      subject: "Hi Carol",
      snippet: "Hello there",
      messageId: "<0102018f-abcd@email.cloudflare.example>",
      inReplyTo: null,
      references: [],
      read: true,
      starred: false,
      hasAttachments: true,
    });
    expect(sent.threadId).toBe(sent.id);
    expect(sent.size).toBeGreaterThan(1234);

    // Stored: listed in Sent, detail with attachment, raw MIME with the normalised Message-ID.
    const list = await callJson("GET", "/v1/messages?folder=sent");
    expect(list.body.messages).toEqual([sent]);
    const detail = await callJson("GET", `/v1/messages/${sent.id}`);
    expect(detail.body.text).toBe("Hello there");
    expect(detail.body.html).toBe("<p>Hello there</p>");
    expect(detail.body.attachments).toEqual([
      { id: `${sent.id}.0`, filename: "notes.bin", mimeType: "application/octet-stream", size: 1234, contentId: null, inline: false },
    ]);
    const bytes = await call("GET", `/v1/attachments/${sent.id}.0`);
    expect(new Uint8Array(await bytes.arrayBuffer())).toEqual(attachment);
    const raw = await (await env.MAIL.get(rawKey(sent.id)))!.text();
    expect(raw).toContain("Message-ID: <0102018f-abcd@email.cloudflare.example>");
    expect(raw).toContain("Bcc: \"Erin\" <erin@outside.example>");
    expect(raw.length).toBe(sent.size);
    // Searchable.
    const found = await callJson("GET", "/v1/messages?folder=sent&q=there");
    expect(found.body.messages).toHaveLength(1);
  });

  it("keeps an already-bracketed messageId as is", async () => {
    const email = fakeEmail(async () => ({ messageId: "<abc@cf.example>" }));
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: baseRequest() });
    expect(res.body.message.messageId).toBe("<abc@cf.example>");
    expect(res.body.providerMessageId).toBe("<abc@cf.example>");
  });

  it("returns 403 sender_not_allowed for a sender outside config.domains", async () => {
    const email = fakeEmail();
    for (const address of ["me@evil.example", "me@acme.test.evil.example"]) {
      const res = await callJson("POST", "/v1/send", {
        env: makeEnv({ EMAIL: email.binding }),
        body: baseRequest({ from: { name: null, address } }),
      });
      expect(res.status).toBe(403);
      expect(res.body.error.code).toBe("sender_not_allowed");
    }
    expect(email.calls).toHaveLength(0);
  });

  it("validates the request", async () => {
    const email = fakeEmail();
    const envWith = makeEnv({ EMAIL: email.binding });
    const bad = [
      {},
      baseRequest({ to: "carol@outside.example" }),
      baseRequest({ to: [{ address: "not-an-email" }] }),
      baseRequest({ subject: 5 }),
      baseRequest({ text: undefined }),
      baseRequest({ to: [] }),
      baseRequest({ attachments: [{ filename: "a", mimeType: "text/plain", contentBase64: "%%%" }] }),
    ];
    for (const body of bad) {
      const res = await callJson("POST", "/v1/send", { env: envWith, body });
      expect(res.status, JSON.stringify(body)).toBe(400);
    }
    const tooMany = Array.from({ length: 51 }, (_, i) => ({ name: null, address: `r${i}@outside.example` }));
    const res = await callJson("POST", "/v1/send", { env: envWith, body: baseRequest({ to: tooMany }) });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("too_many_recipients");
    expect(email.calls).toHaveLength(0);
  });

  it("returns 503 when the EMAIL binding is missing", async () => {
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: undefined }), body: baseRequest() });
    expect(res.status).toBe(503);
    expect(res.body.error.code).toBe("sending_not_configured");
  });

  it("reply: sets In-Reply-To and References and joins the parent's thread", async () => {
    await deliver(
      simpleMessage({
        messageId: "<parent@outside.example>",
        references: "<root@outside.example> <mid@outside.example>",
        inReplyTo: "<mid@outside.example>",
        subject: "Question",
      }),
      { from: "carol@outside.example", to: "contact@acme.test" },
    );
    const parent = (await callJson("GET", "/v1/messages")).body.messages[0];
    const email = fakeEmail(async () => ({ messageId: "reply-1@cf.example" }));
    const res = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: baseRequest({ subject: "Re: Question", inReplyTo: parent.id }),
    });
    expect(res.status).toBe(200);
    expect(email.calls[0]!.headers).toEqual({
      "In-Reply-To": "<parent@outside.example>",
      References: "<root@outside.example> <mid@outside.example> <parent@outside.example>",
    });
    const sent = res.body.message;
    expect(sent.threadId).toBe(parent.threadId);
    expect(sent.inReplyTo).toBe("<parent@outside.example>");
    expect(sent.references).toEqual(["<root@outside.example>", "<mid@outside.example>", "<parent@outside.example>"]);

    const thread = await callJson("GET", `/v1/threads/${parent.threadId}`);
    expect(thread.body.messages.map((m: any) => m.direction)).toEqual(["in", "out"]);

    // A reply to the sent message threads through the stored messageId.
    await deliver(
      simpleMessage({ messageId: "<answer@outside.example>", inReplyTo: "<reply-1@cf.example>", subject: "Re: Re: Question" }),
      { from: "carol@outside.example", to: "contact@acme.test" },
    );
    const thread2 = await callJson("GET", `/v1/threads/${parent.threadId}`);
    expect(thread2.body.messages.map((m: any) => m.subject)).toEqual(["Question", "Re: Question", "Re: Re: Question"]);
  });

  it("reply to an unknown local id is a 404", async () => {
    const email = fakeEmail();
    const res = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: baseRequest({ inReplyTo: "01NOPE" }),
    });
    expect(res.status).toBe(404);
    expect(email.calls).toHaveLength(0);
  });

  it("trims long References to the first and the last 18", () => {
    const refs = Array.from({ length: 30 }, (_, i) => `<m${i}@x.example>`);
    const out = buildReferences({ references: refs, messageId: "<parent@x.example>" });
    expect(out).toHaveLength(19);
    expect(out[0]).toBe("<m0@x.example>");
    expect(out[18]).toBe("<parent@x.example>");
    expect(out[1]).toBe("<m13@x.example>");
    const short = buildReferences({ references: [], messageId: "<p@x.example>" });
    expect(short).toEqual(["<p@x.example>"]);
  });

  it("forward: re-attaches the original's attachments from R2", async () => {
    await deliver(richMessage(), { from: "alice@sender.example", to: "support@acme.test" });
    const original = (await callJson("GET", "/v1/messages")).body.messages[0];
    const email = fakeEmail();
    const res = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: baseRequest({
        from: { name: null, address: "support@acme.test" },
        subject: "Fwd: Quarterly report",
        forwardOf: original.id,
        includeOriginalAttachments: true,
        attachments: [{ filename: "extra.txt", mimeType: "text/plain", contentBase64: base64(new TextEncoder().encode("hi")) }],
      }),
    });
    expect(res.status).toBe(200);
    const builder = email.calls[0]!;
    expect(builder.headers).toBeUndefined();
    expect(builder.attachments).toHaveLength(2);
    expect(builder.attachments![0]).toMatchObject({ filename: "extra.txt", disposition: "attachment" });
    const fwd = builder.attachments![1]!;
    expect(fwd).toMatchObject({ filename: "report-q3.pdf", type: "application/pdf", disposition: "attachment" });
    expect(fwd.content).toBeInstanceOf(ArrayBuffer);
    expect(new Uint8Array(fwd.content as ArrayBuffer)).toEqual(PDF_BYTES);
    // New thread for the forward; the sent copy carries both attachments.
    const sent = res.body.message;
    expect(sent.threadId).toBe(sent.id);
    expect(await r2Keys(`att/${sent.id}/`)).toEqual([`att/${sent.id}/0`, `att/${sent.id}/1`]);

    // Without includeOriginalAttachments nothing is re-attached.
    const plain = fakeEmail();
    await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: plain.binding }),
      body: baseRequest({ forwardOf: original.id }),
    });
    expect(plain.calls[0]!.attachments).toBeUndefined();
    expect(original.messageId).toBe(RICH_MESSAGE_ID);
  });

  it("returns 413 content_too_large above 5 MiB, before calling EMAIL.send", async () => {
    const email = fakeEmail();
    const big = patternBytes(5 * 1024 * 1024 + 1);
    const res = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: baseRequest({ attachments: [{ filename: "big.bin", mimeType: "application/octet-stream", contentBase64: base64(big) }] }),
    });
    expect(res.status).toBe(413);
    expect(res.body.error).toMatchObject({ code: "content_too_large", limit: 5 * 1024 * 1024 });
    expect(res.body.error.size).toBeGreaterThan(5 * 1024 * 1024);
    expect(email.calls).toHaveLength(0);
  });

  it("returns 413 when forwarded originals push the total over 5 MiB", async () => {
    await deliver(richMessage(), { from: "alice@sender.example", to: "support@acme.test" });
    const original = (await callJson("GET", "/v1/messages")).body.messages[0];
    const email = fakeEmail();
    const nearly = patternBytes(5 * 1024 * 1024 - 100);
    const res = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: baseRequest({
        forwardOf: original.id,
        includeOriginalAttachments: true,
        attachments: [{ filename: "n.bin", mimeType: "application/octet-stream", contentBase64: base64(nearly) }],
      }),
    });
    expect(res.status).toBe(413);
    expect(res.body.error.code).toBe("content_too_large");
    expect(email.calls).toHaveLength(0);
  });

  it("maps Email Sending E_* errors to HTTP and echoes providerCode", async () => {
    const table: [string, number, string][] = [
      ["E_VALIDATION_ERROR", 400, "invalid_message"],
      ["E_FIELD_MISSING", 400, "invalid_message"],
      ["E_HEADER_NOT_ALLOWED", 400, "invalid_message"],
      ["E_HEADERS_TOO_LARGE", 400, "invalid_message"],
      ["E_TOO_MANY_RECIPIENTS", 400, "too_many_recipients"],
      ["E_TOO_MANY_ATTACHMENTS", 413, "content_too_large"],
      ["E_CONTENT_TOO_LARGE", 413, "content_too_large"],
      ["E_SENDER_NOT_VERIFIED", 403, "sender_domain_not_onboarded"],
      ["E_SENDER_DOMAIN_NOT_AVAILABLE", 403, "sender_domain_not_onboarded"],
      ["E_RECIPIENT_NOT_ALLOWED", 403, "recipient_not_allowed"],
      ["E_RECIPIENT_SUPPRESSED", 409, "recipient_suppressed"],
      ["E_RATE_LIMIT_EXCEEDED", 429, "sending_limit"],
      ["E_DAILY_LIMIT_EXCEEDED", 429, "sending_limit"],
      ["E_DELIVERY_FAILED", 502, "delivery_failed"],
      ["E_INTERNAL_SERVER_ERROR", 502, "delivery_failed"],
      ["E_SOMETHING_NEW", 502, "delivery_failed"],
    ];
    for (const [providerCode, status, code] of table) {
      expect(mapSendErrorCode(providerCode)).toEqual({ status, code });
      const email = fakeEmail(async () => {
        throw sendingError(providerCode);
      });
      const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: baseRequest() });
      expect(res.status, providerCode).toBe(status);
      expect(res.body.error).toMatchObject({ code, providerCode });
      expect(res.body.error.message).toContain(providerCode);
    }
    // An error whose code only appears in the message, and one with no code at all.
    const inMessage = fakeEmail(async () => {
      throw new Error("send failed: E_RECIPIENT_NOT_ALLOWED (recipient not verified)");
    });
    const r1 = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: inMessage.binding }), body: baseRequest() });
    expect(r1.status).toBe(403);
    expect(r1.body.error.providerCode).toBe("E_RECIPIENT_NOT_ALLOWED");
    const noCode = fakeEmail(async () => {
      throw new Error("boom");
    });
    const r2 = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: noCode.binding }), body: baseRequest() });
    expect(r2.status).toBe(502);
    expect(r2.body.error.code).toBe("delivery_failed");
    expect(r2.body.error.providerCode).toBeUndefined();
    // Nothing was stored for failed sends.
    expect((await callJson("GET", "/v1/messages?folder=sent")).body.messages).toEqual([]);
    expect(await env.DB.prepare("SELECT COUNT(*) AS n FROM messages").first("n")).toBe(0);
  });
});

describe("attachment content", () => {
  it("is each file's own bytes, as an ArrayBuffer of exactly their length", async () => {
    // Every byte value, so any text or base64 round trip would show.
    const all = Uint8Array.from({ length: 256 * 4 }, (_, i) => i % 256);
    const email = fakeEmail();
    const res = await callJson("POST", "/v1/send", {
      env: makeEnv({ EMAIL: email.binding }),
      body: baseRequest({
        attachments: [
          { filename: "photo.jpg", mimeType: "image/jpeg", contentBase64: base64(all) },
          { filename: "empty.txt", mimeType: "text/plain", contentBase64: "" },
        ],
      }),
    });
    expect(res.status).toBe(200);
    const [photo, empty] = email.calls[0]!.attachments!;
    expect(photo!.content).toBeInstanceOf(ArrayBuffer);
    expect((photo!.content as ArrayBuffer).byteLength).toBe(all.byteLength);
    expect(new Uint8Array(photo!.content as ArrayBuffer)).toEqual(all);
    expect((empty!.content as ArrayBuffer).byteLength).toBe(0);
  });

  it("copies only a view's own bytes, never its whole underlying buffer", async () => {
    const { attachmentContent } = await import("../src/send");
    const backing = Uint8Array.from([9, 9, 1, 2, 3, 9, 9]);
    const view = backing.subarray(2, 5);
    const content = attachmentContent(view);
    expect(content.byteLength).toBe(3);
    expect(new Uint8Array(content)).toEqual(Uint8Array.from([1, 2, 3]));
  });
});
