import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { callJson, fakeEmail, makeEnv, resetStore, runScheduled, sendingError, setConfig } from "./helpers";

const DAY = 86_400_000;

function request(recipients: number, extra: Record<string, unknown> = {}) {
  const addrs = Array.from({ length: recipients }, (_, i) => ({ name: null, address: `r${i}@outside.example` }));
  return {
    from: { name: "Me", address: "contact@acme.test" },
    to: addrs.slice(0, 1),
    cc: addrs.slice(1, 2),
    bcc: addrs.slice(2),
    subject: "Budget",
    text: "Hello",
    ...extra,
  };
}

async function sendLog(): Promise<{ ts: number; recipients: number }[]> {
  const { results } = await env.DB.prepare("SELECT ts, recipients FROM send_log ORDER BY ts").all<{
    ts: number;
    recipients: number;
  }>();
  return results;
}

async function usage(): Promise<any> {
  return (await callJson("GET", "/v1/config")).body.sendUsage;
}

beforeEach(async () => {
  await resetStore();
  await env.DB.prepare("DELETE FROM send_log").run();
  await setConfig({ domains: ["acme.test"] });
});

describe("send budget", () => {
  it("lets a send under the cap through and logs its recipients (to + cc + bcc)", async () => {
    await setConfig({ monthlySendLimit: 5 });
    const email = fakeEmail();
    const before = Date.now();
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(3) });
    expect(res.status).toBe(200);
    expect(email.calls).toHaveLength(1);
    const log = await sendLog();
    expect(log.map((r) => r.recipients)).toEqual([3]);
    expect(log[0]!.ts).toBeGreaterThanOrEqual(before);
    const u = await usage();
    expect(u).toEqual({ used: 3, limit: 5, windowDays: 31, resetsAt: new Date(log[0]!.ts + 31 * DAY).toISOString() });
    // Exactly reaching the limit is allowed.
    const second = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(2) });
    expect(second.status).toBe(200);
    expect((await usage()).used).toBe(5);
  });

  it("refuses a send over the cap with 429 monthly_send_limit and never calls the binding", async () => {
    await setConfig({ monthlySendLimit: 3 });
    const email = fakeEmail();
    expect((await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(2) })).status).toBe(200);
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(2) });
    expect(res.status).toBe(429);
    expect(res.body.error.code).toBe("monthly_send_limit");
    expect(res.body.error.message).toBeTypeOf("string");
    const log = await sendLog();
    expect(res.body.error.usage).toEqual({
      used: 2,
      limit: 3,
      windowDays: 31,
      resetsAt: new Date(log[0]!.ts + 31 * DAY).toISOString(),
    });
    expect(email.calls).toHaveLength(1); // only the first send reached Email Sending
    expect(log.map((r) => r.recipients)).toEqual([2]);
    expect((await callJson("GET", "/v1/messages?folder=sent")).body.messages).toHaveLength(1);
    // A smaller send that still fits goes through.
    expect((await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(1) })).status).toBe(200);
  });

  it("never lets concurrent sends overshoot the cap", async () => {
    await setConfig({ monthlySendLimit: 4 });
    const email = fakeEmail();
    const results = await Promise.all(
      Array.from({ length: 4 }, () =>
        callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(2) }),
      ),
    );
    expect(results.map((r) => r.status).sort()).toEqual([200, 200, 429, 429]);
    expect(email.calls).toHaveLength(2);
    expect((await usage()).used).toBe(4);
  });

  it("limit 0 disables sending", async () => {
    await setConfig({ monthlySendLimit: 0 });
    const email = fakeEmail();
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(1) });
    expect(res.status).toBe(429);
    expect(res.body.error.code).toBe("monthly_send_limit");
    expect(res.body.error.usage).toEqual({ used: 0, limit: 0, windowDays: 31, resetsAt: null });
    expect(email.calls).toHaveLength(0);
    expect(await sendLog()).toEqual([]);
  });

  it("does not count sends rejected at the API boundary", async () => {
    await setConfig({ monthlySendLimit: 3 });
    const boundary = [
      "E_VALIDATION_ERROR",
      "E_FIELD_MISSING",
      "E_TOO_MANY_RECIPIENTS",
      "E_TOO_MANY_ATTACHMENTS",
      "E_CONTENT_TOO_LARGE",
      "E_SENDER_NOT_VERIFIED",
      "E_SENDER_DOMAIN_NOT_AVAILABLE",
      "E_RECIPIENT_NOT_ALLOWED",
      "E_RECIPIENT_SUPPRESSED",
      "E_RATE_LIMIT_EXCEEDED",
      "E_DAILY_LIMIT_EXCEEDED",
      "E_HEADER_NOT_ALLOWED",
      "E_HEADER_USE_API_FIELD",
      "E_HEADER_VALUE_INVALID",
      "E_HEADER_VALUE_TOO_LONG",
      "E_HEADER_NAME_INVALID",
      "E_HEADERS_TOO_LARGE",
      "E_HEADERS_TOO_MANY",
    ];
    for (const code of boundary) {
      const failing = fakeEmail(async () => {
        throw sendingError(code);
      });
      const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: failing.binding }), body: request(3) });
      expect(res.status).not.toBe(200);
      expect(res.body.error.providerCode).toBe(code);
      expect(failing.calls).toHaveLength(1);
    }
    expect(await sendLog()).toEqual([]);
    expect(await usage()).toEqual({ used: 0, limit: 3, windowDays: 31, resetsAt: null });
    // The full budget is still available.
    const ok = fakeEmail();
    expect((await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: ok.binding }), body: request(3) })).status).toBe(200);
  });

  it("keeps counting sends Cloudflare may have accepted (delivery, internal, unknown, uncoded, timeout)", async () => {
    await setConfig({ monthlySendLimit: 100 });
    const failures: [string, () => unknown, string | undefined][] = [
      ["E_DELIVERY_FAILED", () => sendingError("E_DELIVERY_FAILED"), "E_DELIVERY_FAILED"],
      ["E_INTERNAL_SERVER_ERROR", () => sendingError("E_INTERNAL_SERVER_ERROR"), "E_INTERNAL_SERVER_ERROR"],
      ["unknown code", () => sendingError("E_SOMETHING_NEW"), "E_SOMETHING_NEW"],
      ["uncoded Error", () => new Error("connection reset"), undefined],
      ["timeout", () => new DOMException("The operation timed out", "TimeoutError"), undefined],
      ["non-Error throw", () => "boom", undefined],
    ];
    let expected = 0;
    for (const [label, makeError, providerCode] of failures) {
      const failing = fakeEmail(async () => {
        throw makeError();
      });
      const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: failing.binding }), body: request(2) });
      expect(res.status, label).toBe(502);
      expect(res.body.error.code, label).toBe("delivery_failed");
      expect(res.body.error.providerCode, label).toBe(providerCode);
      expected += 2;
      expect((await usage()).used, label).toBe(expected);
    }
    expect((await sendLog()).map((r) => r.recipients)).toEqual([2, 2, 2, 2, 2, 2]);
    // Counted failures still consume the cap.
    await setConfig({ monthlySendLimit: 13 });
    const ok = fakeEmail();
    const refused = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: ok.binding }), body: request(2) });
    expect(refused.status).toBe(429);
    expect(ok.calls).toHaveLength(0);
  });

  it("uses a rolling 31-day window: 32-day-old sends no longer count", async () => {
    await setConfig({ monthlySendLimit: 10 });
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("INSERT INTO send_log (ts, recipients) VALUES (?1, ?2)").bind(now - 32 * DAY, 9),
      env.DB.prepare("INSERT INTO send_log (ts, recipients) VALUES (?1, ?2)").bind(now - 20 * DAY, 4),
      env.DB.prepare("INSERT INTO send_log (ts, recipients) VALUES (?1, ?2)").bind(now - 1 * DAY, 2),
    ]);
    const u = await usage();
    expect(u.used).toBe(6);
    expect(u.resetsAt).toBe(new Date(now - 20 * DAY + 31 * DAY).toISOString());
    // 6 used + 4 fits exactly; the 32-day-old 9 would have blocked it.
    const email = fakeEmail();
    expect((await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(4) })).status).toBe(200);
    expect((await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(1) })).status).toBe(429);
  });

  it("scheduled() prunes send_log rows older than 40 days and keeps the rest", async () => {
    const now = Date.now();
    await env.DB.batch([
      env.DB.prepare("INSERT INTO send_log (ts, recipients) VALUES (?1, ?2)").bind(now - 45 * DAY, 1),
      env.DB.prepare("INSERT INTO send_log (ts, recipients) VALUES (?1, ?2)").bind(now - 35 * DAY, 2),
      env.DB.prepare("INSERT INTO send_log (ts, recipients) VALUES (?1, ?2)").bind(now - 1 * DAY, 3),
    ]);
    await runScheduled(now);
    expect((await sendLog()).map((r) => r.recipients)).toEqual([2, 3]);
  });
});

describe("config.monthlySendLimit", () => {
  it("defaults to 3000 and accepts 0 to 100000", async () => {
    expect((await callJson("GET", "/v1/config")).body.monthlySendLimit).toBe(3000);
    for (const value of [0, 1, 100000]) {
      const res = await callJson("PUT", "/v1/config", { body: { monthlySendLimit: value } });
      expect(res.status).toBe(200);
      expect(res.body.monthlySendLimit).toBe(value);
      expect(res.body.sendUsage.limit).toBe(value);
    }
    expect((await callJson("GET", "/v1/config")).body.monthlySendLimit).toBe(100000);
  });

  it("rejects out-of-range or non-integer values with 400 invalid_config", async () => {
    for (const value of [-1, 100001, 1.5, "3000", null, true]) {
      const res = await callJson("PUT", "/v1/config", { body: { monthlySendLimit: value } });
      expect(res.status, JSON.stringify(value)).toBe(400);
      expect(res.body.error.code).toBe("invalid_config");
    }
    expect((await callJson("GET", "/v1/config")).body.monthlySendLimit).toBe(3000);
  });

  it("ignores a client-sent sendUsage", async () => {
    const res = await callJson("PUT", "/v1/config", { body: { sendUsage: { used: -5 }, monthlySendLimit: 7 } });
    expect(res.status).toBe(200);
    expect(res.body.sendUsage).toEqual({ used: 0, limit: 7, windowDays: 31, resetsAt: null });
  });

  it("health and config expose the same usage", async () => {
    await setConfig({ monthlySendLimit: 50 });
    const email = fakeEmail();
    await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request(3) });
    const health = (await callJson("GET", "/v1/health")).body.sendUsage;
    const config = (await callJson("GET", "/v1/config")).body.sendUsage;
    expect(health).toEqual(config);
    expect(health).toMatchObject({ used: 3, limit: 50, windowDays: 31 });
    expect(Date.parse(health.resetsAt)).toBeGreaterThan(Date.now() + 30 * DAY);
  });
});
