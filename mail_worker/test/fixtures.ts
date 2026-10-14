import { base64, patternBytes } from "./helpers";

const enc = new TextEncoder();

function wrap76(value: string): string {
  return value.replace(/.{1,76}/g, "$&\r\n");
}

export const PDF_BYTES = (() => {
  const header = enc.encode("%PDF-1.7\n%\xe2\xe3\xcf\xd3\n");
  const body = patternBytes(3000, 11);
  const out = new Uint8Array(header.length + body.length);
  out.set(header, 0);
  out.set(body, header.length);
  return out;
})();

export const RICH_MESSAGE_ID = "<CAF4x9Qp.20261012.abc123@mail.sender.example>";
export const RICH_SUBJECT = "Quarterly report – final draft";

/** A realistic multipart/mixed message: multipart/alternative (text + HTML) and a PDF attachment. */
export function richMessage(): string {
  const subject = `=?UTF-8?B?${base64(enc.encode(RICH_SUBJECT))}?=`;
  return [
    "Return-Path: <alice@sender.example>",
    "Received: from mail.sender.example (mail.sender.example [192.0.2.10])",
    "\tby mx.cloudflare.net with ESMTPS; Mon, 12 Oct 2026 06:15:31 +0000",
    'From: "Alice Example" <alice@sender.example>',
    "To: Support Team <support@acme.test>, bob@acme.test",
    "Cc: =?UTF-8?Q?Ren=C3=A9e_Dupont?= <renee@sender.example>",
    "Reply-To: Alice Replies <replies@sender.example>",
    `Subject: ${subject}`,
    "Date: Mon, 12 Oct 2026 08:15:30 +0200",
    `Message-ID: ${RICH_MESSAGE_ID}`,
    "List-Unsubscribe: <mailto:unsub@sender.example?subject=unsubscribe>,",
    " <https://sender.example/unsub/123>",
    "MIME-Version: 1.0",
    'Content-Type: multipart/mixed; boundary="mixed-b1"',
    "",
    "This is a multi-part message in MIME format.",
    "",
    "--mixed-b1",
    'Content-Type: multipart/alternative; boundary="alt-b2"',
    "",
    "--alt-b2",
    'Content-Type: text/plain; charset="utf-8"',
    "Content-Transfer-Encoding: quoted-printable",
    "",
    "Hi team,",
    "",
    "Please find attached the =E2=80=9Cquarterly=E2=80=9D report. The numbers for t=",
    "he pelican project look good.",
    "",
    "Thanks,",
    "Alice",
    "--alt-b2",
    'Content-Type: text/html; charset="utf-8"',
    "Content-Transfer-Encoding: quoted-printable",
    "",
    "<html><body><p>Hi team,</p><p>Please find attached the &ldquo;quarterly&rdqu=",
    "o; report. The numbers for the <b>pelican</b> project look good.</p><p>Thanks,<b=",
    "r>Alice</p></body></html>",
    "--alt-b2--",
    "",
    "--mixed-b1",
    'Content-Type: application/pdf; name="report-q3.pdf"',
    'Content-Disposition: attachment; filename="report-q3.pdf"',
    "Content-Transfer-Encoding: base64",
    "",
    wrap76(base64(PDF_BYTES)).trimEnd(),
    "--mixed-b1--",
    "",
  ].join("\r\n");
}

export interface SimpleOptions {
  from?: string;
  to?: string;
  subject?: string;
  messageId?: string;
  inReplyTo?: string;
  references?: string;
  body?: string;
  date?: string;
}

export function simpleMessage(o: SimpleOptions = {}): string {
  const lines = [
    `From: ${o.from ?? "Carol <carol@outside.example>"}`,
    `To: ${o.to ?? "contact@acme.test"}`,
    `Subject: ${o.subject ?? "Hello"}`,
    `Date: ${o.date ?? "Sun, 11 Oct 2026 10:00:00 +0000"}`,
  ];
  if (o.messageId) lines.push(`Message-ID: ${o.messageId}`);
  if (o.inReplyTo) lines.push(`In-Reply-To: ${o.inReplyTo}`);
  if (o.references) lines.push(`References: ${o.references}`);
  lines.push("MIME-Version: 1.0", 'Content-Type: text/plain; charset="utf-8"', "", o.body ?? "Just saying hello.", "");
  return lines.join("\r\n");
}
