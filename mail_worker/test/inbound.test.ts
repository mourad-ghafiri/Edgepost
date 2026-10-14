import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { rawKey } from "../src/store";
import { call, callJson, deliver, r2Keys, resetStore, setConfig } from "./helpers";
import { PDF_BYTES, RICH_MESSAGE_ID, RICH_SUBJECT, richMessage, simpleMessage } from "./fixtures";

beforeEach(async () => {
  await resetStore();
  await setConfig({ domains: ["acme.test"] });
});

describe("email() inbound", () => {
  it("parses and stores a multipart/alternative message with an attachment", async () => {
    const raw = richMessage();
    const fake = await deliver(raw, { from: "alice@sender.example", to: "Support@Acme.test" });
    expect(fake.rejects).toEqual([]);

    const list = await callJson("GET", "/v1/messages");
    expect(list.status).toBe(200);
    expect(list.body.messages).toHaveLength(1);
    const summary = list.body.messages[0];
    expect(summary).toMatchObject({
      folder: "inbox",
      direction: "in",
      mailbox: "support@acme.test",
      domain: "acme.test",
      from: { name: "Alice Example", address: "alice@sender.example" },
      to: [
        { name: "Support Team", address: "support@acme.test" },
        { name: null, address: "bob@acme.test" },
      ],
      cc: [{ name: "Renée Dupont", address: "renee@sender.example" }],
      replyTo: [{ name: "Alice Replies", address: "replies@sender.example" }],
      subject: RICH_SUBJECT,
      date: "2026-10-12T06:15:30.000Z",
      messageId: RICH_MESSAGE_ID,
      inReplyTo: null,
      references: [],
      read: false,
      starred: false,
      hasAttachments: true,
      size: new TextEncoder().encode(raw).byteLength,
    });
    expect(summary.threadId).toBe(summary.id);
    expect(summary.id).toMatch(/^[0-9A-HJKMNP-TV-Z]{26}$/);
    expect(summary.snippet).toBe(
      "Hi team, Please find attached the “quarterly” report. The numbers for the pelican project look good. Thanks, Alice",
    );
    expect(new Date(summary.receivedAt).toISOString()).toBe(summary.receivedAt);

    // D1 row
    const row = await env.DB.prepare("SELECT * FROM messages WHERE id = ?").bind(summary.id).first<any>();
    expect(row.list_unsubscribe).toContain("mailto:unsub@sender.example");

    // R2 objects
    expect(await r2Keys(`raw/${summary.id}`)).toEqual([`raw/${summary.id}.eml`]);
    expect(await r2Keys(`body/${summary.id}`)).toEqual([`body/${summary.id}.json`]);
    expect(await r2Keys(`att/${summary.id}/`)).toEqual([`att/${summary.id}/0`]);
    const rawObj = await env.MAIL.get(`raw/${summary.id}.eml`);
    expect(await rawObj!.text()).toBe(raw);
    const body = (await (await env.MAIL.get(`body/${summary.id}.json`))!.json()) as any;
    expect(body.text).toContain("pelican project");
    expect(body.html).toContain("<b>pelican</b>");
    const att = await env.MAIL.get(`att/${summary.id}/0`);
    expect(new Uint8Array(await att!.arrayBuffer())).toEqual(PDF_BYTES);
    expect(att!.httpMetadata?.contentType).toBe("application/pdf");
  });

  it("returns the detail with bodies, attachments and List-Unsubscribe", async () => {
    await deliver(richMessage(), { from: "alice@sender.example", to: "support@acme.test" });
    const id = (await callJson("GET", "/v1/messages")).body.messages[0].id;
    const { status, body } = await callJson("GET", `/v1/messages/${id}`);
    expect(status).toBe(200);
    expect(body.id).toBe(id);
    expect(body.text).toContain("Please find attached");
    expect(body.html).toContain("<html>");
    expect(body.listUnsubscribe).toBe(
      "<mailto:unsub@sender.example?subject=unsubscribe>, <https://sender.example/unsub/123>",
    );
    expect(body.attachments).toEqual([
      { id: `${id}.0`, filename: "report-q3.pdf", mimeType: "application/pdf", size: PDF_BYTES.byteLength, contentId: null, inline: false },
    ]);
  });

  it("serves attachment bytes and the raw message", async () => {
    const raw = richMessage();
    await deliver(raw, { from: "alice@sender.example", to: "support@acme.test" });
    const id = (await callJson("GET", "/v1/messages")).body.messages[0].id;

    const att = await call("GET", `/v1/attachments/${id}.0`);
    expect(att.status).toBe(200);
    expect(att.headers.get("Content-Type")).toBe("application/pdf");
    expect(att.headers.get("Content-Disposition")).toBe(
      `attachment; filename="report-q3.pdf"; filename*=UTF-8''report-q3.pdf`,
    );
    expect(att.headers.get("Content-Length")).toBe(String(PDF_BYTES.byteLength));
    expect(new Uint8Array(await att.arrayBuffer())).toEqual(PDF_BYTES);

    const stored = await env.MAIL.get(rawKey(id));
    expect(stored!.httpMetadata?.contentType).toBe("message/rfc822");
    expect(await stored!.text()).toBe(raw);

    expect((await call("GET", "/v1/attachments/nope.0")).status).toBe(404);
  });

  it("rejects a message larger than maxInboundBytes without storing it", async () => {
    await setConfig({ maxInboundBytes: 1000 });
    const fake = await deliver(simpleMessage(), { from: "carol@outside.example", to: "contact@acme.test", rawSize: 1001 });
    expect(fake.rejects).toEqual(["Message too large"]);
    expect((await callJson("GET", "/v1/messages")).body.messages).toEqual([]);
    expect(await r2Keys("")).toEqual([]);
  });

  it("rejects an unknown recipient when domains are configured", async () => {
    const fake = await deliver(simpleMessage({ to: "x@elsewhere.example" }), {
      from: "carol@outside.example",
      to: "x@elsewhere.example",
    });
    expect(fake.rejects).toEqual(["Unknown recipient"]);
    expect((await callJson("GET", "/v1/messages")).body.messages).toEqual([]);
  });

  it("accepts any recipient when no domains are configured", async () => {
    await setConfig({ domains: [] });
    const fake = await deliver(simpleMessage({ to: "x@elsewhere.example" }), {
      from: "carol@outside.example",
      to: "x@elsewhere.example",
    });
    expect(fake.rejects).toEqual([]);
    expect((await callJson("GET", "/v1/messages")).body.messages).toHaveLength(1);
  });

  it("forwards a copy when forwardCopies has the mailbox, and a failed forward never blocks storage", async () => {
    await setConfig({ forwardCopies: { "contact@acme.test": "me@personal.example" } });
    const ok = await deliver(simpleMessage(), { from: "carol@outside.example", to: "contact@acme.test" });
    expect(ok.forwards).toEqual(["me@personal.example"]);

    const failing = await deliver(simpleMessage({ subject: "second" }), {
      from: "carol@outside.example",
      to: "contact@acme.test",
      forwardFails: true,
    });
    expect(failing.forwards).toEqual(["me@personal.example"]);
    expect((await callJson("GET", "/v1/messages")).body.messages).toHaveLength(2);

    const other = await deliver(simpleMessage(), { from: "carol@outside.example", to: "other@acme.test" });
    expect(other.forwards).toEqual([]);
  });

  it("still stores a message postal-mime cannot make sense of", async () => {
    const fake = await deliver("this is not really\r\na MIME message", { from: "weird@outside.example", to: "contact@acme.test" });
    expect(fake.rejects).toEqual([]);
    const messages = (await callJson("GET", "/v1/messages")).body.messages;
    expect(messages).toHaveLength(1);
    expect(messages[0].from.address).toBeTruthy();
  });
});

describe("threading", () => {
  it("joins the parent's thread via In-Reply-To", async () => {
    await deliver(simpleMessage({ messageId: "<root@outside.example>", subject: "Plan" }), {
      from: "carol@outside.example",
      to: "contact@acme.test",
    });
    await deliver(
      simpleMessage({ messageId: "<r1@outside.example>", inReplyTo: "<root@outside.example>", subject: "Re: Plan" }),
      { from: "carol@outside.example", to: "contact@acme.test" },
    );
    const [reply, root] = (await callJson("GET", "/v1/messages")).body.messages;
    expect(reply.subject).toBe("Re: Plan");
    expect(reply.inReplyTo).toBe("<root@outside.example>");
    expect(reply.threadId).toBe(root.id);
    expect(root.threadId).toBe(root.id);
  });

  it("joins via References when In-Reply-To is unknown", async () => {
    await deliver(simpleMessage({ messageId: "<root2@outside.example>" }), {
      from: "carol@outside.example",
      to: "contact@acme.test",
    });
    await deliver(
      simpleMessage({
        messageId: "<r2@outside.example>",
        inReplyTo: "<missing@outside.example>",
        references: "<root2@outside.example>\r\n <missing@outside.example>",
      }),
      { from: "dave@outside.example", to: "contact@acme.test" },
    );
    const [reply, root] = (await callJson("GET", "/v1/messages")).body.messages;
    expect(reply.references).toEqual(["<root2@outside.example>", "<missing@outside.example>"]);
    expect(reply.threadId).toBe(root.id);

    const unrelated = await deliver(simpleMessage({ messageId: "<lonely@outside.example>" }), {
      from: "erin@outside.example",
      to: "contact@acme.test",
    });
    expect(unrelated.rejects).toEqual([]);
    const newest = (await callJson("GET", "/v1/messages")).body.messages[0];
    expect(newest.threadId).toBe(newest.id);
  });

  it("returns a thread oldest first", async () => {
    await deliver(simpleMessage({ messageId: "<t0@x.example>", subject: "one" }), { from: "a@x.example", to: "contact@acme.test" });
    await deliver(simpleMessage({ messageId: "<t1@x.example>", inReplyTo: "<t0@x.example>", subject: "two" }), {
      from: "a@x.example",
      to: "contact@acme.test",
    });
    await deliver(
      simpleMessage({ messageId: "<t2@x.example>", inReplyTo: "<t1@x.example>", references: "<t0@x.example> <t1@x.example>", subject: "three" }),
      { from: "a@x.example", to: "contact@acme.test" },
    );
    const newest = (await callJson("GET", "/v1/messages")).body.messages[0];
    const { status, body } = await callJson("GET", `/v1/threads/${newest.threadId}`);
    expect(status).toBe(200);
    expect(body.messages.map((m: any) => m.subject)).toEqual(["one", "two", "three"]);
    expect((await call("GET", "/v1/threads/does-not-exist")).status).toBe(404);
  });
});
