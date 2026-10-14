import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../data/email_routing_models.dart';

/// "Ready" / "Off" / "Misconfigured" / "Unlocked".
String routingHealthLabel(BuildContext context, RoutingHealth h) {
  final l = context.l10n;
  return switch (h) {
    RoutingHealth.ready => l.routingStatusReady,
    RoutingHealth.off => l.routingStatusOff,
    RoutingHealth.misconfigured => l.routingStatusMisconfigured,
    RoutingHealth.unlocked => l.routingStatusUnlocked,
  };
}

/// Why the routing strip is cocked, or null when it sits in line.
String? routingAttentionReason(BuildContext context, RoutingOverview o, {int unverifiedRules = 0}) {
  final l = context.l10n;
  return switch (o.settings.health) {
    RoutingHealth.off => l.routingReasonOff,
    RoutingHealth.misconfigured => l.routingReasonMisconfigured,
    RoutingHealth.unlocked => l.routingReasonUnlocked,
    RoutingHealth.ready => unverifiedRules > 0 ? l.routingReasonUnverified(unverifiedRules) : null,
  };
}

/// Short catch-all summary for the strip field.
String catchAllShortLabel(BuildContext context, RoutingRule? rule) {
  final l = context.l10n;
  final a = rule?.action;
  if (rule == null || !rule.enabled || a == null) return l.routingCatchAllOffShort;
  return switch (a.type) {
    RuleActionType.forward => l.routingActionForward,
    RuleActionType.worker => a.isMailbox ? l.routingActionMailbox : l.routingActionWorker,
    RuleActionType.drop => l.routingActionDrop,
    RuleActionType.unknown => l.routingActionUnknown,
  };
}

/// Where an action delivers, for list rows: an address, "Edgepost mailbox",
/// "Worker name" or "Dropped".
String actionDestinationLabel(BuildContext context, RuleAction? a) {
  final l = context.l10n;
  if (a == null) return l.routingActionUnknown;
  return switch (a.type) {
    RuleActionType.forward => a.target ?? l.routingActionUnknown,
    RuleActionType.worker => a.isMailbox ? l.routingDestMailbox : l.routingDestWorker(a.target ?? ''),
    RuleActionType.drop => l.routingDestDropped,
    RuleActionType.unknown => l.routingActionUnknown,
  };
}

/// Rules forwarding to a destination that isn't verified yet. Empty when the
/// address list isn't known.
Set<String> unverifiedDestinations(List<DestinationAddress>? addresses) => {
      for (final a in addresses ?? const <DestinationAddress>[])
        if (!a.isVerified) a.email.toLowerCase(),
    };

bool forwardsToUnverified(RoutingRule r, Set<String> unverified) {
  final a = r.action;
  return a != null && a.type == RuleActionType.forward && unverified.contains(a.target?.toLowerCase());
}

/// The domain's routing on the board: sky holder, callsign = domain.
class RoutingStatusStrip extends StatelessWidget {
  const RoutingStatusStrip({super.key, required this.domain, required this.overview, this.unverifiedRules = 0});

  final String domain;
  final RoutingOverview overview;
  final int unverifiedRules;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final health = overview.settings.health;
    final status = routingHealthLabel(context, health);
    final reason = routingAttentionReason(context, overview, unverifiedRules: unverifiedRules);
    final catchAll = catchAllShortLabel(context, overview.catchAll);
    return Strip(
      title: domain,
      family: Family.mail,
      caption: l.routingStripCaption,
      cocked: reason != null,
      reason: reason,
      semanticLabel: [
        domain,
        l.routingStripCaption,
        '${l.routingFieldStatus}: $status',
        '${l.routingFieldRules}: ${overview.rules.length}',
        '${l.routingFieldCatchAll}: $catchAll',
        ?reason,
      ].join(', '),
      fields: [
        StripField(l.routingFieldStatus, status, color: health == RoutingHealth.ready ? c.ok : c.attention),
        StripField(l.routingFieldRules, '${overview.rules.length}', flex: 2),
        StripField(l.routingFieldCatchAll, catchAll),
      ],
    );
  }
}

/// A required DNS record, copyable.
class RoutingDnsRecordTile extends StatelessWidget {
  const RoutingDnsRecordTile({super.key, required this.record});
  final RoutingDnsRecord record;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final details = [
      record.content,
      if (record.priority != null) l.routingDnsPriority(record.priority!),
    ].join('\n');
    return Semantics(
      label: '${record.type} ${record.name} ${record.content}',
      hint: l.routingCopyRecordHint,
      excludeSemantics: true,
      child: EpTile(
        title: Text('${record.type}  ${record.name}', maxLines: 2, style: EpType.data(context, size: 14)),
        subtitle: Text(details, maxLines: 4, style: EpType.data(context, size: 13, color: c.inkMuted)),
        trailing: EpIconView(EpIcon.copy, color: c.tint, size: 20),
        onTap: () => copyWithToast(context, record.content),
      ),
    );
  }
}

/// 44 pt / 48 dp copy target.
class CopyIconButton extends StatelessWidget {
  const CopyIconButton({super.key, required this.text, required this.label});
  final String text;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    if (isCupertino(context)) {
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: () => copyWithToast(context, text),
          child: Icon(EpIcon.copy.cupertino, size: 20, color: c.tint),
        ),
      );
    }
    return IconButton(
      tooltip: label,
      onPressed: () => copyWithToast(context, text),
      icon: Icon(EpIcon.copy.material, color: c.tint),
    );
  }
}

/// Small grey paragraph between sections (explanations, not footers).
class RoutingNote extends StatelessWidget {
  const RoutingNote(this.text, {super.key, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg + 4, EpSpace.sm, EpSpace.lg + 4, 0),
        child: Text(text, style: TextStyle(fontSize: 13, height: 1.35, color: color ?? EpColors.of(context).inkMuted)),
      );
}
