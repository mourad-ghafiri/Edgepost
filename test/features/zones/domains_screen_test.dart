import 'package:edgepost/core/cloudflare/models.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/analytics/data/traffic_providers.dart';
import 'package:edgepost/features/zones/data/zones_providers.dart';
import 'package:edgepost/core/strip/strip.dart';
import 'package:edgepost/features/zones/presentation/domains_screen.dart';
import 'package:edgepost/features/zones/presentation/zone_hub_screen.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/accounts.dart';

final _zones = [
  fakeZone(id: 'z1', name: 'atelier-nord.dev'),
  fakeZone(id: 'z2', name: 'fieldnotes.blog'),
];

class _Zones extends ZonesNotifier {
  _Zones(super.accountId);
  @override
  Future<Synced<List<Zone>>> build() async => Synced(_zones, DateTime.now());
}

class _Pinned extends PinnedZonesNotifier {
  _Pinned(super.accountId);
  @override
  Future<Set<String>> build() async => const {};
}

class _Fleet extends FleetTrafficNotifier {
  _Fleet(super.accountId, this.traffic);
  final Map<String, ZoneTraffic>? traffic;
  @override
  Future<Synced<Map<String, ZoneTraffic>>> build() async =>
      traffic == null ? throw StateError('no Analytics access') : Synced(traffic!, DateTime.now());
}

Future<void> _pump(WidgetTester tester, Map<String, ZoneTraffic>? traffic, {Size size = const Size(393, 852)}) async {
  tester.view
    ..physicalSize = size * 3
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        ...accountOverrides(),
        zonesProvider.overrideWith2(_Zones.new),
        pinnedZonesProvider.overrideWith2(_Pinned.new),
        fleetTrafficProvider.overrideWith2((accountId) => _Fleet(accountId, traffic)),
      ],
      child: MaterialApp(
        theme: buildEpTheme(defaultTargetPlatform, Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const DomainsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _both = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android});

void main() {
  testWidgets('each domain shows its requests over 7 days, as Today does', variant: _both, (tester) async {
    await _pump(tester, const {'z1': ZoneTraffic(requests: 128400), 'z2': ZoneTraffic(requests: 912)});
    expect(find.text('Requests · 7d'), findsNWidgets(2));
    expect(find.text('128K'), findsOneWidget);
    expect(find.text('912'), findsOneWidget);
  });

  testWidgets('without Analytics access the cards simply leave it out', variant: _both, (tester) async {
    await _pump(tester, null);
    expect(find.text('atelier-nord.dev'), findsOneWidget);
    expect(find.text('Requests · 7d'), findsNothing);
  });

  testWidgets('on an iPad the domain opens beside the list, and its pages push inside its column', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      tester.view
        ..physicalSize = const Size(1116, 1032) * 2
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      // The Domains tab's routes, as the app's router nests them.
      final router = GoRouter(
        initialLocation: '/domains',
        routes: [
          ShellRoute(
            builder: (c, s, navigator) => DomainsLayout(zoneId: s.pathParameters['zoneId'], navigator: navigator),
            routes: [
              GoRoute(
                path: '/domains',
                builder: (c, s) => const DomainsRoot(),
                routes: [
                  GoRoute(
                    path: ':zoneId',
                    builder: (c, s) => ZoneHubScreen(zoneId: s.pathParameters['zoneId']!),
                    routes: [
                      GoRoute(
                        path: 'dns',
                        builder: (c, s) => const Scaffold(body: Text('DNS page')),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...accountOverrides(),
            zonesProvider.overrideWith2(_Zones.new),
            pinnedZonesProvider.overrideWith2(_Pinned.new),
            fleetTrafficProvider.overrideWith2((accountId) => _Fleet(accountId, const {})),
          ],
          child: MaterialApp.router(
            theme: buildEpTheme(TargetPlatform.iOS, Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Choose a domain to see its DNS, traffic and settings here.'), findsOneWidget);

      await tester.tap(find.text('atelier-nord.dev'));
      await tester.pumpAndSettle();
      expect(find.byType(ZoneHubScreen), findsOneWidget, reason: 'the hub, beside the list');
      expect(find.byType(DomainsScreen), findsOneWidget);
      expect(find.byType(CupertinoNavigationBarBackButton), findsNothing, reason: 'the list is beside it');
      final card = tester.widget<Strip>(
        find.ancestor(of: find.text('atelier-nord.dev').first, matching: find.byType(Strip)),
      );
      expect(card.selected, isTrue);

      await tester.tap(find.text('DNS records'));
      await tester.pumpAndSettle();
      expect(find.text('DNS page'), findsOneWidget);
      expect(find.byType(DomainsScreen), findsOneWidget, reason: 'the list stays beside the column');

      // Narrowed to a phone's width (Slide Over): the same stack, the list
      // under the domain under its DNS.
      tester.view.physicalSize = const Size(393, 852) * 2;
      await tester.pumpAndSettle();
      expect(find.text('DNS page'), findsOneWidget);
      expect(find.byType(DomainsScreen), findsNothing);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ZoneHubScreen), findsOneWidget);
      expect(find.byType(CupertinoNavigationBarBackButton), findsOneWidget, reason: 'back to the list now');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
