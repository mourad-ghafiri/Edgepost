import { errorJson } from "./http";

const encoder = new TextEncoder();

/**
 * Constant-time check of `Authorization: Bearer <key>` against `env.MAIL_API_KEY`, following
 * https://developers.cloudflare.com/workers/examples/protect-against-timing-attacks/ :
 * on a length mismatch the presented value is compared with itself (and negated) so the
 * response time does not reveal the secret's length.
 */
export function isAuthorized(request: Request, apiKey: string | undefined): boolean {
  if (!apiKey) return false; // fail closed when the secret is missing
  const header = request.headers.get("Authorization") ?? "";
  const match = /^Bearer[ \t]+(\S+)[ \t]*$/i.exec(header);
  if (!match) return false;
  const presented = encoder.encode(match[1]!);
  const secret = encoder.encode(apiKey);
  const lengthsMatch = presented.byteLength === secret.byteLength;
  return lengthsMatch
    ? crypto.subtle.timingSafeEqual(presented, secret)
    : !crypto.subtle.timingSafeEqual(presented, presented);
}

export function unauthorized(): Response {
  return errorJson(401, "unauthorized", "Missing or invalid API key", {}, { "WWW-Authenticate": "Bearer" });
}
