import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/access.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/providers.dart';
import '../../zones/data/zones_providers.dart';
import 'traffic_repository.dart';

export 'traffic_models.dart';

/// Traffic for one zone over one range, cached per (zone, range) so switching
/// ranges or reopening the screen paints at once and refreshes quietly.
final zoneTrafficProvider = AsyncNotifierProvider.autoDispose
    .family<ZoneTrafficNotifier, Synced<ZoneTraffic>, (String, TrafficRange)>(ZoneTrafficNotifier.new);

class ZoneTrafficNotifier extends SyncedNotifier<ZoneTraffic> {
  ZoneTrafficNotifier(this.arg);
  final (String, TrafficRange) arg;

  String get zoneId => arg.$1;
  TrafficRange get range => arg.$2;

  CfClient? _client;
  NoAccess? _noAccess;
  String? _account;

  @override
  void prepare() {
    final zone = ref.watch(stableZoneProvider(zoneId));
    _account = zone?.account.id;
    if (zone == null) {
      _client = null;
      return;
    }
    // No token may read analytics here: skip the call. An unchecked one tries.
    final access = ref.watch(accessProvider).zone(zone, Capability.analytics);
    _noAccess = access is NoAccess ? access : null;
    _client = access is Granted ? ref.read(cfClientProvider(access.token.id)) : null;
  }

  @override
  String get cacheAccount => _account ?? (throw StateError('Zone $zoneId is not loaded'));

  @override
  String get cacheKey => 'traffic:$zoneId:${range.name}';

  @override
  Future<ZoneTraffic> fetch() async {
    final missing = _noAccess;
    if (missing != null) throw CfNoAccessException(Capability.analytics.permission, missing.reason);
    final client = _client;
    if (client == null) throw StateError('Zone $zoneId is not loaded');
    return zoneSeries(client, zoneId, range);
  }

  @override
  Object? encode(ZoneTraffic data) => data.toJson();

  @override
  ZoneTraffic decode(Object? json) => ZoneTraffic.fromJson(json as Map<String, dynamic>);
}

/// Last 7 days of traffic for every zone of one account that a token may
/// read analytics for, keyed by zone id. Zones no token may read are absent.
final fleetTrafficProvider =
    AsyncNotifierProvider.family<FleetTrafficNotifier, Synced<Map<String, ZoneTraffic>>, String>(FleetTrafficNotifier.new);

class FleetTrafficNotifier extends SyncedNotifier<Map<String, ZoneTraffic>> {
  FleetTrafficNotifier(this.accountId);
  final String accountId;

  /// Days covered by the fleet view.
  static const days = 7;

  @override
  void prepare() {
    // Rebuild only when the set of zones or the tokens that reach them
    // change, not on every zone-list refresh.
    ref.watch(zonesProvider(accountId).select(
      (s) => (s.value?.data ?? const <Zone>[]).map((z) => '${z.id}:${z.reach.join('+')}').join(','),
    ));
    ref.watch(accessProvider);
  }

  @override
  String get cacheAccount => accountId;

  @override
  String get cacheKey => 'traffic-fleet:${days}d';

  @override
  Future<Map<String, ZoneTraffic>> fetch() async {
    final zones = ref.read(zonesProvider(accountId)).value?.data ?? const <Zone>[];
    final access = ref.read(accessProvider);
    final byToken = <String, List<String>>{};
    for (final z in zones) {
      final a = access.zone(z, Capability.analytics);
      if (a is Granted) byToken.putIfAbsent(a.token.id, () => []).add(z.id);
    }
    final out = <String, ZoneTraffic>{};
    Object? firstError;
    for (final e in byToken.entries) {
      try {
        out.addAll(await fleetDailyTotals(ref.read(cfClientProvider(e.key)), e.value, days: days));
      } on CfException catch (err) {
        // One failing token shouldn't blank the others.
        firstError ??= err;
      }
    }
    if (out.isEmpty && firstError != null) throw firstError;
    return out;
  }

  @override
  Object? encode(Map<String, ZoneTraffic> data) => {for (final e in data.entries) e.key: e.value.toJson()};

  @override
  Map<String, ZoneTraffic> decode(Object? json) => {
        for (final e in (json as Map<String, dynamic>).entries)
          e.key: ZoneTraffic.fromJson(e.value as Map<String, dynamic>),
      };
}
