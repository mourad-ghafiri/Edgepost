import 'package:flutter/material.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';

String capabilityLabel(BuildContext context, Capability c) {
  final l = context.l10n;
  return switch (c) {
    Capability.zones => l.capZones,
    Capability.dns => l.capDns,
    Capability.zoneSettings => l.capZoneSettings,
    Capability.cachePurge => l.capCachePurge,
    Capability.analytics => l.capAnalytics,
    Capability.emailRouting => l.capEmailRouting,
    Capability.emailAddresses => l.capEmailAddresses,
    Capability.dmarc => l.capDmarc,
    Capability.workers => l.capWorkers,
    Capability.workerRoutes => l.capWorkerRoutes,
    Capability.pages => l.capPages,
    Capability.d1 => l.capD1,
    Capability.r2 => l.capR2,
    Capability.registrar => l.capRegistrar,
    Capability.billing => l.capBilling,
  };
}

/// What a token can do, one row per capability, each in one of four states:
/// available ✓, missing ✗ (with the exact dashboard permission), turn on in
/// the dashboard (product not enabled), or not confirmed yet.
class CapabilityList extends StatelessWidget {
  const CapabilityList({super.key, required this.credential, required this.accountId, this.only, this.header, this.footer});

  final Credential credential;

  /// Permissions are checked per account a token reaches.
  final String accountId;

  /// Show just these capabilities (e.g. what mail setup needs).
  final List<Capability>? only;
  final String? header;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final caps = only ?? Capability.values;
    return EpSection(
      header: header,
      footer: footer,
      children: [
        for (final cap in caps)
          Builder(builder: (context) {
            final state = credential.stateOf(accountId, cap);
            final (icon, color, label) = switch (state) {
              CapState.granted => (EpIcon.checkCircle, c.ok, l.capabilityAvailable),
              CapState.denied => (EpIcon.close, c.attention, l.capabilityMissing),
              CapState.notEnabled => (EpIcon.warning, c.caution, l.capabilityNotEnabled),
              CapState.unknown => (EpIcon.info, c.inkMuted, l.capabilityUnknown),
            };
            final detail = switch (state) {
              CapState.granted => null,
              CapState.denied => l.capDeniedHint(cap.permission),
              CapState.notEnabled => cap == Capability.r2 ? l.capR2NotEnabledHint : l.capabilityNotEnabled,
              CapState.unknown => l.capabilityUnknown,
            };
            return MergeSemantics(
              child: EpTile(
                leading: EpIconView(icon, color: color, semanticLabel: label),
                title: Text(capabilityLabel(context, cap)),
                subtitle: detail == null
                    ? null
                    : Text(detail, style: TextStyle(color: state == CapState.denied ? c.attention : c.inkMuted, fontSize: 13)),
              ),
            );
          }),
      ],
    );
  }
}

/// Static list of the recommended token permissions (shown before adding).
class RecommendedPermissions extends StatelessWidget {
  const RecommendedPermissions({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    return EpSection(
      header: l.addTokenRecommended,
      footer: l.addTokenRecommendedHelp,
      children: [
        for (final cap in Capability.values)
          EpTile(
            title: Text(capabilityLabel(context, cap)),
            subtitle: Text(cap.permission, style: EpType.data(context, size: 12, color: c.inkMuted)),
          ),
      ],
    );
  }
}
