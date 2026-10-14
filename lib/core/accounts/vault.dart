import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../cloudflare/cf_client.dart';
import '../cloudflare/cf_errors.dart';
import '../cloudflare/models.dart';
import '../providers.dart';
import 'access.dart';
import 'account.dart';
import 'capability_probe.dart';
import 'credential.dart';
import 'token_verifier.dart';

/// Settings entries kept per account (`{accountId: …}`), removed with it.
const accountScopedSettings = ['pinned_zones', 'mail_identities', 'mail_recent_from', 'mail_sync_cursors', 'alert_state'];

/// Number of distinct account colours (see `EpColors.account`).
const accountColorCount = 6;

class VaultState {
  const VaultState({required this.tokens, required this.accounts, this.activeId, this.previousId});

  /// Every stored token, in the order they were added.
  final List<Credential> tokens;

  /// Accounts the user added, in their switcher order.
  final List<Account> accounts;

  /// The account the app shows; null only before the first account exists.
  final String? activeId;

  /// The account shown before the last switch (long-press switches back).
  final String? previousId;

  Account? get active => accountById(activeId);
  Account? get previous => accountById(previousId);

  Account? accountById(String? id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  List<Credential> tokensFor(String accountId) => [for (final t in tokens) if (t.reaches(accountId)) t];

  /// The account was added but no stored token reaches it any more.
  bool lacksAccess(String accountId) => tokensFor(accountId).isEmpty;

  /// Accounts the stored tokens reach that the user hasn't added.
  List<CfAccount> get available {
    final added = {for (final a in accounts) a.id};
    final out = <String, CfAccount>{};
    for (final t in tokens) {
      for (final a in t.accounts) {
        if (!added.contains(a.id)) out.putIfAbsent(a.id, () => a);
      }
    }
    return out.values.toList();
  }

  Map<String, dynamic> toJson() => {
        'tokens': tokens.map((t) => t.toJson()).toList(),
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'activeId': activeId,
        'previousId': previousId,
      };
}

/// A pasted token, verified but not stored yet.
class TokenCandidate {
  const TokenCandidate({required this.token, required this.check, this.existing});
  final String token;
  final TokenCheck check;

  /// The same token string is already stored under this id.
  final Credential? existing;
}

final vaultProvider = AsyncNotifierProvider<Vault, VaultState>(Vault.new);

/// The stored tokens (empty while loading).
final tokensProvider = Provider<List<Credential>>((ref) => ref.watch(vaultProvider).value?.tokens ?? const []);

/// The accounts the user added, in switcher order (empty while loading).
final accountsProvider = Provider<List<Account>>((ref) => ref.watch(vaultProvider).value?.accounts ?? const []);

/// The account the app shows. Null only during onboarding.
final activeAccountProvider = Provider<Account?>((ref) => ref.watch(vaultProvider).value?.active);

/// Picks tokens for (account, capability) and (zone, capability).
final accessProvider = Provider<AccessResolver>((ref) => AccessResolver(ref.watch(tokensProvider)));

/// Resolved token by id (null while loading or once removed).
final credentialProvider = Provider.family<Credential?, String>((ref, id) {
  for (final c in ref.watch(tokensProvider)) {
    if (c.id == id) return c;
  }
  return null;
});

class Vault extends AsyncNotifier<VaultState> {
  @override
  Future<VaultState> build() async {
    final store = ref.read(secureStoreProvider);
    final j = await store.readVault();
    if (j == null) return const VaultState(tokens: [], accounts: []);
    final tokens = <Credential>[];
    for (final t in (j['tokens'] as List).cast<Map<String, dynamic>>()) {
      final secret = await store.readToken(t['id'] as String);
      if (secret != null) tokens.add(Credential.fromJson(t, secret));
    }
    final accounts = (j['accounts'] as List).cast<Map<String, dynamic>>().map(Account.fromJson).toList();
    return _normalized(VaultState(
      tokens: tokens,
      accounts: accounts,
      activeId: j['activeId'] as String?,
      previousId: j['previousId'] as String?,
    ));
  }

  /// The active account always exists: else the previous one, else the first.
  static VaultState _normalized(VaultState s) {
    bool has(String? id) => id != null && s.accounts.any((a) => a.id == id);
    final active = has(s.activeId) ? s.activeId : (has(s.previousId) ? s.previousId : s.accounts.firstOrNull?.id);
    final previous = has(s.previousId) && s.previousId != active ? s.previousId : null;
    return VaultState(tokens: s.tokens, accounts: s.accounts, activeId: active, previousId: previous);
  }

  Future<void> _save(VaultState next) async {
    final n = _normalized(next);
    await ref.read(secureStoreProvider).writeVault(n.toJson());
    state = AsyncData(n);
  }

  /// Verifies a pasted token without storing anything. Throws a [CfException]
  /// with a displayable message when the token is unusable.
  Future<TokenCandidate> inspect(String token) async {
    final trimmed = token.trim();
    final current = await future;
    final existing = current.tokens.where((t) => t.token == trimmed).firstOrNull;
    final check = await TokenVerifier(ref.read(tokenClientProvider)(trimmed)).verify();
    return TokenCandidate(token: trimmed, check: check, existing: existing);
  }

  /// Stores [candidate] (or refreshes the same token already stored), adds
  /// [accountIds] to the switcher and probes what the token can do in each
  /// account it reaches that the user has added. [onProbed] reports progress.
  /// Returns the ids of the accounts that are new to the app.
  Future<List<String>> add(TokenCandidate candidate, Set<String> accountIds, {String? label, void Function(int done, int total)? onProbed}) async {
    final current = await future;
    final check = candidate.check;
    final base = candidate.existing;
    final id = base?.id ?? _newId();
    final added = {for (final a in current.accounts) a.id};
    final newIds = [for (final a in check.accounts) if (accountIds.contains(a.id) && !added.contains(a.id)) a.id];
    final toProbe = [for (final a in check.accounts) if (added.contains(a.id) || accountIds.contains(a.id)) a.id];

    final client = ref.read(tokenClientProvider)(candidate.token, tokenId: id);
    final caps = <String, Map<Capability, CapState>>{...?base?.capabilities};
    var done = 0;
    // A few accounts at a time: each probe is ~15 cheap reads.
    for (var i = 0; i < toProbe.length; i += 3) {
      final batch = toProbe.skip(i).take(3).toList();
      final results = await Future.wait(batch.map((acc) => CapabilityProbe(client).run(acc)));
      for (var k = 0; k < batch.length; k++) {
        caps[batch[k]] = results[k];
      }
      done += batch.length;
      onProbed?.call(done, toProbe.length);
    }

    final trimmedLabel = label?.trim();
    final cred = Credential(
      id: id,
      label: trimmedLabel != null && trimmedLabel.isNotEmpty ? trimmedLabel : (base?.label ?? _defaultLabel(check)),
      kind: check.kind,
      accounts: check.accounts,
      addedAt: base?.addedAt ?? DateTime.now(),
      expiresOn: check.expiresOn,
      capabilities: caps,
      token: candidate.token,
    );
    await ref.read(secureStoreProvider).writeToken(id, candidate.token);

    final accounts = [...current.accounts];
    for (final acc in check.accounts.where((a) => newIds.contains(a.id))) {
      final used = {for (final a in accounts) a.colorIndex};
      final color = List.generate(accountColorCount, (i) => i).firstWhere((i) => !used.contains(i), orElse: () => accounts.length % accountColorCount);
      accounts.add(Account(id: acc.id, cloudflareName: acc.name, colorIndex: color));
    }
    final tokens = [for (final t in current.tokens) if (t.id != id) t, cred]..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    await _save(VaultState(tokens: tokens, accounts: _refreshNames(accounts, tokens), activeId: current.activeId ?? newIds.firstOrNull, previousId: current.previousId));
    return newIds;
  }

  /// Adds accounts the stored tokens already reach (no new token needed).
  Future<void> addAvailable(Set<String> accountIds, {void Function(int done, int total)? onProbed}) async {
    final current = await future;
    final accounts = [...current.accounts];
    final tokens = [...current.tokens];
    var done = 0;
    for (final accId in accountIds) {
      final reaching = tokens.where((t) => t.reaches(accId)).toList();
      if (reaching.isEmpty || accounts.any((a) => a.id == accId)) continue;
      for (var i = 0; i < tokens.length; i++) {
        final t = tokens[i];
        if (!t.reaches(accId) || t.capabilities.containsKey(accId)) continue;
        final probed = await CapabilityProbe(_client(t)).run(accId);
        tokens[i] = t.copyWith(capabilities: {...t.capabilities, accId: probed});
      }
      final cf = reaching.first.accounts.firstWhere((a) => a.id == accId);
      final used = {for (final a in accounts) a.colorIndex};
      final color = List.generate(accountColorCount, (i) => i).firstWhere((i) => !used.contains(i), orElse: () => accounts.length % accountColorCount);
      accounts.add(Account(id: accId, cloudflareName: cf.name, colorIndex: color));
      onProbed?.call(++done, accountIds.length);
    }
    await _save(VaultState(tokens: tokens, accounts: accounts, activeId: current.activeId, previousId: current.previousId));
  }

  /// Makes [accountId] the account the app shows. Called only by the
  /// account switcher, which resets navigation around it.
  Future<void> activate(String accountId) async {
    final current = await future;
    if (current.activeId == accountId || current.accountById(accountId) == null) return;
    await _save(VaultState(tokens: current.tokens, accounts: current.accounts, activeId: accountId, previousId: current.activeId));
  }

  Future<void> rename(String accountId, String? nickname) async {
    final current = await future;
    final n = nickname?.trim();
    final accounts = [
      for (final a in current.accounts)
        a.id == accountId ? (n == null || n.isEmpty || n == a.cloudflareName ? a.copyWith(clearNickname: true) : a.copyWith(nickname: n)) : a,
    ];
    await _save(VaultState(tokens: current.tokens, accounts: accounts, activeId: current.activeId, previousId: current.previousId));
  }

  /// Removes an account from the app: nothing changes in Cloudflare. Tokens
  /// that no longer reach any added account, the mail connection, the cache
  /// and the account's settings go with it.
  Future<void> removeAccount(String accountId) async {
    final current = await future;
    final store = ref.read(secureStoreProvider);
    final accounts = current.accounts.where((a) => a.id != accountId).toList();
    final keep = [for (final t in current.tokens) if (accounts.any((a) => t.reaches(a.id))) t];
    // The roster first: whatever happens to the cleanup below, the account
    // is gone and the remaining tokens are intact.
    await _save(VaultState(tokens: keep, accounts: accounts, activeId: current.activeId, previousId: current.previousId));
    for (final t in current.tokens.where((t) => !keep.contains(t))) {
      await store.deleteToken(t.id);
    }
    await store.deleteMailService(accountId);
    await store.updateSettings((s) {
      for (final k in accountScopedSettings) {
        final m = s[k];
        if (m is Map) m.remove(accountId);
      }
    });
    await ref.read(cacheStoreProvider).clearAccount(accountId);
  }

  /// Removes one token. Accounts it alone reached stay in the switcher as
  /// "No access" until another token is added.
  Future<void> removeToken(String tokenId) async {
    final current = await future;
    await ref.read(secureStoreProvider).deleteToken(tokenId);
    await _save(VaultState(
      tokens: current.tokens.where((t) => t.id != tokenId).toList(),
      accounts: current.accounts,
      activeId: current.activeId,
      previousId: current.previousId,
    ));
  }

  /// Re-runs the permission check of one token in one account, and re-reads
  /// its expiry (both may have changed in the dashboard).
  Future<void> reprobe(String tokenId, String accountId) async {
    final current = await future;
    final t = current.tokens.firstWhere((c) => c.id == tokenId);
    final client = _client(t);
    final states = await CapabilityProbe(client).run(accountId);
    var updated = t.copyWith(capabilities: {...t.capabilities, accountId: states});
    try {
      updated = updated.withExpiry(await TokenVerifier(client).expiry(t.kind, t.accounts));
    } on CfException {
      // Keep the known date; the permission results still apply.
    }
    final latest = await future;
    await _save(VaultState(
      tokens: [for (final c in latest.tokens) c.id == tokenId ? updated : c],
      accounts: latest.accounts,
      activeId: latest.activeId,
      previousId: latest.previousId,
    ));
  }

  DateTime? _refreshedAt;

  /// Re-reads every token's expiry date (one verify call per token) so a date
  /// changed in the Cloudflare dashboard shows up without re-adding the
  /// token. Runs when the app opens and returns to the foreground, at most
  /// once a minute; failures (offline, revoked) keep the known date.
  Future<void> refreshExpiry({bool force = false}) async {
    final now = DateTime.now();
    if (!force && _refreshedAt != null && now.difference(_refreshedAt!) < const Duration(minutes: 1)) return;
    _refreshedAt = now;
    final current = await future;
    final changed = <String, DateTime?>{};
    for (final t in current.tokens) {
      try {
        final date = await TokenVerifier(_client(t)).expiry(t.kind, t.accounts);
        if (date?.millisecondsSinceEpoch != t.expiresOn?.millisecondsSinceEpoch) changed[t.id] = date;
      } on CfException {
        continue;
      }
    }
    if (changed.isEmpty || !ref.mounted) return;
    final latest = await future;
    await _save(VaultState(
      tokens: [for (final t in latest.tokens) changed.containsKey(t.id) ? t.withExpiry(changed[t.id]) : t],
      accounts: latest.accounts,
      activeId: latest.activeId,
      previousId: latest.previousId,
    ));
  }

  /// A stored token's client. Not [cfClientProvider]: that one depends on
  /// this vault.
  CfClient _client(Credential t) => ref.read(tokenClientProvider)(t.token, tokenId: t.id);

  /// Cloudflare names can change; keep the switcher's names current.
  static List<Account> _refreshNames(List<Account> accounts, List<Credential> tokens) => [
        for (final a in accounts)
          a.copyWith(
            cloudflareName: tokens.expand((t) => t.accounts).where((c) => c.id == a.id).firstOrNull?.name ?? a.cloudflareName,
          ),
      ];

  static String _defaultLabel(TokenCheck check) =>
      check.kind == TokenKind.account && check.accounts.isNotEmpty ? check.accounts.first.name : 'API token';

  static String _newId() {
    final r = Random.secure();
    return List.generate(12, (_) => r.nextInt(36).toRadixString(36)).join();
  }
}
