import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:edgepost/features/mail/data/mail_client.dart';
import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';

const _url = 'https://edgepost-mail.example.workers.dev';

MailClient _client(HttpClientAdapter adapter) => MailClient(
      baseUrl: _url,
      apiKey: 'k',
      accountId: 'acc1',
      dio: Dio(BaseOptions(baseUrl: _url, validateStatus: (_) => true))..httpClientAdapter = adapter,
    );

/// Fails every request with a Dio error of [type].
class _Failing implements HttpClientAdapter {
  _Failing(this.type);
  final DioExceptionType type;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async =>
      throw DioException(requestOptions: o, type: type);
  @override
  void close({bool force = false}) {}
}

const _req = SendRequest(
  from: MailAddress('contact@atelier-nord.dev'),
  to: [MailAddress('lena@varga.studio')],
  subject: 'Hi',
  text: 'Hello',
);

void main() {
  group('sync', () {
    test('reads the sending budget and unread counts', () async {
      final api = FakeCfAdapter()
        ..on('GET', '/v1/sync', (_) => const FakeReply(200, {
              'messages': <Object>[],
              'deleted': <Object>[],
              'cursor': 'c2',
              'sendUsage': {'used': 2450, 'limit': 3000, 'windowDays': 31, 'resetsAt': '2026-11-01T00:00:00Z'},
              'unread': {'total': 4},
            }));
      final r = await _client(api).sync(since: 'c1');
      expect(api.calls.single.query['since'], 'c1');
      expect(r.cursor, 'c2');
      expect(r.sendUsage.used, 2450);
      expect(r.sendUsage.limit, 3000);
      expect(r.sendUsage.resetsAt, DateTime.utc(2026, 11));
      expect(r.unreadTotal, 4);
    });
  });

  group('send', () {
    test('posts attachments base64-encoded and the client message id', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/v1/send', (_) => const FakeReply(200, {
              'message': {
                'id': 'm9',
                'threadId': 't9',
                'folder': 'sent',
                'direction': 'out',
                'mailbox': 'contact@atelier-nord.dev',
                'domain': 'atelier-nord.dev',
                'from': {'address': 'contact@atelier-nord.dev'},
                'to': [
                  {'address': 'lena@varga.studio'},
                ],
                'subject': 'Hi',
                'snippet': 'Hello',
                'date': '2026-10-13T08:00:00Z',
                'read': true,
              },
            }));
      final req = SendRequest(
        from: _req.from,
        to: _req.to,
        subject: _req.subject,
        text: _req.text,
        attachments: [OutgoingAttachment(filename: 'a.txt', mimeType: 'text/plain', bytes: Uint8List.fromList('abc'.codeUnits))],
      ).withClientMessageId('cid-123');
      final m = await _client(api).send(req);
      final body = api.calls.single.body as Map;
      expect(body['clientMessageId'], 'cid-123');
      expect((body['attachments'] as List).single, {'filename': 'a.txt', 'mimeType': 'text/plain', 'contentBase64': 'YWJj'});
      expect(m.id, 'm9');
    });

    test('the encoded-size refusal keeps its code', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/v1/send', (_) => const FakeReply(413, {
              'error': {'code': 'message_too_large', 'message': 'Too large', 'size': 5600000, 'limit': 5242880},
            }));
      await expectLater(
        _client(api).send(_req),
        throwsA(isA<MailException>().having((e) => e.code, 'code', 'message_too_large').having((e) => e.status, 'status', 413)),
      );
    });
  });

  group('errors', () {
    test("a Cloudflare HTML error page is 'service_unavailable', not a generic failure", () async {
      final api = FakeCfAdapter()..on('GET', '/v1/health', (_) => const FakeReply(503, '<html>error 1102</html>'));
      await expectLater(
        _client(api).health(),
        throwsA(isA<MailException>().having((e) => e.code, 'code', 'service_unavailable').having((e) => e.status, 'status', 503)),
      );
    });

    test('no connection and timeouts are told apart', () async {
      await expectLater(
        _client(_Failing(DioExceptionType.connectionError)).health(),
        throwsA(isA<MailException>().having((e) => e.code, 'code', 'network')),
      );
      await expectLater(
        _client(_Failing(DioExceptionType.receiveTimeout)).health(),
        throwsA(isA<MailException>().having((e) => e.code, 'code', 'timeout')),
      );
    });
  });
}
