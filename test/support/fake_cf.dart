import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/cloudflare/cf_client.dart';
import 'package:edgepost/core/cloudflare/rate_limiter.dart';

/// A recorded request, for assertions.
class FakeCall {
  FakeCall(this.method, this.path, this.query, this.body);
  final String method;
  final String path;
  final Map<String, dynamic> query;
  final Object? body;

  @override
  String toString() => '$method $path $query';
}

typedef FakeHandler = FakeReply Function(FakeCall call);

class FakeReply {
  const FakeReply(this.status, this.body, {this.headers = const {}});

  /// Standard v4 success envelope.
  factory FakeReply.ok(Object? result, {Map<String, dynamic>? resultInfo}) => FakeReply(200, {
        'success': true,
        'errors': <Object>[],
        'messages': <Object>[],
        'result': result,
        'result_info': ?resultInfo,
      });

  factory FakeReply.error(int status, int code, String message) => FakeReply(status, {
        'success': false,
        'errors': [
          {'code': code, 'message': message},
        ],
        'messages': <Object>[],
        'result': null,
      });

  final int status;
  final Object? body;
  final Map<String, List<String>> headers;
}

/// In-memory Cloudflare API: route by "METHOD /path" (exact) or by a handler.
/// Unmatched requests answer 404 so tests fail loudly.
class FakeCfAdapter implements HttpClientAdapter {
  final Map<String, FakeHandler> routes = {};
  final List<FakeCall> calls = [];

  void on(String method, String path, FakeHandler handler) => routes['$method $path'] = handler;

  void reply(String method, String path, Object? result, {Map<String, dynamic>? resultInfo}) =>
      on(method, path, (_) => FakeReply.ok(result, resultInfo: resultInfo));

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    Object? body;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final text = utf8.decode(bytes, allowMalformed: true);
      try {
        body = jsonDecode(text);
      } on FormatException {
        body = text;
      }
    } else {
      body = options.data;
    }
    final path = options.uri.path.replaceFirst(RegExp(r'^/client/v4'), '');
    final call = FakeCall(options.method, path, options.uri.queryParameters, body);
    calls.add(call);
    final handler = routes['${options.method} $path'];
    final reply = handler == null ? FakeReply.error(404, 7003, 'No route for ${options.method} $path') : handler(call);
    final payload = reply.body is String ? reply.body as String : jsonEncode(reply.body);
    return ResponseBody.fromString(
      payload,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [reply.body is String ? 'text/plain' : 'application/json'],
        ...reply.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// A [CfClient] wired to [adapter] with an unlimited rate budget.
CfClient fakeClient(FakeCfAdapter adapter) {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.cloudflare.test/client/v4',
    validateStatus: (_) => true,
  ))
    ..httpClientAdapter = adapter;
  return CfClient('test-token', dio: dio, limiter: RateLimiter(budget: 100000));
}

/// Test shorthand: true → granted, false → explicitly denied.
Map<Capability, CapState> capStates(Map<Capability, bool> m) =>
    {for (final e in m.entries) e.key: e.value ? CapState.granted : CapState.denied};
