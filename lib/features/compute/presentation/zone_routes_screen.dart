import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../zones/data/zones_providers.dart';
import '../data/compute_providers.dart';
import 'compute_screen.dart';

/// Workers that answer on one domain: zone routes and Workers custom domains.
class ZoneWorkerRoutesScreen extends ConsumerWidget {
  const ZoneWorkerRoutesScreen({super.key, required this.zoneId});
  final String zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final zone = ref.watch(zoneByIdProvider(zoneId));
    final async = ref.watch(zoneComputeProvider(zoneId));
    final synced = async.value;
    return EpPage(
      title: l.computeZoneRoutesTitle,
      largeTitle: false,
      previousPageTitle: zone?.name,
      subtitle: synced == null || zone == null ? null : SyncLine(synced: synced),
      onRefresh: () => ref.read(zoneComputeProvider(zoneId).notifier).refresh(),
      slivers: zone == null
          ? const [EpFill(child: EpLoading())]
          : async.when(
              loading: () => const [EpFill(child: EpLoading())],
              error: (e, _) => [
                EpFill(
                  child: EpErrorView(
                    error: e,
                    permission: Capability.workerRoutes.permission,
                    onRetry: () => ref.invalidate(zoneComputeProvider(zoneId)),
                  ),
                ),
              ],
              data: (s) => _body(context, zone, s.data),
            ),
    );
  }

  List<Widget> _body(BuildContext context, Zone zone, ZoneCompute d) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final routes = d.routes.value;
    final domains = d.domains.value;
    if (routes != null && domains != null && routes.isEmpty && domains.isEmpty) {
      return [
        EpFill(
          child: EpMessage(icon: EpIcon.compute, title: l.computeZoneRoutesEmptyTitle(zone.name), message: l.computeZoneRoutesEmptyMessage),
        ),
      ];
    }

    void open(String script) => context.go(workerPath(script));

    Widget errorRow(Object e, Capability cap) => EpTile(
          leading: EpIconView(e is CfApiException && e.isPermissionDenied ? EpIcon.key : EpIcon.warning, color: c.caution),
          title: Text(describeError(context, e, permission: cap.permission)),
        );

    return [
      SliverList.list(children: [
        EpSection(
          header: l.computeZoneRoutesSectionRoutes,
          footer: l.computeZoneRoutesRoutesFooter,
          children: [
            if (routes == null)
              d.routes.error != null ? errorRow(d.routes.error!, Capability.workerRoutes) : EpTile(title: Text(l.loading))
            else if (routes.isEmpty)
              EpTile(title: Text(l.computeZoneRoutesNoRoutes, style: TextStyle(color: c.inkMuted)))
            else
              for (final r in routes)
                EpTile(
                  title: Text(r.pattern, style: EpType.data(context, size: 15)),
                  subtitle: Text(r.script == null ? l.computeZoneRoutesNoScript : l.computeZoneRoutesRunsScript(r.script!)),
                  onTap: r.script == null ? null : () => open(r.script!),
                ),
          ],
        ),
        EpSection(
          header: l.computeZoneRoutesSectionDomains,
          footer: l.computeZoneRoutesDomainsFooter,
          children: [
            if (domains == null)
              d.domains.error != null ? errorRow(d.domains.error!, Capability.workers) : EpTile(title: Text(l.loading))
            else if (domains.isEmpty)
              EpTile(title: Text(l.computeZoneRoutesNoDomains, style: TextStyle(color: c.inkMuted)))
            else
              for (final dom in domains)
                EpTile(
                  title: Text(dom.hostname, style: EpType.data(context, size: 15)),
                  subtitle: Text(l.computeZoneRoutesRunsScript(dom.service)),
                  onTap: () => open(dom.service),
                ),
          ],
        ),
      ]),
    ];
  }
}
