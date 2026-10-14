import 'dart:convert';

import 'package:edgepost/app/app.dart';
import 'package:edgepost/app/router.dart';
import 'package:edgepost/core/accounts/account.dart';
import 'package:edgepost/core/accounts/vault.dart';
import 'package:edgepost/core/adaptive/ep_page.dart';
import 'package:edgepost/core/adaptive/ep_widgets.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/features/accounts/account_button.dart';
import 'package:edgepost/features/accounts/account_detail_screen.dart';
import 'package:edgepost/features/accounts/account_signals.dart';
import 'package:edgepost/features/accounts/add_account_screen.dart';
import 'package:edgepost/features/mail/background/mail_sync_task.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounts.dart';
import '../support/fake_cf.dart';
import '../support/memory_cache.dart';

/// One token reaching both test accounts; [roster] is what the user added.
Map<String, String> _keychain(List<Account> roster, {String active = 'a1'}) {
  final token = fakeToken(accounts: const [testAccount, otherAccount]);
  return {
    'vault': jsonEncode(VaultState(tokens: [token], accounts: roster, activeId: active).toJson()),
    'token.c1': token.token,
    'settings': '{}',
  };
}

/// The whole app on a Cloudflare that answers nothing (every call is a 404),
/// with [signals] standing in for what each account has waiting.
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  List<Account> roster = const [testAccount, otherAccount],
  Map<String, AccountSignal> signals = const {},
}) async {
  tester.view
    ..physicalSize = const Size(1179, 2556)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  FlutterSecureStorage.setMockInitialValues(_keychain(roster));
  // Empty but well-formed lists; everything else is a 404.
  final api = FakeCfAdapter()..reply('GET', '/zones', <Object>[], resultInfo: {'page': 1, 'total_pages': 1});
  final container = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      tokenClientProvider.overrideWithValue((token, {tokenId}) => fakeClient(api)),
      cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
      accountButtonProvider.overrideWithValue(const AccountButton()),
      accountSignalProvider.overrideWith((ref, id) => signals[id] ?? const AccountSignal(needsYou: 0, unread: 0)),
    ],
  );
  addTearDown(container.dispose);
  // The app reads its platform above MaterialApp; without a Theme there,
  // that's a fallback theme cached by whichever test ran first.
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: Theme(data: ThemeData(platform: defaultTargetPlatform), child: const EdgepostApp()),
  ));
  await _frames(tester);
  return container;
}

/// A few frames: enough for the keychain, the fake API and a switch (which
/// waits for frames), without waiting on the app's live-refresh clock.
Future<void> _frames(WidgetTester tester, [int n = 12]) async {
  for (var i = 0; i < n; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Lets toasts time out, then takes the app down (its clock stops with it).
/// The platform override must be gone before the test body ends.
Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  debugDefaultTargetPlatformOverride = null;
}

/// The switcher's "+".
final _addButton = find.byWidgetPredicate((w) => w is EpIconButton && w.label == 'Add account');

String _location(ProviderContainer c) => c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    pendingNotificationRoute.value = null;
    debugDefaultTargetPlatformOverride = null;
  });

  for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('switching from the avatar resets every tab and shows the other account (${platform.name})', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final c = await _pumpApp(tester, signals: const {'a2': AccountSignal(needsYou: 2, unread: 3)});

      // Today lists the other account while it has something waiting.
      expect(find.text('OTHER ACCOUNTS'), findsOneWidget);
      expect(find.text('Studio Ember'), findsOneWidget);
      expect(find.text('NEEDS YOU'), findsWidgets);
      expect(find.text('3'), findsOneWidget, reason: 'its unread count');

      // Deep in Settings for the first account.
      c.read(routerProvider).go('/settings');
      await _frames(tester);
      c.read(routerProvider).push('/settings/account/a1');
      await _frames(tester);
      expect(find.byType(AccountDetailScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(AccountDetailScreen))).pop();
      await _frames(tester);

      // The switcher: both accounts, the other one's counts, a "+".
      await tester.tap(find.byType(AccountButton));
      await _frames(tester);
      expect(find.text('Accounts'), findsWidgets, reason: 'the sheet (and Settings\' section on Android)');
      expect(find.text('Studio'), findsWidgets);
      expect(find.text('Studio Ember'), findsNWidgets(2), reason: 'Settings lists it too, under the sheet');
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(_addButton, findsOneWidget);

      await tester.tap(find.text('Studio Ember').last);
      await _frames(tester, 20);

      expect(tester.takeException(), isNull, reason: 'no duplicate GlobalKey while the tabs are rebuilt');
      expect(c.read(activeAccountProvider)!.id, 'a2');
      expect(_location(c), '/settings', reason: 'the same tab, back at its root');
      expect(find.text('Switched to Studio Ember'), findsOneWidget);
      expect(find.text('OTHER ACCOUNTS'), findsNothing, reason: 'the first account has nothing waiting');

      // Long-press: back to the account shown before.
      await tester.longPress(find.byType(AccountButton));
      await _frames(tester, 20);
      expect(c.read(activeAccountProvider)!.id, 'a1');
      expect(tester.takeException(), isNull);

      await _finish(tester);
    });
  }

  testWidgets('with one account, the switcher offers the accounts its token already reaches', (tester) async {
    final c = await _pumpApp(tester, roster: const [testAccount]);

    await tester.tap(find.byType(AccountButton));
    await _frames(tester);
    expect(find.text('Studio Ember'), findsNothing, reason: 'reachable, but not added');
    await tester.tap(_addButton);
    await _frames(tester);
    expect(find.byType(AddAccountScreen), findsOneWidget);

    // Reachable with the stored token: one tap adds it and opens it.
    await tester.tap(find.text('Studio Ember'));
    await _frames(tester, 30);
    expect(c.read(accountsProvider).map((a) => a.id), ['a1', 'a2']);
    expect(c.read(activeAccountProvider)!.id, 'a2');
    expect(find.byType(AddAccountScreen), findsNothing);
    expect(find.text('Switched to Studio Ember'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _finish(tester);
  });

  testWidgets('a tapped notification opens in its own account, after a full-screen flow closes', (tester) async {
    final c = await _pumpApp(tester);

    pendingNotificationRoute.value = '/mail?account=a2';
    await _frames(tester, 20);
    expect(c.read(activeAccountProvider)!.id, 'a2');
    expect(_location(c), '/mail', reason: 'the account goes, the route stays');

    // Adding an account covers the tabs: the tap waits rather than closing it.
    c.read(routerProvider).push('/accounts/add');
    await _frames(tester);
    pendingNotificationRoute.value = '/today/budget?account=a1';
    await _frames(tester, 20);
    expect(find.byType(AddAccountScreen), findsOneWidget);
    expect(c.read(activeAccountProvider)!.id, 'a2');

    c.read(routerProvider).pop();
    await _frames(tester, 20);
    expect(c.read(activeAccountProvider)!.id, 'a1');
    expect(_location(c), '/today/budget');

    // An account removed since: Today.
    pendingNotificationRoute.value = '/mail?account=gone';
    await _frames(tester, 20);
    expect(_location(c), '/today');
    expect(c.read(activeAccountProvider)!.id, 'a1');
    expect(tester.takeException(), isNull);

    await _finish(tester);
  });
}
