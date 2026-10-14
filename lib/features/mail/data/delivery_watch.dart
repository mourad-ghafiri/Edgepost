import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/access.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/providers.dart';
import '../../zones/data/zones_providers.dart';
import 'mail_providers.dart';
import 'sending_health.dart';

/// Delivered vs failed sends of one sending domain over the last 7 days.
class DomainDelivery {
  const DomainDelivery({required this.zoneId, required this.domain, required this.delivered, required this.failed});

  factory DomainDelivery.fromCounts(Zone zone, Map<String, int> byStatus) => DomainDelivery(
    zoneId: zone.id,
    domain: zone.name,
    delivered: byStatus['delivered'] ?? 0,
    failed: (byStatus['deliveryFailed'] ?? 0) + (byStatus['failed'] ?? 0) + (byStatus['rejected'] ?? 0),
  );

  factory DomainDelivery.fromJson(Map<String, dynamic> j) => DomainDelivery(
    zoneId: '${j['zoneId']}',
    domain: '${j['domain']}',
    delivered: (j['delivered'] as num).toInt(),
    failed: (j['failed'] as num).toInt(),
  );

  final String zoneId;
  final String domain;
  final int delivered;
  final int failed;

  int get finished => delivered + failed;
  double? get rate => finished == 0 ? null : delivered / finished;

  /// Below Cloudflare's 95% delivery target, with enough sends to mean
  /// something (https://developers.cloudflare.com/email-service/concepts/deliverability/).
  bool get low => finished >= 5 && rate! < 0.95;

  Map<String, dynamic> toJson() => {'zoneId': zoneId, 'domain': domain, 'delivered': delivered, 'failed': failed};
}

/// Delivery rate of every domain the account's mail service sends from, one
/// GraphQL query each, refreshed on the slow tier. Domains no token may read
/// analytics for are skipped.
final deliveryWatchProvider = AsyncNotifierProvider.family<DeliveryWatch, Synced<List<DomainDelivery>>, String>(
  DeliveryWatch.new,
);

class DeliveryWatch extends SyncedNotifier<List<DomainDelivery>> {
  DeliveryWatch(this.accountId);
  final String accountId;

  List<(String, Zone)> _targets = const [];

  @override
  void prepare() {
    // Rebuild only when the sending domains or their tokens change, not on
    // every zone refresh.
    ref.watch(
      zonesProvider(accountId).select((z) => z.value?.data.map((z) => '${z.id}:${z.reach.join('+')}').join(',')),
    );
    ref.watch(mailServiceProvider(accountId).select((s) => '${s?.domains}${s?.sendingDomains}'));
    ref.watch(accessProvider);
    final service = ref.read(mailServiceProvider(accountId));
    final names = {...?service?.sendingDomains, ...?service?.domains};
    final access = ref.read(accessProvider);
    _targets = [
      for (final z in ref.read(zonesProvider(accountId)).value?.data ?? const <Zone>[])
        if (names.contains(z.name))
          if (access.zone(z, Capability.analytics) case Granted(:final token)) (token.id, z),
    ];
  }

  @override
  String get cacheAccount => accountId;

  @override
  String get cacheKey => 'delivery';

  @override
  Future<List<DomainDelivery>> fetch() async => [
    for (final (tokenId, z) in _targets)
      DomainDelivery.fromCounts(z, await fetchSendingCounts(ref.read(cfClientProvider(tokenId)), z)),
  ];

  @override
  Object? encode(List<DomainDelivery> data) => data.map((d) => d.toJson()).toList();

  @override
  List<DomainDelivery> decode(Object? json) =>
      (json as List).cast<Map<String, dynamic>>().map(DomainDelivery.fromJson).toList();
}
