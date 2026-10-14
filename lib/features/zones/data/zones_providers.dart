import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/providers.dart';

/// Every zone of one account. Each token that reaches the account lists its
/// zones; a zone records which tokens listed it, since a token can be limited
/// to some zones.
final zonesProvider = AsyncNotifierProvider.family<ZonesNotifier, Synced<List<Zone>>, String>(ZonesNotifier.new);

class ZonesNotifier extends SyncedNotifier<List<Zone>> {
  ZonesNotifier(this.accountId);
  final String accountId;

  List<Credential> _tokens = const [];

  @override
  void prepare() {
    // Rebuild only when the set of usable tokens changes (not on expiry
    // refreshes or other accounts' probes).
    ref.watch(tokensProvider.select((ts) => [for (final t in ts) if (_usable(t)) t.id].join(',')));
    _tokens = ref.read(tokensProvider).where(_usable).toList();
  }

  bool _usable(Credential t) => t.reaches(accountId) && t.can(accountId, Capability.zones);

  @override
  String get cacheAccount => accountId;

  @override
  String get cacheKey => 'zones';

  @override
  Future<List<Zone>> fetch() async {
    final byId = <String, Zone>{};
    for (final t in _tokens) {
      final rows = await ref.read(cfClientProvider(t.id)).getAll('/zones', query: {'account.id': accountId, 'order': 'name', 'direction': 'asc'});
      for (final r in rows) {
        final id = '${r['id']}';
        byId[id] = byId[id]?.reachedBy(t.id) ?? Zone.fromJson(r, reach: [t.id]);
      }
    }
    return byId.values.toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Object? encode(List<Zone> data) => data.map((z) => z.toJson()).toList();

  @override
  List<Zone> decode(Object? json) => (json as List).cast<Map<String, dynamic>>().map(Zone.fromCache).toList();

  /// Replaces one zone after a mutation (pause, dev mode…).
  void upsert(Zone zone) {
    final cur = state.value?.data;
    if (cur == null) return;
    setData([for (final z in cur) z.id == zone.id ? zone : z]);
  }
}

/// A zone of the active account, by id (null until loaded, or when it isn't
/// one of the active account's zones).
final zoneByIdProvider = Provider.family<Zone?, String>((ref, id) {
  final account = ref.watch(activeAccountProvider)?.id;
  if (account == null) return null;
  for (final z in ref.watch(zonesProvider(account)).value?.data ?? const <Zone>[]) {
    if (z.id == id) return z;
  }
  return null;
});

/// The same zone, but only rebuilt when its identity or the tokens that reach
/// it change (not on every zone-list refresh). Per-zone repositories watch
/// this so a 60-second refresh doesn't rebuild them.
final stableZoneProvider = Provider.family<Zone?, String>((ref, id) {
  ref.watch(zoneByIdProvider(id).select((z) => z == null ? null : (z.id, z.account.id, z.reach.join(','))));
  return ref.read(zoneByIdProvider(id));
});

/// Pinned zone ids of one account, kept in the app settings.
final pinnedZonesProvider = AsyncNotifierProvider.family<PinnedZonesNotifier, Set<String>, String>(PinnedZonesNotifier.new);

class PinnedZonesNotifier extends AsyncNotifier<Set<String>> {
  PinnedZonesNotifier(this.accountId);
  final String accountId;

  @override
  Future<Set<String>> build() async {
    final s = await ref.read(secureStoreProvider).readSettings();
    return {...((s['pinned_zones'] as Map?)?[accountId] as List? ?? const []).cast<String>()};
  }

  Future<void> toggle(String zoneId) async {
    final cur = {...?state.value};
    cur.contains(zoneId) ? cur.remove(zoneId) : cur.add(zoneId);
    state = AsyncData(cur);
    final pinned = cur.toList();
    await ref.read(secureStoreProvider).updateSettings((s) {
      final all = Map<String, dynamic>.from((s['pinned_zones'] as Map?) ?? const {});
      all[accountId] = pinned;
      s['pinned_zones'] = all;
    });
  }
}
