import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../zones/data/zones_providers.dart';
import '../data/dns_providers.dart';
import '../data/dns_record.dart';
import '../data/mail_check.dart';
import 'dns_widgets.dart';

/// Read-only report on MX, SPF, DMARC and DKIM, built from the zone's records.
class DnsMailCheckScreen extends ConsumerWidget {
  const DnsMailCheckScreen({super.key, required this.zoneId});
  final String zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final zone = ref.watch(zoneByIdProvider(zoneId));
    final async = ref.watch(dnsRecordsProvider(zoneId));
    final synced = async.value;
    return EpPage(
      title: l.dnsMailTitle,
      largeTitle: false,
      previousPageTitle: l.dnsTitle,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: zone == null ? null : () => ref.read(dnsRecordsProvider(zoneId).notifier).refresh(),
      slivers: zone == null
          ? const [EpFill(child: EpLoading())]
          : dnsAccessDenied(ref, zone)
          ? [EpFill(child: dnsPermissionView(ref, zone))]
          : async.when(
              loading: () => const [EpFill(child: EpLoading())],
              error: (e, _) => [
                EpFill(
                  child: EpErrorView(
                    error: e,
                    permission: Capability.dns.permission,
                    onRetry: () => ref.invalidate(dnsRecordsProvider(zoneId)),
                  ),
                ),
              ],
              data: (s) => _report(context, zone, s.data),
            ),
    );
  }

  List<Widget> _report(BuildContext context, Zone zone, List<DnsRecord> records) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final items = checkMailRecords(records, zone.name);
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.sm, EpSpace.lg, 0),
          child: Text(l.dnsMailIntro(zone.name), style: TextStyle(color: c.inkMuted, height: 1.4)),
        ),
      ),
      for (final item in items)
        SliverToBoxAdapter(
          child: EpSection(
            header: switch (item.kind) {
              MailCheckKind.mx => l.dnsMailMx,
              MailCheckKind.spf => l.dnsMailSpf,
              MailCheckKind.dmarc => l.dnsMailDmarc,
              MailCheckKind.dkim => l.dnsMailDkim,
            },
            footer: _advice(context, item, zone),
            children: [
              _statusTile(context, item),
              for (final r in item.records)
                EpTile(
                  title: Text(
                    item.kind == MailCheckKind.mx && r.priority != null
                        ? '${r.priority}  ${r.content}'
                        : DnsNames.relative(r.name, zone.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: EpType.data(context, size: 14),
                  ),
                  subtitle: item.kind == MailCheckKind.mx
                      ? null
                      : Text(
                          txtValue(r.content),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: EpType.data(context, size: 12, color: c.inkMuted),
                        ),
                  onTap: () => context.push('/domains/$zoneId/dns/${r.id}'),
                ),
              if (item.finding == MailCheckFinding.dmarcMissing)
                EpTile(
                  leading: EpIconView(EpIcon.add, color: c.tint),
                  title: Text(l.dnsMailAddDmarc),
                  onTap: () => context.push(
                    Uri(
                      path: '/domains/$zoneId/dns/new',
                      queryParameters: {'type': 'TXT', 'name': '_dmarc', 'content': 'v=DMARC1; p=none'},
                    ).toString(),
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _statusTile(BuildContext context, MailCheckItem item) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final (icon, color, label) = switch (item.status) {
      MailCheckStatus.ok => (EpIcon.checkCircle, c.ok, l.dnsMailStatusOk),
      MailCheckStatus.warn => (EpIcon.warning, c.caution, l.dnsMailStatusWarn),
      MailCheckStatus.missing => (EpIcon.warning, c.attention, l.dnsMailStatusMissing),
    };
    return EpTile(
      leading: EpIconView(icon, color: color),
      title: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  String _advice(BuildContext context, MailCheckItem item, Zone zone) {
    final l = context.l10n;
    final z = zone.name;
    return switch (item.finding) {
      MailCheckFinding.mxOk => l.dnsMailMxOk(z),
      MailCheckFinding.mxEmailRouting => l.dnsMailMxRouting(z),
      MailCheckFinding.mxNull => l.dnsMailMxNull(z),
      MailCheckFinding.mxMissing => l.dnsMailMxMissing(z),
      MailCheckFinding.spfOk => l.dnsMailSpfOk(z),
      MailCheckFinding.spfMultiple => l.dnsMailSpfMultiple,
      MailCheckFinding.spfPassAll => l.dnsMailSpfPassAll(z),
      MailCheckFinding.spfMissing => l.dnsMailSpfMissing(z),
      MailCheckFinding.dmarcOk => l.dnsMailDmarcOk,
      MailCheckFinding.dmarcMonitorOnly => l.dnsMailDmarcNone,
      MailCheckFinding.dmarcMultiple => l.dnsMailDmarcMultiple,
      MailCheckFinding.dmarcMissing => l.dnsMailDmarcMissing(z),
      MailCheckFinding.dkimOk => l.dnsMailDkimOk(item.records.length),
      MailCheckFinding.dkimMissing => l.dnsMailDkimMissing(z),
    };
  }
}
