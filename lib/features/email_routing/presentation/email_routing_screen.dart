import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../zones/data/zones_providers.dart';
import '../data/email_routing_models.dart';
import '../data/email_routing_providers.dart';
import 'add_address_dialog.dart';
import 'mail_auth_section.dart';
import 'routing_widgets.dart';

/// Email Routing for one domain: status strip, address rules, catch-all,
/// destinations, mail authentication health and the routing DNS records.
class EmailRoutingScreen extends ConsumerStatefulWidget {
  const EmailRoutingScreen({super.key, required this.zoneId});
  final String zoneId;

  @override
  ConsumerState<EmailRoutingScreen> createState() => _EmailRoutingScreenState();
}

enum _CatchAllChoice { off, forward, mailbox, drop }

class _EmailRoutingScreenState extends ConsumerState<EmailRoutingScreen> {
  bool _busy = false;

  String get _base => '/domains/${widget.zoneId}/email';

  RoutingOverviewNotifier get _notifier => ref.read(routingOverviewProvider(widget.zoneId).notifier);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final zone = ref.watch(zoneByIdProvider(widget.zoneId));
    if (zone == null) {
      return EpPage(title: l.routingTitle, largeTitle: false, slivers: const [EpFill(child: EpLoading())]);
    }
    final async = ref.watch(routingOverviewProvider(widget.zoneId));
    final account = zone.account.id;
    final addressesAsync = ref.watch(destinationAddressesProvider(account));
    final synced = async.value;
    final enabled = synced?.data.settings.enabled ?? false;

    return EpPage(
      title: l.routingTitle,
      largeTitle: false,
      previousPageTitle: zone.name,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => Future.wait([
        ref.read(routingOverviewProvider(widget.zoneId).notifier).refresh(),
        ref.read(destinationAddressesProvider(account).notifier).refresh(),
        ref.read(mailAuthProvider(widget.zoneId).notifier).refresh(),
      ]),
      primaryAction: enabled
          ? EpAction(icon: EpIcon.add, label: l.routingAddRule, onPressed: () => context.push('$_base/rule/new'))
          : null,
      slivers: async.when(
        loading: () => [const EpFill(child: EpLoading())],
        error: (e, _) => [
          EpFill(
            child: EpErrorView(
              error: e,
              permission: Capability.emailRouting.permission,
              onRetry: () => ref.invalidate(routingOverviewProvider(widget.zoneId)),
            ),
          ),
        ],
        data: (s) => [
          SliverList.list(children: _body(context, zone, s.data, addressesAsync)),
        ],
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    Zone zone,
    RoutingOverview o,
    AsyncValue<Synced<List<DestinationAddress>>> addressesAsync,
  ) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final addresses = addressesAsync.value?.data;
    final unverified = unverifiedDestinations(addresses);
    final unverifiedRules = o.rules.where((r) => r.enabled && forwardsToUnverified(r, unverified)).length;
    final health = o.settings.health;
    final pending = addresses?.where((a) => !a.isVerified).length ?? 0;

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
        child: RoutingStatusStrip(domain: zone.name, overview: o, unverifiedRules: unverifiedRules),
      ),

      // Turn on / repair.
      if (health == RoutingHealth.off) ...[
        EpSection(
          header: l.routingEnableHeader,
          footer: o.dnsRecords.isEmpty ? l.routingEnableExplain(zone.name) : l.routingEnableRecordsFooter,
          children: [for (final r in o.dnsRecords) RoutingDnsRecordTile(record: r)],
        ),
        if (o.dnsRecords.isNotEmpty) RoutingNote(l.routingEnableExplain(zone.name)),
        _actionButton(l.routingEnableAction, () => _enable(zone, o)),
      ] else if (health == RoutingHealth.misconfigured) ...[
        RoutingNote(l.routingMisconfiguredExplain),
        _actionButton(l.routingRepairAction, () => _repair(zone)),
      ] else if (health == RoutingHealth.unlocked) ...[
        RoutingNote(l.routingUnlockedExplain),
        _actionButton(l.routingLockAction, () => _repair(zone)),
      ],

      // Address rules.
      EpSection(
        header: l.routingRulesHeader,
        footer: [
          l.routingRulesCount(o.rules.length, kMaxRoutingRules),
          if (!o.settings.enabled) l.routingRulesOffFooter,
        ].join(' '),
        children: [
          if (o.rules.isEmpty)
            EpTile(
              title: Text(l.routingRulesEmptyTitle),
              subtitle: Text(l.routingRulesEmptyMessage(zone.name), maxLines: 4),
            ),
          for (final r in o.rules)
            _RuleRow(
              key: ValueKey(r.id),
              rule: r,
              unverified: forwardsToUnverified(r, unverified),
              onEdit: () => context.push('$_base/rule/${r.id}'),
              onToggle: () => _toggle(r),
              onDelete: () => _delete(r),
            ),
          EpTile(
            leading: EpIconView(EpIcon.add, color: c.tint),
            title: Text(l.routingAddRule),
            onTap: () => context.push('$_base/rule/new'),
          ),
        ],
      ),

      // Catch-all.
      EpSection(
        header: l.routingCatchAllHeader,
        footer: l.routingCatchAllFooter(zone.name),
        children: [
          EpTile(
            title: Text(l.routingCatchAllTitle),
            subtitle: Text(_catchAllLine(context, o.catchAll), maxLines: 2),
            onTap: _busy ? null : () => _editCatchAll(zone, o, addresses),
          ),
        ],
      ),

      // Destination addresses.
      EpSection(
        children: [
          EpTile(
            leading: EpIconView(EpIcon.person, color: c.tint),
            title: Text(l.routingDestinationsLink),
            subtitle: pending > 0
                ? Text(l.routingPendingCount(pending), maxLines: 2, style: TextStyle(color: c.caution))
                : null,
            additionalInfo: pending == 0 && addresses != null ? Text('${addresses.length}') : null,
            onTap: () => context.push('$_base/addresses'),
          ),
        ],
      ),

      MailAuthSection(
        zoneId: widget.zoneId,
        domain: zone.name,
        routingEnabled: o.settings.enabled,
        requiredRecords: o.dnsRecords,
      ),

      // Records Email Routing manages.
      if (o.settings.enabled && o.dnsRecords.isNotEmpty)
        EpSection(
          header: l.routingDnsHeader,
          footer: o.settings.recordsLocked ? l.routingDnsLockedFooter : l.routingDnsUnlockedFooter,
          children: [
            for (final r in o.dnsRecords) RoutingDnsRecordTile(record: r),
            if (o.settings.recordsLocked)
              EpTile(
                leading: EpIconView(EpIcon.lock, color: c.tint),
                title: Text(l.routingUnlockAction),
                onTap: _busy ? null : _unlock,
              ),
          ],
        ),

      if (o.settings.enabled)
        EpSection(
          footer: l.routingDisableFooter,
          children: [
            EpTile(
              title: Text(l.routingDisableAction),
              destructive: true,
              onTap: _busy ? null : () => _disable(zone),
            ),
          ],
        ),
    ];
  }

  Widget _actionButton(String label, VoidCallback onPressed) => Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, EpSpace.sm),
        child: SizedBox(
          width: double.infinity,
          child: EpButton(label: label, busy: _busy, onPressed: onPressed),
        ),
      );

  String _catchAllLine(BuildContext context, RoutingRule? rule) {
    final l = context.l10n;
    if (rule == null || !rule.enabled) return l.routingCatchAllOffLine;
    return '${l.routingRuleArrow} ${actionDestinationLabel(context, rule.action)}';
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _run(Future<void> Function() action, {required String permission, String? success}) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted && success != null) showEpToast(context, success);
    } on Object catch (e) {
      if (mounted) showEpToast(context, describeError(context, e, permission: permission));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enable(Zone zone, RoutingOverview o) async {
    final l = context.l10n;
    final records = o.dnsRecords.map((r) => r.line).join('\n');
    final ok = await showEpConfirm(
      context,
      title: l.routingEnableConfirmTitle(zone.name),
      message: records.isEmpty
          ? l.routingEnableConfirmMessage(zone.name)
          : '${l.routingEnableConfirmMessage(zone.name)}\n\n$records',
      confirmLabel: l.routingEnableAction,
    );
    if (!ok || !mounted) return;
    // POST /email/routing/dns needs "Zone Settings Write" per the API reference.
    await _run(_notifier.enable, permission: Capability.zoneSettings.permission, success: l.routingEnabledToast);
  }

  Future<void> _repair(Zone zone) =>
      _run(_notifier.enable, permission: Capability.zoneSettings.permission, success: context.l10n.routingRepairedToast);

  Future<void> _unlock() async {
    final l = context.l10n;
    final ok = await showEpConfirm(
      context,
      title: l.routingUnlockConfirmTitle,
      message: l.routingUnlockConfirmMessage,
      confirmLabel: l.routingUnlockAction,
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(_notifier.unlock, permission: Capability.zoneSettings.permission);
  }

  Future<void> _disable(Zone zone) async {
    final l = context.l10n;
    final ok = await showEpTypedConfirm(
      context,
      title: l.routingDisableConfirmTitle,
      message: l.routingDisableConfirmMessage(zone.name),
      expected: zone.name,
      confirmLabel: l.routingDisableAction,
    );
    if (!ok || !mounted) return;
    await _run(_notifier.disable, permission: Capability.zoneSettings.permission, success: l.routingDisabledToast);
  }

  Future<void> _toggle(RoutingRule r) => _run(
        () => _notifier.setRuleEnabled(r, !r.enabled),
        permission: Capability.emailRouting.permission,
        success: r.enabled
            ? context.l10n.routingRuleTurnedOff(r.address ?? '')
            : context.l10n.routingRuleTurnedOn(r.address ?? ''),
      );

  Future<bool> _delete(RoutingRule r) async {
    final l = context.l10n;
    final ok = await showEpConfirm(
      context,
      title: l.routingRuleDeleteTitle(r.address ?? ''),
      message: l.routingRuleDeleteMessage,
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!ok || !mounted || r.id == null) return false;
    var done = false;
    await _run(() async {
      await _notifier.deleteRule(r.id!);
      done = true;
    }, permission: Capability.emailRouting.permission, success: l.routingRuleDeleted(r.address ?? ''));
    return done;
  }

  Future<void> _editCatchAll(Zone zone, RoutingOverview o, List<DestinationAddress>? addresses) async {
    final l = context.l10n;
    final choice = await showEpActionSheet<_CatchAllChoice>(
      context,
      title: l.routingCatchAllSheetTitle,
      message: l.routingCatchAllSheetMessage(zone.name),
      actions: [
        EpSheetAction(label: l.routingCatchAllOff, value: _CatchAllChoice.off, icon: EpIcon.pause),
        EpSheetAction(label: l.routingCatchAllForward, value: _CatchAllChoice.forward, icon: EpIcon.forward),
        EpSheetAction(label: l.routingDestMailbox, value: _CatchAllChoice.mailbox, icon: EpIcon.inbox),
        EpSheetAction(label: l.routingCatchAllDrop, value: _CatchAllChoice.drop, icon: EpIcon.trash, destructive: true),
      ],
    );
    if (choice == null || !mounted) return;
    final permission = Capability.emailRouting.permission;
    switch (choice) {
      case _CatchAllChoice.off:
        final keep = o.catchAll?.action ?? const RuleAction.drop();
        await _run(() => _notifier.setCatchAll(keep, enabled: false),
            permission: permission, success: l.routingCatchAllSaved);
      case _CatchAllChoice.mailbox:
        await _run(() => _notifier.setCatchAll(const RuleAction.worker(kMailWorkerName), enabled: true),
            permission: permission, success: l.routingCatchAllSaved);
      case _CatchAllChoice.drop:
        await _run(() => _notifier.setCatchAll(const RuleAction.drop(), enabled: true),
            permission: permission, success: l.routingCatchAllSaved);
      case _CatchAllChoice.forward:
        final dest = await _pickDestination(zone, addresses);
        if (dest == null || !mounted) return;
        await _run(() => _notifier.setCatchAll(RuleAction.forward(dest), enabled: true),
            permission: permission, success: l.routingCatchAllSaved);
    }
  }

  /// Verified and pending destinations, plus "Add address…".
  Future<String?> _pickDestination(Zone zone, List<DestinationAddress>? addresses) async {
    final l = context.l10n;
    const addSentinel = '\u0000add';
    final picked = await showEpActionSheet<String>(
      context,
      title: l.routingPickDestinationTitle,
      message: addresses == null ? l.routingPickDestinationUnavailable : null,
      actions: [
        for (final a in addresses ?? const <DestinationAddress>[])
          EpSheetAction(label: a.isVerified ? a.email : l.routingPendingAddress(a.email), value: a.email),
        EpSheetAction(label: l.routingAddAddressEllipsis, value: addSentinel, icon: EpIcon.add),
      ],
    );
    if (picked == addSentinel) {
      if (!mounted) return null;
      final created = await showAddDestinationDialog(context, zone.account.id);
      return created?.email;
    }
    return picked;
  }
}

/// An address rule: address in data type, where it goes underneath. Swipe
/// right to turn on/off, left to delete; long-press for all actions.
class _RuleRow extends StatelessWidget {
  const _RuleRow({
    super.key,
    required this.rule,
    required this.unverified,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final RoutingRule rule;
  final bool unverified;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final Future<bool> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final address = rule.address ?? '';
    final dest = actionDestinationLabel(context, rule.action);
    final isAddress = rule.action?.type == RuleActionType.forward;
    final notes = <String>[
      if (!rule.enabled) l.routingRuleOffNote,
      if (unverified) l.routingRuleUnverifiedNote,
      if (rule.managedByWrangler) l.routingRuleWranglerNote,
    ];
    final toggleLabel = rule.enabled ? l.routingRuleTurnOff : l.routingRuleTurnOn;

    final tile = EpTile(
      title: Text(
        address,
        maxLines: 2,
        style: TextStyle(fontSize: 15, color: rule.enabled ? c.ink : c.inkMuted),
      ),
      subtitle: Text.rich(
        TextSpan(children: [
          TextSpan(text: '${l.routingRuleArrow} '),
          TextSpan(text: dest, style: isAddress ? EpType.data(context, size: 13, color: c.inkMuted) : null),
          if (notes.isNotEmpty)
            TextSpan(
              text: '\n${notes.join(' ')}',
              style: TextStyle(color: unverified ? c.caution : c.inkMuted, fontWeight: FontWeight.w500),
            ),
        ]),
        maxLines: 5,
      ),
      onTap: onEdit,
    );

    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: toggleLabel): onToggle,
        CustomSemanticsAction(label: l.actionDelete): () => onDelete(),
      },
      child: Dismissible(
        key: ValueKey('dismiss-${rule.id}'),
        background: _SwipeBackground(
          icon: rule.enabled ? EpIcon.pause : EpIcon.play,
          label: toggleLabel,
          color: c.tint,
          onColor: c.onTint,
          alignment: AlignmentDirectional.centerStart,
        ),
        secondaryBackground: _SwipeBackground(
          icon: EpIcon.trash,
          label: l.actionDelete,
          color: c.attention,
          onColor: c.surface,
          alignment: AlignmentDirectional.centerEnd,
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            onToggle();
            return false;
          }
          return onDelete();
        },
        child: GestureDetector(
          onLongPress: () => _showActions(context, toggleLabel),
          child: tile,
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context, String toggleLabel) async {
    final l = context.l10n;
    final choice = await showEpActionSheet<int>(
      context,
      title: rule.address,
      actions: [
        EpSheetAction(label: l.actionEdit, value: 0, icon: EpIcon.edit),
        EpSheetAction(label: toggleLabel, value: 1, icon: rule.enabled ? EpIcon.pause : EpIcon.play),
        EpSheetAction(label: l.actionDelete, value: 2, icon: EpIcon.trash, destructive: true),
      ],
    );
    switch (choice) {
      case 0:
        onEdit();
      case 1:
        onToggle();
      case 2:
        await onDelete();
    }
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.icon,
    required this.label,
    required this.color,
    required this.onColor,
    required this.alignment,
  });

  final EpIcon icon;
  final String label;
  final Color color;
  final Color onColor;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: color,
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpSpace.xl),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                EpIconView(icon, color: onColor, size: 20),
                const SizedBox(width: EpSpace.sm),
                Text(label, style: TextStyle(color: onColor, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}
