import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/adaptive/ep_icons.dart';
import 'package:edgepost/core/adaptive/ep_widgets.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/dns/dns_routes.dart';
import 'package:edgepost/features/zones/data/zones_providers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';

final testZone = fakeZone();

Credential testCredential({bool dns = true}) => fakeToken(caps: {Capability.zones: true, Capability.dns: dns});

/// Runs [body] once per platform, with the platform override reset after.
void testBothPlatforms(String description, Future<void> Function(WidgetTester tester, TargetPlatform platform) body) {
  for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$description (${platform.name})', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      tester.view
        ..physicalSize = const Size(1170, 2532)
        ..devicePixelRatio = 3;
      try {
        await body(tester, platform);
      } finally {
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

/// Pumps the DNS routes under `/domains/:zoneId` at [location].
Future<GoRouter> pumpDns(
  WidgetTester tester, {
  required FakeCfAdapter api,
  required String location,
  Credential? credential,
}) async {
  final platform = defaultTargetPlatform;
  final cred = credential ?? testCredential();
  final client = fakeClient(api);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/domains/:zoneId',
        builder: (c, s) => const Scaffold(body: Text('zone hub')),
        routes: dnsRoutes,
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
        zoneByIdProvider.overrideWith((ref, id) => id == testZone.id ? testZone : null),
        cfClientProvider.overrideWith((ref, id) => client),
      ],
      child: MaterialApp.router(
        theme: buildEpTheme(platform, Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await settle(tester);
  return router;
}

/// Lets fake network futures and animations finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

/// Waits out toasts (the iOS banner and the Android snack bar use timers).
Future<void> drainToasts(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpAndSettle();
}

/// The toolbar button for [icon] in the platform idiom.
Finder toolbarButton(TargetPlatform platform, EpIcon icon) => platform == TargetPlatform.iOS
    ? find.ancestor(of: find.byIcon(icon.cupertino), matching: find.byType(CupertinoButton))
    : find.ancestor(of: find.byIcon(icon.material), matching: find.byType(IconButton));

bool isEnabled(WidgetTester tester, Finder button) {
  final w = tester.widget(button.first);
  if (w is CupertinoButton) return w.onPressed != null;
  if (w is IconButton) return w.onPressed != null;
  throw StateError('Not a button: $w');
}

/// The primary "add" action: nav-bar + on iOS, extended FAB on Android.
Finder addButton(TargetPlatform platform) => platform == TargetPlatform.iOS
    ? find.ancestor(of: find.byIcon(EpIcon.add.cupertino), matching: find.byType(CupertinoButton))
    : find.byType(FloatingActionButton);

/// The editable text inside the [EpTextField] labelled [label].
Finder fieldInput(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(EpTextField)),
  matching: find.byType(EditableText),
);

String fieldText(WidgetTester tester, String label) => tester.widget<EditableText>(fieldInput(label)).controller.text;
