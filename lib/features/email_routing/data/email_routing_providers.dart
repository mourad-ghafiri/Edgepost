import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/access.dart';
import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/cloudflare/cf_client.dart';
import '../../../core/providers.dart';
import '../../zones/data/zones_providers.dart';
import 'email_routing_repository.dart';
import 'mail_auth.dart';

/// Raised while the zone (and so its token) isn't known yet.
class RoutingZoneUnavailable implements Exception {
  const RoutingZoneUnavailable(this.zoneId);
  final String zoneId;
}

// ---------------------------------------------------------------------------
// Settings + rules + catch-all + required DNS, per zone
// ---------------------------------------------------------------------------

final routingOverviewProvider =
    AsyncNotifierProvider.family<RoutingOverviewNotifier, Synced<RoutingOverview>, String>(
  RoutingOverviewNotifier.new,
  isAutoDispose: true,
);

class RoutingOverviewNotifier extends SyncedNotifier<RoutingOverview> {
  RoutingOverviewNotifier(this.zoneId);
  final String zoneId;
  late CfClient _client;
  late String _account;

  @override
  void prepare() {
    final zone = ref.watch(stableZoneProvider(zoneId));
    if (zone == null) throw RoutingZoneUnavailable(zoneId);
    _client = ref.zoneClient(zone, Capability.emailRouting);
    _account = zone.account.id;
  }

  @override
  String get cacheAccount => _account;

  @override
  String get cacheKey => 'email-routing:$zoneId';

  @override
  Future<RoutingOverview> fetch() async {
    final settings = await fetchRoutingSettings(_client, zoneId);
    final rules = await fetchRoutingRules(_client, zoneId);
    RoutingRule? catchAll;
    try {
      catchAll = await fetchCatchAll(_client, zoneId);
    } on Object {
      catchAll = null; // shown as "Off"; the rules above already proved access
    }
    var dns = const <RoutingDnsRecord>[];
    try {
      dns = await fetchRoutingDnsRecords(_client, zoneId);
    } on Object {
      dns = const [];
    }
    rules.sort(_byAddress);
    return RoutingOverview(settings: settings, rules: rules, catchAll: catchAll, dnsRecords: dns);
  }

  static int _byAddress(RoutingRule a, RoutingRule b) =>
      (a.address ?? '').toLowerCase().compareTo((b.address ?? '').toLowerCase());

  @override
  Object? encode(RoutingOverview data) => data.toJson();

  @override
  RoutingOverview decode(Object? json) => RoutingOverview.fromJson(json as Map<String, dynamic>);

  RoutingOverview? get _current => state.value?.data;

  /// Turns routing on (adds and locks MX + SPF) or re-locks unlocked records.
  Future<void> enable() async {
    await enableRouting(_client, zoneId);
    await refresh();
  }

  Future<void> disable() async {
    await disableRouting(_client, zoneId);
    await refresh();
  }

  Future<void> unlock() async {
    await unlockRoutingRecords(_client, zoneId);
    await refresh();
  }

  /// Creates [rule] when it has no id, otherwise replaces it.
  Future<RoutingRule> saveRule(RoutingRule rule) async {
    final saved = rule.id == null
        ? await createRoutingRule(_client, zoneId, rule)
        : await updateRoutingRule(_client, zoneId, rule);
    final cur = _current;
    if (cur != null) {
      final rules = [
        for (final r in cur.rules)
          if (r.id != saved.id && r.id != rule.id) r,
        saved,
      ]..sort(_byAddress);
      setData(cur.copyWith(rules: rules));
    }
    return saved;
  }

  Future<void> setRuleEnabled(RoutingRule rule, bool enabled) => saveRule(rule.copyWith(enabled: enabled));

  Future<void> deleteRule(String ruleId) async {
    await deleteRoutingRule(_client, zoneId, ruleId);
    final cur = _current;
    if (cur != null) setData(cur.copyWith(rules: [for (final r in cur.rules) if (r.id != ruleId) r]));
  }

  Future<void> setCatchAll(RuleAction action, {required bool enabled}) async {
    final saved = await updateCatchAll(_client, zoneId, action: action, enabled: enabled);
    final cur = _current;
    if (cur != null) setData(cur.copyWith(catchAll: saved));
  }
}

// ---------------------------------------------------------------------------
// Destination addresses, per account
// ---------------------------------------------------------------------------

final destinationAddressesProvider =
    AsyncNotifierProvider.family<DestinationAddressesNotifier, Synced<List<DestinationAddress>>, String>(
  DestinationAddressesNotifier.new,
  isAutoDispose: true,
);

class DestinationAddressesNotifier extends SyncedNotifier<List<DestinationAddress>> {
  DestinationAddressesNotifier(this.accountId);
  final String accountId;
  late CfClient _client;

  @override
  void prepare() {
    ref.watch(accessProvider);
    _client = ref.accountClient(accountId, Capability.emailAddresses);
  }

  @override
  String get cacheAccount => accountId;

  @override
  String get cacheKey => 'email-addresses';

  @override
  Future<List<DestinationAddress>> fetch() => fetchDestinationAddresses(_client, accountId);

  @override
  Object? encode(List<DestinationAddress> data) => data.map((a) => a.toJson()).toList();

  @override
  List<DestinationAddress> decode(Object? json) =>
      (json as List).cast<Map<String, dynamic>>().map(DestinationAddress.fromJson).toList();

  Future<DestinationAddress> add(String email) async {
    final created = await createDestinationAddress(_client, accountId, email);
    final cur = state.value?.data ?? const <DestinationAddress>[];
    setData([
      for (final a in cur)
        if (a.email.toLowerCase() != created.email.toLowerCase()) a,
      created,
    ]..sort((a, b) => a.email.toLowerCase().compareTo(b.email.toLowerCase())));
    return created;
  }

  Future<void> remove(String addressId) async {
    await deleteDestinationAddress(_client, accountId, addressId);
    final cur = state.value?.data ?? const <DestinationAddress>[];
    setData([for (final a in cur) if (a.id != addressId) a]);
  }
}

// ---------------------------------------------------------------------------
// Mail authentication inputs, per zone
// ---------------------------------------------------------------------------

final mailAuthProvider = AsyncNotifierProvider.family<MailAuthNotifier, Synced<MailAuthInputs>, String>(
  MailAuthNotifier.new,
  isAutoDispose: true,
);

class MailAuthNotifier extends SyncedNotifier<MailAuthInputs> {
  MailAuthNotifier(this.zoneId);
  final String zoneId;
  late CfClient _client;
  bool _canDns = false;
  bool _canAuth = false;

  late String _account;

  @override
  void prepare() {
    final zone = ref.watch(stableZoneProvider(zoneId));
    if (zone == null) throw RoutingZoneUnavailable(zoneId);
    final access = ref.watch(accessProvider);
    final dns = access.zone(zone, Capability.dns), dmarc = access.zone(zone, Capability.dmarc);
    _canDns = dns is Granted;
    _canAuth = dmarc is Granted;
    // Without either permission the checks that need none still run.
    _client = ref.zoneClient(zone, _canDns ? Capability.dns : (_canAuth ? Capability.dmarc : Capability.zones));
    _account = zone.account.id;
  }

  @override
  String get cacheAccount => _account;

  @override
  String get cacheKey => 'email-auth:$zoneId:$_canDns:$_canAuth';

  @override
  Future<MailAuthInputs> fetch() => fetchMailAuthInputs(_client, zoneId, canDns: _canDns, canEmailAuth: _canAuth);

  @override
  Object? encode(MailAuthInputs data) => data.toJson();

  @override
  MailAuthInputs decode(Object? json) => MailAuthInputs.fromJson(json as Map<String, dynamic>);
}
