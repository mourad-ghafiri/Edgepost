import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/providers.dart';
import '../../zones/data/zones_providers.dart';
import 'dns_record.dart';
import 'dns_repository.dart';

/// Repository for one zone, or null until the zone list has loaded.
final dnsRepositoryProvider = Provider.family<DnsRepository?, String>((ref, zoneId) {
  final zone = ref.watch(stableZoneProvider(zoneId));
  if (zone == null) return null;
  return DnsRepository(ref.zoneClient(zone, Capability.dns), zoneId);
});

/// Records of one zone, cached for instant display and revalidated quietly.
final dnsRecordsProvider = AsyncNotifierProvider.family<DnsNotifier, Synced<List<DnsRecord>>, String>(DnsNotifier.new);

/// Raised when the user tries a fourth BIND import within a minute;
/// Cloudflare allows three per minute.
class DnsImportThrottled implements Exception {
  const DnsImportThrottled(this.wait);
  final Duration wait;
}

class DnsNotifier extends SyncedNotifier<List<DnsRecord>> {
  DnsNotifier(this.zoneId);

  final String zoneId;
  DnsRepository? _repo;
  String? _account;

  /// Recent import attempts (Cloudflare: three per minute per user).
  static final List<DateTime> _imports = [];
  static DateTime Function() clock = DateTime.now;

  @visibleForTesting
  static void resetImportLog() => _imports.clear();

  DnsRepository get repository => _repo ?? (throw StateError('Zone $zoneId is not loaded yet'));

  @override
  void prepare() {
    _repo = ref.watch(dnsRepositoryProvider(zoneId));
    _account = ref.read(stableZoneProvider(zoneId))?.account.id;
  }

  @override
  String get cacheAccount => _account ?? (throw StateError('Zone $zoneId is not loaded yet'));

  @override
  String get cacheKey => 'dns:$zoneId';

  @override
  Future<List<DnsRecord>> fetch() async => sortRecords(await repository.list());

  @override
  Object? encode(List<DnsRecord> data) => data.map((r) => r.toJson()).toList();

  @override
  List<DnsRecord> decode(Object? json) => (json as List).cast<Map<String, dynamic>>().map(DnsRecord.fromJson).toList();

  List<DnsRecord> get _current => state.value?.data ?? const [];

  void _put(List<DnsRecord> list) {
    if (!ref.mounted) return;
    if (!state.hasValue) {
      // A first load is still running: let it pick the change up instead of
      // replacing the whole list with a partial one.
      ref.invalidateSelf();
      return;
    }
    setData(sortRecords(list));
  }

  void _swap(String id, DnsRecord? replacement) {
    final out = <DnsRecord>[];
    var found = false;
    for (final r in _current) {
      if (r.id == id) {
        found = true;
        if (replacement != null) out.add(replacement);
      } else {
        out.add(r);
      }
    }
    if (!found && replacement != null) out.add(replacement);
    _put(out);
  }

  Future<DnsRecord> create(Map<String, dynamic> body) async {
    final rec = await repository.create(body);
    _swap(rec.id, rec);
    return rec;
  }

  /// Saves an edit. Shows the change at once and rolls back if Cloudflare
  /// refuses it. A type change becomes an atomic delete + create.
  Future<DnsRecord> save(DnsRecord original, Map<String, dynamic> body) async {
    final optimistic = DnsRecord.fromJson({...original.toJson(), ...body, 'id': original.id});
    _swap(original.id, optimistic);
    try {
      final saved = await repository.update(original, body);
      if (saved.id != original.id) _swap(original.id, null);
      _swap(saved.id, saved);
      return saved;
    } on Object {
      _swap(original.id, original);
      rethrow;
    }
  }

  /// Removes [record] from the list at once, then deletes it; restores it
  /// when the delete fails. A record that is already gone counts as deleted.
  Future<void> delete(DnsRecord record) async {
    _swap(record.id, null);
    try {
      await repository.delete(record.id);
    } on CfApiException catch (e) {
      if (e.isNotFound) return;
      _swap(record.id, record);
      rethrow;
    } on Object {
      _swap(record.id, record);
      rethrow;
    }
  }

  /// Undo for [delete]: re-creates the record (it gets a new id).
  Future<DnsRecord> restore(DnsRecord deleted) async {
    _swap(deleted.id, deleted);
    try {
      final rec = await repository.recreate(deleted);
      _swap(deleted.id, null);
      _swap(rec.id, rec);
      return rec;
    } on Object {
      _swap(deleted.id, null);
      rethrow;
    }
  }

  /// Applies several changes in one atomic batch (templates).
  Future<DnsBatchResult> applyBatch({
    List<String> deletes = const [],
    List<Map<String, dynamic>> posts = const [],
  }) async {
    final result = await repository.batch(deletes: deletes, posts: posts);
    _put([..._current.where((r) => !deletes.contains(r.id)), ...result.posts]);
    return result;
  }

  Future<String> exportBind() => repository.exportBind();

  Future<DnsImportResult> importBind(Uint8List bytes, {required String filename, required bool proxied}) async {
    final now = clock();
    _imports.removeWhere((t) => now.difference(t) >= const Duration(minutes: 1));
    if (_imports.length >= 3) {
      throw DnsImportThrottled(const Duration(minutes: 1) - now.difference(_imports.first));
    }
    _imports.add(now);
    final result = await repository.importBind(bytes, filename: filename, proxied: proxied);
    if (ref.mounted) await refresh();
    return result;
  }
}

/// Known types in editor order, then other types A–Z; by name, then value.
List<DnsRecord> sortRecords(Iterable<DnsRecord> records) {
  final list = records.toList();
  list.sort((a, b) {
    final t = DnsTypes.order(a.type).compareTo(DnsTypes.order(b.type));
    if (t != 0) return t;
    final tn = a.type.compareTo(b.type);
    if (tn != 0) return tn;
    final n = a.name.compareTo(b.name);
    if (n != 0) return n;
    final p = (a.priority ?? 0).compareTo(b.priority ?? 0);
    if (p != 0) return p;
    return a.content.compareTo(b.content);
  });
  return list;
}
