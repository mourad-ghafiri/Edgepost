import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/zone_controls/zone_controls_routes.dart';
import 'package:edgepost/features/zones/data/zones_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import 'controls_harness.dart';

const _platforms = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android});

/// Deep-links into /domains/z1/controls/purge-urls through the feature's own
/// routes, so the route wiring is exercised too.
Future<void> _pumpRouter(WidgetTester tester, FakeCfAdapter api) async {
  final cred = testCredential();
  final client = fakeClient(api);
  final router = GoRouter(
    initialLocation: '/domains/z1/controls/purge-urls',
    routes: [
      GoRoute(
        path: '/domains/:zoneId',
        builder: (c, s) => const Scaffold(body: Text('hub')),
        routes: zoneControlsRoutes,
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
        ...accountOverrides(tokens: [cred]),
        zonesProvider.overrideWith2((account) => FakeZonesNotifier(account, [testZone()])),
        cfClientProvider.overrideWith((ref, id) => client),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildEpTheme(defaultTargetPlatform, Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('rejects URLs outside the zone before sending anything', (tester) async {
    final api = FakeCfAdapter()..reply('POST', '/zones/z1/purge_cache', {'id': 'p1'});
    await _pumpRouter(tester, api);

    expect(find.text('Purge URLs'), findsWidgets);
    await tester.enterText(find.byType(EditableText), 'https://example.com/a.css\nhttps://other.org/b.css');
    await tester.pump();
    await tester.tap(find.text('Purge 1 URL'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Not on example.com: https://other.org/b.css'), findsOneWidget);
    expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
  }, variant: _platforms);

  testWidgets('purges valid URLs with a files body and returns to the controls', (tester) async {
    final api = FakeCfAdapter()..reply('POST', '/zones/z1/purge_cache', {'id': 'p1'});
    await _pumpRouter(tester, api);

    await tester.enterText(find.byType(EditableText), 'https://example.com/a.css\nhttps://cdn.example.com/b.js');
    await tester.pump();
    await tester.tap(find.text('Purge 2 URLs'));
    await tester.pumpAndSettle();

    final post = api.calls.singleWhere((c) => c.method == 'POST');
    expect(post.path, '/zones/z1/purge_cache');
    expect(post.body, {
      'files': ['https://example.com/a.css', 'https://cdn.example.com/b.js'],
    });
    expect(find.text('2 URLs purged.'), findsOneWidget);
    expect(find.text('SSL, cache & security'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
  }, variant: _platforms);
}
