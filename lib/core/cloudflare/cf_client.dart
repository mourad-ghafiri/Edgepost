import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'cf_envelope.dart';
import 'cf_errors.dart';
import 'rate_limiter.dart';

/// Base URL of the Cloudflare v4 API. Overridable with
/// `--dart-define=CF_API_BASE=http://127.0.0.1:8789/client/v4` so integration
/// tests run against the local fake API instead of a real account.
const String kCfApiBase =
    String.fromEnvironment('CF_API_BASE', defaultValue: 'https://api.cloudflare.com/client/v4');

/// Typed, rate-limited client for one API token.
///
/// All Cloudflare traffic in the app goes through here: it attaches the bearer
/// token, decodes the v4 envelope, maps failures to [CfException]s, retries
/// idempotent reads on transient errors, and keeps the token inside its
/// request budget.
class CfClient {
  CfClient(this._token, {Dio? dio, RateLimiter? limiter, String baseUrl = kCfApiBase})
      : limiter = limiter ?? RateLimiter(),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              sendTimeout: const Duration(seconds: 60),
              validateStatus: (_) => true,
              headers: {'Accept': 'application/json'},
            ));

  final String _token;
  final Dio _dio;
  final RateLimiter limiter;

  Future<CfResponse> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query, idempotent: true);

  Future<CfResponse> post(String path, {Object? data, Map<String, dynamic>? query}) =>
      _send('POST', path, data: data, query: query);

  Future<CfResponse> put(String path, {Object? data, Map<String, dynamic>? query}) =>
      _send('PUT', path, data: data, query: query);

  Future<CfResponse> patch(String path, {Object? data, Map<String, dynamic>? query}) =>
      _send('PATCH', path, data: data, query: query);

  Future<CfResponse> delete(String path, {Object? data, Map<String, dynamic>? query}) =>
      _send('DELETE', path, data: data, query: query);

  /// Fetches every page of a list endpoint. Handles both `page`/`per_page`
  /// and cursor pagination. [maxPages] bounds runaway lists.
  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    Map<String, dynamic>? query,
    int perPage = 50,
    int maxPages = 40,
  }) async {
    final out = <Map<String, dynamic>>[];
    var page = 1;
    String? cursor;
    for (var i = 0; i < maxPages; i++) {
      final q = <String, dynamic>{...?query, 'per_page': perPage};
      if (cursor != null) {
        q['cursor'] = cursor;
      } else {
        q['page'] = page;
      }
      final res = await get(path, query: q);
      out.addAll(res.list);
      final info = res.resultInfo;
      if (info == null || !info.hasNextPage || res.list.isEmpty) break;
      if (info.cursor != null && info.cursor!.isNotEmpty) {
        cursor = info.cursor;
      } else {
        page++;
      }
    }
    return out;
  }

  /// Raw text endpoint (e.g. BIND export).
  Future<String> getText(String path) async {
    final res = await _raw('GET', path, responseType: ResponseType.plain, idempotent: true);
    final body = res.data;
    if ((res.statusCode ?? 0) >= 400) {
      Object? decoded = body;
      if (body is String) {
        try {
          decoded = jsonDecode(body);
        } on FormatException {
          decoded = null;
        }
      }
      CfResponse.parse(decoded, res.statusCode ?? 0);
    }
    return '$body';
  }

  /// POST to the GraphQL Analytics API. Returns `data`, throws on `errors`.
  Future<Map<String, dynamic>> graphql(String query, {Map<String, dynamic>? variables}) async {
    final res = await _raw('POST', '/graphql',
        data: {'query': query, 'variables': ?variables}, idempotent: true);
    final body = res.data;
    if (res.statusCode == 401) throw const CfAuthException();
    if (body is! Map<String, dynamic>) {
      throw CfApiException(statusCode: res.statusCode ?? 0, errors: const []);
    }
    final errors = body['errors'];
    if (errors is List && errors.isNotEmpty) {
      // GraphQL answers 200 even when the token lacks Analytics access; report
      // that as a 403 so screens explain the missing permission.
      final text = errors.map((e) => e is Map ? '${e['message']}' : '$e').join(' ').toLowerCase();
      final denied = text.contains('not authorized') || text.contains('does not have access') || text.contains('permission');
      throw CfApiException(
        statusCode: denied ? 403 : (res.statusCode ?? 0),
        errors: errors
            .whereType<Map<String, dynamic>>()
            .map((e) => CfApiError(0, '${e['message'] ?? 'GraphQL error'}'))
            .toList(),
      );
    }
    return (body['data'] as Map<String, dynamic>?) ?? const {};
  }

  Future<CfResponse> _send(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    bool idempotent = false,
  }) async {
    final res = await _raw(method, path, data: data, query: query, idempotent: idempotent);
    return CfResponse.parse(res.data, res.statusCode ?? 0);
  }

  Future<Response<Object?>> _raw(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    bool idempotent = false,
    ResponseType responseType = ResponseType.json,
  }) async {
    var attempt = 0;
    while (true) {
      if (!await limiter.acquire()) {
        throw CfRateLimitedException(limiter.delayBeforeNext());
      }
      try {
        final res = await _dio.request<Object?>(
          path,
          data: data,
          queryParameters: query,
          options: Options(
            method: method,
            responseType: responseType,
            headers: {'Authorization': 'Bearer $_token'},
            contentType: data is FormData ? null : Headers.jsonContentType,
          ),
        );
        final status = res.statusCode ?? 0;
        if (status == 429) {
          final retryAfter = _retryAfter(res.headers) ?? const Duration(minutes: 5);
          limiter.blockFor(retryAfter);
          throw CfRateLimitedException(retryAfter);
        }
        if (status >= 500 && idempotent && attempt < 2) {
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: 600 * (1 << attempt)));
          continue;
        }
        _debugLog(method, path, status);
        return res;
      } on DioException catch (e) {
        if (idempotent && attempt < 2 && _isTransient(e)) {
          attempt++;
          await Future<void>.delayed(Duration(milliseconds: 600 * (1 << attempt)));
          continue;
        }
        throw CfNetworkException(_networkMessage(e));
      }
    }
  }

  static Duration? _retryAfter(Headers headers) {
    final v = headers.value('retry-after');
    final s = v == null ? null : int.tryParse(v.trim());
    return s == null ? null : Duration(seconds: s);
  }

  static bool _isTransient(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.connectionError;

  static String _networkMessage(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          'Cloudflare took too long to answer.',
        DioExceptionType.badCertificate => 'The secure connection could not be verified.',
        _ => 'No connection to Cloudflare.',
      };

  static void _debugLog(String method, String path, int status) {
    // Never logs headers or bodies: they can carry the token or mail content.
    if (kDebugMode) debugPrint('CF $method $path → $status');
  }
}
