/// Errors raised by [CfClient]. Every failure the UI can show maps to one of
/// these, so screens never have to inspect raw Dio exceptions.
sealed class CfException implements Exception {
  const CfException(this.message);

  /// Human-readable summary, already suitable for display.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// One entry of the Cloudflare v4 `errors` array.
class CfApiError {
  const CfApiError(this.code, this.message);

  factory CfApiError.fromJson(Map<String, dynamic> json) =>
      CfApiError((json['code'] as num?)?.toInt() ?? 0, '${json['message'] ?? ''}');

  final int code;
  final String message;

  @override
  String toString() => '$code: $message';
}

/// The API answered with `success: false` or a non-2xx status.
class CfApiException extends CfException {
  CfApiException({required this.statusCode, required this.errors, String? fallback})
      : super(errors.isNotEmpty
            ? errors.map((e) => e.message).where((m) => m.isNotEmpty).join(' · ')
            : (fallback ?? 'Cloudflare returned HTTP $statusCode'));

  final int statusCode;
  final List<CfApiError> errors;

  bool hasCode(int code) => errors.any((e) => e.code == code);

  /// 403 or the generic auth error code: the token lacks a permission.
  bool get isPermissionDenied =>
      statusCode == 403 || hasCode(10000) || hasCode(9109);

  bool get isNotFound => statusCode == 404;
}

/// The token itself is invalid, expired, or revoked (HTTP 401 / code 1000).
class CfAuthException extends CfException {
  const CfAuthException([super.message = 'The API token is invalid or expired.']);
}

/// The per-token request budget was exhausted. Cloudflare blocks the token for
/// up to five minutes after a 429.
class CfRateLimitedException extends CfException {
  CfRateLimitedException(this.retryAfter)
      : super('Cloudflare rate limit reached. Try again in ${_fmt(retryAfter)}.');

  final Duration retryAfter;

  static String _fmt(Duration d) =>
      d.inMinutes >= 1 ? '${d.inMinutes} min ${d.inSeconds % 60}s' : '${d.inSeconds}s';
}

/// No network, DNS failure, TLS failure or timeout.
class CfNetworkException extends CfException {
  const CfNetworkException([super.message = 'No connection to Cloudflare.']);
}

/// A response arrived but could not be understood.
class CfProtocolException extends CfException {
  const CfProtocolException(super.message);
}

/// No stored token can do this for the account (or zone): none reaches it,
/// every one was refused [permission], or the feature needs a user token.
class CfNoAccessException extends CfException {
  const CfNoAccessException(this.permission, this.reason) : super('No token can do this: $permission.');

  /// The dashboard permission that would allow it.
  final String permission;
  final NoAccessKind reason;
}

enum NoAccessKind { noToken, denied, needsUserToken }
