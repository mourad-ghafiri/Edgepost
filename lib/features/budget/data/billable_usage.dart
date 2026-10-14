import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/access.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/providers.dart';

/// Usage of one billable service in the current billing period.
class ServiceUsage {
  const ServiceUsage({required this.name, required this.quantity, required this.unit, required this.cost, this.family});

  final String name;
  final String? family;
  final double quantity;
  final String unit;
  final double cost;

  Map<String, dynamic> toJson() => {'name': name, 'family': family, 'quantity': quantity, 'unit': unit, 'cost': cost};

  factory ServiceUsage.fromJson(Map<String, dynamic> j) => ServiceUsage(
        name: '${j['name']}',
        family: j['family'] as String?,
        quantity: (j['quantity'] as num).toDouble(),
        unit: '${j['unit']}',
        cost: (j['cost'] as num).toDouble(),
      );
}

/// One account's billable usage for its current billing period.
class AccountUsage {
  const AccountUsage({
    required this.services,
    required this.currency,
    this.periodStart,
    this.periodEnd,
  });

  final List<ServiceUsage> services;
  final String currency;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  double get totalCost => services.fold(0, (s, x) => s + x.cost);

  Map<String, dynamic> toJson() => {
        'services': services.map((x) => x.toJson()).toList(),
        'currency': currency,
        'periodStart': periodStart?.toIso8601String(),
        'periodEnd': periodEnd?.toIso8601String(),
      };

  factory AccountUsage.fromJson(Map<String, dynamic> j) => AccountUsage(
        services: (j['services'] as List).cast<Map<String, dynamic>>().map(ServiceUsage.fromJson).toList(),
        currency: '${j['currency']}',
        periodStart: parseCfDate(j['periodStart']),
        periodEnd: parseCfDate(j['periodEnd']),
      );
}

/// `GET /accounts/{account_id}/billable-usage` with no parameters returns the
/// current billing period's usage records (Alpha;
/// https://developers.cloudflare.com/api/resources/billing/subresources/usage/).
/// Records are summed per `ServiceName`.
Future<AccountUsage> fetchAccountUsage(CfClient client, String accountId) async {
  final res = await client.get('/accounts/$accountId/billable-usage');
  final records = res.list;
  final byService = <String, ServiceUsage>{};
  DateTime? start, end;
  var currency = 'USD';
  for (final r in records) {
    final name = '${r['ServiceName'] ?? r['ChargeDescription'] ?? '—'}';
    final prev = byService[name];
    final qty = (r['ConsumedQuantity'] as num?)?.toDouble() ?? 0;
    final cost = (r['BilledCost'] as num?)?.toDouble() ?? 0;
    byService[name] = ServiceUsage(
      name: name,
      family: r['ServiceFamilyName'] as String? ?? prev?.family,
      quantity: (prev?.quantity ?? 0) + qty,
      unit: '${r['ConsumedUnit'] ?? r['PricingUnit'] ?? ''}'.trim(),
      cost: (prev?.cost ?? 0) + cost,
    );
    currency = '${r['BillingCurrency'] ?? currency}';
    final ps = parseCfDate(r['BillingPeriodStart']) ?? parseCfDate(r['ChargePeriodStart']);
    final pe = parseCfDate(r['ChargePeriodEnd']);
    if (ps != null && (start == null || ps.isBefore(start))) start = ps;
    if (pe != null && (end == null || pe.isAfter(end))) end = pe;
  }
  final services = byService.values.toList()..sort((a, b) => b.cost != a.cost ? b.cost.compareTo(a.cost) : a.name.compareTo(b.name));
  return AccountUsage(services: services, currency: currency, periodStart: start, periodEnd: end);
}

/// One account's usage this period, or null when no token may read its
/// billing (the Budget card then shows emails sent only).
final billableUsageProvider =
    AsyncNotifierProvider.family<BillableUsageNotifier, Synced<AccountUsage?>, String>(BillableUsageNotifier.new);

class BillableUsageNotifier extends SyncedNotifier<AccountUsage?> {
  BillableUsageNotifier(this.accountId);
  final String accountId;

  @override
  void prepare() => ref.watch(accessProvider.select((a) => a.account(accountId, Capability.billing)));

  @override
  String get cacheAccount => accountId;

  @override
  String get cacheKey => 'billing';

  @override
  Future<AccountUsage?> fetch() async {
    final access = ref.read(accessProvider).account(accountId, Capability.billing);
    if (access is! Granted) return null;
    return fetchAccountUsage(ref.read(cfClientProvider(access.token.id)), accountId);
  }

  @override
  Object? encode(AccountUsage? data) => data?.toJson();

  @override
  AccountUsage? decode(Object? json) => json == null ? null : AccountUsage.fromJson(json as Map<String, dynamic>);
}
