// Minimal RFC 5322 / MIME writer used for the stored copy of sent mail (raw/<id>.eml), so that
// forwarding with attachments and `size` work for sent messages too. Email Sending composes the
// real outgoing MIME itself; this is a faithful local record, not what was put on the wire.

import type { Address } from "./types";

export interface MimeAttachment {
  filename: string;
  mimeType: string;
  bytes: Uint8Array;
  inline: boolean;
  contentId: string | null;
}

export interface MimeInput {
  from: Address;
  to: Address[];
  cc: Address[];
  bcc: Address[];
  replyTo: Address | null;
  subject: string;
  date: Date;
  messageId: string | null;
  inReplyTo: string | null;
  references: string[];
  text: string;
  html: string | null;
  attachments: MimeAttachment[];
}

const encoder = new TextEncoder();

function isPrintableAscii(value: string): boolean {
  return /^[\x20-\x7e]*$/.test(value);
}

function encodeWord(value: string): string {
  if (isPrintableAscii(value)) return value;
  return `=?UTF-8?B?${encoder.encode(value).toBase64()}?=`;
}

function formatAddress(a: Address): string {
  if (!a.name) return a.address;
  const name = isPrintableAscii(a.name) ? `"${a.name.replace(/(["\\])/g, "\\$1")}"` : encodeWord(a.name);
  return `${name} <${a.address}>`;
}

function wrap76(b64: string): string {
  return b64.replace(/.{1,76}/g, "$&\r\n");
}

function quoteParam(value: string): string {
  return isPrintableAscii(value) ? `"${value.replace(/(["\\])/g, "\\$1")}"` : `"${encodeWord(value)}"`;
}

function boundary(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  return `=_ek_${[...bytes].map((b) => b.toString(16).padStart(2, "0")).join("")}`;
}

function textPart(contentType: string, value: string): string {
  return (
    `Content-Type: ${contentType}; charset=utf-8\r\n` +
    "Content-Transfer-Encoding: base64\r\n\r\n" +
    wrap76(encoder.encode(value).toBase64())
  );
}

function attachmentPart(att: MimeAttachment): string {
  const disposition = att.inline ? "inline" : "attachment";
  let headers =
    `Content-Type: ${att.mimeType}; name=${quoteParam(att.filename)}\r\n` +
    `Content-Disposition: ${disposition}; filename=${quoteParam(att.filename)}\r\n` +
    "Content-Transfer-Encoding: base64\r\n";
  if (att.contentId) headers += `Content-ID: <${att.contentId}>\r\n`;
  return `${headers}\r\n${wrap76(att.bytes.toBase64())}`;
}

function multipart(subtype: string, parts: string[]): string {
  const b = boundary();
  return (
    `Content-Type: multipart/${subtype}; boundary="${b}"\r\n\r\n` +
    parts.map((p) => `--${b}\r\n${p}\r\n`).join("") +
    `--${b}--\r\n`
  );
}

export function buildMime(input: MimeInput): Uint8Array {
  const headers: string[] = [
    `From: ${formatAddress(input.from)}`,
    `Date: ${input.date.toUTCString().replace("GMT", "+0000")}`,
    `Subject: ${encodeWord(input.subject)}`,
  ];
  if (input.to.length) headers.push(`To: ${input.to.map(formatAddress).join(", ")}`);
  if (input.cc.length) headers.push(`Cc: ${input.cc.map(formatAddress).join(", ")}`);
  if (input.bcc.length) headers.push(`Bcc: ${input.bcc.map(formatAddress).join(", ")}`);
  if (input.replyTo) headers.push(`Reply-To: ${formatAddress(input.replyTo)}`);
  if (input.messageId) headers.push(`Message-ID: ${input.messageId}`);
  if (input.inReplyTo) headers.push(`In-Reply-To: ${input.inReplyTo}`);
  if (input.references.length) headers.push(`References: ${input.references.join(" ")}`);
  headers.push("MIME-Version: 1.0");

  const body = input.html
    ? multipart("alternative", [textPart("text/plain", input.text), textPart("text/html", input.html)])
    : textPart("text/plain", input.text);
  const content =
    input.attachments.length > 0 ? multipart("mixed", [body, ...input.attachments.map(attachmentPart)]) : body;
  return encoder.encode(`${headers.join("\r\n")}\r\n${content}`);
}
