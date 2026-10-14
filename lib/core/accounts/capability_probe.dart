import '../cloudflare/cf_client.dart';
import '../cloudflare/cf_errors.dart';
import 'credential.dart';

/// Discovers which features a token can use by issuing one inexpensive read
/// per capability (free: Cloudflare API calls aren't billed, only rate-limited).
///
/// Only an explicit permission refusal counts as [CapState.denied]. A
/// rejected parameter, a network hiccup or a rate limit is [CapState.unknown],
/// so a flaky check never hides a feature. Edit rights are confirmed the first
/// time the user changes something.
class CapabilityProbe {
  const CapabilityProbe(this.client);
  final CfClient client;

  /// Probes what this token can do in one account. Zone-level checks use one
  /// of that account's zones.
  Future<Map<Capability, CapState>> run(String account) async {
    final out = <Capability, CapState>{};

    String? zoneId;
    out[Capability.zones] = await _check(() async {
      // per_page: 5–50; account.id filters to one account
      // (https://developers.cloudflare.com/api/resources/zones/methods/list/)
      final zones = await client.get('/zones', query: {'per_page': 5, 'account.id': account});
      if (zones.list.isNotEmpty) zoneId = '${zones.list.first['id']}';
      return null;
    });

    Future<void> probe(Capability c, Future<Object?> Function() read, {bool r2 = false}) async =>
        out[c] = await _check(read, r2: r2);

    final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final z = zoneId;
    await Future.wait([
      if (z != null) ...[
        probe(Capability.dns, () => client.get('/zones/$z/dns_records', query: {'per_page': 5})),
        probe(Capability.zoneSettings, () => client.get('/zones/$z/settings/ssl')),
        // Needs Zone Settings Read (https://developers.cloudflare.com/api/resources/email_routing/methods/get/)
        probe(Capability.emailRouting, () => client.get('/zones/$z/email/routing')),
        probe(Capability.dmarc, () => client.get('/zones/$z/email/auth/dmarc-reports')),
        probe(Capability.workerRoutes, () => client.get('/zones/$z/workers/routes')),
        probe(
          Capability.analytics,
          () => client.graphql(
            r'query($z: string!, $d: Date!) { viewer { zones(filter: {zoneTag: $z}) { '
            r'httpRequests1dGroups(limit: 1, filter: {date_geq: $d, date_leq: $d}) { sum { requests } } } } }',
            variables: {'z': z, 'd': today},
          ),
        ),
      ],
      ...[
        // per_page: 5–50 (https://developers.cloudflare.com/api/resources/email_routing/subresources/addresses/methods/list/)
        probe(Capability.emailAddresses, () => client.get('/accounts/$account/email/routing/addresses', query: {'per_page': 5})),
        probe(Capability.workers, () => client.get('/accounts/$account/workers/scripts')),
        probe(Capability.pages, () => client.get('/accounts/$account/pages/projects')),
        // per_page: minimum 10 (https://developers.cloudflare.com/api/resources/d1/subresources/database/methods/list/)
        probe(Capability.d1, () => client.get('/accounts/$account/d1/database', query: {'per_page': 10})),
        probe(Capability.r2, () => client.get('/accounts/$account/r2/buckets', query: {'per_page': 1}), r2: true),
        probe(Capability.registrar, () => client.get('/accounts/$account/registrar/registrations')),
        // https://developers.cloudflare.com/api/resources/billing/subresources/usage/
        probe(Capability.billing, () => client.get('/accounts/$account/billable-usage/info')),
      ],
    ]);

    // Zone-level checks need a zone; with none, they stay open (unknown).
    for (final c in const [
      Capability.dns,
      Capability.zoneSettings,
      Capability.emailRouting,
      Capability.dmarc,
      Capability.workerRoutes,
      Capability.analytics,
    ]) {
      out.putIfAbsent(c, () => CapState.unknown);
    }
    // Cache purge has no read endpoint; confirmed on first use.
    out[Capability.cachePurge] = out[Capability.zones] == CapState.denied ? CapState.denied : CapState.unknown;
    return out;
  }

  static Future<CapState> _check(Future<Object?> Function() read, {bool r2 = false}) async {
    try {
      await read();
      return CapState.granted;
    } on CfApiException catch (e) {
      // R2 answers with an "enable R2" error until its one-time subscription
      // checkout is done (https://developers.cloudflare.com/r2/get-started/).
      if (r2 && isR2NotEnabled(e)) return CapState.notEnabled;
      if (e.isPermissionDenied) return CapState.denied;
      // 404 on a sub-resource that only exists once configured still proves access.
      if (e.isNotFound) return CapState.granted;
      return CapState.unknown;
    } on CfAuthException {
      return CapState.denied;
    } on CfException {
      return CapState.unknown;
    }
  }

  static bool isR2NotEnabled(CfApiException e) {
    final m = e.message.toLowerCase();
    return e.hasCode(10042) || (m.contains('r2') && (m.contains('enable') || m.contains('purchase') || m.contains('subscription')));
  }
}
