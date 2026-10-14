import 'dart:async';
import 'dart:convert';

import 'package:edgepost/features/compute/data/compute_api.dart';
import 'package:edgepost/features/compute/data/tail.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';

// Trace messages shaped like wrangler's TailEventMessage
// (github.com/cloudflare/workers-sdk, packages/wrangler/src/tail/createTail.ts)
// and the Tail Workers TailItem
// (https://developers.cloudflare.com/workers/runtime-apis/handlers/tail/).
const _requestEvent = '''
{
  "outcome": "ok",
  "scriptName": "my-worker",
  "exceptions": [],
  "logs": [
    {"message": ["Handling", {"path": "/api/users"}], "level": "log", "timestamp": 1760259600123},
    {"message": ["cache miss"], "level": "warn", "timestamp": 1760259600130}
  ],
  "eventTimestamp": 1760259600100,
  "event": {
    "request": {
      "url": "https://api.example.com/api/users?page=2",
      "method": "get",
      "headers": {"accept": "application/json", "cf-connecting-ip": "REDACTED"},
      "cf": {"colo": "CDG", "country": "FR", "httpProtocol": "HTTP/2"}
    },
    "response": {"status": 200}
  }
}
''';

const _exceptionEvent = '''
{
  "outcome": "exception",
  "scriptName": "my-worker",
  "exceptions": [
    {"name": "TypeError", "message": "Cannot read properties of undefined (reading 'id')", "timestamp": 1760259601200}
  ],
  "logs": [
    {"message": ["Failed to load user"], "level": "error", "timestamp": 1760259601190}
  ],
  "eventTimestamp": 1760259601100,
  "event": {
    "request": {"url": "https://api.example.com/api/users/42", "method": "POST", "headers": {}, "cf": {}},
    "response": {"status": 500}
  }
}
''';

const _scheduledEvent = '''
{"outcome": "ok", "scriptName": "my-worker", "exceptions": [], "logs": [],
 "eventTimestamp": 1760259700000, "event": {"cron": "*/5 * * * *", "scheduledTime": 1760259700000}}
''';

const _overload = '''
{"outcome": "ok", "scriptName": "my-worker", "exceptions": [], "logs": [], "eventTimestamp": 1760259800000,
 "event": {"message": "Tail is currently in sampling mode due to the high volume of messages.", "type": "overload"}}
''';

class FakeSocket implements TailSocket {
  final controller = StreamController<Object?>();
  final sent = <String>[];
  bool closed = false;

  @override
  Future<void> get ready async {}

  @override
  Stream<Object?> get stream => controller.stream;

  @override
  void send(String message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

void main() {
  group('TailEvent.parse', () {
    test('request event with logs and response status', () {
      final e = TailEvent.parse(_requestEvent)!;
      expect(e.kind, TailEventKind.request);
      expect(e.method, 'GET');
      expect(e.url, 'https://api.example.com/api/users?page=2');
      expect(e.status, 200);
      expect(e.outcome, 'ok');
      expect(e.failed, isFalse);
      expect(e.logs.map((l) => l.level), [TailLevel.log, TailLevel.warn]);
      expect(e.logs.first.message, 'Handling {"path":"/api/users"}');
      expect(e.timestamp, DateTime.fromMillisecondsSinceEpoch(1760259600100, isUtc: true).toLocal());
    });

    test('exception event', () {
      final e = TailEvent.parse(utf8.encode(_exceptionEvent))!; // binary frames decode too
      expect(e.failed, isTrue);
      expect(e.status, 500);
      expect(e.exceptions.single.name, 'TypeError');
      expect(e.exceptions.single.message, contains("reading 'id'"));
      expect(e.logs.single.level, TailLevel.error);
    });

    test('scheduled and overload info events', () {
      final s = TailEvent.parse(_scheduledEvent)!;
      expect(s.kind, TailEventKind.scheduled);
      expect(s.cron, '*/5 * * * *');
      final o = TailEvent.parse(_overload)!;
      expect(o.kind, TailEventKind.info);
      expect(o.infoType, 'overload');
    });

    test('ignores non-JSON frames', () {
      expect(TailEvent.parse('not json'), isNull);
      expect(TailEvent.parse(42), isNull);
    });
  });

  group('TailController', () {
    late FakeCfAdapter api;
    late FakeSocket socket;
    Uri? connectedTo;

    setUp(() {
      api = FakeCfAdapter()
        ..on('POST', '/accounts/a1/workers/scripts/my-worker/tails', (call) {
          expect(call.body, {'filters': <Object>[]});
          return FakeReply.ok({
            'id': '03dc9f77817b488fb26c5861ec18f791',
            'url': 'wss://tail.developers.workers.dev/03dc9f77817b488fb26c5861ec18f791',
            'expires_at': '2026-10-12T15:00:00Z',
          });
        })
        ..reply('DELETE', '/accounts/a1/workers/scripts/my-worker/tails/03dc9f77817b488fb26c5861ec18f791', null);
      socket = FakeSocket();
      connectedTo = null;
    });

    TailController make() => TailController(
      api: ComputeApi(fakeClient(api)),
      accountId: 'a1',
      script: 'my-worker',
      connector: (url) {
        connectedTo = url;
        return socket;
      },
    );

    test('starts, streams, pauses, resumes and deletes the tail on stop', () async {
      final t = make();
      await t.start();
      expect(t.status, TailStatus.live);
      expect(connectedTo.toString(), startsWith('wss://tail.developers.workers.dev/'));
      expect(socket.sent, ['{"debug":false}']);
      expect(t.expiresAt, DateTime.utc(2026, 10, 12, 15));

      socket.controller.add(_requestEvent);
      await pumpEventQueue();
      expect(t.events, hasLength(1));

      t.pause();
      socket.controller.add(_exceptionEvent);
      await pumpEventQueue();
      expect(t.events, hasLength(1));
      expect(t.heldCount, 1);

      t.resume();
      expect(t.events, hasLength(2));
      expect(t.events.last.failed, isTrue);

      t.clear();
      expect(t.events, isEmpty);

      await t.stop();
      expect(t.status, TailStatus.stopped);
      expect(socket.closed, isTrue);
      expect(api.calls.last.method, 'DELETE');
      t.dispose();
    });

    test('a closed socket ends the session and deletes the tail', () async {
      final t = make();
      await t.start();
      await socket.controller.close();
      await pumpEventQueue();
      expect(t.status, TailStatus.ended);
      expect(api.calls.where((c) => c.method == 'DELETE'), hasLength(1));
      t.dispose();
    });

    test('dispose cleans up without a stop', () async {
      final t = make();
      await t.start();
      t.dispose();
      await pumpEventQueue();
      expect(socket.closed, isTrue);
      expect(api.calls.where((c) => c.method == 'DELETE'), hasLength(1));
    });

    test('keeps at most maxEvents', () async {
      final t = TailController(
        api: ComputeApi(fakeClient(api)),
        accountId: 'a1',
        script: 'my-worker',
        connector: (_) => socket,
        maxEvents: 3,
      );
      await t.start();
      for (var i = 0; i < 5; i++) {
        socket.controller.add(_scheduledEvent);
      }
      await pumpEventQueue();
      expect(t.events, hasLength(3));
      t.dispose();
    });
  });
}
