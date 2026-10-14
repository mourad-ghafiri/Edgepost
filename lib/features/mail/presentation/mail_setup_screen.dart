import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/accounts/access.dart';
import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../onboarding/presentation/capability_list.dart';
import '../../zones/data/zones_providers.dart';
import '../data/branding.dart';
import '../data/mail_dns_check.dart';
import '../data/mail_models.dart';
import '../data/mail_providers.dart';
import '../data/mail_routing_adapter.dart';
import '../data/provisioning.dart';
import '../mail_routes.dart' show mailDomainPath;
import 'domain_brand_screen.dart' show brandSummary;
import 'mail_widgets.dart';
import 'sending_health_screen.dart';

/// Current send budget from the Worker.
final _sendUsageProvider = FutureProvider.autoDispose.family<SendUsage, String>((ref, accountId) async {
  final cfg = await ref.read(mailClientProvider(accountId)).config();
  return SendUsage.fromJson(cfg['sendUsage'] as Map<String, dynamic>);
});

String _limitLabel(BuildContext context, int v, {bool short = false}) {
  final l = context.l10n;
  if (v == 0) return l.mailBudgetOff;
  final n = NumberFormat.decimalPattern().format(v);
  return v == 3000 && !short ? l.mailBudgetIncluded(n) : l.mailBudgetValue(n);
}

/// Sending limit choices, all at or under the 3,000 emails Workers Paid
/// includes, so the default can never cause overage.
Future<int?> pickSendLimit(BuildContext context, int current) => showEpActionSheet<int>(
  context,
  title: context.l10n.mailBudgetLimit,
  message: context.l10n.mailBudgetExplain,
  actions: [
    for (final v in const [3000, 2000, 1000, 500, 0])
      EpSheetAction(label: _limitLabel(context, v), value: v, icon: v == current ? EpIcon.check : null),
  ],
);

/// Set up, update, or extend the mail service of the active account.
class MailSetupScreen extends ConsumerStatefulWidget {
  const MailSetupScreen({super.key});

  @override
  ConsumerState<MailSetupScreen> createState() => _MailSetupScreenState();
}

class _MailSetupScreenState extends ConsumerState<MailSetupScreen> {
  final Set<String> _zoneIds = {};
  RoutingChoice _choice = RoutingChoice.catchAll;
  final _localParts = TextEditingController(text: 'contact');
  bool _sending = true;
  bool _running = false;
  bool _addingDomains = false;
  List<ProvisionStep> _steps = const [];
  MailService? _result;
  bool _updating = false;
  int _sendLimit = 3000;
  final Set<String> _probed = {};
  bool _probing = false;

  /// What mail setup needs from the token.
  static const _required = [
    Capability.zones,
    Capability.emailRouting,
    Capability.workers,
    Capability.d1,
    Capability.r2,
  ];

  @override
  void dispose() {
    _localParts.dispose();
    super.dispose();
  }

  /// Fresh permission check each time setup opens for a token: stored results
  /// can be stale (permissions edited, R2 turned on since).
  Future<void> _recheck(String credentialId, String accountId) async {
    if (_probing) return;
    setState(() => _probing = true);
    try {
      await ref.read(vaultProvider.notifier).reprobe(credentialId, accountId);
    } on Object catch (e) {
      if (mounted) showEpToast(context, describeError(context, e));
    } finally {
      _probed.add(credentialId);
      if (mounted) setState(() => _probing = false);
    }
  }

  /// Blocks deploy only for an explicit refusal or R2 not turned on; anything
  /// inconclusive is attempted and explained by the step that fails.
  ({bool denied, bool r2Off}) _blockers(Credential cred, String accountId) => (
    denied: _required.any((c) => cred.stateOf(accountId, c) == CapState.denied),
    r2Off: cred.stateOf(accountId, Capability.r2) == CapState.notEnabled,
  );

  Future<void> _run(String accountId, Credential cred, List<Zone> zones) async {
    final bundle = await ref.read(workerBundleProvider.future);
    final existing = ref.read(mailServiceProvider(accountId));
    final parts = _localParts.text
        .split(RegExp(r'[,\s]+'))
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toList();
    final plans = [
      for (final z in zones.where((z) => _zoneIds.contains(z.id)))
        DomainPlan(zone: z, choice: _choice, localParts: parts, enableSending: _sending),
    ];
    setState(() {
      _running = true;
      _result = null;
      _steps = MailProvisioner.plan(plans);
    });
    final p = MailProvisioner(
      client: ref.read(cfClientProvider(cred.id)),
      accountId: accountId,
      bundle: bundle,
      routing: ref.read(mailRoutingProvider),
      existing: existing,
      monthlySendLimit: _sendLimit,
    );
    try {
      final service = await p.run(plans, (s) {
        if (!mounted) return;
        setState(() => _steps = [for (final x in _steps) x.sameLine(s) ? s : x]);
      });
      await ref.read(mailServicesProvider.notifier).save(service);
      ref.invalidate(mailboxesProvider);
      if (mounted) setState(() => _result = service);
    } on Object {
      // The failing step shows its error and a retry.
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _update(MailService s, Credential cred) async {
    final l = context.l10n;
    setState(() => _updating = true);
    try {
      final bundle = await ref.read(workerBundleProvider.future);
      final p = MailProvisioner(
        client: ref.read(cfClientProvider(cred.id)),
        accountId: s.accountId,
        bundle: bundle,
        routing: ref.read(mailRoutingProvider),
        existing: s,
      );
      final updated = await p.update(s);
      await ref.read(mailServicesProvider.notifier).save(updated);
      if (mounted) showEpToast(context, l.mailServiceVersion(updated.workerVersion));
    } on Object catch (e) {
      if (mounted) showEpToast(context, describeError(context, e));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final account = ref.watch(activeAccountProvider)!.id;
    // One token deploys everything; the first that reaches the account shows
    // what it still lacks.
    final pick = ref.watch(accessProvider).all(account, _required.toSet());
    final cred = pick is Granted ? pick.token : ref.watch(tokensProvider).where((t) => t.reaches(account)).firstOrNull;
    if (cred == null) {
      return EpPage(
        title: l.mailSetupTitle,
        largeTitle: false,
        slivers: [
          EpFill(
            child: EpMessage(icon: EpIcon.key, title: l.errorNoToken),
          ),
        ],
      );
    }
    final service = ref.watch(mailServiceProvider(account));
    final zones = ref.watch(zonesProvider(account)).value?.data ?? const <Zone>[];

    final showWizard = service == null || _addingDomains || _steps.isNotEmpty;
    if (showWizard && !_probed.contains(cred.id) && !_probing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recheck(cred.id, account);
      });
    }
    return EpPage(
      title: service == null ? l.mailSetupTitle : l.mailServiceTitle,
      largeTitle: false,
      slivers: [
        if (service != null && !showWizard) ..._manage(context, service, cred),
        if (showWizard) ..._wizard(context, account, cred, zones, service),
      ],
    );
  }

  List<Widget> _manage(BuildContext context, MailService s, Credential cred) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final bundle = ref.watch(workerBundleProvider).value;
    final updateAvailable = bundle != null && compareVersions(bundle.version, s.workerVersion) > 0;
    final brands = ref.watch(brandsProvider(s.accountId)).value?.data ?? const <DomainBrand>[];
    return [
      SliverToBoxAdapter(
        child: EpSection(
          header: l.mailServiceTitle,
          footer: updateAvailable ? l.mailServiceUpdateAvailable(bundle.version) : null,
          children: [
            EpTile(title: Text(l.mailServiceVersion(s.workerVersion))),
            EpTile(
              title: Text(l.mailServiceUrl),
              subtitle: Text(s.workerUrl, style: EpType.data(context, size: 13, color: c.inkMuted)),
              onTap: () => copyWithToast(context, s.workerUrl),
            ),
            if (updateAvailable)
              EpTile(
                leading: EpIconView(EpIcon.deploy, color: c.tint),
                title: Text(l.mailServiceUpdate, style: TextStyle(color: c.tint)),
                trailing: _updating ? const CircularProgressIndicator.adaptive() : null,
                onTap: _updating ? null : () => _update(s, cred),
              ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: EpSection(children: [SendingHealthLink(onTap: () => context.push('/mail/health'))]),
      ),
      SliverToBoxAdapter(child: _BudgetSection(accountId: s.accountId)),
      SliverToBoxAdapter(
        child: _DnsCheckSection(accountId: s.accountId, domains: s.domains),
      ),
      SliverToBoxAdapter(
        child: EpSection(
          header: l.mailServiceDomains,
          children: [
            // Each domain opens its signature and logo.
            for (final d in s.domains)
              EpTile(
                title: Text(d, style: EpType.data(context, size: 15)),
                subtitle: Text(
                  [
                    brandSummary(context, brandOf(brands, d)),
                    if (s.sendingDomains.contains(d)) l.actionSend,
                  ].join(' · '),
                ),
                onTap: () => context.push(mailDomainPath(d)),
              ),
            EpTile(
              leading: EpIconView(EpIcon.add, color: c.tint),
              title: Text(l.mailServiceAddDomains, style: TextStyle(color: c.tint)),
              onTap: () => setState(() => _addingDomains = true),
            ),
          ],
        ),
      ),
      SliverToBoxAdapter(
        child: EpSection(
          footer: l.mailServiceForgetBody,
          children: [
            EpTile(
              title: Text(l.mailServiceForget),
              destructive: true,
              onTap: () async {
                final ok = await showEpConfirm(
                  context,
                  title: l.mailServiceForget,
                  message: l.mailServiceForgetBody,
                  confirmLabel: l.actionRemove,
                  destructive: true,
                );
                if (ok) await ref.read(mailServicesProvider.notifier).forget(s.accountId);
              },
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _wizard(BuildContext context, String account, Credential cred, List<Zone> zones, MailService? existing) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final blockers = _blockers(cred, account);
    final blocked = blockers.denied || blockers.r2Off;
    final allGranted = _required.every((cap) => cred.stateOf(account, cap) == CapState.granted);
    final available = zones.where((z) => !(existing?.domains.contains(z.name) ?? false)).toList();

    if (_steps.isNotEmpty) {
      final failed = _steps.where((s) => s.state == ProvisionState.failed && s.id != 'sending').firstOrNull;
      return [
        SliverToBoxAdapter(
          child: EpSection(
            header: _running ? l.mailSetupRunning : (_result != null ? l.mailSetupDone : null),
            children: [for (final s in _steps) _StepTile(step: s)],
          ),
        ),
        if (_result != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(EpSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l.mailSetupDoneBody, style: TextStyle(color: c.inkMuted)),
                  _DnsCheckSection(accountId: account, domains: _result!.domains),
                  const SizedBox(height: EpSpace.lg),
                  EpButton(label: l.mailSetupOpenInbox, onPressed: () => context.go('/mail')),
                ],
              ),
            ),
          ),
        if (!_running && failed != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(EpSpace.lg),
              child: EpButton(label: l.mailSetupRetry, onPressed: () => _run(account, cred, zones)),
            ),
          ),
      ];
    }

    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
          child: Text(l.mailSetupIntro, style: TextStyle(color: c.ink, fontSize: 16, height: 1.45)),
        ),
      ),
      SliverToBoxAdapter(
        child: EpSection(
          header: l.mailSetupRequirements,
          children: [
            EpTile(
              leading: EpIconView(EpIcon.key, color: c.inkMuted),
              title: Text(l.mailSetupReqToken),
            ),
            EpTile(
              leading: EpIconView(EpIcon.cloud, color: c.inkMuted),
              title: Text(l.mailSetupReqR2),
            ),
            EpTile(
              leading: EpIconView(EpIcon.send, color: c.inkMuted),
              title: Text(l.mailSetupReqPaid),
            ),
          ],
        ),
      ),
      // Permission check: shown unless everything is confirmed.
      if (_probing)
        SliverToBoxAdapter(
          child: EpSection(
            children: [
              EpTile(leading: const CircularProgressIndicator.adaptive(), title: Text(l.capChecking)),
            ],
          ),
        )
      else if (!allGranted)
        SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CapabilityList(
                header: l.mailStepPermissions,
                credential: cred,
                accountId: account,
                only: _required,
                footer: blockers.denied ? l.mailSetupBlockedDenied : (blockers.r2Off ? l.mailSetupBlockedR2 : null),
              ),
              EpSection(
                children: [
                  EpTile(
                    leading: EpIconView(EpIcon.refresh, color: c.tint),
                    title: Text(l.capCheckAgain, style: TextStyle(color: c.tint)),
                    onTap: () => _recheck(cred.id, account),
                  ),
                  EpTile(
                    leading: EpIconView(EpIcon.external, color: c.tint),
                    title: Text(l.capOpenDashboard, style: TextStyle(color: c.tint)),
                    onTap: () =>
                        launchUrl(Uri.parse('https://dash.cloudflare.com/'), mode: LaunchMode.externalApplication),
                  ),
                ],
              ),
            ],
          ),
        ),
      if (!blocked && !_probing) ...[
        SliverToBoxAdapter(
          child: EpSection(
            header: l.mailSetupDomains,
            footer: l.mailSetupDomainsHelp,
            children: [
              for (final z in available)
                EpTile(
                  title: Text(z.name, style: EpType.data(context, size: 15)),
                  trailing: Checkbox.adaptive(
                    value: _zoneIds.contains(z.id),
                    onChanged: (v) => setState(() => v == true ? _zoneIds.add(z.id) : _zoneIds.remove(z.id)),
                  ),
                  onTap: () => setState(() => _zoneIds.contains(z.id) ? _zoneIds.remove(z.id) : _zoneIds.add(z.id)),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.mailSetupRouting, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: EpSpace.sm),
                EpSegmented<RoutingChoice>(
                  segments: {RoutingChoice.catchAll: l.mailSetupCatchAll, RoutingChoice.specific: l.mailSetupSpecific},
                  value: _choice,
                  onChanged: (v) => setState(() => _choice = v),
                ),
                if (_choice == RoutingChoice.specific) ...[
                  const SizedBox(height: EpSpace.md),
                  EpTextField(
                    label: l.mailSetupSpecific,
                    controller: _localParts,
                    helperText: l.mailSetupAddressesHelp,
                    autocorrect: false,
                  ),
                ],
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            footer: l.mailSetupSendingHelp,
            children: [
              EpSwitchTile(title: l.mailSetupSending, value: _sending, onChanged: (v) => setState(() => _sending = v)),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.mailBudgetTitle,
            footer: l.mailBudgetExplain,
            children: [
              EpTile(
                title: Text(l.mailBudgetLimit),
                additionalInfo: Text(_limitLabel(context, _sendLimit, short: true)),
                onTap: () async {
                  final v = await pickSendLimit(context, _sendLimit);
                  if (v != null && mounted) setState(() => _sendLimit = v);
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(EpSpace.lg),
            child: EpButton(
              label: l.mailSetupRun,
              busy: _running,
              onPressed: _zoneIds.isEmpty ? null : () => _run(account, cred, zones),
            ),
          ),
        ),
      ],
    ];
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({required this.step});
  final ProvisionStep step;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final d = step.domain ?? '';
    final title = switch (step.id) {
      'd1' => l.mailStepD1,
      'r2' => l.mailStepR2,
      'upload' => l.mailStepUpload,
      'publish' => l.mailStepPublish,
      'schedule' => l.mailStepSchedule,
      'connect' => l.mailStepConnect,
      'route' => l.mailStepRoute(d),
      'sending' => l.mailStepSending(d),
      _ => l.mailStepSave,
    };
    final explain = switch (step.problem) {
      ProvisionProblem.r2Disabled => l.mailErrR2Disabled,
      ProvisionProblem.noWorkersSubdomain => l.mailErrNoSubdomain,
      ProvisionProblem.healthTimeout => l.mailErrHealth,
      ProvisionProblem.sendingPending => l.mailSendingPending(step.error ?? ''),
      _ => step.error == null ? null : l.mailCloudflareSaid(step.error!),
    };
    final Widget leading = switch (step.state) {
      ProvisionState.running => const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
      ),
      ProvisionState.done => EpIconView(EpIcon.checkCircle, color: c.ok),
      ProvisionState.attention => EpIconView(EpIcon.info, color: c.caution),
      ProvisionState.failed => EpIconView(EpIcon.warning, color: c.attention),
      ProvisionState.skipped => EpIconView(EpIcon.close, color: c.inkMuted),
      ProvisionState.pending => EpIconView(EpIcon.timer, color: c.inkMuted),
    };
    final showDetail = step.state == ProvisionState.failed || step.state == ProvisionState.attention;
    return EpTile(
      leading: leading,
      title: Text(title),
      subtitle: showDetail && explain != null
          ? Text(explain, style: TextStyle(color: step.state == ProvisionState.failed ? c.attention : c.inkMuted))
          : null,
    );
  }
}

class _BudgetSection extends ConsumerWidget {
  const _BudgetSection({required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final usage = ref.watch(_sendUsageProvider(accountId));
    final fmt = NumberFormat.decimalPattern();
    final u = usage.value;
    return EpSection(
      header: l.mailBudgetTitle,
      footer: l.mailBudgetExplain,
      children: [
        if (usage.isLoading && !usage.hasValue)
          EpTile(title: Text(l.loading))
        else if (u != null) ...[
          EpTile(
            title: Text(l.mailBudgetUsage(fmt.format(u.used), fmt.format(u.limit))),
            subtitle: u.resetsAt == null
                ? null
                : Text(l.mailBudgetResets(DateFormat.yMMMd().format(u.resetsAt!.toLocal()))),
          ),
          EpTile(
            title: Text(l.mailBudgetLimit),
            additionalInfo: Text(_limitLabel(context, u.limit, short: true)),
            onTap: () async {
              final v = await pickSendLimit(context, u.limit);
              if (v == null || v == u.limit) return;
              try {
                await ref.read(mailClientProvider(accountId)).putConfig({'monthlySendLimit': v});
                ref.invalidate(_sendUsageProvider(accountId));
                if (context.mounted) showEpToast(context, l.mailBudgetSaved);
              } on Object catch (e) {
                if (context.mounted) showEpToast(context, describeMailError(context, e));
              }
            },
          ),
        ] else if (usage.hasError)
          EpTile(title: Text(describeMailError(context, usage.error!))),
      ],
    );
  }
}

/// Duplicate DMARC/SPF records across the mail domains, with a shortcut to
/// each domain's DNS records to remove the extra copy.
final _dnsIssuesProvider = FutureProvider.autoDispose.family<List<MailDnsIssue>, (String, String)>((ref, key) async {
  final (accountId, domainsKey) = key;
  final domains = domainsKey.split(',').where((d) => d.isNotEmpty).toSet();
  final zones = (await ref.watch(zonesProvider(accountId).future)).data.where((z) => domains.contains(z.name)).toList();
  final results = await Future.wait(zones.map((z) => checkMailDns(ref.zoneClient(z, Capability.dns), z)));
  return results.expand((r) => r).toList();
});

class _DnsCheckSection extends ConsumerWidget {
  const _DnsCheckSection({required this.accountId, required this.domains});
  final String accountId;
  final List<String> domains;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final issues = ref.watch(_dnsIssuesProvider((accountId, (domains.toList()..sort()).join(','))));
    final date = DateFormat.yMMMd();
    return EpSection(
      header: l.mailDnsCheckTitle,
      footer: l.mailDnsCheckHelp,
      children: issues.when(
        loading: () => [EpTile(title: Text(l.mailDnsCheckRunning))],
        error: (e, _) => [EpTile(title: Text(describeError(context, e)))],
        data: (list) => list.isEmpty
            ? [
                EpTile(
                  leading: EpIconView(EpIcon.checkCircle, color: c.ok),
                  title: Text(l.mailDnsCheckClean),
                ),
              ]
            : [
                for (final i in list)
                  EpTile(
                    leading: EpIconView(EpIcon.warning, color: c.attention),
                    title: Text(i.zone.name, style: EpType.data(context, size: 15)),
                    subtitle: Text(
                      [
                        i.kind == MailDnsIssueKind.duplicateDmarc
                            ? l.mailDnsDupDmarc(i.records.length)
                            : l.mailDnsDupSpf(i.records.length, i.name),
                        for (final r in i.records)
                          '• ${r['content']}'
                              '${parseCfDate(r['created_on']) == null ? '' : '  (${l.mailDnsAddedOn(date.format(parseCfDate(r['created_on'])!.toLocal()))})'}',
                      ].join('\n'),
                    ),
                    onTap: () => context.push('/domains/${i.zone.id}/dns'),
                  ),
              ],
      ),
    );
  }
}
