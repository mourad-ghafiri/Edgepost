import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../data/compute_providers.dart';
import 'compute_screen.dart' show pagesPath;
import 'compute_strips.dart';
import 'pages_actions.dart';

String pagesDomainStatusLabel(BuildContext context, String status) {
  final l = context.l10n;
  return switch (status) {
    'active' => l.pagesDomainActive,
    'pending' => l.pagesDomainPending,
    'initializing' => l.pagesDomainInitializing,
    'blocked' => l.pagesDomainBlocked,
    'deactivated' => l.pagesDomainDeactivated,
    'error' => l.pagesDomainError,
    _ => status,
  };
}

/// One Pages project: where it lives, its custom domains, and its
/// deployments as strips.
class PagesProjectScreen extends ConsumerWidget {
  const PagesProjectScreen({super.key, required this.project});

  final String project;

  PagesKey _keyOf(WidgetRef ref) => (accountId: ref.read(activeAccountProvider)!.id, project: project);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(pagesProjectProvider(_keyOf(ref)));
    final synced = async.value;
    final subdomain = synced?.data.project.subdomain;
    return EpPage(
      title: project,
      largeTitle: false,
      previousPageTitle: l.tabCompute,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => ref.read(pagesProjectProvider(_keyOf(ref)).notifier).refresh(),
      actions: [
        if (subdomain != null)
          EpAction(icon: EpIcon.external, label: l.pagesOpenSite, onPressed: () => openExternal(subdomain)),
      ],
      slivers: async.when(
        loading: () => const [EpFill(child: EpLoading())],
        error: (e, _) => [
          EpFill(
            child: EpErrorView(
              error: e,
              permission: Capability.pages.permission,
              onRetry: () => ref.invalidate(pagesProjectProvider(_keyOf(ref))),
            ),
          ),
        ],
        data: (s) => [SliverList.list(children: _body(context, ref, s.data))],
      ),
    );
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, PagesProjectDetail d) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final p = d.project;
    final liveId = p.canonicalDeployment?.id;
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
        child: PagesProjectStrip(project: p),
      ),
      EpSection(
        header: l.pagesSectionProject,
        children: [
          if (p.subdomain != null)
            EpTile(
              title: Text(l.pagesSite),
              subtitle: Text(p.subdomain!, style: EpType.data(context, size: 14, color: c.inkMuted)),
              trailing: EpIconView(EpIcon.external, size: 18, color: c.tint, semanticLabel: l.actionOpen),
              onTap: () => openExternal(p.subdomain!),
            ),
          EpTile(
            title: Text(l.pagesProductionBranch),
            additionalInfo: Text(p.productionBranch ?? '—', style: EpType.data(context, size: 14)),
          ),
          if (p.repoOwner != null && p.repoName != null)
            EpTile(
              title: Text(l.pagesRepository),
              subtitle: Text('${p.repoOwner}/${p.repoName}', style: EpType.data(context, size: 14, color: c.inkMuted)),
              additionalInfo: p.sourceType == null ? null : Text(_sourceLabel(p.sourceType!)),
            ),
          if (p.createdOn != null) EpTile(title: Text(l.pagesCreated), additionalInfo: Text(dateLabel(p.createdOn))),
        ],
      ),
      _domains(context, d),
      StripBay(
        title: l.pagesSectionDeployments,
        count: d.deployments.length,
        empty: Padding(
          padding: const EdgeInsets.symmetric(vertical: EpSpace.md),
          child: Text(l.pagesNoDeployments, style: TextStyle(color: c.inkMuted)),
        ),
        children: [
          for (final dep in d.deployments)
            PagesDeploymentStrip(
              key: ValueKey(dep.id),
              deployment: dep,
              live: dep.id == liveId,
              onTap: () => context.push(
                '${pagesPath(project)}/deployments/${dep.id}',
              ),
              onLongPress: () => showPagesDeploymentActions(context, ref, _keyOf(ref), dep, p),
            ),
        ],
      ),
      if (d.deployments.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg + 4, EpSpace.sm, EpSpace.lg + 4, 0),
          child: Text(l.pagesDeploymentsHint, style: TextStyle(color: c.inkMuted, fontSize: 13)),
        ),
    ];
  }

  static String _sourceLabel(String type) => switch (type) {
        'github' => 'GitHub',
        'gitlab' => 'GitLab',
        _ => type,
      };

  Widget _domains(BuildContext context, PagesProjectDetail d) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final list = d.domains.value;
    final err = d.domains.error;
    return EpSection(
      header: l.pagesSectionDomains,
      children: [
        if (list == null && err != null)
          EpTile(
            leading: EpIconView(
              err is CfApiException && err.isPermissionDenied ? EpIcon.key : EpIcon.warning,
              color: c.caution,
            ),
            title: Text(describeError(context, err, permission: Capability.pages.permission)),
          )
        else if (list == null)
          EpTile(title: Text(l.loading))
        else if (list.isEmpty)
          EpTile(title: Text(l.pagesNoDomains, style: TextStyle(color: c.inkMuted)))
        else
          for (final dom in list)
            EpTile(
              title: Text(dom.name, style: EpType.data(context, size: 15)),
              subtitle: dom.errorMessage == null || dom.active ? null : Text(dom.errorMessage!),
              additionalInfo: Text(
                pagesDomainStatusLabel(context, dom.status),
                style: TextStyle(color: dom.active ? c.ok : (dom.failing ? c.attention : c.caution)),
              ),
              onTap: dom.active ? () => openExternal(dom.name) : null,
            ),
      ],
    );
  }
}
