import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/cloudflare/models.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/zones/data/zones_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';

export '../../support/memory_cache.dart';

/// Copy of test/features/zone_controls/controls_harness.dart so each feature's
/// tests stand alone.
///
/// Zones list without the keychain or network.
class FakeZonesNotifier extends ZonesNotifier {
  FakeZonesNotifier(super.accountId, this.zones);
  final List<Zone> zones;

  @override
  Future<Synced<List<Zone>>> build() async => Synced(zones, DateTime.now());
}

/// A zone of the test account, listed by the test token.
Zone testZone({String id = 'z1', String name = 'example.com', bool paused = false, String plan = 'Free Website'}) =>
    Zone.fromJson({
      'id': id,
      'name': name,
      'status': 'active',
      'paused': paused,
      'account': {'id': testAccount.id, 'name': testAccount.cloudflareName},
      'plan': {'name': plan},
    }, reach: const ['c1']);

/// The test token; every permission granted unless [capabilities] says.
Credential testCredential({Map<Capability, bool>? capabilities}) =>
    fakeToken(caps: capabilities ?? {for (final c in Capability.values) c: true});

/// Pumps [child] inside the app's theme and localizations for the current
/// test platform, with every Cloudflare call going to [api].
Future<ProviderContainer> pumpEp(
  WidgetTester tester, {
  required Widget child,
  required FakeCfAdapter api,
  List<Zone>? zones,
  Credential? credential,
  MemoryCacheStore? cache,
  Brightness brightness = Brightness.light,
}) async {
  final platform = defaultTargetPlatform;
  final cred = credential ?? testCredential();
  final client = fakeClient(api);
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        cacheStoreProvider.overrideWithValue(cache ?? MemoryCacheStore()),
        ...accountOverrides(tokens: [cred]),
        zonesProvider.overrideWith2((account) => FakeZonesNotifier(account, zones ?? [testZone()])),
        cfClientProvider.overrideWith((ref, id) => client),
      ],
      child: MaterialApp(
        theme: buildEpTheme(platform, brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return ProviderScope.containerOf(tester.element(find.byWidget(child)));
}

/// The scroll view of an [EpPage].
Finder pageScrollable() =>
    find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;

/// Scrolls [finder] fully into view.
Future<void> reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: pageScrollable());
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}
