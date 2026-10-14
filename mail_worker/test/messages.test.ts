import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { call, callJson, deliver, r2Keys, resetStore, runScheduled, setConfig } from "./helpers";
import { richMessage, simpleMessage } from "./fixtures";

async function seed(): Promise<Record<string, any>> {
  // Five inbound messages across two mailboxes and two domains, oldest first.
  const specs = [
    { to: "contact@acme.test", subject: "Invoice 1001", body: "Your invoice for October." },
    { to: "sales@acme.test", subject: "Partnership idea", body: "Let us build a pelican sanctuary together." },
    { to: "contact@acme.test", subject: "Lunch?", body: "Pizza or ramen this Friday?" },
    { to: "info@other.test", subject: "Domain renewal", body: "Your domain renews soon." },
    { to: "contact@acme.test", subject: "Pelicans again", body: "More about birds." },
  ];
  for (const [i, s] of specs.entries()) {
    await deliver(simpleMessage({ to: s.to, subject: s.subject, body: s.body, messageId: `<seed${i}@outside.example>` }), {
      from: "carol@outside.example",
      to: s.to,
    });
  }
  const all = (await callJson("GET", "/v1/messages")).body.messages as any[];
  return Object.fromEntries(all.map((m) => [m.subject, m]));
}

beforeEach(async () => {
  await resetStore();
  await setConfig({ domains: ["acme.test", "other.test"] });
});

describe("GET /v1/messages", () => {
  it("lists newest first with cursor paging", async () => {
    await seed();
    const page1 = await callJson("GET", "/v1/messages?limit=2");
    expect(page1.body.messages.map((m: any) => m.subject)).toEqual(["Pelicans again", "Domain renewal"]);
    expect(page1.body.nextCursor).toBeTypeOf("string");
    const page2 = await callJson("GET", `/v1/messages?limit=2&cursor=${encodeURIComponent(page1.body.nextCursor)}`);
    expect(page2.body.messages.map((m: any) => m.subject)).toEqual(["Lunch?", "Partnership idea"]);
    const page3 = await callJson("GET", `/v1/messages?limit=2&cursor=${encodeURIComponent(page2.body.nextCursor)}`);
    expect(page3.body.messages.map((m: any) => m.subject)).toEqual(["Invoice 1001"]);
    expect(page3.body.nextCursor).toBeNull();
  });

  it("defaults the limit to 50 and caps it at 100", async () => {
    await seed();
    const res = await callJson("GET", "/v1/messages?limit=1000");
    expect(res.status).toBe(200);
    expect(res.body.messages).toHaveLength(5);
    expect(res.body.nextCursor).toBeNull();
    expect((await call("GET", "/v1/messages?limit=0")).status).toBe(400);
  });

  it("filters by mailbox, domain, unread, starred and folder", async () => {
    const byS = await seed();
    const mailbox = await callJson("GET", "/v1/messages?mailbox=Contact@acme.test");
    expect(mailbox.body.messages.map((m: any) => m.subject)).toEqual(["Pelicans again", "Lunch?", "Invoice 1001"]);

    const domain = await callJson("GET", "/v1/messages?domain=other.test");
    expect(domain.body.messages.map((m: any) => m.subject)).toEqual(["Domain renewal"]);

    await call("PATCH", `/v1/messages/${byS["Lunch?"].id}`, { body: { read: true, starred: true } });
    const unread = await callJson("GET", "/v1/messages?unread=1&mailbox=contact@acme.test");
    expect(unread.body.messages.map((m: any) => m.subject)).toEqual(["Pelicans again", "Invoice 1001"]);
    const starred = await callJson("GET", "/v1/messages?starred=1");
    expect(starred.body.messages.map((m: any) => m.subject)).toEqual(["Lunch?"]);

    await call("PATCH", `/v1/messages/${byS["Invoice 1001"].id}`, { body: { folder: "archive" } });
    const archive = await callJson("GET", "/v1/messages?folder=archive");
    expect(archive.body.messages.map((m: any) => m.subject)).toEqual(["Invoice 1001"]);
    const inbox = await callJson("GET", "/v1/messages");
    expect(inbox.body.messages).toHaveLength(4);
    expect((await call("GET", "/v1/messages?folder=spam")).status).toBe(400);
  });

  it("searches subject, body and participants with q (prefix, AND)", async () => {
    await seed();
    await deliver(richMessage(), { from: "alice@sender.example", to: "support@acme.test" });
    const q = async (text: string, extra = "") =>
      (await callJson("GET", `/v1/messages?q=${encodeURIComponent(text)}${extra}`)).body.messages.map((m: any) => m.subject);
    expect(await q("pelican")).toEqual(["Quarterly report – final draft", "Pelicans again", "Partnership idea"]);
    expect(await q("pelican sanctuary")).toEqual(["Partnership idea"]);
    expect(await q("invo")).toEqual(["Invoice 1001"]);
    expect(await q("Renée")).toEqual(["Quarterly report – final draft"]);
    expect(await q("renee")).toEqual(["Quarterly report – final draft"]);
    expect(await q("ramen", "&mailbox=sales@acme.test")).toEqual([]);
    expect(await q('"quoted" (weird) AND OR*')).toEqual([]);
    expect(await q("   ")).toHaveLength(6);
  });
});

describe("mailboxes", () => {
  it("summarises addresses with unread and total counts", async () => {
    const byS = await seed();
    await call("PATCH", `/v1/messages/${byS["Lunch?"].id}`, { body: { read: true } });
    const { body } = await callJson("GET", "/v1/mailboxes");
    const hello = body.mailboxes.find((m: any) => m.address === "contact@acme.test");
    expect(hello).toMatchObject({ domain: "acme.test", unread: 2, total: 3 });
    expect(hello.lastAt).toBe(byS["Pelicans again"].receivedAt);
    expect(body.mailboxes.map((m: any) => m.address).sort()).toEqual(["contact@acme.test", "info@other.test", "sales@acme.test"]);
  });
});

describe("PATCH and batch", () => {
  it("updates flags and folder and returns the summary", async () => {
    const byS = await seed();
    const id = byS["Lunch?"].id;
    const res = await callJson("PATCH", `/v1/messages/${id}`, { body: { read: true, starred: true, folder: "archive" } });
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({ id, read: true, starred: true, folder: "archive" });
    const back = await callJson("PATCH", `/v1/messages/${id}`, { body: { starred: false, folder: "inbox" } });
    expect(back.body).toMatchObject({ read: true, starred: false, folder: "inbox" });
  });

  it("validates PATCH bodies and ids", async () => {
    const byS = await seed();
    const id = byS["Lunch?"].id;
    expect((await call("PATCH", `/v1/messages/${id}`, { body: { read: "yes" } })).status).toBe(400);
    expect((await call("PATCH", `/v1/messages/${id}`, { body: { folder: "junk" } })).status).toBe(400);
    expect((await call("PATCH", `/v1/messages/${id}`, { rawBody: "nope" })).status).toBe(400);
    const missing = await callJson("PATCH", "/v1/messages/NOPE", { body: { read: true } });
    expect(missing.status).toBe(404);
    expect(missing.body.error.code).toBe("not_found");
  });
});

describe("DELETE", () => {
  it("moves to trash first, then purges D1 rows and R2 objects", async () => {
    await deliver(richMessage(), { from: "alice@sender.example", to: "support@acme.test" });
    const id = (await callJson("GET", "/v1/messages")).body.messages[0].id;
    expect(await r2Keys(`att/${id}/`)).toHaveLength(1);

    const first = await callJson("DELETE", `/v1/messages/${id}`);
    expect(first.body).toEqual({ result: "trashed" });
    const trash = await callJson("GET", "/v1/messages?folder=trash");
    expect(trash.body.messages.map((m: any) => m.id)).toEqual([id]);

    const second = await callJson("DELETE", `/v1/messages/${id}`);
    expect(second.body).toEqual({ result: "purged" });
    expect((await call("GET", `/v1/messages/${id}`)).status).toBe(404);
    expect(await r2Keys(`raw/${id}`)).toEqual([]);
    expect(await r2Keys(`body/${id}`)).toEqual([]);
    expect(await r2Keys(`att/${id}/`)).toEqual([]);
    const counts = await env.DB.batch([
      env.DB.prepare("SELECT COUNT(*) AS n FROM attachments WHERE message_id = ?").bind(id),
      env.DB.prepare("SELECT COUNT(*) AS n FROM messages_fts WHERE messages_fts MATCH 'pelican'"),
    ]);
    expect(counts.map((c: any) => c.results[0].n)).toEqual([0, 0]);
    expect((await call("DELETE", `/v1/messages/${id}`)).status).toBe(404);
  });
});

describe("GET /v1/sync", () => {
  it("returns only changes after the cursor, plus tombstones", async () => {
    const start = await callJson("GET", "/v1/sync");
    expect(start.body).toMatchObject({ messages: [], deleted: [] });
    const c0 = start.body.cursor as string;

    const byS = await seed();
    const s1 = await callJson("GET", `/v1/sync?since=${c0}`);
    expect(s1.body.messages.map((m: any) => m.subject)).toEqual([
      "Invoice 1001",
      "Partnership idea",
      "Lunch?",
      "Domain renewal",
      "Pelicans again",
    ]);
    expect(s1.body.deleted).toEqual([]);
    const c1 = s1.body.cursor as string;
    expect(Number(c1)).toBeGreaterThan(Number(c0));

    const nothing = await callJson("GET", `/v1/sync?since=${c1}`);
    expect(nothing.body).toMatchObject({ messages: [], deleted: [], cursor: c1 });

    await call("PATCH", `/v1/messages/${byS["Lunch?"].id}`, { body: { read: true } });
    await call("DELETE", `/v1/messages/${byS["Invoice 1001"].id}`); // trash
    await call("DELETE", `/v1/messages/${byS["Domain renewal"].id}`); // trash
    await call("DELETE", `/v1/messages/${byS["Domain renewal"].id}`); // purge

    const s2 = await callJson("GET", `/v1/sync?since=${c1}`);
    expect(s2.body.messages.map((m: any) => [m.subject, m.folder, m.read])).toEqual([
      ["Lunch?", "inbox", true],
      ["Invoice 1001", "trash", false],
    ]);
    expect(s2.body.deleted).toEqual([byS["Domain renewal"].id]);
    expect(Number(s2.body.cursor)).toBeGreaterThan(Number(c1));
    expect((await callJson("GET", `/v1/sync?since=${s2.body.cursor}`)).body.messages).toEqual([]);
    expect((await call("GET", "/v1/sync?since=abc")).status).toBe(400);
  });
});

describe("scheduled()", () => {
  it("purges trash older than trashRetentionDays and keeps the rest", async () => {
    await setConfig({ trashRetentionDays: 30 });
    const byS = await seed();
    await call("DELETE", `/v1/messages/${byS["Lunch?"].id}`);
    await call("DELETE", `/v1/messages/${byS["Invoice 1001"].id}`);
    // Make one of them look trashed 40 days ago.
    const old = new Date(Date.now() - 40 * 86_400_000).toISOString();
    await env.DB.prepare("UPDATE messages SET trashed_at = ? WHERE id = ?").bind(old, byS["Invoice 1001"].id).run();

    await runScheduled(Date.now());
    const trash = await callJson("GET", "/v1/messages?folder=trash");
    expect(trash.body.messages.map((m: any) => m.subject)).toEqual(["Lunch?"]);
    expect(await r2Keys(`raw/${byS["Invoice 1001"].id}`)).toEqual([]);
    expect((await call("GET", `/v1/messages/${byS["Invoice 1001"].id}`)).status).toBe(404);

    // 31 days later the other one goes too; inbox is untouched.
    await runScheduled(Date.now() + 31 * 86_400_000);
    expect((await callJson("GET", "/v1/messages?folder=trash")).body.messages).toEqual([]);
    expect((await callJson("GET", "/v1/messages")).body.messages).toHaveLength(3);
  });
});
