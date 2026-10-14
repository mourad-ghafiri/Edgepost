import 'dart:io';

import 'package:edgepost/app/router.dart';
import 'package:edgepost/core/accounts/account.dart';
import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/accounts/token_verifier.dart';
import 'package:edgepost/core/accounts/vault.dart';
import 'package:edgepost/core/cloudflare/models.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/storage/cache_store.dart';
import 'package:edgepost/core/storage/secure_store.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cf.dart';

const _personal = CfAccount(id: 'a1', name: 'Personal');
const _client = CfAccount(id: 'a2', name: 'Client Co');

/// Starts empty; the pasted token reaches two accounts, and adding needs no
/// network.
class _Vault extends Vault {
  @override
  Future<VaultState> build() async => const VaultState(tokens: [], accounts: []);

  @override
  Future<TokenCandidate> inspect(String token) async =>
      TokenCandidate(token: token, check: const TokenCheck(kind: TokenKind.user, accounts: [_personal, _client]));

  @override
  Future<List<String>> add(TokenCandidate candidate, Set<String> accountIds, {String? label, void Function(int, int)? onProbed}) async {
    final ids = [for (final a in candidate.check.accounts) if (accountIds.contains(a.id)) a.id];
    final token = Credential(
      id: 'c1',
      label: 'Personal',
      kind: TokenKind.user,
      accounts: candidate.check.accounts,
      addedAt: DateTime(2026, 10, 12),
      token: candidate.token,
      capabilities: {for (final id in ids) id: capStates({Capability.zones: true})},
    );
    state = AsyncData(VaultState(
      tokens: [token],
      accounts: [
        for (final (i, a) in candidate.check.accounts.where((a) => ids.contains(a.id)).indexed)
          Account(id: a.id, cloudflareName: a.name, colorIndex: i),
      ],
      activeId: ids.first,
    ));
    return ids;
  }
}

/// In-memory stand-in for the keychain.
class _MemSecure extends SecureStore {
  final Map<String, dynamic> settings = {};
  @override
  Future<Map<String, dynamic>> readSettings() async => {...settings};
  @override
  Future<void> writeSettings(Map<String, dynamic> s) async => settings
    ..clear()
    ..addAll(s);
  @override
  Future<Map<String, dynamic>?> readMailService(String accountId) async => null;
}

void main() {
  testWidgets('first run: the token\'s accounts are chosen, their permissions shown, then Today', (tester) async {
    tester.view.physicalSize = const Size(1179, 2556); // iPhone-sized
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        vaultProvider.overrideWith(_Vault.new),
        secureStoreProvider.overrideWithValue(_MemSecure()),
        cacheStoreProvider.overrideWithValue(CacheStore(root: () async => Directory.systemTemp.createTempSync('ek-router'))),
      ],
    );
    addTearDown(container.dispose);
    final router = container.read(routerProvider);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildEpTheme(TargetPlatform.android, Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/welcome');

    await tester.scrollUntilVisible(find.text('Add a Cloudflare API token'), 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a Cloudflare API token'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/welcome/token');

    await tester.enterText(find.byType(EditableText).at(1), 'tok');
    await tester.ensureVisible(find.text('Verify and add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verify and add'));
    await tester.pumpAndSettle();

    // Both accounts start ticked; keep only Personal.
    expect(find.text('Choose accounts'), findsOneWidget);
    expect(find.text('Add 2 accounts'), findsOneWidget);
    await tester.tap(find.text('Client Co'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add 1 account'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(router.state.uri.path, '/welcome/token', reason: 'stays to show the checklist');
    expect(find.text('Token added'), findsOneWidget);
    expect(container.read(accountsProvider).map((a) => a.id), ['a1']);
    expect(container.read(activeAccountProvider)?.id, 'a1');

    await tester.scrollUntilVisible(find.text('Done'), 400, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(router.state.uri.path, '/today');
  });
}
