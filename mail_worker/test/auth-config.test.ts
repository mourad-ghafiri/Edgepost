import { beforeEach, describe, expect, it } from "vitest";
import { WORKER_VERSION } from "../src/version";
import { API_KEY, call, callJson, makeEnv, resetStore } from "./helpers";

beforeEach(async () => {
  await resetStore();
});

describe("auth gate", () => {
  it("rejects a request without Authorization", async () => {
    const { status, body, response } = await callJson("GET", "/v1/health", { key: null });
    expect(status).toBe(401);
    expect(body.error.code).toBe("unauthorized");
    expect(response.headers.get("WWW-Authenticate")).toBe("Bearer");
  });

  it("rejects a wrong key of the same length and of a different length", async () => {
    const sameLength = API_KEY.slice(0, -1) + (API_KEY.endsWith("x") ? "y" : "x");
    expect((await call("GET", "/v1/health", { key: sameLength })).status).toBe(401);
    expect((await call("GET", "/v1/health", { key: "short" })).status).toBe(401);
    expect((await call("GET", "/v1/messages", { key: `${API_KEY}extra` })).status).toBe(401);
  });

  it("rejects non-Bearer schemes", async () => {
    const res = await call("GET", "/v1/health", { key: null });
    expect(res.status).toBe(401);
    const basic = await (await import("../src/index")).default.fetch(
      new Request<unknown, IncomingRequestCfProperties>("https://x.example/v1/health", { headers: { Authorization: `Basic ${API_KEY}` } }),
      makeEnv(),
      {} as ExecutionContext,
    );
    expect(basic.status).toBe(401);
  });

  it("gates unknown routes too (no route discovery without the key)", async () => {
    expect((await call("GET", "/nope", { key: null })).status).toBe(401);
    expect((await call("GET", "/nope")).status).toBe(404);
  });

  it("fails closed when MAIL_API_KEY is not configured", async () => {
    const res = await call("GET", "/v1/health", { env: makeEnv({ MAIL_API_KEY: undefined }) });
    expect(res.status).toBe(401);
  });

  it("accepts the right key (scheme is case-insensitive)", async () => {
    expect((await call("GET", "/v1/health")).status).toBe(200);
    const res = await (await import("../src/index")).default.fetch(
      new Request<unknown, IncomingRequestCfProperties>("https://x.example/v1/health", { headers: { Authorization: `bearer ${API_KEY}` } }),
      makeEnv(),
      {} as ExecutionContext,
    );
    expect(res.status).toBe(200);
  });
});

describe("health", () => {
  it("reports version, time, domains and sending state", async () => {
    await call("PUT", "/v1/config", { body: { domains: ["acme.test"] } });
    const { status, body } = await callJson("GET", "/v1/health");
    expect(status).toBe(200);
    expect(body).toMatchObject({ version: WORKER_VERSION, domains: ["acme.test"], sendingConfigured: true });
    expect(Object.keys(body).sort()).toEqual(["domains", "sendUsage", "sendingConfigured", "time", "version"]);
    expect(body.sendUsage).toEqual({ used: 0, limit: 3000, windowDays: 31, resetsAt: null });
    expect(new Date(body.time).toISOString()).toBe(body.time);
  });

  it("reports sendingConfigured=false without the EMAIL binding", async () => {
    const { body } = await callJson("GET", "/v1/health", { env: makeEnv({ EMAIL: undefined }) });
    expect(body.sendingConfigured).toBe(false);
  });
});

describe("config", () => {
  it("returns defaults", async () => {
    const { status, body } = await callJson("GET", "/v1/config");
    expect(status).toBe(200);
    expect(body).toEqual({
      domains: [],
      forwardCopies: {},
      maxInboundBytes: 25 * 1024 * 1024,
      trashRetentionDays: 30,
      monthlySendLimit: 3000,
      sendUsage: { used: 0, limit: 3000, windowDays: 31, resetsAt: null },
    });
  });

  it("applies a partial update and normalises values", async () => {
    let res = await callJson("PUT", "/v1/config", { body: { domains: ["Acme.TEST", "acme.test", "other.example."] } });
    expect(res.status).toBe(200);
    expect(res.body.domains).toEqual(["acme.test", "other.example"]);
    expect(res.body.trashRetentionDays).toBe(30);

    res = await callJson("PUT", "/v1/config", {
      body: { forwardCopies: { "Contact@Acme.test": "me@personal.example" }, trashRetentionDays: 7, maxInboundBytes: 1000 },
    });
    expect(res.body).toEqual({
      domains: ["acme.test", "other.example"],
      forwardCopies: { "contact@acme.test": "me@personal.example" },
      maxInboundBytes: 1000,
      trashRetentionDays: 7,
      monthlySendLimit: 3000,
      sendUsage: { used: 0, limit: 3000, windowDays: 31, resetsAt: null },
    });
    const get = await callJson("GET", "/v1/config");
    expect(get.body).toEqual(res.body);
  });

  it("rejects invalid values with 400", async () => {
    const cases: unknown[] = [
      { domains: "acme.test" },
      { domains: ["not a domain"] },
      { forwardCopies: { "contact@acme.test": "nope" } },
      { maxInboundBytes: -1 },
      { trashRetentionDays: 0 },
      [],
    ];
    for (const body of cases) {
      const res = await callJson("PUT", "/v1/config", { body });
      expect(res.status, JSON.stringify(body)).toBe(400);
      expect(res.body.error.code).toBe("invalid_config");
    }
    const bad = await callJson("PUT", "/v1/config", { rawBody: "{nope" });
    expect(bad.status).toBe(400);
    expect(bad.body.error.code).toBe("invalid_json");
  });

  it("returns 405 for an unsupported method", async () => {
    const res = await callJson("DELETE", "/v1/config");
    expect(res.status).toBe(405);
    expect(res.body.error.code).toBe("method_not_allowed");
  });
});
