import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

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
import 'compute_strips.dart';
import 'pages_actions.dart';

String pagesStageLabel(BuildContext context, String name) {
  final l = context.l10n;
  return switch (name) {
    'queued' => l.pagesStageQueued,
    'initialize' => l.pagesStageInitialize,
    'clone_repo' => l.pagesStageClone,
    'build' => l.pagesStageBuild,
    'deploy' => l.pagesStageDeploy,
    _ => name,
  };
}

String pagesStageStatusLabel(BuildContext context, String status) {
  final l = context.l10n;
  return switch (status) {
    'success' => l.pagesStageSuccess,
    'active' => l.pagesStageActive,
    'idle' => l.pagesStageIdle,
    'failure' => l.pagesStageFailure,
    'canceled' => l.pagesStageCanceled,
    'skipped' => l.pagesStageSkipped,
    _ => status,
  };
}

/// One Pages deployment: what was built, each stage, the build log, and
/// retry / rollback.
class PagesDeploymentScreen extends ConsumerStatefulWidget {
  const PagesDeploymentScreen({super.key, required this.project, required this.deploymentId});

  final String project;
  final String deploymentId;

  @override
  ConsumerState<PagesDeploymentScreen> createState() => _PagesDeploymentScreenState();
}

class _PagesDeploymentScreenState extends ConsumerState<PagesDeploymentScreen> {
  bool _busy = false;

  String get _account => ref.read(activeAccountProvider)!.id;
  PagesDeploymentKey get _key => (accountId: _account, project: widget.project, deploymentId: widget.deploymentId);
  PagesKey get _projectKey => (accountId: _account, project: widget.project);

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(pagesDeploymentProvider(_key));
    final project = ref.watch(pagesProjectProvider(_projectKey)).value?.data.project;
    final synced = async.value;
    return EpPage(
      title: synced?.data.deployment.displayId ?? widget.deploymentId.split('-').first,
      largeTitle: false,
      previousPageTitle: widget.project,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => ref.read(pagesDeploymentProvider(_key).notifier).refresh(),
      slivers: async.when(
        loading: () => const [EpFill(child: EpLoading())],
        error: (e, _) => [
          EpFill(
            child: EpErrorView(
              error: e,
              permission: Capability.pages.permission,
              onRetry: () => ref.invalidate(pagesDeploymentProvider(_key)),
            ),
          ),
        ],
        data: (s) => _body(context, s.data, project),
      ),
    );
  }

  List<Widget> _body(BuildContext context, PagesDeploymentDetail detail, PagesProjectInfo? project) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final d = detail.deployment;
    final live = project?.canonicalDeployment?.id == d.id;
    final rollback = canRollbackPages(d, project);
    final log = detail.log.value;

    return [
      SliverList.list(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
          child: PagesDeploymentStrip(deployment: d, live: live),
        ),
        EpSection(
          children: [
            if (d.url != null)
              EpTile(
                leading: EpIconView(EpIcon.external, color: c.tint),
                title: Text(l.pagesOpenDeployment),
                subtitle: Text(d.url!, style: EpType.data(context, size: 13, color: c.inkMuted)),
                onTap: () => openExternal(d.url!),
              ),
            EpTile(
              leading: _busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator.adaptive())
                  : EpIconView(EpIcon.refresh, color: c.tint),
              title: Text(l.pagesRetry),
              subtitle: Text(l.pagesRetryHint),
              onTap: _busy ? null : () => _retry(context, d),
            ),
            if (rollback)
              EpTile(
                leading: EpIconView(EpIcon.undo, color: c.attention),
                title: Text(l.pagesRollbackAction),
                subtitle: Text(l.pagesRollbackHint),
                destructive: true,
                onTap: _busy ? null : () => _rollback(context, d),
              ),
          ],
        ),
        EpSection(
          header: l.pagesSectionDeployment,
          children: [
            EpTile(
              title: Text(l.pagesFieldEnv),
              additionalInfo: Text(d.isProduction ? l.pagesEnvProduction : l.pagesEnvPreview),
            ),
            if (d.branch != null)
              EpTile(title: Text(l.pagesFieldBranch), additionalInfo: Text(d.branch!, style: EpType.data(context))),
            if (d.commitHash != null)
              EpTile(
                title: Text(l.pagesCommit),
                subtitle: d.commitMessage == null ? null : Text(d.commitMessage!.trim(), maxLines: 4, overflow: TextOverflow.ellipsis),
                additionalInfo: Text(
                  d.commitHash!.length > 7 ? d.commitHash!.substring(0, 7) : d.commitHash!,
                  style: EpType.data(context),
                ),
                onTap: () => copyWithToast(context, d.commitHash!),
              ),
            if (d.triggerType != null) EpTile(title: Text(l.pagesTrigger), additionalInfo: Text(_trigger(context, d.triggerType!))),
            EpTile(title: Text(l.pagesCreated), additionalInfo: Text(dateTimeLabel(d.createdOn))),
            for (final a in d.aliases)
              EpTile(
                title: Text(a, style: EpType.data(context, size: 14)),
                subtitle: Text(l.pagesAlias),
                onTap: () => openExternal(a),
              ),
          ],
        ),
        if (d.stages.isNotEmpty)
          EpSection(
            header: l.pagesSectionStages,
            children: [
              for (final s in d.stages)
                EpTile(
                  title: Text(pagesStageLabel(context, s.name)),
                  subtitle: s.duration == null ? null : Text(_duration(s.duration!)),
                  additionalInfo: Text(
                    pagesStageStatusLabel(context, s.status),
                    style: TextStyle(
                      color: switch (s.status) {
                        'success' => c.ok,
                        'failure' => c.attention,
                        'active' => c.caution,
                        _ => c.inkMuted,
                      },
                    ),
                  ),
                ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xl, EpSpace.lg, EpSpace.sm),
          child: Semantics(
            header: true,
            child: Text(
              l.pagesSectionBuildLog.toUpperCase(),
              style: EpType.groupLabel(context),
            ),
          ),
        ),
      ]),
      if (log == null)
        SliverToBoxAdapter(child: _logState(context, detail.log.error))
      else if (log.lines.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
            child: Text(l.pagesLogEmpty, style: TextStyle(color: c.inkMuted)),
          ),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
          sliver: DecoratedSliver(
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.hairline),
              borderRadius: BorderRadius.circular(EpRadius.md),
            ),
            sliver: SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: EpSpace.sm),
              sliver: SliverList.builder(
                itemCount: log.lines.length,
                itemBuilder: (context, i) => _LogLine(line: log.lines[i]),
              ),
            ),
          ),
        ),
        if (log.total > log.lines.length)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.sm, EpSpace.lg, 0),
              child: Text(l.pagesLogPartial(log.lines.length, log.total), style: TextStyle(color: c.inkMuted, fontSize: 13)),
            ),
          ),
      ],
    ];
  }

  Widget _logState(BuildContext context, Object? error) {
    final c = EpColors.of(context);
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
      child: Text(
        error == null
            ? l.loading
            : (error is CfApiException && error.isNotFound
                ? l.pagesLogUnavailable
                : describeError(context, error, permission: Capability.pages.permission)),
        style: TextStyle(color: error == null ? c.inkMuted : c.caution),
      ),
    );
  }

  String _trigger(BuildContext context, String type) {
    final l = context.l10n;
    return switch (type) {
      'github:push' => l.pagesTriggerPush,
      'ad_hoc' => l.pagesTriggerUpload,
      'deploy_hook' => l.pagesTriggerHook,
      _ => type,
    };
  }

  static String _duration(Duration d) {
    final m = d.inMinutes, s = d.inSeconds % 60;
    return m > 0 ? '${m}m ${s.toString().padLeft(2, '0')}s' : '${d.inSeconds}s';
  }

  Future<void> _retry(BuildContext context, PagesDeployment d) async {
    setState(() => _busy = true);
    await retryPagesDeployment(context, ref, _projectKey, d);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _rollback(BuildContext context, PagesDeployment d) async {
    setState(() => _busy = true);
    final done = await rollbackPagesDeployment(context, ref, _projectKey, d);
    if (done) await ref.read(pagesDeploymentProvider(_key).notifier).refresh();
    if (mounted) setState(() => _busy = false);
  }
}

class _LogLine extends StatelessWidget {
  const _LogLine({required this.line});
  final PagesLogLine line;

  static final _time = DateFormat.Hms();

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final text = line.line;
    final lower = text.toLowerCase();
    final color = lower.contains('error') || lower.contains('failed')
        ? c.attention
        : (lower.contains('warn') ? c.caution : c.ink);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: EpSpace.md, vertical: 1),
      child: Text.rich(
        TextSpan(children: [
          if (line.ts != null) TextSpan(text: '${_time.format(line.ts!.toLocal())}  ', style: TextStyle(color: c.inkMuted)),
          TextSpan(text: text, style: TextStyle(color: color)),
        ]),
        style: EpType.numbers(EpType.data(context, size: 12)),
      ),
    );
  }
}
