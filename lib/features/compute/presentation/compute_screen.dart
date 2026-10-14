import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../data/compute_providers.dart';
import 'compute_strips.dart';

/// Official guidance shown under the Pages bays
/// (https://developers.cloudflare.com/pages/).
const kPagesMigrationGuide = 'https://developers.cloudflare.com/workers/static-assets/migration-guides/migrate-from-pages/';

String workerPath(String script) => '/compute/workers/${Uri.encodeComponent(script)}';

String pagesPath(String project) => '/compute/pages/${Uri.encodeComponent(project)}';

/// Text for a kind the board can't show for an account.
String gapMessage(BuildContext context, ComputeGap gap) {
  final l = context.l10n;
  return switch (gap.reason) {
    GapReason.permission => l.computeGapPermission(gap.kind.capability.permission),
    GapReason.userToken => l.registrarAccountTokenShort,
    GapReason.failed => l.computeGapFailed(gap.message ?? l.errorGeneric),
  };
}

/// The Compute tab: the account's Workers and Pages strips, then Registrar.
class ComputeScreen extends ConsumerWidget {
  const ComputeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final account = ref.watch(activeAccountProvider)!.id;
    final async = ref.watch(computeOverviewProvider(account));
    final synced = async.value;
    return EpPage(
      title: l.tabCompute,
      account: true,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => ref.read(computeOverviewProvider(account).notifier).refresh(),
      slivers: async.when(
        skipLoadingOnRefresh: true,
        loading: () => const [EpFill(child: EpLoading())],
        error: (e, _) => [
          EpFill(child: EpErrorView(error: e, onRetry: () => ref.invalidate(computeOverviewProvider(account)))),
        ],
        data: (s) => _board(context, s.data),
      ),
    );
  }

  List<Widget> _board(BuildContext context, ComputeOverview o) {
    final l = context.l10n;
    bool blocked(ComputeKind k) {
      final g = o.gapFor(k);
      return g != null && g.reason != GapReason.failed;
    }

    final children = <Widget>[
      if (blocked(ComputeKind.workers) && blocked(ComputeKind.pages))
        Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.xl, EpSpace.bay, EpSpace.xl, EpSpace.sm),
          child: EpMessage(
            icon: EpIcon.key,
            title: l.computeNoAccessTitle,
            message: l.computeNoAccessMessage(Capability.workers.permission, Capability.pages.permission),
          ),
        )
      else ...[
        _workersBay(context, o),
        _pagesBay(context, o),
      ],
      Padding(padding: const EdgeInsets.only(top: EpSpace.lg), child: _RegistrarRow(overview: o)),
      if (o.gapFor(ComputeKind.pages) == null) const _PagesNote(),
    ];
    return [SliverList.list(children: children)];
  }

  Widget _workersBay(BuildContext context, ComputeOverview o) {
    final l = context.l10n;
    final gap = o.gapFor(ComputeKind.workers);
    return StripBay(
      key: const ValueKey('workers'),
      title: l.computeBayWorkers,
      count: gap == null ? o.workers.length : null,
      empty: _BayNote(
        icon: gap == null ? null : EpIcon.key,
        text: gap == null ? l.workersEmpty : gapMessage(context, gap),
      ),
      children: [
        for (final w in o.workers)
          WorkerStrip(key: ValueKey('w-${w.name}'), worker: w, onTap: () => context.push(workerPath(w.name))),
      ],
    );
  }

  Widget _pagesBay(BuildContext context, ComputeOverview o) {
    final l = context.l10n;
    final gap = o.gapFor(ComputeKind.pages);
    final list = [...o.pages]
      ..sort((x, y) {
        final fx = x.latestStatus == DeployStatus.failed ? 0 : 1;
        final fy = y.latestStatus == DeployStatus.failed ? 0 : 1;
        return fx != fy ? fx - fy : x.name.compareTo(y.name);
      });
    return StripBay(
      key: const ValueKey('pages'),
      title: l.computeBayPages,
      count: gap == null ? list.length : null,
      empty: _BayNote(
        icon: gap == null ? null : EpIcon.key,
        text: gap == null ? l.pagesEmpty : gapMessage(context, gap),
      ),
      children: [
        for (final p in list)
          PagesProjectStrip(key: ValueKey('p-${p.name}'), project: p, onTap: () => context.push(pagesPath(p.name))),
      ],
    );
  }
}

/// Quiet line inside an empty bay.
class _BayNote extends StatelessWidget {
  const _BayNote({required this.text, this.icon});
  final String text;
  final EpIcon? icon;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: EpSpace.md, vertical: EpSpace.md),
      decoration: BoxDecoration(
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(EpRadius.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: EpIconView(icon!, size: 18, color: c.inkMuted),
            ),
            const SizedBox(width: EpSpace.sm),
          ],
          Expanded(child: Text(text, style: TextStyle(color: c.inkMuted, fontSize: 15, height: 1.35))),
        ],
      ),
    );
  }
}

class _RegistrarRow extends StatelessWidget {
  const _RegistrarRow({required this.overview});
  final ComputeOverview overview;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final o = overview;
    final attention = o.registrarAttention().length;
    final gap = o.gapFor(ComputeKind.registrar);
    final String summary;
    Color? color;
    if (o.registrar.isNotEmpty) {
      if (attention > 0) {
        summary = l.registrarSummaryAttention(attention);
        color = c.attention;
      } else {
        summary = l.registrarSummary(o.registrar.length);
      }
    } else if (gap?.reason == GapReason.userToken) {
      summary = l.registrarAccountTokenShort;
    } else if (gap?.reason == GapReason.permission) {
      summary = l.registrarNeedsPermission(Capability.registrar.permission);
    } else if (gap?.reason == GapReason.failed) {
      summary = l.registrarSummaryFailed;
      color = c.caution;
    } else {
      summary = l.registrarSummaryNone;
    }
    return EpSection(
      header: l.registrarTitle,
      children: [
        EpTile(
          leading: EpIconView(EpIcon.calendar, color: c.tint),
          title: Text(l.registrarRowTitle),
          subtitle: Text(summary, style: color == null ? null : TextStyle(color: color)),
          onTap: () => context.push('/compute/registrar'),
        ),
      ],
    );
  }
}

/// Cloudflare's own guidance, said once and quietly: new projects belong on
/// Workers (https://developers.cloudflare.com/pages/).
class _PagesNote extends StatelessWidget {
  const _PagesNote();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg + 4, EpSpace.md, EpSpace.lg + 4, 0),
      child: Semantics(
        link: true,
        child: InkWell(
          onTap: () => launchUrl(Uri.parse(kPagesMigrationGuide), mode: LaunchMode.externalApplication),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '${l.pagesWorkersNote} '),
                    TextSpan(text: l.pagesWorkersNoteLink, style: TextStyle(color: c.tint)),
                  ],
                ),
                style: TextStyle(color: c.inkMuted, fontSize: 13, height: 1.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
