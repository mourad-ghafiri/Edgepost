import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/features/zone_controls/data/zone_settings_repository.dart';
import 'package:edgepost/features/zone_controls/presentation/zone_controls_screen.dart';
import 'package:edgepost/features/zones/data/zones_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';
import 'controls_harness.dart';

const _platforms = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android});

Map<String, dynamic> _setting(String id, Object value, {bool editable = true, int? timeRemaining}) => {
      'id': id,
      'value': value,
      'editable': editable,
      'time_remaining': ?timeRemaining,
    };

/// A zone on Free with sensible defaults; [overrides] replaces values.
FakeCfAdapter _api({Map<String, Object> overrides = const {}, Set<String> notEditable = const {}}) {
  final values = <String, Object>{
    SettingId.ssl: 'strict',
    SettingId.alwaysUseHttps: 'off',
    SettingId.httpsRewrites: 'on',
    SettingId.minTls: '1.2',
    SettingId.tls13: 'on',
    SettingId.devMode: 'off',
    SettingId.securityLevel: 'medium',
    ...overrides,
  };
  final api = FakeCfAdapter();
  for (final e in values.entries) {
    api.on('GET', '/zones/z1/settings/${e.key}', (_) {
      final dev = e.key == SettingId.devMode && values[e.key] == 'on';
      return FakeReply.ok(
        _setting(e.key, values[e.key]!, editable: !notEditable.contains(e.key), timeRemaining: dev ? 5400 : null),
      );
    });
  }
  api.reply('GET', '/zones/z1/dnssec', {
    'status': 'active',
    'ds': 'example.com. 3600 IN DS 2371 13 2 1F987CC6583E92DF0890718C42',
    'digest': '1F987CC6583E92DF0890718C42',
    'digest_type': '2',
    'digest_algorithm': 'SHA256',
    'algorithm': '13',
    'key_type': 'ECDSAP256SHA256',
    'key_tag': 2371,
    'flags': 257,
    'public_key': 'mdsswUyr3DPW132mOi8V9xESWE8jTo0dxCjjnopKl+GqJxpVXckHAeF+KkxLbxILfDLUT0rAK9iUzy1L53eKGQ==',
  });
  return api;
}

void main() {
  testWidgets('shows encryption, cache, security, pause and DNSSEC', (tester) async {
    final api = _api();
    await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));

    expect(find.text('SSL, cache & security'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Full (strict)'), findsOneWidget);
    expect(find.text('Always Use HTTPS'), findsOneWidget);
    expect(find.text('TLS 1.2'), findsOneWidget);

    await reveal(tester, find.text('Purge everything'));
    expect(find.text('Development mode'), findsOneWidget);
    await reveal(tester, find.text('Under Attack mode'));
    await reveal(tester, find.text('Pause Cloudflare'));
    await reveal(tester, find.text('DS record'));
    expect(find.text('Active'), findsWidgets);

    // One request per setting, never the bulk endpoint.
    final settingCalls = api.calls.where((c) => c.path.startsWith('/zones/z1/settings')).toList();
    expect(settingCalls, hasLength(SettingId.all.length));
    expect(settingCalls.map((c) => c.path), isNot(contains('/zones/z1/settings')));
  }, variant: _platforms);

  testWidgets('a switch saves with PATCH {value} and keeps the new value', (tester) async {
    final api = _api();
    api.on('PATCH', '/zones/z1/settings/always_use_https',
        (call) => FakeReply.ok(_setting('always_use_https', (call.body as Map)['value'] as String)));
    await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));

    final tile = find.ancestor(of: find.text('Always Use HTTPS'), matching: find.byType(MergeSemantics));
    final toggle = find.descendant(of: tile, matching: find.byType(Switch));
    expect(tester.widget<Switch>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(api.calls.last.method, 'PATCH');
    expect(api.calls.last.body, {'value': 'on'});
    expect(tester.widget<Switch>(toggle).value, isTrue);
  }, variant: _platforms);

  testWidgets('a failed save rolls back and explains why', (tester) async {
    final api = _api();
    api.on('PATCH', '/zones/z1/settings/always_use_https',
        (_) => FakeReply.error(400, 1007, 'Invalid value for zone setting always_use_https'));
    await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));

    final tile = find.ancestor(of: find.text('Always Use HTTPS'), matching: find.byType(MergeSemantics));
    final toggle = find.descendant(of: tile, matching: find.byType(Switch));
    await tester.tap(toggle);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.textContaining("Couldn't change Always Use HTTPS"), findsOneWidget);
    await tester.pump(const Duration(seconds: 6)); // let the toast expire
  }, variant: _platforms);

  testWidgets('weak SSL cocks the strip and plan-locked settings explain themselves', (tester) async {
    final api = _api(overrides: {SettingId.ssl: 'flexible'}, notEditable: {SettingId.tls13});
    await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));

    expect(find.textContaining("SSL is Flexible: traffic to your server isn't encrypted."), findsOneWidget);
    expect(find.textContaining('leave traffic between Cloudflare and your server unencrypted'), findsOneWidget);
    expect(find.text("Your plan can't change this setting."), findsOneWidget);
  }, variant: _platforms);

  testWidgets('development mode shows a live countdown', (tester) async {
    final api = _api(overrides: {SettingId.devMode: 'on'});
    await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));
    await reveal(tester, find.text('Development mode'));

    // 5400 s from the API, counted down from when it was read.
    final countdown = find.textContaining(RegExp(r'Cache bypassed\. 1:(30:00|29:\d\d) left\.'));
    expect(countdown, findsOneWidget);
    final switchTile = find.ancestor(of: find.text('Development mode'), matching: find.byType(MergeSemantics));
    expect(tester.widget<Switch>(find.descendant(of: switchTile, matching: find.byType(Switch))).value, isTrue);
    await tester.pump(const Duration(seconds: 2));
    expect(countdown, findsOneWidget);
  }, variant: _platforms);

  testWidgets('missing Zone Settings permission names the permission', (tester) async {
    final api = FakeCfAdapter();
    for (final id in SettingId.all) {
      api.on('GET', '/zones/z1/settings/$id', (_) => FakeReply.error(403, 10000, 'Authentication error'));
    }
    api.on('GET', '/zones/z1/dnssec', (_) => FakeReply.error(403, 10000, 'Authentication error'));
    await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));

    expect(find.textContaining(Capability.zoneSettings.permission), findsOneWidget);
    expect(find.text('Try again'), findsWidgets);
    // Purge stays available: it needs a different permission.
    expect(find.text('Purge everything'), findsOneWidget);
  }, variant: _platforms);

  testWidgets('pausing needs the domain typed, then updates the zone', (tester) async {
    final api = _api();
    api.on('PATCH', '/zones/z1', (call) => FakeReply.ok({
          'id': 'z1',
          'name': 'example.com',
          'status': 'active',
          'paused': (call.body as Map)['paused'],
          'account': {'id': 'a1', 'name': 'Studio'},
          'plan': {'name': 'Free Website'},
        }));
    final container = await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));
    await reveal(tester, find.text('Pause Cloudflare'));
    await tester.tap(find.text('Pause Cloudflare'));
    await tester.pumpAndSettle();

    expect(find.text('Pause Cloudflare?'), findsOneWidget);
    // The confirm button stays disabled until the domain is typed.
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.method == 'PATCH'), isEmpty);

    await tester.enterText(find.byType(EditableText).last, 'example.com');
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pumpAndSettle();

    expect(api.calls.last.method, 'PATCH');
    expect(api.calls.last.body, {'paused': true});
    expect(container.read(zoneByIdProvider('z1'))!.paused, isTrue);
    expect(find.text('Resume Cloudflare'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  }, variant: _platforms);

  testWidgets('purge everything asks for the domain, then sends purge_everything', (tester) async {
    final api = _api()..reply('POST', '/zones/z1/purge_cache', {'id': 'p1'});
    await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));
    await reveal(tester, find.text('Purge everything'));
    await tester.tap(find.text('Purge everything'));
    await tester.pumpAndSettle();

    expect(find.text('Purge all cached files?'), findsOneWidget);
    await tester.enterText(find.byType(EditableText).last, 'example.com');
    await tester.pump();
    await tester.tap(find.text('Purge everything').last);
    await tester.pumpAndSettle();

    expect(api.calls.last.path, '/zones/z1/purge_cache');
    expect(api.calls.last.body, {'purge_everything': true});
    expect(find.textContaining('Cache purged for example.com'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  }, variant: _platforms);

  testWidgets('Under Attack turns on after a confirm and off back to the earlier level', (tester) async {
    final api = _api(overrides: {SettingId.securityLevel: 'high'});
    api.on('PATCH', '/zones/z1/settings/security_level',
        (call) => FakeReply.ok(_setting('security_level', (call.body as Map)['value'] as String)));
    await pumpEp(tester, api: api, child: const ZoneControlsScreen(zoneId: 'z1'));
    await reveal(tester, find.text('Under Attack mode'));

    final tile = find.ancestor(of: find.text('Under Attack mode'), matching: find.byType(MergeSemantics));
    final toggle = find.descendant(of: tile, matching: find.byType(Switch));
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('Turn on Under Attack mode?'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();

    expect(api.calls.last.body, {'value': 'under_attack'});
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(find.text('Restored when Under Attack mode is turned off.'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(api.calls.last.body, {'value': 'high'});
    expect(tester.widget<Switch>(toggle).value, isFalse);
  }, variant: _platforms);
}
