import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../data/compute_providers.dart';
import 'compute_screen.dart';
import 'compute_strips.dart';

/// One Worker: what runs, where it's reachable, what's deployed, and the
/// way back to an earlier version.
class WorkerDetailScreen extends ConsumerStatefulWidget {
  const WorkerDetailScreen({super.key, required this.script});

  final String script;

  @override
  ConsumerState<WorkerDetailScreen> createState() => _WorkerDetailScreenState();
}

class _WorkerDetailScreenState extends ConsumerState<WorkerDetailScreen> {
  String? _busyVersion;

  WorkerKey get _key => (accountId: ref.read(activeAccountProvider)!.id, script: widget.script);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final async = ref.watch(workerDetailProvider(_key));
    final info = ref.watch(computeOverviewProvider(_key.accountId).select((s) => s.value?.data.worker(widget.script)));
    final synced = async.value;
    return EpPage(
      title: widget.script,
      largeTitle: false,
      previousPageTitle: l.tabCompute,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => ref.read(workerDetailProvider(_key).notifier).refresh(),
      actions: [
        EpAction(
          icon: EpIcon.logs,
          label: l.workersLiveLogs,
          onPressed: () => context.push('${workerPath(widget.script)}/logs'),
        ),
      ],
      slivers: async.when(
        loading: () => const [EpFill(child: EpLoading())],
        error: (e, _) => [
          EpFill(
            child: EpErrorView(
              error: e,
              permission: Capability.workers.permission,
              onRetry: () => ref.invalidate(workerDetailProvider(_key)),
            ),
          ),
        ],
        data: (s) => [SliverList.list(children: _body(context, s.data, info))],
      ),
    );
  }

  List<Widget> _body(BuildContext context, WorkerDetail d, WorkerScriptInfo? info) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final settings = d.settings.value;
    final stripInfo = info ??
        WorkerScriptInfo(
          name: widget.script,
          compatibilityDate: settings?.compatibilityDate,
          usageModel: settings?.usageModel,
        );
    final devUrl = d.workersDevUrl(widget.script);
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
        child: WorkerStrip(worker: stripInfo),
      ),
      EpSection(
        children: [
          EpTile(
            leading: EpIconView(EpIcon.logs, color: c.tint),
            title: Text(l.workersLiveLogs),
            subtitle: Text(l.workersLiveLogsHint),
            onTap: () => context.push('${workerPath(widget.script)}/logs'),
          ),
          if (devUrl != null)
            EpTile(
              leading: EpIconView(EpIcon.external, color: c.tint),
              title: Text(l.workersOpenWorkersDev),
              subtitle: Text(devUrl, style: EpType.data(context, size: 13, color: c.inkMuted)),
              onTap: () => launchUrl(Uri.parse(devUrl), mode: LaunchMode.externalApplication),
            ),
        ],
      ),
      _overview(context, d, info),
      _triggers(context, d, info),
      _deployments(context, d),
      _versions(context, d),
      _secrets(context, d),
    ];
  }

  Widget _row(String title, String value, {bool data = false}) => Builder(
        builder: (context) => EpTile(
          title: Text(title),
          additionalInfo: Text(value, style: data ? EpType.data(context, size: 14) : null),
        ),
      );

  Widget _errorRow(BuildContext context, Object error) {
    final c = EpColors.of(context);
    return EpTile(
      leading: EpIconView(error is CfApiException && error.isPermissionDenied ? EpIcon.key : EpIcon.warning,
          color: c.caution),
      title: Text(describeError(context, error, permission: Capability.workers.permission)),
    );
  }

  Widget _pendingRow(BuildContext context) => EpTile(title: Text(context.l10n.loading));

  Widget _overview(BuildContext context, WorkerDetail d, WorkerScriptInfo? info) {
    final l = context.l10n;
    final s = d.settings.value;
    final compat = s?.compatibilityDate ?? info?.compatibilityDate;
    final flags = (s?.compatibilityFlags.isNotEmpty ?? false) ? s!.compatibilityFlags : (info?.compatibilityFlags ?? const []);
    final usage = s?.usageModel ?? info?.usageModel;
    return EpSection(
      header: l.workersSectionOverview,
      children: [
        if (info?.createdOn != null) _row(l.workersCreated, dateTimeLabel(info!.createdOn)),
        if (info?.modifiedOn != null) _row(l.workersModified, dateTimeLabel(info!.modifiedOn)),
        _row(l.workersCompatDate, compat ?? '—'),
        if (flags.isNotEmpty)
          EpTile(
            title: Text(l.workersCompatFlags),
            subtitle: Text(flags.join(', '), style: EpType.data(context, size: 13)),
          ),
        if (usage != null) _row(l.workersUsageModel, usage),
        if (info?.lastDeployedFrom != null) _row(l.workersDeployedFrom, info!.lastDeployedFrom!),
        if (info != null && info.handlers.isNotEmpty) _row(l.workersHandlers, info.handlers.join(', ')),
        if (d.settings.error != null) _errorRow(context, d.settings.error!),
      ],
    );
  }

  Widget _triggers(BuildContext context, WorkerDetail d, WorkerScriptInfo? info) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final sub = d.subdomain.value;
    final domains = d.domains.value ?? const <WorkerCustomDomain>[];
    final routes = info?.routes ?? const <WorkerRoute>[];
    final unreachable = sub?.enabled == false && d.domains.value != null && domains.isEmpty && routes.isEmpty;
    return EpSection(
      header: l.workersSectionTriggers,
      footer: unreachable ? l.workersNoTriggers : null,
      children: [
        if (sub != null)
          EpTile(
            title: Text(l.workersDev),
            subtitle: Text(sub.previewsEnabled ? l.workersPreviewsOn : l.workersPreviewsOff),
            additionalInfo: Text(
              sub.enabled ? l.workersStateOn : l.workersStateOff,
              style: TextStyle(color: sub.enabled ? c.ok : c.inkMuted),
            ),
          )
        else if (d.subdomain.error != null)
          _errorRow(context, d.subdomain.error!)
        else
          _pendingRow(context),
        for (final dom in domains)
          EpTile(
            leading: EpIconView(EpIcon.domains, color: c.tint),
            title: Text(dom.hostname, style: EpType.data(context, size: 15)),
            subtitle: Text(l.workersCustomDomain),
            trailing: EpIconView(EpIcon.external, size: 18, color: c.inkMuted, semanticLabel: l.actionOpen),
            onTap: () => launchUrl(Uri.parse('https://${dom.hostname}'), mode: LaunchMode.externalApplication),
          ),
        if (d.domains.error != null) _errorRow(context, d.domains.error!),
        for (final r in routes)
          EpTile(
            leading: EpIconView(EpIcon.link, color: c.inkMuted),
            title: Text(r.pattern, style: EpType.data(context, size: 15)),
            subtitle: Text(l.workersRoute),
            trailing: IconButton(
              tooltip: l.actionCopy,
              icon: EpIconView(EpIcon.copy, size: 18, color: c.inkMuted),
              onPressed: () => copyWithToast(context, r.pattern),
            ),
          ),
      ],
    );
  }

  String _versionLabel(BuildContext context, WorkerVersion? v, String id) {
    final l = context.l10n;
    if (v?.number != null) return l.workersVersionNumber(v!.number!);
    return l.workersVersionShort(id.split('-').first);
  }

  Widget _deployments(BuildContext context, WorkerDetail d) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final list = d.deployments.value;
    if (list == null) {
      return EpSection(
        header: l.workersSectionDeployment,
        children: [d.deployments.error != null ? _errorRow(context, d.deployments.error!) : _pendingRow(context)],
      );
    }
    if (list.isEmpty) {
      return EpSection(header: l.workersSectionDeployment, children: [EpTile(title: Text(l.workersNoDeployments))]);
    }
    final active = list.first;
    final earlier = list.skip(1).take(5).toList();
    String byline(WorkerDeployment x) =>
        [?x.message, ?x.source, ?x.authorEmail].join(' · ');
    return EpSection(
      header: l.workersSectionDeployment,
      footer: active.versions.length > 1 ? l.workersGradualFooter : null,
      children: [
        EpTile(
          title: Text(l.workersActiveDeployment),
          subtitle: byline(active).isEmpty ? null : Text(byline(active)),
          additionalInfo: Text(whenLabel(context, active.createdOn)),
        ),
        for (final split in active.versions)
          EpTile(
            leading: EpIconView(EpIcon.deploy, color: c.ok),
            title: Text(_versionLabel(context, d.versionById(split.versionId), split.versionId)),
            subtitle: Text(split.versionId, style: EpType.data(context, size: 12, color: c.inkMuted)),
            additionalInfo: Text(
              l.workersPercent(_pct(split.percentage)),
              style: EpType.numbers(TextStyle(color: c.ok, fontWeight: FontWeight.w600)),
            ),
          ),
        for (final x in earlier)
          EpTile(
            title: Text(
              x.versions.map((v) => '${_versionLabel(context, d.versionById(v.versionId), v.versionId)}'
                  '${x.versions.length > 1 ? ' ${l.workersPercent(_pct(v.percentage))}' : ''}').join(' · '),
            ),
            subtitle: byline(x).isEmpty ? null : Text(byline(x), maxLines: 1, overflow: TextOverflow.ellipsis),
            additionalInfo: Text(whenLabel(context, x.createdOn)),
          ),
      ],
    );
  }

  static String _pct(double p) => p == p.roundToDouble() ? p.toInt().toString() : p.toStringAsFixed(1);

  Widget _versions(BuildContext context, WorkerDetail d) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final list = d.versions.value;
    if (list == null) {
      return EpSection(
        header: l.workersSectionVersions,
        children: [d.versions.error != null ? _errorRow(context, d.versions.error!) : _pendingRow(context)],
      );
    }
    final active = d.activeDeployment;
    return EpSection(
      header: l.workersSectionVersions,
      footer: list.isEmpty ? null : l.workersVersionsFooter,
      children: [
        if (list.isEmpty) EpTile(title: Text(l.workersNoVersions)),
        for (final v in list.take(10))
          Builder(builder: (context) {
            final share = active?.percentageOf(v.id) ?? 0;
            final label = _versionLabel(context, v, v.id);
            final busy = _busyVersion == v.id;
            final servesAll = active?.servesOnly(v.id) ?? false;
            return EpTile(
              title: Text(label),
              subtitle: Text(
                [whenLabel(context, v.createdOn), ?v.source, ?(v.message ?? v.authorEmail)].join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              additionalInfo: share > 0
                  ? Text(
                      l.workersLiveShare(_pct(share)),
                      style: EpType.numbers(TextStyle(color: c.ok, fontWeight: FontWeight.w600)),
                    )
                  : null,
              trailing: busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator.adaptive()) : null,
              onTap: servesAll || _busyVersion != null ? null : () => _versionActions(context, v, label),
            );
          }),
      ],
    );
  }

  Widget _secrets(BuildContext context, WorkerDetail d) {
    final l = context.l10n;
    final list = d.secrets.value;
    return EpSection(
      header: l.workersSectionSecrets,
      footer: l.workersSecretsFooter,
      children: [
        if (list == null)
          d.secrets.error != null ? _errorRow(context, d.secrets.error!) : _pendingRow(context)
        else if (list.isEmpty)
          EpTile(title: Text(l.workersNoSecrets))
        else
          for (final s in list)
            EpTile(
              leading: EpIconView(EpIcon.lock, color: EpColors.of(context).inkMuted),
              title: Text(s.name, style: EpType.data(context, size: 15)),
              additionalInfo: Text(s.type == 'secret_key' ? l.workersSecretKey : l.workersSecretText),
            ),
      ],
    );
  }

  Future<void> _versionActions(BuildContext context, WorkerVersion v, String label) async {
    final l = context.l10n;
    final choice = await showEpActionSheet<String>(
      context,
      title: label,
      message: v.id,
      actions: [
        EpSheetAction(label: l.workersRollbackAction, value: 'rollback', icon: EpIcon.undo, destructive: true),
        EpSheetAction(label: l.workersCopyVersionId, value: 'copy', icon: EpIcon.copy),
      ],
    );
    if (!context.mounted) return;
    if (choice == 'copy') return copyWithToast(context, v.id);
    if (choice == 'rollback') await _rollback(context, v, label);
  }

  Future<void> _rollback(BuildContext context, WorkerVersion v, String label) async {
    final l = context.l10n;
    final ok = await showEpConfirm(
      context,
      title: l.workersRollbackTitle(label),
      message: l.workersRollbackMessage(widget.script, label, v.shortId),
      confirmLabel: l.workersRollbackConfirm,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await _runRollback(context, v, label, force: false);
  }

  Future<void> _runRollback(BuildContext context, WorkerVersion v, String label, {required bool force}) async {
    final l = context.l10n;
    setState(() => _busyVersion = v.id);
    try {
      await ref.read(workerDetailProvider(_key).notifier).rollbackTo(v.id, force: force);
      if (context.mounted) showEpToast(context, l.workersRollbackDone(label));
    } on CfApiException catch (e) {
      if (!context.mounted) return;
      if (e.isPermissionDenied || force) {
        showEpToast(context, describeError(context, e, permission: Capability.workers.permission));
        return;
      }
      setState(() => _busyVersion = null);
      final again = await showEpConfirm(
        context,
        title: l.workersRollbackBlockedTitle,
        message: l.workersRollbackBlockedMessage(e.message),
        confirmLabel: l.workersRollbackForce,
        destructive: true,
      );
      if (again && context.mounted) await _runRollback(context, v, label, force: true);
    } on CfException catch (e) {
      if (context.mounted) showEpToast(context, describeError(context, e));
    } finally {
      if (mounted && _busyVersion == v.id) setState(() => _busyVersion = null);
    }
  }
}
