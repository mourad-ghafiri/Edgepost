import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../data/zones_providers.dart';
import 'zone_strip.dart';

/// Everything about one domain, one tap away.
class ZoneHubScreen extends ConsumerWidget {
  const ZoneHubScreen({super.key, required this.zoneId});
  final String zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final account = ref.watch(activeAccountProvider)!.id;
    final zone = ref.watch(zoneByIdProvider(zoneId));
    final pinned = ref.watch(pinnedZonesProvider(account)).value?.contains(zoneId) ?? false;
    if (zone == null) {
      return EpPage(
        title: l.tabDomains,
        largeTitle: false,
        splitRoot: true,
        slivers: const [EpFill(child: EpLoading())],
      );
    }
    final c = EpColors.of(context);
    final date = DateFormat.yMMMd();
    final base = '/domains/$zoneId';

    return EpPage(
      title: zone.name,
      largeTitle: false,
      splitRoot: true,
      onRefresh: () => ref.read(zonesProvider(account).notifier).refresh(),
      actions: [
        EpAction(
          icon: pinned ? EpIcon.pinFill : EpIcon.pin,
          label: pinned ? l.zoneHubUnpin : l.zoneHubPin,
          onPressed: () => ref.read(pinnedZonesProvider(account).notifier).toggle(zoneId),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
            child: ZoneStrip(zone: zone, pinned: pinned),
          ),
        ),
        if (zone.status == ZoneStatus.pending && zone.nameServers.isNotEmpty)
          SliverToBoxAdapter(
            child: EpSection(
              header: l.zoneHubNameservers,
              footer: l.zoneHubNameserversHelp,
              children: [
                for (final ns in zone.nameServers)
                  EpTile(
                    title: Text(ns, style: EpType.data(context, size: 15)),
                    trailing: EpIconView(EpIcon.copy, color: c.tint, semanticLabel: l.actionCopy),
                    onTap: () => copyWithToast(context, ns),
                  ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.zoneHubManage,
            children: [
              _link(context, EpIcon.dns, l.zoneHubDns, '$base/dns'),
              _link(context, EpIcon.shield, l.zoneHubControls, '$base/controls'),
              _link(context, EpIcon.chart, l.zoneHubAnalytics, '$base/analytics'),
              _link(context, EpIcon.mail, l.zoneHubEmail, '$base/email'),
              _link(context, EpIcon.inbox, l.zoneHubMailbox, '/mail?domain=${Uri.encodeComponent(zone.name)}'),
              _link(context, EpIcon.compute, l.zoneHubWorkers, '$base/routes'),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.zoneHubDetails,
            children: [
              if (zone.createdOn != null)
                EpTile(title: Text(l.zoneHubCreated), additionalInfo: Text(date.format(zone.createdOn!.toLocal()))),
              if (zone.activatedOn != null)
                EpTile(title: Text(l.zoneHubActivated), additionalInfo: Text(date.format(zone.activatedOn!.toLocal()))),
              if (zone.originalRegistrar != null)
                EpTile(title: Text(l.zoneHubRegistrar), additionalInfo: Text(zone.originalRegistrar!)),
              EpTile(
                leading: EpIconView(EpIcon.external, color: c.tint),
                title: Text(l.zoneHubOpenDashboard),
                onTap: () => launchUrl(
                  Uri.parse('https://dash.cloudflare.com/${zone.account.id}/${zone.name}'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _link(BuildContext context, EpIcon icon, String label, String path) => EpTile(
        leading: EpIconView(icon, color: EpColors.of(context).tint),
        title: Text(label),
        onTap: () => context.push(path),
      );
}
