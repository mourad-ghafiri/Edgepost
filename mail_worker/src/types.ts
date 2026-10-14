/** Bindings set by the app at upload time (see API.md "Bindings"). */
export interface Env {
  DB: D1Database;
  MAIL: R2Bucket;
  /** Email Sending binding. Optional: receiving works without it. */
  EMAIL?: SendEmail;
  /** Bearer key the app sends. */
  MAIL_API_KEY?: string;
}

export type Folder = "inbox" | "sent" | "archive" | "trash";
export const FOLDERS: readonly Folder[] = ["inbox", "sent", "archive", "trash"];

export type Direction = "in" | "out";

export type Address = { name: string | null; address: string };

export type MessageSummary = {
  id: string;
  threadId: string;
  folder: Folder;
  direction: Direction;
  mailbox: string;
  domain: string;
  from: Address;
  to: Address[];
  cc: Address[];
  replyTo: Address[];
  subject: string;
  snippet: string;
  date: string;
  receivedAt: string;
  messageId: string | null;
  inReplyTo: string | null;
  references: string[];
  read: boolean;
  starred: boolean;
  hasAttachments: boolean;
  size: number;
};

export type Attachment = {
  id: string;
  filename: string;
  mimeType: string;
  size: number;
  contentId: string | null;
  inline: boolean;
};

export type MessageDetail = MessageSummary & {
  text: string | null;
  html: string | null;
  attachments: Attachment[];
  listUnsubscribe: string | null;
};

export interface MailConfig {
  domains: string[];
  forwardCopies: Record<string, string>;
  maxInboundBytes: number;
  trashRetentionDays: number;
  /** Recipients allowed per rolling 31-day window; 0 disables sending (API.md "Send budget"). */
  monthlySendLimit: number;
}

/** Send budget usage, counted in recipients over a rolling window. */
export type SendUsage = {
  used: number;
  limit: number;
  windowDays: number;
  resetsAt: string | null;
};

export const MIB = 1024 * 1024;

export const DEFAULT_CONFIG: Readonly<MailConfig> = Object.freeze({
  domains: [],
  forwardCopies: {},
  maxInboundBytes: 25 * MIB,
  trashRetentionDays: 30,
  monthlySendLimit: 3000,
});

export const MAX_MONTHLY_SEND_LIMIT = 100_000;
