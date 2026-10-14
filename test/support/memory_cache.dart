import 'dart:convert';

import 'package:edgepost/core/storage/cache_store.dart';

/// In-memory cache. The file-backed [CacheStore] does real disk IO, which
/// never completes inside `testWidgets`' fake async zone, and
/// [SyncedNotifier.build] awaits the cache write.
class MemoryCacheStore extends CacheStore {
  /// Entries by account, then key.
  final Map<String, Map<String, CacheHit>> entries = {};

  @override
  Future<CacheHit?> read(String account, String key) async => entries[account]?[key];

  @override
  Future<void> write(String account, String key, Object? value) async =>
      (entries[account] ??= {})[key] = CacheHit(jsonDecode(jsonEncode(value)), DateTime.now());

  @override
  Future<void> remove(String account, String key) async => entries[account]?.remove(key);

  @override
  Future<void> removeWhere(String account, bool Function(String key) test) async =>
      entries[account]?.removeWhere((k, _) => test(k));

  @override
  Future<void> clearAccount(String account) async => entries.remove(account);
}
