import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'accounts/vault.dart';
import 'cloudflare/cf_client.dart';
import 'cloudflare/rate_limiter.dart';
import 'storage/cache_store.dart';
import 'storage/secure_store.dart';

export 'accounts/vault.dart'
    show accessProvider, accountsProvider, activeAccountProvider, credentialProvider, tokensProvider, vaultProvider;

final secureStoreProvider = Provider<SecureStore>((ref) => SecureStore());
final cacheStoreProvider = Provider<CacheStore>((ref) => CacheStore());

final Map<String, RateLimiter> _limiters = {};

/// True when any token has used 80% of its request budget or is blocked after
/// a 429: live refresh slows down until it recovers.
bool rateBudgetLow() => _limiters.values.any((l) {
      final blocked = l.blockedUntil != null && DateTime.now().isBefore(l.blockedUntil!);
      return blocked || l.remaining < l.budget * 0.2;
    });

/// Makes a client for a token string. Once the token is stored, [tokenId]
/// shares its rate limiter, which outlives provider rebuilds so the
/// per-token budget is tracked across the whole session. The vault uses this
/// directly ([cfClientProvider] depends on the vault).
typedef TokenClientFactory = CfClient Function(String token, {String? tokenId});

final tokenClientProvider = Provider<TokenClientFactory>(
  (ref) => (token, {tokenId}) => CfClient(token, limiter: tokenId == null ? null : _limiters.putIfAbsent(tokenId, RateLimiter.new)),
);

/// The client of a stored token.
final cfClientProvider = Provider.family<CfClient, String>((ref, tokenId) {
  final cred = ref.watch(credentialProvider(tokenId));
  if (cred == null) throw StateError('Unknown token $tokenId');
  return ref.watch(tokenClientProvider)(cred.token, tokenId: tokenId);
});

/// Value plus freshness, so screens can say "synced 2 min ago" and keep showing
/// the last good data when a refresh fails.
class Synced<T> {
  const Synced(this.data, this.syncedAt, {this.refreshing = false, this.refreshError});

  final T data;
  final DateTime syncedAt;
  final bool refreshing;
  final Object? refreshError;

  Synced<T> copyWith({bool? refreshing, Object? refreshError}) =>
      Synced(data, syncedAt, refreshing: refreshing ?? this.refreshing, refreshError: refreshError ?? this.refreshError);
}

/// Stale-while-revalidate base: emits the cached copy immediately, then the
/// network copy. A failed refresh keeps the cached data and records the error.
abstract class SyncedNotifier<T> extends AsyncNotifier<Synced<T>> {
  /// Cloudflare account the data belongs to (its cache lives in that
  /// account's directory, removed with the account).
  String get cacheAccount;
  String get cacheKey;
  Future<T> fetch();
  Object? encode(T data);
  T decode(Object? json);

  CacheStore get _cache => ref.read(cacheStoreProvider);

  /// Called synchronously at the start of every build: `ref.watch` the
  /// providers this list depends on here and keep them in fields, because
  /// [fetch] also runs outside build (refresh, revalidate).
  void prepare() {}

  @override
  Future<Synced<T>> build() async {
    prepare();
    final hit = await _cache.read(cacheAccount, cacheKey);
    if (hit != null) {
      unawaited(Future<void>.microtask(_revalidate));
      return Synced<T>(decode(hit.value), hit.savedAt, refreshing: true);
    }
    final fresh = await fetch();
    unawaited(_cache.write(cacheAccount, cacheKey, encode(fresh)));
    return Synced<T>(fresh, DateTime.now());
  }

  bool _inFlight = false;

  /// Pull-to-refresh and live ticks. Keeps current data visible while loading;
  /// a refresh already running absorbs new requests. Never throws: a failure
  /// shows in the state (the screen's error view, or "couldn't refresh").
  Future<void> refresh() async {
    if (_inFlight) return;
    final cur = state.value;
    if (cur == null) {
      ref.invalidateSelf();
      await future.then<void>((_) {}, onError: (Object _) {});
      return;
    }
    _inFlight = true;
    try {
      await _revalidate();
    } finally {
      _inFlight = false;
    }
  }

  /// Replaces data locally after a successful mutation and persists it.
  void setData(T data) {
    state = AsyncData(Synced<T>(data, DateTime.now()));
    unawaited(_cache.write(cacheAccount, cacheKey, encode(data)));
  }

  Future<void> _revalidate() async {
    try {
      final fresh = await fetch();
      if (!ref.mounted) return;
      unawaited(_cache.write(cacheAccount, cacheKey, encode(fresh)));
      state = AsyncData(Synced<T>(fresh, DateTime.now()));
    } on Object catch (e, st) {
      if (!ref.mounted) return;
      final cur = state.value;
      state = cur == null ? AsyncError(e, st) : AsyncData(cur.copyWith(refreshing: false, refreshError: e));
    }
  }
}
