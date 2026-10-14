/** An error that maps to `{"error":{"code","message",...}}` with an HTTP status. */
export class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly extra: Record<string, unknown> = {},
  ) {
    super(message);
    this.name = "HttpError";
  }
}

const BASE_HEADERS: Record<string, string> = {
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
};

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...BASE_HEADERS, ...headers },
  });
}

export function errorJson(
  status: number,
  code: string,
  message: string,
  extra: Record<string, unknown> = {},
  headers: Record<string, string> = {},
): Response {
  return json({ error: { code, message, ...extra } }, status, headers);
}

export function fromHttpError(err: HttpError): Response {
  return errorJson(err.status, err.code, err.message, err.extra);
}

export const badRequest = (message: string, code = "invalid_request"): HttpError =>
  new HttpError(400, code, message);

export const notFound = (message = "Not found"): HttpError => new HttpError(404, "not_found", message);

export function withBaseHeaders(headers: Record<string, string>): Record<string, string> {
  return { ...BASE_HEADERS, ...headers };
}
