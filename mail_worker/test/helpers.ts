import { createExecutionContext, createScheduledController, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import worker from "../src/index";
import type { Env } from "../src/types";

// Typed as an incoming request, as in the Workers Vitest integration docs.
const IncomingRequest = Request<unknown, IncomingRequestCfProperties>;

export const API_KEY = "test-key-7f3a9c1e5b2d8f4a6c0e9b7d";

/** The test env with an optional fake EMAIL binding (or none). */
export function makeEnv(overrides: Partial<Env> = {}): Env {
  return {
    DB: env.DB,
    MAIL: env.MAIL,
    EMAIL: env.EMAIL,
    MAIL_API_KEY: env.MAIL_API_KEY,
    ...overrides,
  };
}

export interface CallOptions {
  body?: unknown;
  rawBody?: string;
  key?: string | null;
  env?: Env;
}

export async function call(method: string, path: string, opts: CallOptions = {}): Promise<Response> {
  const headers = new Headers();
  const key = opts.key === undefined ? API_KEY : opts.key;
  if (key !== null) headers.set("Authorization", `Bearer ${key}`);
  let body: string | undefined;
  if (opts.rawBody !== undefined) body = opts.rawBody;
  else if (opts.body !== undefined) body = JSON.stringify(opts.body);
  if (body !== undefined) headers.set("Content-Type", "application/json");
  const request = new IncomingRequest(`https://mail.example.workers.dev${path}`, { method, headers, body });
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, opts.env ?? makeEnv(), ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

export async function callJson<T = any>(
  method: string,
  path: string,
  opts: CallOptions = {},
): Promise<{ status: number; body: T; response: Response }> {
  const response = await call(method, path, opts);
  const body = (await response.json()) as T;
  return { status: response.status, body, response };
}

export interface FakeInbound {
  message: ForwardableEmailMessage;
  rejects: string[];
  forwards: string[];
}

export function inboundMessage(
  raw: string | Uint8Array,
  envelope: { from: string; to: string; rawSize?: number; forwardFails?: boolean },
): FakeInbound {
  const bytes = typeof raw === "string" ? new TextEncoder().encode(raw) : raw;
  const rejects: string[] = [];
  const forwards: string[] = [];
  const headers = new Headers();
  const message = {
    from: envelope.from,
    to: envelope.to,
    headers,
    raw: new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(bytes);
        controller.close();
      },
    }),
    rawSize: envelope.rawSize ?? bytes.byteLength,
    canBeForwarded: true,
    setReject(reason: string) {
      rejects.push(reason);
    },
    async forward(rcptTo: string) {
      forwards.push(rcptTo);
      if (envelope.forwardFails) throw new Error("destination address not verified");
      return { messageId: "<fwd@example>" };
    },
    async reply() {
      throw new Error("not used");
    },
  };
  return { message: message as unknown as ForwardableEmailMessage, rejects, forwards };
}

export async function deliver(
  raw: string | Uint8Array,
  envelope: { from: string; to: string; rawSize?: number; forwardFails?: boolean },
  testEnv: Env = makeEnv(),
): Promise<FakeInbound> {
  const fake = inboundMessage(raw, envelope);
  const ctx = createExecutionContext();
  await worker.email(fake.message, testEnv, ctx);
  await waitOnExecutionContext(ctx);
  return fake;
}

export async function runScheduled(scheduledTime: number, testEnv: Env = makeEnv()): Promise<void> {
  const controller = createScheduledController({ scheduledTime, cron: "0 3 * * *" });
  const ctx = createExecutionContext();
  await worker.scheduled(controller, testEnv, ctx);
  await waitOnExecutionContext(ctx);
}

export interface FakeEmail {
  binding: SendEmail;
  calls: EmailMessageBuilder[];
}

export function fakeEmail(impl?: (builder: EmailMessageBuilder) => Promise<EmailSendResult>): FakeEmail {
  const calls: EmailMessageBuilder[] = [];
  const binding = {
    async send(builder: EmailMessageBuilder): Promise<EmailSendResult> {
      calls.push(builder);
      if (impl) return impl(builder);
      return { messageId: `${crypto.randomUUID()}@cf-sending.example` };
    },
  } as unknown as SendEmail;
  return { binding, calls };
}

/** Error shaped like Email Sending's: an Error with a `code` property. */
export function sendingError(code: string, message = `${code}: rejected`): Error {
  return Object.assign(new Error(message), { code });
}

/** Clears every table and R2 object so each test starts from an empty mailbox. */
export async function resetStore(): Promise<void> {
  // Run one API call first so the schema exists.
  await call("GET", "/v1/health");
  await env.DB.batch([
    env.DB.prepare("DELETE FROM messages_fts"),
    env.DB.prepare("DELETE FROM attachments"),
    env.DB.prepare("DELETE FROM messages"),
    env.DB.prepare("DELETE FROM tombstones"),
    env.DB.prepare("DELETE FROM config"),
    env.DB.prepare("DELETE FROM brands"),
    env.DB.prepare("UPDATE meta SET value = '0' WHERE key = 'change_seq'"),
  ]);
  let cursor: string | undefined;
  do {
    const listed = await env.MAIL.list({ cursor });
    if (listed.objects.length) await env.MAIL.delete(listed.objects.map((o) => o.key));
    cursor = listed.truncated ? listed.cursor : undefined;
  } while (cursor);
}

export async function r2Keys(prefix: string): Promise<string[]> {
  const listed = await env.MAIL.list({ prefix });
  return listed.objects.map((o) => o.key).sort();
}

export async function setConfig(config: Record<string, unknown>): Promise<void> {
  const res = await call("PUT", "/v1/config", { body: config });
  if (res.status !== 200) throw new Error(`config PUT failed: ${res.status} ${await res.text()}`);
}

export function base64(bytes: Uint8Array): string {
  return bytes.toBase64();
}

export function patternBytes(length: number, seed = 7): Uint8Array {
  const out = new Uint8Array(length);
  for (let i = 0; i < length; i++) out[i] = (i * 31 + seed) & 0xff;
  return out;
}
