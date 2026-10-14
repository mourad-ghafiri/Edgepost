/// Email Routing calls, as top-level functions over a [CfClient].
///
/// Other features (mail setup) call the four public helpers below with these
/// exact signatures:
///   enableRouting, routeAddressToWorker, setCatchAllToWorker, fetchRoutingSettings.
///
/// Endpoints follow https://developers.cloudflare.com/api/resources/email_routing/
/// and avoid the deprecated `/enable`, `/disable` and `/unlock` paths.
library;

import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/cf_errors.dart';
import 'email_routing_models.dart';

export 'email_routing_models.dart';

String _routing(String zoneId) => '/zones/$zoneId/email/routing';

// ---------------------------------------------------------------------------
// Public helpers (stable signatures used by other features)
// ---------------------------------------------------------------------------

/// Turns Email Routing on: Cloudflare adds and locks the MX and SPF records
/// (`POST /zones/{zone_id}/email/routing/dns`). Also re-locks records after an
/// unlock.
Future<void> enableRouting(CfClient client, String zoneId) async {
  await client.post('${_routing(zoneId)}/dns');
}

/// Points the literal rule for [address] at the Worker [workerName]: updates
/// the existing rule matching that address (keeping its name and priority)
/// or creates a new one. The rule is enabled either way.
///
/// The worker action's `value` is the Worker script name (the API reference
/// does not state the format explicitly).
Future<void> routeAddressToWorker(CfClient client, String zoneId, String address, String workerName) async {
  final wanted = address.trim().toLowerCase();
  final rules = await fetchRoutingRules(client, zoneId);
  final action = RuleAction.worker(workerName);
  for (final r in rules) {
    if (r.address?.toLowerCase() == wanted) {
      await updateRoutingRule(client, zoneId, r.copyWith(actions: [action], enabled: true));
      return;
    }
  }
  await createRoutingRule(client, zoneId, RoutingRule.forAddress(address.trim(), action));
}

/// Sends every address without its own rule to the Worker [workerName].
Future<void> setCatchAllToWorker(CfClient client, String zoneId, String workerName) =>
    updateCatchAll(client, zoneId, action: RuleAction.worker(workerName), enabled: true);

/// `GET /zones/{zone_id}/email/routing`.
Future<RoutingSettings> fetchRoutingSettings(CfClient client, String zoneId) async {
  final res = await client.get(_routing(zoneId));
  return RoutingSettings.fromJson(res.map);
}

// ---------------------------------------------------------------------------
// Settings and DNS
// ---------------------------------------------------------------------------

/// Turns Email Routing off and removes the MX records it added
/// (`DELETE /zones/{zone_id}/email/routing/dns`).
Future<void> disableRouting(CfClient client, String zoneId) async {
  await client.delete('${_routing(zoneId)}/dns');
}

/// Unlocks the MX records Email Routing locked
/// (`PATCH /zones/{zone_id}/email/routing/dns`).
Future<void> unlockRoutingRecords(CfClient client, String zoneId) async {
  await client.patch('${_routing(zoneId)}/dns');
}

/// Records Email Routing needs (`GET /zones/{zone_id}/email/routing/dns`).
/// The reference documents an array; an object wrapping `record`/`records`
/// is accepted too.
Future<List<RoutingDnsRecord>> fetchRoutingDnsRecords(CfClient client, String zoneId) async {
  final res = await client.get('${_routing(zoneId)}/dns');
  final r = res.result;
  final List<Object?> rows = switch (r) {
    final List<Object?> list => list,
    final Map<String, dynamic> map => (map['record'] ?? map['records'] ?? const <Object?>[]) as List<Object?>,
    _ => const [],
  };
  return rows.whereType<Map<String, dynamic>>().map(RoutingDnsRecord.fromJson).toList();
}

// ---------------------------------------------------------------------------
// Rules
// ---------------------------------------------------------------------------

/// Address rules for the zone. A catch-all row, if the list includes one, is
/// left out: it lives at `/rules/catch_all`.
Future<List<RoutingRule>> fetchRoutingRules(CfClient client, String zoneId) async {
  final rows = await client.getAll('${_routing(zoneId)}/rules');
  return rows.map(RoutingRule.fromJson).where((r) => !r.isCatchAll).toList();
}

Future<RoutingRule> createRoutingRule(CfClient client, String zoneId, RoutingRule rule) async {
  final res = await client.post('${_routing(zoneId)}/rules', data: rule.toRequestBody());
  return _ruleOr(res.result, rule);
}

Future<RoutingRule> updateRoutingRule(CfClient client, String zoneId, RoutingRule rule) async {
  final id = rule.id;
  if (id == null) throw ArgumentError('updateRoutingRule needs a rule id');
  final res = await client.put('${_routing(zoneId)}/rules/$id', data: rule.toRequestBody());
  return _ruleOr(res.result, rule);
}

Future<void> deleteRoutingRule(CfClient client, String zoneId, String ruleId) async {
  await client.delete('${_routing(zoneId)}/rules/$ruleId');
}

/// `GET /rules/catch_all`. Null when the zone has none (404).
Future<RoutingRule?> fetchCatchAll(CfClient client, String zoneId) async {
  try {
    final res = await client.get('${_routing(zoneId)}/rules/catch_all');
    final r = res.result;
    return r is Map<String, dynamic> ? RoutingRule.fromJson(r) : null;
  } on CfApiException catch (e) {
    if (e.isNotFound) return null;
    rethrow;
  }
}

/// `PUT /rules/catch_all` with matchers `[{type: all}]`.
Future<RoutingRule> updateCatchAll(
  CfClient client,
  String zoneId, {
  required RuleAction action,
  required bool enabled,
}) async {
  final rule = RoutingRule(actions: [action], matchers: const [RuleMatcher.all()], enabled: enabled);
  final res = await client.put('${_routing(zoneId)}/rules/catch_all', data: rule.toRequestBody());
  return _ruleOr(res.result, rule);
}

RoutingRule _ruleOr(Object? result, RoutingRule fallback) =>
    result is Map<String, dynamic> ? RoutingRule.fromJson(result) : fallback;

// ---------------------------------------------------------------------------
// Destination addresses (account level)
// ---------------------------------------------------------------------------

String _addresses(String accountId) => '/accounts/$accountId/email/routing/addresses';

Future<List<DestinationAddress>> fetchDestinationAddresses(CfClient client, String accountId) async {
  final rows = await client.getAll(_addresses(accountId));
  return rows.map(DestinationAddress.fromJson).toList()
    ..sort((a, b) => a.email.toLowerCase().compareTo(b.email.toLowerCase()));
}

/// Adds a destination; Cloudflare emails the owner a verification link.
Future<DestinationAddress> createDestinationAddress(CfClient client, String accountId, String email) async {
  final res = await client.post(_addresses(accountId), data: {'email': email.trim()});
  final r = res.result;
  return r is Map<String, dynamic> ? DestinationAddress.fromJson(r) : DestinationAddress(id: '', email: email.trim());
}

Future<void> deleteDestinationAddress(CfClient client, String accountId, String addressId) async {
  await client.delete('${_addresses(accountId)}/$addressId');
}
