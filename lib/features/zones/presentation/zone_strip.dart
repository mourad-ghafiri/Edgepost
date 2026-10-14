import 'package:flutter/material.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';

/// Why a zone needs the user, from the zone record alone (no extra calls).
/// Deeper checks (SSL off, routing misconfigured…) are added by Today.
String? zoneAttentionReason(BuildContext context, Zone z) {
  final l = context.l10n;
  if (z.status == ZoneStatus.pending || z.status == ZoneStatus.initializing) return l.zoneReasonPending;
  if (z.paused) return l.zoneReasonPaused;
  if (z.developmentMode > 0) return l.zoneReasonDevMode((z.developmentMode / 60).ceil());
  return null;
}

String zoneStatusLabel(BuildContext context, Zone z) {
  final l = context.l10n;
  if (z.paused) return l.zoneStatusPaused;
  return switch (z.status) {
    ZoneStatus.active => l.zoneStatusActive,
    ZoneStatus.pending || ZoneStatus.initializing => l.zoneStatusPending,
    ZoneStatus.moved => l.zoneStatusMoved,
    _ => l.zoneStatusOther,
  };
}

/// A domain's card: its name, status and plan, plus any extra fields.
class ZoneStrip extends StatelessWidget {
  const ZoneStrip({
    super.key,
    required this.zone,
    this.onTap,
    this.reason,
    this.pinned = false,
    this.selected = false,
    this.extraFields = const [],
  });

  final Zone zone;
  final VoidCallback? onTap;

  /// Overrides the computed reason (Today passes deeper findings).
  final String? reason;
  final bool pinned;

  /// Open beside the list (an iPad split).
  final bool selected;
  final List<StripField> extraFields;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final why = reason ?? zoneAttentionReason(context, zone);
    final status = zoneStatusLabel(context, zone);
    // Waiting on nameservers or paused is caution; red is for gone (moved,
    // deleted, deactivated), and the card's reason line says what to do.
    final statusColor = switch (zone.status) {
      ZoneStatus.active when !zone.paused => c.ok,
      ZoneStatus.active || ZoneStatus.pending || ZoneStatus.initializing => c.caution,
      ZoneStatus.unknown => c.inkMuted,
      _ => c.attention,
    };
    return Strip(
      title: zone.name,
      family: Family.domains,
      cocked: why != null,
      reason: why,
      selected: selected,
      onTap: onTap,
      leading: pinned ? const FamilyGlyph(family: Family.domains, icon: EpIcon.pinFill) : null,
      semanticLabel: [zone.name, status, ?why].join(', '),
      fields: [
        StripField(l.zoneFieldStatus, status, color: statusColor),
        StripField(l.zoneFieldPlan, _shortPlan(zone.planName)),
        ...extraFields,
      ],
    );
  }

  static String _shortPlan(String? plan) {
    if (plan == null || plan.isEmpty) return '—';
    return plan.replaceAll(RegExp(r'\s*(Website|Plan)\s*', caseSensitive: false), ' ').trim();
  }
}
