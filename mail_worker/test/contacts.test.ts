import { beforeEach, describe, expect, it } from "vitest";
import { callJson, deliver, fakeEmail, makeEnv, resetStore, setConfig } from "./helpers";
import { simpleMessage } from "./fixtures";

const ME = { name: "Mourad", address: "contact@acme.test" };

async function send(to: { name: string | null; address: string }[], cc: { name: string | null; address: string }[] = []) {
  const email = fakeEmail(async () => ({ messageId: `${crypto.randomUUID()}@email.cloudflare.example` }));
  const res = await callJson("POST", "/v1/send", {
    env: makeEnv({ EMAIL: email.binding }),
    body: { from: ME, to, cc, bcc: [{ name: null, address: "hidden@outside.example" }], subject: "Hi", text: "Hello" },
  });
  expect(res.status).toBe(200);
}

beforeEach(async () => {
  await resetStore();
  await setConfig({ domains: ["acme.test"] });
});

describe("GET /v1/contacts", () => {
  it("needs the key", async () => {
    expect((await callJson("GET", "/v1/contacts", { key: null })).status).toBe(401);
  });

  it("is empty before anything is sent", async () => {
    const { status, body } = await callJson("GET", "/v1/contacts");
    expect(status).toBe(200);
    expect(body).toEqual({ contacts: [] });
  });

  it("ranks To and Cc recipients of sent mail by how often, then how recently", async () => {
    await send([{ name: "Carol", address: "carol@outside.example" }]);
    await send([{ name: null, address: "Dave@Outside.example" }], [{ name: null, address: "carol@outside.example" }]);
    await send([{ name: "Lena Berg", address: "lena@client.example" }]);
    // Received mail is not someone you sent to.
    await deliver(simpleMessage(), { from: "lena@client.example", to: "contact@acme.test" });

    const { body } = await callJson("GET", "/v1/contacts");
    const contacts = body.contacts as { address: string; name: string | null; count: number; lastSent: string }[];
    expect(contacts.map((c) => [c.address, c.name, c.count])).toEqual([
      ["carol@outside.example", "Carol", 2],
      ["lena@client.example", "Lena Berg", 1],
      ["dave@outside.example", null, 1],
    ]);
    expect(contacts.every((c) => !Number.isNaN(Date.parse(c.lastSent)))).toBe(true);
    expect(contacts.some((c) => c.address === "hidden@outside.example")).toBe(false);
  });

  it("counts an address once per message", async () => {
    await send([{ name: null, address: "carol@outside.example" }], [{ name: "Carol", address: "CAROL@outside.example" }]);
    const { body } = await callJson("GET", "/v1/contacts");
    expect(body.contacts).toEqual([
      expect.objectContaining({ address: "carol@outside.example", name: "Carol", count: 1 }),
    ]);
  });
});
