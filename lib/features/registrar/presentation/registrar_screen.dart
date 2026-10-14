import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../compute/data/compute_providers.dart';

String registrationStatusLabel(BuildContext context, RegistrationStatus s) {
  final l = context.l10n;
  return switch (s) {
    RegistrationStatus.active => l.registrarStatusActive,
    RegistrationStatus.registrationPending => l.registrarStatusRegistering,
    RegistrationStatus.transferPending => l.registrarStatusTransferring,
    RegistrationStatus.expired => l.registrarStatusExpired,
    RegistrationStatus.suspended => l.registrarStatusSuspended,
    RegistrationStatus.redemptionPeriod => l.registrarStatusRedemption,
    RegistrationStatus.pendingDelete => l.registrarStatusPendingDelete,
    RegistrationStatus.unknown => l.registrarStatusUnknown,
  };
}

/// Why a registration is cocked, or null when it's in line.
String? registrarAttentionReason(BuildContext context, RegistrarDomainInfo d, {DateTime? now}) {
  final l = context.l10n;
  if (d.status.critical) return l.registrarReasonStatus(registrationStatusLabel(context, d.status));
  if (!d.needsAttention(now: now)) return null;
  final days = d.daysLeft(now: now) ?? 0;
  return days <= 0 ? l.registrarReasonToday : l.registrarReasonExpiring(days);
}

/// A registered domain on the board: buff holder (it's a domain), cocked when
/// it will lapse without the user acting.
class RegistrarStrip extends StatelessWidget {
  const RegistrarStrip({super.key, required this.domain});
  final RegistrarDomainInfo domain;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final d = domain;
    final reason = registrarAttentionReason(context, d);
    final expires = d.expiresAt == null ? '—' : DateFormat.yMMMd().format(d.expiresAt!.toLocal());
    final renew = d.autoRenew ? l.registrarAutoRenewOn : l.registrarAutoRenewOff;
    return Strip(
      title: d.name,
      family: Family.domains,
      cocked: reason != null,
      reason: reason,
      semanticLabel: [d.name, l.registrarExpiresSemantics(expires), renew, ?reason].join(', '),
      fields: [
        StripField(l.registrarFieldExpires, expires, color: reason != null ? c.attention : null),
        StripField(l.registrarFieldAutoRenew, renew, color: d.autoRenew ? c.ok : c.inkMuted, flex: 2),
        StripField(l.registrarFieldLock, d.locked ? l.registrarLocked : l.registrarUnlocked, flex: 2),
      ],
    );
  }
}

/// Domains the account registered with Cloudflare Registrar, soonest expiry
/// first.
class RegistrarScreen extends ConsumerWidget {
  const RegistrarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final account = ref.watch(activeAccountProvider)!.id;
    final async = ref.watch(computeOverviewProvider(account));
    final synced = async.value;
    return EpPage(
      title: l.registrarTitle,
      largeTitle: false,
      previousPageTitle: l.tabCompute,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => ref.read(computeOverviewProvider(account).notifier).refresh(),
      slivers: async.when(
        loading: () => const [EpFill(child: EpLoading())],
        error: (e, _) => [
          EpFill(
            child: EpErrorView(
              error: e,
              permission: Capability.registrar.permission,
              onRetry: () => ref.invalidate(computeOverviewProvider(account)),
            ),
          ),
        ],
        data: (s) => _body(context, s.data),
      ),
    );
  }

  List<Widget> _body(BuildContext context, ComputeOverview o) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final gap = o.gapFor(ComputeKind.registrar);
    final domains = o.registrar;

    if (domains.isEmpty) {
      final message = switch (gap?.reason) {
        GapReason.userToken => EpMessage(
            icon: EpIcon.key,
            title: l.registrarAccountTokenTitle,
            message: l.registrarAccountTokenMessage(Capability.registrar.permission),
          ),
        GapReason.permission => EpMessage(
            icon: EpIcon.key,
            title: l.registrarPermissionTitle,
            message: l.registrarPermissionMessage(Capability.registrar.permission),
          ),
        GapReason.failed => EpMessage(icon: EpIcon.warning, title: l.registrarFailedTitle, message: gap!.message),
        null => EpMessage(icon: EpIcon.calendar, title: l.registrarEmptyTitle, message: l.registrarEmptyMessage),
      };
      return [EpFill(child: message)];
    }

    final attention = domains.where((d) => d.needsAttention()).toList();
    final inLine = domains.where((d) => !d.needsAttention()).toList();
    return [
      SliverList.list(children: [
        if (attention.isNotEmpty)
          StripBay(
            title: l.registrarBayAttention,
            count: attention.length,
            children: [for (final d in attention) RegistrarStrip(key: ValueKey('a-${d.name}'), domain: d)],
          ),
        StripBay(
          title: l.registrarBayAll,
          count: inLine.length,
          empty: Text(l.registrarAllAttention, style: TextStyle(color: c.inkMuted)),
          children: [for (final d in inLine) RegistrarStrip(key: ValueKey('r-${d.name}'), domain: d)],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg + 4, EpSpace.lg, EpSpace.lg + 4, 0),
          child: Text(l.registrarFooter, style: TextStyle(color: c.inkMuted, fontSize: 13)),
        ),
      ]),
    ];
  }
}
