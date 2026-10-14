import 'package:edgepost/core/cloudflare/cf_errors.dart';
import 'package:edgepost/features/zone_controls/data/purge.dart';
import 'package:edgepost/features/zone_controls/data/zone_settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';
import 'controls_harness.dart';

/// Response shape from the zone settings reference.
Map<String, dynamic> setting(String id, Object value, {bool editable = true, Object? timeRemaining}) => {
      'id': id,
      'value': value,
      'editable': editable,
      'modified_on': '2026-10-01T08:00:00Z',
      'time_remaining': ?timeRemaining,
    };

void main() {
  group('ZoneSettingsRepository settings', () {
    test('reads one setting with GET /zones/{id}/settings/{setting}', () async {
      final api = FakeCfAdapter()..reply('GET', '/zones/z1/settings/ssl', setting('ssl', 'strict'));
      final s = await ZoneSettingsRepository(fakeClient(api)).get('z1', SettingId.ssl);
      expect(s.id, 'ssl');
      expect(s.text, 'strict');
      expect(s.editable, isTrue);
      expect(s.modifiedOn, DateTime.utc(2026, 10, 1, 8));
      expect(api.calls.single.method, 'GET');
    });

    test('writes one setting with PATCH and a {value} body', () async {
      final api = FakeCfAdapter()
        ..on('PATCH', '/zones/z1/settings/always_use_https',
            (call) => FakeReply.ok(setting('always_use_https', (call.body as Map)['value'] as String)));
      final s = await ZoneSettingsRepository(fakeClient(api)).set('z1', SettingId.alwaysUseHttps, 'on');
      expect(api.calls.single.body, {'value': 'on'});
      expect(s.isOn, isTrue);
    });

    test('never uses the deprecated bulk settings endpoint', () async {
      final api = FakeCfAdapter();
      for (final id in SettingId.all) {
        api.reply('GET', '/zones/z1/settings/$id', setting(id, 'off'));
      }
      await ZoneSettingsRepository(fakeClient(api)).getMany('z1');
      expect(api.calls.map((c) => c.path), isNot(contains('/zones/z1/settings')));
      expect(api.calls, hasLength(SettingId.all.length));
    });

    test('getMany keeps the settings it could read and reports the rest', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/zones/z1/settings/ssl', setting('ssl', 'full'))
        ..reply('GET', '/zones/z1/settings/development_mode', setting('development_mode', 'on', timeRemaining: 3600))
        ..on('GET', '/zones/z1/settings/tls_1_3', (_) => FakeReply.error(403, 10000, 'Authentication error'));
      final r = await ZoneSettingsRepository(fakeClient(api))
          .getMany('z1', [SettingId.ssl, SettingId.devMode, SettingId.tls13]);
      expect(r.settings.keys, unorderedEquals(['ssl', 'development_mode']));
      expect(r.settings['development_mode']!.timeRemaining, 3600);
      expect(r.errors['tls_1_3'], isA<CfApiException>().having((e) => e.isPermissionDenied, 'permission', true));
      expect(SettingIssue.from(r.errors['tls_1_3']!).permission, isTrue);
    });

    test('time_remaining is false when dev mode was never enabled', () {
      final s = ZoneSetting.fromJson(setting('development_mode', 'off', timeRemaining: false));
      expect(s.timeRemaining, isNull);
      expect(s.isOn, isFalse);
    });
  });

  group('ZoneSettingsRepository zone actions', () {
    test('pause is PATCH /zones/{id} with {paused} and returns the zone', () async {
      final api = FakeCfAdapter()
        ..on('PATCH', '/zones/z1', (call) => FakeReply.ok({
              'id': 'z1',
              'name': 'example.com',
              'status': 'active',
              'paused': (call.body as Map)['paused'],
              'account': {'id': 'a1', 'name': 'Studio'},
              'plan': {'name': 'Free Website'},
            }));
      final zone = await ZoneSettingsRepository(fakeClient(api)).setPaused(testZone(), true);
      expect(api.calls.single.body, {'paused': true});
      expect(zone.paused, isTrue);
      expect(zone.reach, ['c1']);
      expect(zone.account.name, 'Studio');
    });

    test('purge everything sends only {"purge_everything": true}', () async {
      final api = FakeCfAdapter()..reply('POST', '/zones/z1/purge_cache', {'id': 'p1'});
      await ZoneSettingsRepository(fakeClient(api)).purgeEverything('z1');
      expect(api.calls.single.body, {'purge_everything': true});
    });

    test('purge by URL sends {"files": [...]} in batches of 100', () async {
      final api = FakeCfAdapter()..reply('POST', '/zones/z1/purge_cache', {'id': 'p1'});
      final urls = [for (var i = 0; i < 230; i++) 'https://example.com/a$i.css'];
      final progress = <int>[];
      final n = await ZoneSettingsRepository(fakeClient(api)).purgeFiles('z1', urls, onProgress: progress.add);
      expect(n, 230);
      expect(api.calls, hasLength(3));
      expect(api.calls.map((c) => ((c.body as Map)['files'] as List).length), [100, 100, 30]);
      expect((api.calls.first.body as Map).keys, ['files']);
      expect(progress, [100, 200, 230]);
    });

    test('purge rate limit (code 1134) is recognised', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/zones/z1/purge_cache', (_) => FakeReply.error(429, 1134, 'Rate limited'));
      final repo = ZoneSettingsRepository(fakeClient(api));
      Object? error;
      try {
        await repo.purgeEverything('z1');
      } on Object catch (e) {
        error = e;
      }
      expect(isPurgeRateLimited(error!), isTrue);
    });

    test('reads DNSSEC from GET /zones/{id}/dnssec', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/zones/z1/dnssec', {
          'algorithm': '13',
          'digest': '48E939042E82C22542CB377B580DFDC52A361CEFDC72E7F9107E2B6BD9306A45',
          'digest_algorithm': 'SHA256',
          'digest_type': '2',
          'ds': 'example.com. 3600 IN DS 16953 13 2 48E939042E82C22542CB377B580DFDC52A361CEFDC72E7F9107E2B6BD9306A45',
          'flags': 257,
          'key_tag': 42,
          'key_type': 'ECDSAP256SHA256',
          'modified_on': '2014-01-01T05:20:00Z',
          'public_key': 'oXiGYrSTO+LSCJ3mohc8EP+CzF9KxBj8/ydXJ22pKuZP3VAC3/Md/k7xZfz470CoRyZJ6gV6vml07IC3d8xqhA==',
          'status': 'active',
        });
      final d = await ZoneSettingsRepository(fakeClient(api)).dnssec('z1');
      expect(d.status, 'active');
      expect(d.keyTag, 42);
      expect(d.digestType, '2');
      expect(d.hasRecord, isTrue);
    });
  });

  group('checkPurgeUrls', () {
    test('accepts the zone and its subdomains, de-duplicates, skips blank lines', () {
      final r = checkPurgeUrls(
        'https://example.com/a.css\n\n  https://cdn.example.com/b.js  \nhttps://example.com/a.css\nhttp://EXAMPLE.com/c',
        'example.com',
      );
      expect(r.urls, ['https://example.com/a.css', 'https://cdn.example.com/b.js', 'http://EXAMPLE.com/c']);
      expect(r.rejected, isEmpty);
      expect(r.ok, isTrue);
    });

    test('rejects other domains, look-alikes, non-URLs and non-http schemes', () {
      final r = checkPurgeUrls(
        'https://other.com/x\nhttps://notexample.com/x\nexample.com/path\nftp://example.com/f',
        'example.com',
      );
      expect(r.urls, isEmpty);
      expect(r.rejected.map((e) => e.problem), [
        PurgeUrlProblem.otherDomain,
        PurgeUrlProblem.otherDomain,
        PurgeUrlProblem.notUrl,
        PurgeUrlProblem.notHttp,
      ]);
    });

    test('empty input is empty, not an error list', () {
      final r = checkPurgeUrls('  \n ', 'example.com');
      expect(r.isEmpty, isTrue);
      expect(r.ok, isFalse);
    });
  });

  group('PurgeCooldown', () {
    test('allows 5 purges per minute per account, then says how long to wait', () {
      var now = DateTime(2026, 10, 12, 9);
      final cd = PurgeCooldown(clock: () => now);
      for (var i = 0; i < 5; i++) {
        expect(cd.waitFor('a1'), Duration.zero);
        cd.record('a1');
        now = now.add(const Duration(seconds: 2));
      }
      expect(cd.waitFor('a1'), const Duration(seconds: 50));
      expect(cd.waitFor('a2'), Duration.zero);
      now = now.add(const Duration(seconds: 51));
      expect(cd.waitFor('a1'), Duration.zero);
    });

    test('exhaust blocks for a full window after a server-side rejection', () {
      var now = DateTime(2026, 10, 12, 9);
      final cd = PurgeCooldown(clock: () => now)..exhaust('a1');
      expect(cd.waitFor('a1'), const Duration(minutes: 1));
      now = now.add(const Duration(minutes: 1));
      expect(cd.waitFor('a1'), Duration.zero);
    });
  });

  test('chunked splits evenly with a short tail', () {
    expect(chunked([1, 2, 3, 4, 5], 2), [
      [1, 2],
      [3, 4],
      [5],
    ]);
    expect(chunked(<int>[], 3), isEmpty);
  });
}
