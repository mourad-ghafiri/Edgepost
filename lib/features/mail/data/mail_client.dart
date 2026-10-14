import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'mail_models.dart';

/// Error from the mail Worker (`{"error":{"code","message","providerCode"}}`).
class MailException implements Exception {
  const MailException(this.code, this.message, {this.status = 0, this.providerCode});

  final String code;
  final String message;
  final int status;
  final String? providerCode;

  bool get isNetwork => code == 'network';

  @override
  String toString() => 'MailException($code, $message)';
}

/// HTTP client for one account's mail Worker (mail_worker/API.md).
class MailClient {
  MailClient({required this.baseUrl, required String apiKey, required this.accountId, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 45),
              sendTimeout: const Duration(seconds: 90),
              validateStatus: (_) => true,
            ),
          ) {
    _dio.options.headers['Authorization'] = 'Bearer $apiKey';
  }

  final String baseUrl;
  final String accountId;
  final Dio _dio;

  Future<Map<String, dynamic>> health() => _json('GET', '/v1/health');

  Future<Map<String, dynamic>> config() => _json('GET', '/v1/config');

  Future<Map<String, dynamic>> putConfig(Map<String, dynamic> config) => _json('PUT', '/v1/config', data: config);

  Future<List<Mailbox>> mailboxes() async {
    final j = await _json('GET', '/v1/mailboxes');
    return (j['mailboxes'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((m) => Mailbox.fromJson(m, accountId: accountId))
        .toList();
  }

  Future<MessagePage> messages({
    MailFolder folder = MailFolder.inbox,
    String? mailbox,
    String? domain,
    String? query,
    bool unreadOnly = false,
    bool starredOnly = false,
    String? cursor,
    int limit = 50,
  }) async {
    final j = await _json(
      'GET',
      '/v1/messages',
      query: {
        'folder': folder.name,
        'mailbox': ?mailbox,
        'domain': ?domain,
        if (query != null && query.isNotEmpty) 'q': query,
        if (unreadOnly) 'unread': '1',
        if (starredOnly) 'starred': '1',
        'cursor': ?cursor,
        'limit': '$limit',
      },
    );
    return MessagePage(_summaries(j['messages']), j['nextCursor'] as String?);
  }

  Future<List<MessageSummary>> thread(String threadId) async =>
      _summaries((await _json('GET', '/v1/threads/${Uri.encodeComponent(threadId)}'))['messages']);

  Future<MessageDetail> message(String id) async =>
      MessageDetail.fromJson(await _json('GET', '/v1/messages/${Uri.encodeComponent(id)}'), accountId: accountId);

  Future<Uint8List> attachment(String id) => _bytes('/v1/attachments/${Uri.encodeComponent(id)}');

  Future<MessageSummary> update(String id, {bool? read, bool? starred, MailFolder? folder}) async {
    final j = await _json(
      'PATCH',
      '/v1/messages/${Uri.encodeComponent(id)}',
      data: {
        'read': ?read,
        'starred': ?starred,
        'folder': ?folder?.name,
      },
    );
    return MessageSummary.fromJson(j, accountId: accountId);
  }

  /// Moves to trash, or purges when already in trash. Returns "trashed" / "purged".
  Future<String> delete(String id) async =>
      '${(await _json('DELETE', '/v1/messages/${Uri.encodeComponent(id)}'))['result']}';

  Future<SyncResult> sync({String? since}) async {
    final j = await _json('GET', '/v1/sync', query: {'since': ?since});
    final usage = j['sendUsage'] as Map<String, dynamic>, unread = j['unread'] as Map<String, dynamic>;
    return SyncResult(
      _summaries(j['messages']),
      (j['deleted'] as List).map((e) => '$e').toList(),
      j['cursor'] as String,
      sendUsage: SendUsage.fromJson(usage),
      unreadTotal: (unread['total'] as num).toInt(),
    );
  }

  Future<MessageSummary> send(SendRequest r) async {
    final j = await _json(
      'POST',
      '/v1/send',
      data: {
        'from': r.from.toJson(),
        'to': r.to.map((a) => a.toJson()).toList(),
        'cc': r.cc.map((a) => a.toJson()).toList(),
        'bcc': r.bcc.map((a) => a.toJson()).toList(),
        'replyTo': r.replyTo?.toJson(),
        'subject': r.subject,
        'text': r.text,
        'html': r.html,
        'attachments': [
          for (final a in r.attachments)
            {'filename': a.filename, 'mimeType': a.mimeType, 'contentBase64': base64Encode(a.bytes)},
        ],
        'inReplyTo': r.inReplyTo,
        'forwardOf': r.forwardOf,
        'includeOriginalAttachments': r.includeOriginalAttachments,
        'brandLogo': r.brandLogo,
        'clientMessageId': ?r.clientMessageId,
      },
      receiveTimeout: const Duration(seconds: 120),
      sendTimeout: const Duration(seconds: 120),
    );
    return MessageSummary.fromJson(j['message'] as Map<String, dynamic>, accountId: accountId);
  }

  /// Every configured domain's signature and logo.
  /// The people sent to, most often first (`GET /v1/contacts`).
  Future<List<MailContact>> contacts() async => ((await _json('GET', '/v1/contacts'))['contacts'] as List)
      .cast<Map<String, dynamic>>()
      .map(MailContact.fromJson)
      .toList();

  Future<List<DomainBrand>> brands() async => ((await _json('GET', '/v1/brands'))['brands'] as List)
      .cast<Map<String, dynamic>>()
      .map(DomainBrand.fromJson)
      .toList();

  Future<DomainBrand> putSignature(String domain, String signature) async => DomainBrand.fromJson(
    await _json('PUT', '/v1/brands/${Uri.encodeComponent(domain)}', data: {'signature': signature}),
  );

  /// Uploads a PNG logo (see `prepareLogo`).
  Future<DomainBrand> putLogo(String domain, Uint8List png) async => DomainBrand.fromJson(
    await _json(
      'PUT',
      '/v1/brands/${Uri.encodeComponent(domain)}/logo',
      data: Stream.value(png),
      contentType: 'image/png',
      headers: {Headers.contentLengthHeader: png.length},
    ),
  );

  Future<DomainBrand> deleteLogo(String domain) async =>
      DomainBrand.fromJson(await _json('DELETE', '/v1/brands/${Uri.encodeComponent(domain)}/logo'));

  Future<Uint8List> logo(String domain) => _bytes('/v1/brands/${Uri.encodeComponent(domain)}/logo');

  List<MessageSummary> _summaries(Object? list) => (list as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((m) => MessageSummary.fromJson(m, accountId: accountId))
      .toList();

  Future<Map<String, dynamic>> _json(
    String method,
    String path, {
    Object? data,
    Map<String, dynamic>? query,
    Duration? receiveTimeout,
    Duration? sendTimeout,
    String? contentType,
    Map<String, dynamic>? headers,
  }) async {
    final Response<Object?> res;
    try {
      res = await _dio.request<Object?>(
        path,
        data: data,
        queryParameters: query,
        options: Options(
          method: method,
          contentType: contentType ?? (data == null ? null : Headers.jsonContentType),
          headers: headers,
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
        ),
      );
    } on DioException catch (e) {
      throw switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => const MailException('timeout', 'Your mail service took too long to answer.'),
        _ => const MailException('network', 'No connection to your mail service.'),
      };
    }
    if (kDebugMode) debugPrint('MAIL $method $path → ${res.statusCode}');
    final body = res.data;
    final status = res.statusCode ?? 0;
    if (status >= 400 || body is! Map<String, dynamic>) {
      final e = body is Map<String, dynamic> ? body['error'] : null;
      final err = e is Map<String, dynamic> ? e : null;
      // Cloudflare's own error pages (e.g. 1102, 5xx) aren't JSON.
      if (err == null && status >= 500) {
        throw MailException('service_unavailable', 'Mail service unavailable ($status).', status: status);
      }
      if (err == null && status == 404) throw _serviceMissing;
      throw MailException(
        '${err?['code'] ?? (status == 401 ? 'unauthorized' : 'http_$status')}',
        '${err?['message'] ?? 'Mail service error ($status).'}',
        status: status,
        providerCode: err?['providerCode'] as String?,
      );
    }
    return body;
  }

  /// The Worker answers every error, its own 404s too, as `{"error": {...}}`
  /// JSON. A 404 without it is Cloudflare saying no Worker is there: it was
  /// deleted from the account.
  static const _serviceMissing = MailException(
    'service_missing',
    'The mail service is no longer in your Cloudflare account.',
    status: 404,
  );

  static bool _isApiError(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return false;
    try {
      final j = jsonDecode(utf8.decode(bytes));
      return j is Map<String, dynamic> && j['error'] is Map;
    } on FormatException {
      return false;
    }
  }

  Future<Uint8List> _bytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(path, options: Options(responseType: ResponseType.bytes));
      if (res.statusCode == 404 && !_isApiError(res.data)) throw _serviceMissing;
      if ((res.statusCode ?? 0) >= 400) {
        throw MailException(
          'http_${res.statusCode}',
          'Couldn\'t download (${res.statusCode}).',
          status: res.statusCode ?? 0,
        );
      }
      return Uint8List.fromList(res.data ?? const []);
    } on DioException {
      throw const MailException('network', 'No connection to your mail service.');
    }
  }
}
