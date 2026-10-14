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
import '../../zones/data/zones_providers.dart';
import '../data/email_routing_models.dart';
import '../data/email_routing_providers.dart';
import 'add_address_dialog.dart';

enum _Kind { forward, mailbox, worker, drop }

/// Create or edit one address rule: local part, action, destination, on/off.
class RuleEditorScreen extends ConsumerStatefulWidget {
  const RuleEditorScreen({super.key, required this.zoneId, this.ruleId});
  final String zoneId;

  /// Null for a new rule.
  final String? ruleId;

  @override
  ConsumerState<RuleEditorScreen> createState() => _RuleEditorScreenState();
}

class _RuleEditorScreenState extends ConsumerState<RuleEditorScreen> {
  final _local = TextEditingController();
  final _manualDest = TextEditingController();
  _Kind _kind = _Kind.forward;
  String? _destination;
  String? _otherWorker;
  bool _enabled = true;
  bool _initialized = false;
  bool _submitted = false;
  bool _busy = false;

  bool get _isNew => widget.ruleId == null;

  @override
  void dispose() {
    _local.dispose();
    _manualDest.dispose();
    super.dispose();
  }

  void _initFrom(RoutingRule? rule, String domain) {
    if (_initialized) return;
    _initialized = true;
    if (rule == null) return;
    final address = rule.address ?? '';
    final suffix = '@${domain.toLowerCase()}';
    _local.text = address.toLowerCase().endsWith(suffix) ? address.substring(0, address.length - suffix.length) : address;
    _enabled = rule.enabled;
    final a = rule.action;
    switch (a?.type) {
      case RuleActionType.forward:
        _kind = _Kind.forward;
        _destination = a?.target;
        _manualDest.text = a?.target ?? '';
      case RuleActionType.worker:
        if (a!.isMailbox) {
          _kind = _Kind.mailbox;
        } else {
          _kind = _Kind.worker;
          _otherWorker = a.target;
        }
      case RuleActionType.drop:
        _kind = _Kind.drop;
      case RuleActionType.unknown || null:
        _kind = _Kind.forward;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final title = _isNew ? l.routingEditorNewTitle : l.routingEditorEditTitle;
    final zone = ref.watch(zoneByIdProvider(widget.zoneId));
    if (zone == null) {
      return EpPage(title: title, largeTitle: false, slivers: const [EpFill(child: EpLoading())]);
    }
    final async = ref.watch(routingOverviewProvider(widget.zoneId));
    return EpPage(
      title: title,
      largeTitle: false,
      previousPageTitle: l.routingTitle,
      slivers: async.when(
        skipLoadingOnReload: true,
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
        data: (s) {
          final rule = _isNew ? null : s.data.ruleById(widget.ruleId!);
          if (!_isNew && rule == null && !_initialized) {
            return [
              EpFill(
                child: EpMessage(
                  icon: EpIcon.search,
                  title: l.routingEditorGoneTitle,
                  message: l.routingEditorGoneMessage,
                  action: EpButton(label: l.actionClose, secondary: true, onPressed: () => context.pop()),
                ),
              ),
            ];
          }
          _initFrom(rule, zone.name);
          return [SliverList.list(children: _form(context, zone, s.data, rule))];
        },
      ),
    );
  }

  List<Widget> _form(BuildContext context, Zone zone, RoutingOverview o, RoutingRule? rule) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final localError = _submitted ? _localErrorText(context, zone, o, rule) : null;
    final full = '${_local.text.trim()}@${zone.name}';
    final segments = <_Kind, String>{
      _Kind.forward: l.routingActionForward,
      _Kind.mailbox: l.routingActionMailbox,
      if (_otherWorker != null) _Kind.worker: l.routingActionWorker,
      _Kind.drop: l.routingActionDrop,
    };

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
        child: EpTextField(
          label: l.routingEditorAddressLabel,
          controller: _local,
          placeholder: l.routingEditorAddressPlaceholder,
          keyboardType: TextInputType.emailAddress,
          monospace: true,
          autocorrect: false,
          autofocus: _isNew,
          enabled: !_busy,
          textInputAction: TextInputAction.done,
          errorText: localError,
          helperText: _local.text.trim().isEmpty ? l.routingEditorAddressHelp : l.routingEditorAddressPreview(full),
          onChanged: (_) => setState(() {}),
          suffix: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 12, start: 4),
              child: Text(
                '@${zone.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: EpType.data(context, size: 15, color: c.inkMuted),
              ),
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xl, EpSpace.lg, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l.routingEditorActionLabel,
                  style: TextStyle(fontSize: 13, color: c.inkMuted, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: EpSpace.sm),
            EpSegmented<_Kind>(
              segments: segments,
              value: _kind,
              onChanged: (v) => setState(() => _kind = v),
            ),
            const SizedBox(height: EpSpace.sm),
            Text(_kindHelp(context), style: TextStyle(fontSize: 13, height: 1.35, color: c.inkMuted)),
          ],
        ),
      ),
      if (_kind == _Kind.forward) _destinations(context, zone),
      EpSection(
        children: [
          EpSwitchTile(
            title: l.routingEditorEnabled,
            subtitle: l.routingEditorEnabledHelp,
            value: _enabled,
            onChanged: _busy ? null : (v) => setState(() => _enabled = v),
          ),
        ],
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, 0),
        child: SizedBox(
          width: double.infinity,
          child: EpButton(label: l.actionSave, busy: _busy, onPressed: () => _save(zone, o, rule)),
        ),
      ),
      if (rule != null)
        EpSection(
          children: [
            EpTile(
              title: Text(l.routingEditorDelete),
              destructive: true,
              onTap: _busy ? null : () => _delete(rule),
            ),
          ],
        ),
    ];
  }

  String _kindHelp(BuildContext context) {
    final l = context.l10n;
    return switch (_kind) {
      _Kind.forward => l.routingEditorForwardHelp,
      _Kind.mailbox => l.routingEditorMailboxHelp(kMailWorkerName),
      _Kind.worker => l.routingEditorWorkerHelp(_otherWorker ?? ''),
      _Kind.drop => l.routingEditorDropHelp,
    };
  }

  Widget _destinations(BuildContext context, Zone zone) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final account = zone.account.id;
    final async = ref.watch(destinationAddressesProvider(account));
    final addresses = async.value?.data;
    final selected = addresses?.where((a) => a.email.toLowerCase() == _destination?.toLowerCase()).firstOrNull;
    final pendingSelected = selected != null && !selected.isVerified;

    if (async.hasError && addresses == null) {
      // Can't list destinations (usually a missing permission): type one in.
      return Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xl, EpSpace.lg, 0),
        child: EpTextField(
          label: l.routingEditorDeliverTo,
          controller: _manualDest,
          placeholder: l.routingAddressPlaceholder,
          keyboardType: TextInputType.emailAddress,
          monospace: true,
          autocorrect: false,
          enabled: !_busy,
          errorText: _submitted && !isValidEmail(_manualDest.text) ? l.routingAddressInvalid : null,
          helperText: describeError(context, async.error!, permission: Capability.emailAddresses.permission),
          onChanged: (v) => setState(() => _destination = v.trim()),
        ),
      );
    }

    return EpSection(
      header: l.routingEditorDeliverTo,
      footer: pendingSelected
          ? l.routingEditorPendingFooter(selected.email)
          : (_submitted && _destination == null ? l.routingEditorPickDestination : l.routingEditorDestFooter),
      children: [
        if (addresses == null) EpTile(title: Text(l.loading)),
        for (final a in addresses ?? const <DestinationAddress>[])
          EpTile(
            title: Text(a.email, maxLines: 2, style: EpType.data(context, size: 15)),
            subtitle: a.isVerified
                ? null
                : Text(l.routingAddressWaiting, style: TextStyle(color: c.caution)),
            trailing: a.email.toLowerCase() == _destination?.toLowerCase()
                ? EpIconView(EpIcon.check, color: c.tint, semanticLabel: l.routingSelected)
                : const SizedBox(width: 24),
            onTap: _busy ? null : () => setState(() => _destination = a.email),
          ),
        EpTile(
          leading: EpIconView(EpIcon.add, color: c.tint),
          title: Text(l.routingAddAddressEllipsis),
          onTap: _busy
              ? null
              : () async {
                  final created = await showAddDestinationDialog(context, account);
                  if (created != null && mounted) setState(() => _destination = created.email);
                },
        ),
      ],
    );
  }

  String? _localErrorText(BuildContext context, Zone zone, RoutingOverview o, RoutingRule? rule) {
    final l = context.l10n;
    final problem = validateLocalPart(_local.text, domain: zone.name);
    if (problem != null) {
      return switch (problem) {
        LocalPartProblem.empty => l.routingEditorAddressRequired,
        LocalPartProblem.tooLong => l.routingEditorAddressTooLong,
        LocalPartProblem.invalid => l.routingEditorAddressInvalid,
      };
    }
    final full = '${_local.text.trim()}@${zone.name}'.toLowerCase();
    final clash = o.rules.any((r) => r.id != rule?.id && r.address?.toLowerCase() == full);
    return clash ? l.routingEditorDuplicate : null;
  }

  RuleAction? _action() => switch (_kind) {
        _Kind.forward => (_destination == null || _destination!.isEmpty) ? null : RuleAction.forward(_destination!),
        _Kind.mailbox => const RuleAction.worker(kMailWorkerName),
        _Kind.worker => RuleAction.worker(_otherWorker!),
        _Kind.drop => const RuleAction.drop(),
      };

  Future<void> _save(Zone zone, RoutingOverview o, RoutingRule? rule) async {
    final l = context.l10n;
    setState(() => _submitted = true);
    if (_localErrorText(context, zone, o, rule) != null) return;
    if (rule == null && o.rules.length >= kMaxRoutingRules) {
      showEpToast(context, l.routingEditorLimit(kMaxRoutingRules));
      return;
    }
    final action = _action();
    if (action == null || (action.type == RuleActionType.forward && !isValidEmail(action.target ?? ''))) {
      showEpToast(context, l.routingEditorPickDestination);
      return;
    }
    final address = '${_local.text.trim()}@${zone.name}';
    final next = rule == null
        ? RoutingRule.forAddress(address, action, enabled: _enabled)
        : rule.copyWith(actions: [action], matchers: [RuleMatcher.to(address)], enabled: _enabled);
    setState(() => _busy = true);
    try {
      await ref.read(routingOverviewProvider(widget.zoneId).notifier).saveRule(next);
      if (!mounted) return;
      showEpToast(context, l.routingRuleSaved(address));
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showEpToast(context, describeError(context, e, permission: Capability.emailRouting.permission));
    }
  }

  Future<void> _delete(RoutingRule rule) async {
    final l = context.l10n;
    final ok = await showEpConfirm(
      context,
      title: l.routingRuleDeleteTitle(rule.address ?? ''),
      message: l.routingRuleDeleteMessage,
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!ok || !mounted || rule.id == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(routingOverviewProvider(widget.zoneId).notifier).deleteRule(rule.id!);
      if (!mounted) return;
      showEpToast(context, l.routingRuleDeleted(rule.address ?? ''));
      context.pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showEpToast(context, describeError(context, e, permission: Capability.emailRouting.permission));
    }
  }
}
