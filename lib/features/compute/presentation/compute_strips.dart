import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../data/compute_models.dart';

String deployStatusLabel(BuildContext context, DeployStatus? s) {
  final l = context.l10n;
  return switch (s) {
    DeployStatus.success => l.pagesStatusSuccess,
    DeployStatus.failed => l.pagesStatusFailed,
    DeployStatus.building => l.pagesStatusBuilding,
    DeployStatus.queued => l.pagesStatusQueued,
    DeployStatus.canceled => l.pagesStatusCanceled,
    DeployStatus.skipped => l.pagesStatusSkipped,
    DeployStatus.unknown => l.pagesStatusUnknown,
    null => l.pagesStatusNone,
  };
}

Color deployStatusColor(BuildContext context, DeployStatus? s) {
  final c = EpColors.of(context);
  return switch (s) {
    DeployStatus.success => c.ok,
    DeployStatus.failed => c.attention,
    DeployStatus.building || DeployStatus.queued => c.caution,
    _ => c.inkMuted,
  };
}

/// Relative time or an em dash when unknown.
String whenLabel(BuildContext context, DateTime? t) => t == null ? '—' : relativeTime(context, t);

/// Short, locale-aware date ("Oct 12, 2026").
String dateLabel(DateTime? t) => t == null ? '—' : DateFormat.yMMMd().format(t.toLocal());

/// Date and time for detail rows ("Oct 12, 2026, 9:41 AM").
String dateTimeLabel(DateTime? t) => t == null ? '—' : DateFormat.yMMMd().add_jm().format(t.toLocal());

/// Why a Pages project is cocked, or null when it's in line.
String? pagesAttentionReason(BuildContext context, PagesProjectInfo p) {
  final d = p.latestDeployment;
  if (d == null || d.status != DeployStatus.failed) return null;
  final l = context.l10n;
  final when = whenLabel(context, d.lastActivity);
  final branch = d.branch;
  return branch == null ? l.pagesReasonFailedNoBranch(when) : l.pagesReasonFailed(branch, when);
}

/// A Worker on the board: sage holder, callsign = script name.
class WorkerStrip extends StatelessWidget {
  const WorkerStrip({super.key, required this.worker, this.onTap, this.caption});

  final WorkerScriptInfo worker;
  final VoidCallback? onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final modified = whenLabel(context, worker.modifiedOn);
    final compat = worker.compatibilityDate;
    return Strip(
      title: worker.name,
      family: Family.compute,
      caption: caption,
      onTap: onTap,
      semanticLabel: l.workersStripSemantics(worker.name, modified, worker.routes.length),
      fields: [
        StripField(l.workersFieldModified, modified),
        StripField(l.workersFieldRoutes, '${worker.routes.length}', flex: 2),
        if (compat != null)
          StripField(l.workersFieldCompat, compat)
        else
          StripField(l.workersFieldUsage, worker.usageModel ?? '—'),
      ],
    );
  }
}

/// A Pages project on the board: sage holder; cocked when its latest build
/// failed.
class PagesProjectStrip extends StatelessWidget {
  const PagesProjectStrip({super.key, required this.project, this.onTap, this.caption});

  final PagesProjectInfo project;
  final VoidCallback? onTap;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = project.latestDeployment;
    final status = deployStatusLabel(context, d?.status);
    final reason = pagesAttentionReason(context, project);
    final when = whenLabel(context, d?.lastActivity);
    return Strip(
      title: project.name,
      family: Family.compute,
      caption: caption ?? when,
      onTap: onTap,
      cocked: reason != null,
      reason: reason,
      semanticLabel: [project.name, status, ?d?.branch, when, ?reason].join(', '),
      fields: [
        StripField(l.pagesFieldStatus, status, color: deployStatusColor(context, d?.status)),
        StripField(l.pagesFieldBranch, d?.branch ?? '—', data: d?.branch != null),
      ],
    );
  }
}

/// One Pages deployment in a project's list.
class PagesDeploymentStrip extends StatelessWidget {
  const PagesDeploymentStrip({super.key, required this.deployment, this.onTap, this.onLongPress, this.live = false});

  final PagesDeployment deployment;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Currently serving production.
  final bool live;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final d = deployment;
    final status = deployStatusLabel(context, d.status);
    final env = d.isProduction ? l.pagesEnvProduction : l.pagesEnvPreview;
    final when = whenLabel(context, d.createdOn);
    final title = d.commitTitle;
    return Strip(
      title: d.displayId,
      family: Family.compute,
      caption: [env, if (live) l.pagesLiveMarker].join(' · '),
      onTap: onTap,
      onLongPress: onLongPress,
      semanticLabel: l.pagesDeploymentSemantics(d.displayId, status, env, d.branch ?? '—', when) +
          (live ? ', ${l.pagesLiveMarker}' : '') +
          (title == null ? '' : ', $title'),
      detail: title == null ? null : Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      fields: [
        StripField(l.pagesFieldStatus, status, color: deployStatusColor(context, d.status)),
        StripField(l.pagesFieldBranch, d.branch ?? '—', data: d.branch != null),
        StripField(l.pagesFieldWhen, when, flex: 2),
      ],
    );
  }
}
