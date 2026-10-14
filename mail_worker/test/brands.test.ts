import { beforeEach, describe, expect, it } from "vitest";
import { BRAND_LOGO_CID, MAX_LOGO_BYTES, MAX_SIGNATURE_CHARS, pngSize } from "../src/brand";
import { call, callJson, fakeEmail, makeEnv, resetStore, setConfig } from "./helpers";

/** The start of a PNG: signature and IHDR (enough for the Worker's checks). */
function png(width: number, height: number, padTo = 0): Uint8Array {
  const head = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52];
  const bytes = new Uint8Array(Math.max(33, padTo));
  bytes.set(head);
  const view = new DataView(bytes.buffer);
  view.setUint32(16, width);
  view.setUint32(20, height);
  bytes.set([8, 6, 0, 0, 0], 24);
  return bytes;
}

async function putLogo(domain: string, bytes: Uint8Array, type = "image/png"): Promise<Response> {
  const env = makeEnv();
  const { default: worker } = await import("../src/index");
  const { createExecutionContext, waitOnExecutionContext } = await import("cloudflare:test");
  const request = new Request(`https://mail.example.workers.dev/v1/brands/${domain}/logo`, {
    method: "PUT",
    headers: { Authorization: `Bearer ${env.MAIL_API_KEY}`, "Content-Type": type },
    body: bytes,
  });
  const ctx = createExecutionContext();
  const response = await worker.fetch(request as Request<unknown, IncomingRequestCfProperties>, env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

beforeEach(async () => {
  await resetStore();
  await setConfig({ domains: ["acme.test", "beta.test"] });
});

describe("brands", () => {
  it("lists every configured domain, blank until set", async () => {
    const { status, body } = await callJson("GET", "/v1/brands");
    expect(status).toBe(200);
    expect(body.brands).toEqual([
      { domain: "acme.test", signature: "", logo: null },
      { domain: "beta.test", signature: "", logo: null },
    ]);
  });

  it("saves a signature per domain, trimmed, with line breaks kept", async () => {
    const res = await callJson("PUT", "/v1/brands/ACME.test", { body: { signature: "  Mourad\r\nAcme Studio  " } });
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ domain: "acme.test", signature: "Mourad\nAcme Studio", logo: null });
    expect((await callJson("GET", "/v1/brands")).body.brands[1]).toEqual({ domain: "beta.test", signature: "", logo: null });
  });

  it("refuses unknown domains and over-long signatures", async () => {
    expect((await callJson("PUT", "/v1/brands/other.test", { body: { signature: "x" } })).body.error.code).toBe("domain_not_configured");
    const long = await callJson("PUT", "/v1/brands/acme.test", { body: { signature: "x".repeat(MAX_SIGNATURE_CHARS + 1) } });
    expect(long.status).toBe(400);
    expect(long.body.error.code).toBe("signature_too_long");
  });

  it("stores a PNG logo with the size read from the file, serves it, and removes it", async () => {
    const put = await putLogo("acme.test", png(480, 96));
    expect(put.status).toBe(200);
    const brand = (await put.json()) as { logo: { type: string; width: number; height: number; size: number } };
    expect(brand.logo).toMatchObject({ type: "image/png", width: 480, height: 96, size: 33 });

    const got = await call("GET", "/v1/brands/acme.test/logo");
    expect(got.status).toBe(200);
    expect(got.headers.get("Content-Type")).toBe("image/png");
    expect(new Uint8Array(await got.arrayBuffer())).toEqual(png(480, 96));

    const removed = await callJson("DELETE", "/v1/brands/acme.test/logo");
    expect(removed.body.logo).toBeNull();
    expect((await call("GET", "/v1/brands/acme.test/logo")).status).toBe(404);
  });

  it("refuses logos that aren't PNG, are too large, or are oddly sized", async () => {
    const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, ...new Array(40).fill(0)]);
    expect((await putLogo("acme.test", jpeg)).status).toBe(400);
    expect((await putLogo("acme.test", png(10, 10), "image/jpeg")).status).toBe(400);
    expect((await putLogo("acme.test", png(10, 10, MAX_LOGO_BYTES + 1))).status).toBe(413);
    expect((await putLogo("acme.test", png(5000, 10))).status).toBe(400);
    expect(pngSize(png(7, 3))).toEqual({ width: 7, height: 3 });
  });
});

describe("POST /v1/send with brandLogo", () => {
  const request = {
    from: { name: "Mourad", address: "contact@acme.test" },
    to: [{ name: null, address: "carol@outside.example" }],
    subject: "Hello",
    text: "Hi\n\n-- \nMourad",
    html: '<p>Hi</p><img src="cid:logo@edgepost" width="120" height="24" alt="">',
    brandLogo: true,
  };

  it("attaches the sender domain's logo inline and keeps it with the sent copy", async () => {
    await putLogo("acme.test", png(240, 48));
    const email = fakeEmail(async () => ({ messageId: "abc@email.cloudflare.example" }));
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request });
    expect(res.status).toBe(200);
    const sent = email.calls[0] as { attachments: Record<string, unknown>[] };
    expect(sent.attachments).toHaveLength(1);
    expect(sent.attachments[0]).toMatchObject({ disposition: "inline", contentId: BRAND_LOGO_CID, filename: "logo.png", type: "image/png" });
    // The logo's own bytes.
    expect(new Uint8Array(sent.attachments[0]!.content as ArrayBuffer)).toEqual(png(240, 48));
    expect(res.body.message.hasAttachments).toBe(false);

    const detail = await callJson("GET", `/v1/messages/${res.body.message.id}`);
    expect(detail.body.attachments).toEqual([
      expect.objectContaining({ filename: "logo.png", mimeType: "image/png", contentId: BRAND_LOGO_CID, inline: true }),
    ]);
  });

  it("refuses when the domain has no logo, before spending the budget", async () => {
    const used = async (): Promise<number> => (await callJson("GET", "/v1/config")).body.sendUsage.used;
    const before = await used();
    const email = fakeEmail(async () => ({ messageId: "abc@email.cloudflare.example" }));
    const res = await callJson("POST", "/v1/send", { env: makeEnv({ EMAIL: email.binding }), body: request });
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe("brand_logo_missing");
    expect(email.calls).toHaveLength(0);
    expect(await used()).toBe(before);
  });
});
