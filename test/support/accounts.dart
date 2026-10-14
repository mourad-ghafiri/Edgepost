import 'package:edgepost/core/accounts/account.dart';
import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/cloudflare/models.dart';
import 'package:edgepost/core/providers.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'fake_cf.dart';

/// The account most tests run in, and a second one for scoping tests.
const testAccount = Account(id: 'a1', cloudflareName: 'Studio', colorIndex: 0);
const otherAccount = Account(id: 'a2', cloudflareName: 'Studio Ember', colorIndex: 1);

/// A stored token reaching [accounts], with the same permission check result
/// ([caps]: true → granted, false → denied) in each.
Credential fakeToken({
  String id = 'c1',
  String label = 'Test',
  TokenKind kind = TokenKind.user,
  List<Account> accounts = const [testAccount],
  Map<Capability, bool> caps = const {},
  DateTime? expiresOn,
}) =>
    Credential(
      id: id,
      label: label,
      kind: kind,
      accounts: [for (final a in accounts) CfAccount(id: a.id, name: a.cloudflareName)],
      addedAt: DateTime(2026),
      token: 'token-$id',
      expiresOn: expiresOn,
      capabilities: {for (final a in accounts) a.id: capStates(caps)},
    );

/// A zone of [account], listed by the tokens in [reach].
Zone fakeZone({
  String id = 'z1',
  String name = 'example.com',
  String status = 'active',
  Account account = testAccount,
  List<String> reach = const ['c1'],
}) =>
    Zone.fromJson({
      'id': id,
      'name': name,
      'status': status,
      'account': {'id': account.id, 'name': account.cloudflareName},
    }, reach: reach);

/// The vault as screens see it: [tokens], the roster, and [active] on screen.
List<Override> accountOverrides({
  List<Credential>? tokens,
  List<Account> accounts = const [testAccount],
  Account? active,
}) =>
    [
      tokensProvider.overrideWithValue(tokens ?? [fakeToken()]),
      accountsProvider.overrideWithValue(accounts),
      activeAccountProvider.overrideWithValue(active ?? accounts.first),
    ];
