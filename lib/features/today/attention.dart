import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/accounts/credential.dart';
import '../../core/cloudflare/models.dart';
import '../../core/providers.dart';
import '../budget/presentation/budget_widgets.dart';
import '../compute/data/compute_providers.dart';
import '../email_routing/data/email_routing_models.dart';
import '../email_routing/data/email_routing_providers.dart';
import '../mail/data/delivery_watch.dart';
import '../mail/data/mail_models.dart';
import '../mail/data/mail_providers.dart';
import '../mail/data/provisioning.dart' show compareVersions, workerBundleProvider;
import '../zones/data/zones_providers.dart';

/// One thing cocked out of line in "Needs you". [key] is stable across
/// refreshes, so a resolved item can spring back into line before it leaves.
sealed class Attention {
  const Attention();
  String get key;
}

/// The sending budget passed 80% or usage costs money.
final class BudgetAttention extends Attention {
  const BudgetAttention();
  @override
  String get key => 'budget';
}

/// A domain pending, paused, or in development mode.
final class ZoneAttention extends Attention {
  const ZoneAttention(this.zone);
  final Zone zone;
  @override
  String get key => 'zone:${zone.id}';
}

/// A Pages project whose latest deployment failed.
final class PagesAttention extends Attention {
  const PagesAttention(this.project);
  final PagesProjectInfo project;
  @override
  String get key => 'pages:${project.name}';
}

/// A registration about to lapse.
final class RegistrarAttention extends Attention {
  const RegistrarAttention(this.domain);
  final RegistrarDomainInfo domain;
  @override
  String get key => 'registrar:${domain.name}';
}

/// A token that reaches the account expires within 14 days.
final class TokenAttention extends Attention {
  const TokenAttention(this.token);
  final Credential token;
  @override
  String get key => 'token:${token.id}';
}

/// The account's mail service runs an older Worker than the app bundles.
final class MailUpdateAttention extends Attention {
  const MailUpdateAttention(this.service, this.bundled);
  final MailService service;
  final String bundled;
  @override
  String get key => 'mailworker';
}

/// A mail domain's routing is off or broken: mail stops arriving silently.
final class RoutingAttention extends Attention {
  const RoutingAttention(this.zone, this.overview);
  final Zone zone;
  final RoutingOverview overview;
  @override
  String get key => 'routing:${zone.id}';
}

/// A sending domain delivers below Cloudflare's 95% target.
final class DeliveryAttention extends Attention {
  const DeliveryAttention(this.zone, this.delivery);
  final Zone zone;
  final DomainDelivery delivery;
  @override
  String get key => 'delivery:${zone.id}';
}

bool zoneNeedsYou(Zone z) =>
    z.status == ZoneStatus.pending || z.status == ZoneStatus.initializing || z.paused || z.developmentMode > 0;

bool pagesNeedsYou(PagesProjectInfo p) => p.latestDeployment?.status == DeployStatus.failed;

bool tokenExpiresSoon(Credential c, {DateTime? now}) =>
    c.expiresOn != null && c.expiresOn!.difference(now ?? DateTime.now()).inDays <= 14;

bool routingNeedsYou(RoutingOverview o) => o.settings.health != RoutingHealth.ready;

/// Everything cocked out of line in one account, most urgent first. Today
/// renders it, the tab badge counts it, the account switcher shows it for
/// every account. Routing and delivery need per-zone and GraphQL reads, so
/// they're checked for the account on screen only.
final needsYouProvider = Provider.family<List<Attention>, String>((ref, accountId) {
  final onScreen = ref.watch(activeAccountProvider)?.id == accountId;
  final zones = ref.watch(zonesProvider(accountId)).value?.data ?? const <Zone>[];
  final compute = ref.watch(computeOverviewProvider(accountId)).value?.data;
  final service = ref.watch(mailServiceProvider(accountId));
  final bundled = ref.watch(workerBundleProvider).value?.version;
  final tokens = [
    for (final t in ref.watch(tokensProvider))
      if (t.reaches(accountId) && tokenExpiresSoon(t)) t,
  ];

  return [
    if (ref.watch(budgetSummaryProvider(accountId).select((b) => b.needsAttention))) const BudgetAttention(),
    for (final z in zones.where(zoneNeedsYou)) ZoneAttention(z),
    if (compute != null) ...[
      for (final p in compute.pages.where(pagesNeedsYou)) PagesAttention(p),
      for (final r in compute.registrar.where((r) => r.needsAttention())) RegistrarAttention(r),
    ],
    for (final t in tokens) TokenAttention(t),
    if (service != null && bundled != null && compareVersions(bundled, service.workerVersion) > 0)
      MailUpdateAttention(service, bundled),
    if (onScreen && service != null) ...[
      for (final z in zones.where((z) => service.domains.contains(z.name)))
        if (ref.watch(routingOverviewProvider(z.id)).value?.data case final o? when routingNeedsYou(o))
          RoutingAttention(z, o),
      for (final d in ref.watch(deliveryWatchProvider(accountId)).value?.data ?? const <DomainDelivery>[])
        if (d.low)
          if (zones.where((z) => z.id == d.zoneId).firstOrNull case final z?) DeliveryAttention(z, d),
    ],
  ];
});
