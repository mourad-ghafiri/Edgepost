import 'dart:convert';

import 'package:edgepost/core/accounts/account.dart';
import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/accounts/vault.dart';
import 'package:edgepost/core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounts.dart';
import '../support/fake_cf.dart';
import '../support/memory_cache.dart';

const _third = Account(id: 'a3', cloudflareName: 'Side Project', colorIndex: 2);

/// Keychain contents for a vault of [tokens] and [accounts].
Map<String, String> _stored({
  required List<Credential> tokens,
  List<Account> accounts = const [testAccount],
  String? active,
  String? previous,
  Map<String, Object?> extra = const {},
}) =>
    {
      'vault': jsonEncode(VaultState(tokens: tokens, accounts: accounts, activeId: active, previousId: previous).toJson()),
      for (final t in tokens) 'token.${t.id}': t.token,
      for (final e in extra.entries) e.key: jsonEncode(e.value),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MemoryCacheStore cache;

  ProviderContainer container([FakeCfAdapter? api]) {
    cache = MemoryCacheStore();
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        cacheStoreProvider.overrideWithValue(cache),
        tokenClientProvider.overrideWithValue((token, {tokenId}) => fakeClient(api ?? FakeCfAdapter())),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<String?> keychain(String key) => const FlutterSecureStorage().read(key: key);

  group('expiry', () {
    final token = fakeToken(expiresOn: DateTime.utc(2026, 10, 20));

    test('a date changed in the dashboard replaces the stored one, and is saved', () async {
      FlutterSecureStorage.setMockInitialValues(_stored(tokens: [token]));
      final api = FakeCfAdapter()
        ..reply('GET', '/user/tokens/verify', {'id': 'tok', 'status': 'active', 'expires_on': '2027-04-01T00:00:00Z'});
      final c = container(api);
      expect((await c.read(vaultProvider.future)).tokens.single.expiresOn, DateTime.utc(2026, 10, 20));

      await c.read(vaultProvider.notifier).refreshExpiry();

      expect(c.read(tokensProvider).single.expiresOn, DateTime.utc(2027, 4));
      final saved = jsonDecode((await keychain('vault'))!) as Map<String, dynamic>;
      expect(((saved['tokens'] as List).single as Map)['expiresOn'], startsWith('2027-04-01'));
    });

    test('an expiry removed in the dashboard clears the date', () async {
      FlutterSecureStorage.setMockInitialValues(_stored(tokens: [token]));
      final api = FakeCfAdapter()..reply('GET', '/user/tokens/verify', {'id': 'tok', 'status': 'active'});
      final c = container(api);
      await c.read(vaultProvider.future);
      await c.read(vaultProvider.notifier).refreshExpiry();
      expect(c.read(tokensProvider).single.expiresOn, isNull);
    });

    test('offline keeps the known date, and checks run at most once a minute', () async {
      FlutterSecureStorage.setMockInitialValues(_stored(tokens: [token]));
      final api = FakeCfAdapter()..on('GET', '/user/tokens/verify', (_) => FakeReply.error(500, 10000, 'down'));
      final c = container(api);
      await c.read(vaultProvider.future);
      await c.read(vaultProvider.notifier).refreshExpiry();
      final calls = api.calls.length;
      expect(calls, greaterThan(0));
      await c.read(vaultProvider.notifier).refreshExpiry();
      expect(c.read(tokensProvider).single.expiresOn, DateTime.utc(2026, 10, 20));
      expect(api.calls.length, calls, reason: 'second check within a minute is skipped');
    });
  });

  group('active account', () {
    test('an empty keychain has no accounts and nothing active', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final v = await container().read(vaultProvider.future);
      expect(v.accounts, isEmpty);
      expect(v.active, isNull);
    });

    test('a missing active account falls back to the previous one, then the first', () async {
      final both = fakeToken(accounts: const [testAccount, otherAccount]);
      FlutterSecureStorage.setMockInitialValues(
        _stored(tokens: [both], accounts: const [testAccount, otherAccount], active: 'gone', previous: 'a2'),
      );
      expect((await container().read(vaultProvider.future)).activeId, 'a2');

      FlutterSecureStorage.setMockInitialValues(_stored(tokens: [both], accounts: const [testAccount, otherAccount], active: 'gone'));
      expect((await container().read(vaultProvider.future)).activeId, 'a1');
    });

    test('switching remembers the previous account; unknown ids are ignored', () async {
      final both = fakeToken(accounts: const [testAccount, otherAccount]);
      FlutterSecureStorage.setMockInitialValues(_stored(tokens: [both], accounts: const [testAccount, otherAccount], active: 'a1'));
      final c = container();
      await c.read(vaultProvider.future);
      final vault = c.read(vaultProvider.notifier);

      await vault.activate('a2');
      expect((c.read(vaultProvider).value!.activeId, c.read(vaultProvider).value!.previousId), ('a2', 'a1'));
      expect(c.read(activeAccountProvider)!.name, 'Studio Ember');

      await vault.activate('nope');
      expect(c.read(vaultProvider).value!.activeId, 'a2');

      final saved = jsonDecode((await keychain('vault'))!) as Map<String, dynamic>;
      expect((saved['activeId'], saved['previousId']), ('a2', 'a1'), reason: 'the switch survives a restart');
    });
  });

  group('removing', () {
    test('an account takes its own token, mail, cache and settings with it, and keeps shared tokens', () async {
      final own = fakeToken(id: 'only-a2', accounts: const [otherAccount]);
      final shared = fakeToken(id: 'both', accounts: const [testAccount, otherAccount]);
      FlutterSecureStorage.setMockInitialValues(_stored(
        tokens: [own, shared],
        accounts: const [testAccount, otherAccount],
        active: 'a2',
        previous: 'a1',
        extra: {
          'mail.a2': {'gone': true},
          'mail.a1': {'kept': true},
          'settings': {
            'budget_alerts': true,
            'pinned_zones': {'a1': ['z1'], 'a2': ['z9']},
            'alert_state': {'a2': {'send': '80'}},
          },
        },
      ));
      final c = container();
      await c.read(vaultProvider.future);
      await cache.write('a2', 'zones', ['z9']);
      await cache.write('a1', 'zones', ['z1']);

      await c.read(vaultProvider.notifier).removeAccount('a2');

      final v = c.read(vaultProvider).value!;
      expect(v.accounts.map((a) => a.id), ['a1']);
      expect(v.activeId, 'a1', reason: 'the removed account was on screen');
      expect(v.previousId, isNull);
      expect(v.tokens.map((t) => t.id), ['both']);
      expect(await keychain('token.only-a2'), isNull);
      expect(await keychain('token.both'), isNotNull);
      expect(await keychain('mail.a2'), isNull);
      expect(await keychain('mail.a1'), isNotNull);
      final settings = jsonDecode((await keychain('settings'))!) as Map<String, dynamic>;
      expect(settings['pinned_zones'], {'a1': ['z1']});
      expect(settings['alert_state'], isEmpty);
      expect(settings['budget_alerts'], isTrue, reason: 'app-wide settings stay');
      expect(cache.entries.keys, ['a1']);
    });

    test('the last token of an account leaves it in the switcher without access', () async {
      FlutterSecureStorage.setMockInitialValues(_stored(tokens: [fakeToken()]));
      final c = container();
      await c.read(vaultProvider.future);
      await c.read(vaultProvider.notifier).removeToken('c1');
      final v = c.read(vaultProvider).value!;
      expect(v.accounts.single.id, 'a1');
      expect(v.lacksAccess('a1'), isTrue);
      expect(await keychain('token.c1'), isNull);
    });
  });

  test('a nickname replaces the Cloudflare name; blank or the same name resets it', () async {
    FlutterSecureStorage.setMockInitialValues(_stored(tokens: [fakeToken()]));
    final c = container();
    await c.read(vaultProvider.future);
    final vault = c.read(vaultProvider.notifier);

    await vault.rename('a1', '  Clients ');
    expect(c.read(activeAccountProvider)!.name, 'Clients');
    await vault.rename('a1', 'Studio');
    expect(c.read(activeAccountProvider)!.nickname, isNull);
    await vault.rename('a1', 'Clients');
    await vault.rename('a1', '');
    expect(c.read(activeAccountProvider)!.name, 'Studio');
  });

  test('accounts a stored token reaches can be added without a new token, in the next free colour', () async {
    // Checked in a1 only, as when it was added for that account.
    final wide = fakeToken(accounts: const [testAccount, otherAccount, _third]).copyWith(capabilities: {'a1': const {}});
    FlutterSecureStorage.setMockInitialValues(_stored(tokens: [wide]));
    final c = container();
    expect((await c.read(vaultProvider.future)).available.map((a) => a.id), ['a2', 'a3']);

    await c.read(vaultProvider.notifier).addAvailable({'a3'});

    final v = c.read(vaultProvider).value!;
    expect(v.accounts.map((a) => (a.id, a.colorIndex)), [('a1', 0), ('a3', 1)]);
    expect(v.activeId, 'a1', reason: 'adding never switches by itself');
    expect(v.available.map((a) => a.id), ['a2']);
    expect(v.tokens.single.capabilities.keys, containsAll(['a1', 'a3']), reason: 'probed in the new account');
  });
}
