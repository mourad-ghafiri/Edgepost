// Runs /v1/send against Miniflare's own local send_email binding (from wrangler.jsonc) instead of
// a fake, to check the builder shape against the official local implementation. Local only.
import { describe, expect, it } from "vitest";
import { base64, callJson, deliver, resetStore, setConfig } from "./helpers";
import { richMessage } from "./fixtures";

describe("Miniflare send_email binding", () => {
  it("accepts the builder (address objects, headers, base64 and binary attachments)", async () => {
    await resetStore();
    await setConfig({ domains: ["acme.test"] });
    await deliver(richMessage(), { from: "alice@sender.example", to: "support@acme.test" });
    const original = (await callJson("GET", "/v1/messages")).body.messages[0];
    const res = await callJson("POST", "/v1/send", {
      body: {
        from: { name: "Mourad", address: "contact@acme.test" },
        to: [{ name: "Carol", address: "carol@outside.example" }],
        cc: [{ name: null, address: "dave@outside.example" }],
        replyTo: { name: null, address: "replies@acme.test" },
        subject: "Re: Quarterly report",
        text: "Thanks!",
        html: "<p>Thanks!</p>",
        inReplyTo: original.id,
        forwardOf: original.id,
        includeOriginalAttachments: true,
        attachments: [{ filename: "a.txt", mimeType: "text/plain", contentBase64: base64(new TextEncoder().encode("hello")) }],
      },
    });
    expect(res.status).toBe(200);
    expect(res.body.message.messageId).toMatch(/^<[^<>]+@acme\.test>$/);
    expect(res.body.message.threadId).toBe(original.threadId);
    expect(res.body.message.inReplyTo).toBe(original.messageId);
  });
});
