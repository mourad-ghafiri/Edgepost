# Edgepost Mail Worker: HTTP API contract (v1)

The Worker `edgepost-mail` runs in the **user's own Cloudflare account**. The app deploys it, Email Routing
delivers inbound mail to its `email()` handler, and the app talks to its `fetch()` handler over this API.
It is the only mailbox, because Cloudflare has none
(https://developers.cloudflare.com/email-service/examples/email-routing/email-storage/).

## Bindings (set by the app at upload time)

| Binding | Type | Purpose |
|---|---|---|
| `DB` | D1 | message index, threads, attachments metadata, full-text search, config |
| `MAIL` | R2 | raw `.eml`, parsed bodies, attachment bytes |
| `EMAIL` | send_email | outbound mail via Email Sending (`env.EMAIL.send({...})`) |
| `MAIL_API_KEY` | secret_text | bearer key the app sends; compared in constant time |

The Worker creates its D1 schema itself (one idempotent `CREATE … IF NOT EXISTS` set, applied once per isolate), so the app never runs SQL. There are no schema versions or migrations.

## Conventions

- Every request sends `Authorization: Bearer <MAIL_API_KEY>`. Anything else returns `401 {"error":{"code":"unauthorized"}}`.
- JSON in, JSON out (UTF-8). Times are ISO 8601 UTC strings. IDs are opaque, time-sortable strings (ULID).
- An error is `{"error":{"code":"<snake_case>","message":"<human text>"}}` with a meaningful HTTP status.
- Addresses are `{"name": string|null, "address": string}`.
- Lists are cursor-paged: `?cursor=&limit=` (default 50, max 100). The response carries `nextCursor` (null at the end).

## Types

```ts
type Address = { name: string | null; address: string };

type MessageSummary = {
  id: string;
  threadId: string;
  folder: "inbox" | "sent" | "archive" | "trash";
  direction: "in" | "out";
  mailbox: string;          // domain address it landed on (envelope `to`) or was sent from
  domain: string;           // mailbox's domain
  from: Address;
  to: Address[];
  cc: Address[];
  replyTo: Address[];
  subject: string;
  snippet: string;          // first ~160 chars of the text body, whitespace collapsed
  date: string;             // Date header, falling back to receivedAt
  receivedAt: string;
  messageId: string | null; // RFC 5322 Message-ID including angle brackets
  inReplyTo: string | null;
  references: string[];
  read: boolean;
  starred: boolean;
  hasAttachments: boolean;
  size: number;             // raw bytes
};

type Attachment = {
  id: string; filename: string; mimeType: string; size: number;
  contentId: string | null; inline: boolean;
};

type MessageDetail = MessageSummary & {
  text: string | null;
  html: string | null;      // as received; the app renders it sandboxed (no JS, remote content blocked)
  attachments: Attachment[];
  listUnsubscribe: string | null;
};
```

## Endpoints

| Method & path | Body / query | Response |
|---|---|---|
| `GET /v1/health` | none | `{version, time, domains: string[], sendingConfigured: boolean, sendUsage: SendUsage}` |
| `GET /v1/config` | none | `{domains: string[], forwardCopies: {[mailbox]: string}, maxInboundBytes, trashRetentionDays, monthlySendLimit, sendUsage: SendUsage}` |
| `PUT /v1/config` | same shape (partial allowed) | updated config |
| `GET /v1/mailboxes` | none | `{mailboxes: [{address, domain, unread, total, lastAt}]}` |
| `GET /v1/messages` | `folder` (default inbox), `mailbox`, `domain`, `q` (full-text), `unread=1`, `starred=1`, `cursor`, `limit` | `{messages: MessageSummary[], nextCursor}`, newest first |
| `GET /v1/threads/:threadId` | none | `{messages: MessageSummary[]}`, oldest first |
| `GET /v1/messages/:id` | none | `MessageDetail` |
| `GET /v1/attachments/:id` | none | bytes, with `Content-Type` and `Content-Disposition` |
| `PATCH /v1/messages/:id` | `{read?, starred?, folder?}` | `MessageSummary` |
| `DELETE /v1/messages/:id` | none | `{result: "trashed" \| "purged"}`. Outside trash it moves to trash; in trash it purges the D1 rows and R2 objects |
| `GET /v1/sync` | `since` (opaque cursor; omit for "latest only") | `{messages: MessageSummary[], deleted: string[], cursor, hasMore, sendUsage: SendUsage, unread: {total}}`: changes after `since` plus the live counters |
| `POST /v1/send` | `SendRequest` | `{message: MessageSummary, providerMessageId, duplicate: boolean}`. `duplicate` is true when `clientMessageId` repeats a send from the last 15 min |
| `GET /v1/contacts` | none | `{contacts: [{address, name, count, lastSent}]}`: To and Cc recipients of the last 2,000 outgoing messages (addresses lower-cased, the latest display name, messages sent to, last ISO date), most often then most recent first, at most 500. Bcc is not kept, so never listed. For the app's recipient suggestions |
| `GET /v1/brands` | none | `{brands: Brand[]}`, one per configured domain, in config order |
| `PUT /v1/brands/:domain` | `{signature: string}` (≤ 2,000 characters; `\r\n` normalised, trimmed) | `Brand` |
| `GET /v1/brands/:domain/logo` | none | PNG bytes; 404 when the domain has no logo |
| `PUT /v1/brands/:domain/logo` | PNG bytes, `Content-Type: image/png`, ≤ 256 KiB, each side 1–2,000 px (read from the file) | `Brand` |
| `DELETE /v1/brands/:domain/logo` | none | `Brand` |

```ts
type SendRequest = {
  from: Address;                 // must be on one of config.domains
  to: Address[]; cc?: Address[]; bcc?: Address[];
  replyTo?: Address | null;
  subject: string;
  text: string;                  // full body including any quote the app composed
  html?: string | null;
  attachments?: { filename: string; mimeType: string; contentBase64: string }[];
  inReplyTo?: string | null;     // LOCAL id of the message being replied to
  forwardOf?: string | null;     // LOCAL id of the message being forwarded
  includeOriginalAttachments?: boolean; // with forwardOf: re-attach originals from R2
  brandLogo?: boolean;           // attach the From domain's logo inline (Content-ID logo@edgepost)
  clientMessageId?: string | null; // 8–100 chars; idempotency key
};

type Brand = {
  domain: string;
  signature: string;             // plain text; the app renders it into the text and HTML parts
  logo: { type: "image/png"; size: number; width: number; height: number; updatedAt: string } | null;
};
```

### Domain branding

Each domain the mail service handles has a signature and an optional logo; a domain outside
`config.domains` is `404 domain_not_configured`. The app puts the signature into the message it
composes (and lets the user edit it per message). With `brandLogo: true`, the Worker adds the From
domain's logo to the message as an **inline** attachment with Content-ID `logo@edgepost`
(https://developers.cloudflare.com/email-service/api/send-emails/workers-api/), so the HTML's
`<img src="cid:logo@edgepost">` shows without loading remote images. The logo counts toward the
5 MiB size limit and is kept with the sent copy; it doesn't set `hasAttachments`. A domain without a
logo is `400 brand_logo_missing`, before anything is sent or counted.

### Send budget

Email Sending has no spending cap: Workers Paid includes 3,000 emails per month, then $0.35 per 1,000
(https://developers.cloudflare.com/email-service/platform/pricing/). The Worker enforces its own cap so a
user can never be billed for overage by accident.

- `config.monthlySendLimit`: integer 0–100000, default **3000**. `0` disables sending.
- Usage is counted in **recipients** (to + cc + bcc) in a rolling **31-day** window. This window is
  deliberately conservative, because Cloudflare's quota follows the billing cycle and not the calendar
  month. A send is counted unless Email Sending rejects it at the API boundary with a documented `E_*`
  rejection (validation, header, size, sender/recipient, rate-limit codes). Delivery failures, internal
  errors and unknown errors are counted, because Cloudflare may already have accepted and billed them.
- `PUT /v1/config` answers `400 invalid_config` for out-of-range values.
- A send that would push usage over the limit is refused **before** calling Email Sending, with
  `429 monthly_send_limit` and `error.usage`. Refused sends never reach Cloudflare, so they never count
  toward its quota.
- `SendUsage = {used: number, limit: number, windowDays: 31, resetsAt: string|null}`. `resetsAt` is when
  the oldest counted send leaves the window.

### Reply and forward semantics (server side)

- **`inReplyTo`.** The Worker loads the parent message and sets these headers:
  - `In-Reply-To: <parent Message-ID>`
  - `References: <parent References…> <parent Message-ID>`, trimmed to the first and the last 18 entries when long.

  Both headers are on Email Sending's allowlist (https://developers.cloudflare.com/email-service/reference/headers/). The sent copy joins the parent's `threadId`.
- **`forwardOf`** with `includeOriginalAttachments`. The Worker attaches the original's attachments from R2. The total must stay within the 5 MiB outbound limit, otherwise the response is `413 content_too_large`.
- **`Message-ID`.** Cloudflare sets it. The Worker stores the `messageId` returned by `send()` on the sent copy (normalised to `<…>`), so replies to sent mail thread correctly.
- **Size.** The 5 MiB limit applies to the message *as sent*: each attachment counts `4·⌈n/3⌉·1.027 + 300`
  bytes, text and HTML count UTF-8 bytes × 1.03, plus about 2 KB of headers. Over the limit the response is
  `413 {"error":{"code":"content_too_large","size":…,"limit":5242880}}`.
- **Idempotency.** A repeated `clientMessageId` that already succeeded within 15 min returns the first result
  with `duplicate: true`. While it's still sending, the answer is `409 send_in_progress`. A failed send frees
  the id.
- **Sender check.** `from.address` must belong to `config.domains`, otherwise the response is `403 sender_not_allowed`.

### Send error mapping (`E_*` from Email Sending → HTTP)

| Email Sending | HTTP | `error.code` |
|---|---|---|
| E_VALIDATION_ERROR, E_FIELD_MISSING, E_HEADER_* | 400 | `invalid_message` |
| E_TOO_MANY_RECIPIENTS | 400 | `too_many_recipients` |
| E_TOO_MANY_ATTACHMENTS, E_CONTENT_TOO_LARGE | 413 | `content_too_large` |
| E_SENDER_NOT_VERIFIED, E_SENDER_DOMAIN_NOT_AVAILABLE | 403 | `sender_domain_not_onboarded` |
| E_RECIPIENT_NOT_ALLOWED | 403 | `recipient_not_allowed` (Workers Paid / onboarding needed) |
| E_RECIPIENT_SUPPRESSED | 409 | `recipient_suppressed` |
| E_RATE_LIMIT_EXCEEDED, E_DAILY_LIMIT_EXCEEDED | 429 | `sending_limit` |
| E_DELIVERY_FAILED, E_INTERNAL_SERVER_ERROR, other | 502 | `delivery_failed` |
| *(Worker's own cap, before calling Email Sending)* | 429 | `monthly_send_limit` |

The original `E_*` code is echoed as `error.providerCode`.

## Inbound (`email()` handler)

1. If `message.rawSize` exceeds `config.maxInboundBytes` (default 25 MiB), call `setReject("Message too large")`.
2. If `config.domains` is non-empty and the envelope `to` is on none of them, call `setReject("Unknown recipient")`.
3. Read `message.raw` and store it at R2 `raw/<id>.eml`. Parse it with `postal-mime`.
4. Resolve the thread:
   - First by `In-Reply-To` / `References` against stored `messageId`s.
   - Otherwise a new thread whose id is the message id.
5. Store bodies at R2 `body/<id>.json` (`{text, html}`) and attachments at `att/<id>/<n>`. Insert D1 rows (message, attachments, FTS) and bump the change sequence.
6. If `config.forwardCopies[mailbox]` is set, call `message.forward(dest)`. The destination must be verified; failures are logged and never block storage.

## Scheduled (`scheduled()` handler, daily cron set by the app)

Purges trash older than `trashRetentionDays` (default 30).
