import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/cloudflare/cf_errors.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/storage/cache_store.dart';
import 'package:edgepost/features/dns/data/dns_draft.dart';
import 'package:edgepost/features/dns/data/dns_providers.dart';
import 'package:edgepost/features/dns/data/dns_record.dart';
import 'package:edgepost/features/dns/data/dns_repository.dart';
import 'package:edgepost/features/zones/data/zones_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import 'dns_fixtures.dart';

const _zone = 'example.com';
const _base = '/zones/z1/dns_records';

Map<String, dynamic> _echo(FakeCall call, String id) => {
  ...(call.body as Map<String, dynamic>),
  'id': id,
  'proxiable': true,
  'created_on': '2026-10-12T09:00:00Z',
  'modified_on': '2026-10-12T09:00:00Z',
};

void main() {
  group('DnsRepository', () {
    late FakeCfAdapter api;
    late DnsRepository repo;

    setUp(() {
      api = FakeCfAdapter();
      repo = DnsRepository(fakeClient(api), 'z1');
    });

    test('lists every page of records', () async {
      api.on('GET', _base, (call) {
        final page = int.parse(call.query['page']!);
        return FakeReply.ok(
          [page == 1 ? aRecordJson() : mxJson()],
          resultInfo: {'page': page, 'per_page': 100, 'count': 1, 'total_count': 2, 'total_pages': 2},
        );
      });
      final records = await repo.list();
      expect(records.map((r) => r.type), ['A', 'MX']);
      expect(api.calls.first.query['per_page'], '100');
    });

    test('create POSTs the draft body', () async {
      api.on('POST', _base, (call) => FakeReply.ok(_echo(call, 'new1')));
      final d = DnsDraft(type: 'MX')
        ..name = '@'
        ..content = 'mx1.example.net'
        ..priority = '10'
        ..comment = 'Primary mail';
      final rec = await repo.create(d.toBody(_zone));
      expect(rec.id, 'new1');
      final call = api.calls.single;
      expect(call.method, 'POST');
      expect(call.path, _base);
      expect(call.body, {
        'type': 'MX',
        'name': 'example.com',
        'content': 'mx1.example.net',
        'priority': 10,
        'ttl': 1,
        'comment': 'Primary mail',
      });
    });

    test('same-type edit PATCHes the record', () async {
      final original = DnsRecord.fromJson(cnameJson());
      api.on('PATCH', '$_base/rec-www', (call) => FakeReply.ok(_echo(call, 'rec-www')));
      final d = DnsDraft.fromRecord(original, _zone)
        ..content = 'target.example.net'
        ..proxied = true;
      final saved = await repo.update(original, d.toBody(_zone));
      expect(saved.content, 'target.example.net');
      final call = api.calls.single;
      expect(call.method, 'PATCH');
      expect(call.body, {
        'type': 'CNAME',
        'name': 'www.example.com',
        'content': 'target.example.net',
        'ttl': 1,
        'proxied': true,
      });
    });

    test('a type change is one atomic batch: delete + post, never PATCH or PUT', () async {
      final original = DnsRecord.fromJson(cnameJson());
      api.on('POST', '$_base/batch', (call) {
        final posts = (call.body as Map)['posts'] as List;
        return FakeReply.ok({
          'deletes': [cnameJson()],
          'patches': <Object>[],
          'puts': <Object>[],
          'posts': [
            {...(posts.single as Map<String, dynamic>), 'id': 'rec-new', 'proxiable': true},
          ],
        });
      });
      final d = DnsDraft.fromRecord(original, _zone)
        ..type = 'A'
        ..content = '203.0.113.10'
        ..proxied = false;
      expect(d.isTypeChange, isTrue);
      final saved = await repo.update(original, d.toBody(_zone));
      expect(saved.id, 'rec-new');
      expect(saved.type, 'A');
      expect(api.calls, hasLength(1));
      final call = api.calls.single;
      expect('${call.method} ${call.path}', 'POST $_base/batch');
      expect(call.body, {
        'deletes': [
          {'id': 'rec-www'},
        ],
        'posts': [
          {'type': 'A', 'name': 'www.example.com', 'content': '203.0.113.10', 'ttl': 300, 'proxied': false},
        ],
      });
    });

    test('a failed batch surfaces the API error', () async {
      final original = DnsRecord.fromJson(cnameJson());
      api.on(
        'POST',
        '$_base/batch',
        (_) => FakeReply.error(400, 81053, 'An A, AAAA, or CNAME record with that host already exists.'),
      );
      final body =
          (DnsDraft.fromRecord(original, _zone)
                ..type = 'A'
                ..content = '203.0.113.10')
              .toBody(_zone);
      await expectLater(repo.update(original, body), throwsA(isA<CfApiException>()));
    });

    test('undo re-creates the deleted record with the same settings', () async {
      api.on('POST', _base, (call) => FakeReply.ok(_echo(call, 'restored')));
      final deleted = DnsRecord.fromJson(mxJson());
      final rec = await repo.recreate(deleted);
      expect(rec.id, 'restored');
      expect(api.calls.single.body, {
        'type': 'MX',
        'name': 'example.com',
        'content': 'route1.mx.cloudflare.net',
        'ttl': 3600,
        'priority': 10,
      });
    });

    test('exports BIND text', () async {
      api.on('GET', '$_base/export', (_) => const FakeReply(200, r'example.com.	1	IN	A	198.51.100.4'));
      expect(await repo.exportBind(), contains('IN\tA\t198.51.100.4'));
    });

    test('imports a zone file as multipart field "file"', () async {
      api.on('POST', '$_base/import', (_) => FakeReply.ok({'recs_added': 2, 'total_records_parsed': 3}));
      final bytes = Uint8List.fromList(utf8.encode('www 300 IN A 203.0.113.10\n'));
      final result = await repo.importBind(bytes, filename: 'zone.txt', proxied: true);
      expect((result.added, result.parsed), (2, 3));
      final body = api.calls.single.body as String;
      expect(body, contains('name="file"; filename="zone.txt"'));
      expect(body, contains('www 300 IN A 203.0.113.10'));
      expect(body, contains('name="proxied"'));
      expect(body, contains('true'));
    });

    test('refuses zone files over 256 KiB before uploading', () async {
      final big = Uint8List(DnsRepository.maxImportBytes + 1);
      await expectLater(repo.importBind(big, filename: 'big.txt'), throwsA(isA<CfApiException>()));
      expect(api.calls, isEmpty);
    });
  });

  group('DnsNotifier', () {
    late FakeCfAdapter api;
    late ProviderContainer container;

    setUp(() {
      api = FakeCfAdapter()..reply('GET', _base, [aRecordJson(), cnameJson(), mxJson()], resultInfo: onePage(3));
      final zone = fakeZone(name: _zone);
      final client = fakeClient(api);
      container = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          cacheStoreProvider.overrideWithValue(CacheStore(root: () async => Directory.systemTemp.createTempSync())),
          ...accountOverrides(tokens: [fakeToken(caps: {Capability.dns: true})]),
          zoneByIdProvider.overrideWith((ref, id) => id == 'z1' ? zone : null),
          cfClientProvider.overrideWith((ref, id) => client),
        ],
      );
      DnsNotifier.resetImportLog();
    });

    tearDown(() => container.dispose());

    Future<List<DnsRecord>> load() async => (await container.read(dnsRecordsProvider('z1').future)).data;
    List<DnsRecord> current() => container.read(dnsRecordsProvider('z1')).value!.data;

    test('loads and sorts records by type', () async {
      final list = await load();
      expect(list.map((r) => r.type), ['A', 'CNAME', 'MX']);
    });

    test('delete removes at once and rolls back when Cloudflare refuses', () async {
      await load();
      api.on('DELETE', '$_base/rec-www', (_) => FakeReply.error(403, 10000, 'Authentication error'));
      final notifier = container.read(dnsRecordsProvider('z1').notifier);
      final www = current().firstWhere((r) => r.id == 'rec-www');
      final pending = notifier.delete(www);
      expect(current().any((r) => r.id == 'rec-www'), isFalse, reason: 'optimistic removal');
      await expectLater(pending, throwsA(isA<CfApiException>()));
      expect(current().any((r) => r.id == 'rec-www'), isTrue, reason: 'rolled back');
    });

    test('delete then undo re-creates the record via POST', () async {
      await load();
      api
        ..reply('DELETE', '$_base/rec-mx', {'id': 'rec-mx'})
        ..on('POST', _base, (call) => FakeReply.ok(_echo(call, 'rec-mx-2')));
      final notifier = container.read(dnsRecordsProvider('z1').notifier);
      final mx = current().firstWhere((r) => r.id == 'rec-mx');
      await notifier.delete(mx);
      expect(current().map((r) => r.id), isNot(contains('rec-mx')));
      await notifier.restore(mx);
      expect(current().map((r) => r.id), contains('rec-mx-2'));
      final post = api.calls.last;
      expect(post.method, 'POST');
      expect(post.body, mx.toCreateBody());
    });

    test('save rolls back an optimistic edit on failure', () async {
      await load();
      api.on('PATCH', '$_base/rec-www', (_) => FakeReply.error(400, 9005, 'Content for CNAME record is invalid.'));
      final notifier = container.read(dnsRecordsProvider('z1').notifier);
      final www = current().firstWhere((r) => r.id == 'rec-www');
      final body = (DnsDraft.fromRecord(www, _zone)..content = 'bad..target').toBody(_zone);
      await expectLater(notifier.save(www, body), throwsA(isA<CfApiException>()));
      expect(current().firstWhere((r) => r.id == 'rec-www').content, 'example.com');
    });

    test('a type change replaces the record in the list', () async {
      await load();
      api.on('POST', '$_base/batch', (call) {
        final post = ((call.body as Map)['posts'] as List).single as Map<String, dynamic>;
        return FakeReply.ok({
          'deletes': [cnameJson()],
          'posts': [
            {...post, 'id': 'rec-new'},
          ],
        });
      });
      final notifier = container.read(dnsRecordsProvider('z1').notifier);
      final www = current().firstWhere((r) => r.id == 'rec-www');
      final body =
          (DnsDraft.fromRecord(www, _zone)
                ..type = 'AAAA'
                ..content = '2001:db8::1')
              .toBody(_zone);
      await notifier.save(www, body);
      expect(current().map((r) => r.id), ['023e105f4ecef8ad9ca31a8372d0c353', 'rec-new', 'rec-mx']);
    });

    test('a fourth import within a minute is refused locally', () async {
      await load();
      api.on('POST', '$_base/import', (_) => FakeReply.ok({'recs_added': 0, 'total_records_parsed': 0}));
      final notifier = container.read(dnsRecordsProvider('z1').notifier);
      final bytes = Uint8List.fromList(utf8.encode('; empty\n'));
      for (var i = 0; i < 3; i++) {
        await notifier.importBind(bytes, filename: 'z.txt', proxied: false);
      }
      await expectLater(
        notifier.importBind(bytes, filename: 'z.txt', proxied: false),
        throwsA(isA<DnsImportThrottled>()),
      );
      expect(api.calls.where((c) => c.path.endsWith('/import')), hasLength(3));
    });
  });
}
