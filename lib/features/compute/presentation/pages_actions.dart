import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/l10n.dart';
import '../data/compute_providers.dart';

/// Rollback applies to production and needs an earlier successful deployment
/// (https://developers.cloudflare.com/api/resources/pages/subresources/projects/subresources/deployments/methods/rollback/).
bool canRollbackPages(PagesDeployment d, PagesProjectInfo? project) =>
    d.isProduction && d.status == DeployStatus.success && project?.canonicalDeployment?.id != d.id;

/// "a1b2c3d4 on main (Fix header)" for confirmations.
String pagesDeploymentName(BuildContext context, PagesDeployment d) {
  final l = context.l10n;
  final title = d.commitTitle;
  final base = d.branch == null ? d.displayId : l.pagesDeploymentOnBranch(d.displayId, d.branch!);
  return title == null ? base : '$base ($title)';
}

Future<void> openExternal(String url) async {
  final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Starts a new build from [d]'s commit. Returns the new deployment.
Future<PagesDeployment?> retryPagesDeployment(
  BuildContext context,
  WidgetRef ref,
  PagesKey key,
  PagesDeployment d,
) async {
  final l = context.l10n;
  try {
    final created = await ref.read(pagesProjectProvider(key).notifier).retry(d.id);
    if (context.mounted) showEpToast(context, l.pagesRetryStarted(d.branch ?? d.displayId));
    return created;
  } on CfException catch (e) {
    if (context.mounted) showEpToast(context, describeError(context, e, permission: Capability.pages.permission));
    return null;
  }
}

/// Confirms, then points production back at [d].
Future<bool> rollbackPagesDeployment(
  BuildContext context,
  WidgetRef ref,
  PagesKey key,
  PagesDeployment d,
) async {
  final l = context.l10n;
  final ok = await showEpConfirm(
    context,
    title: l.pagesRollbackTitle(d.displayId),
    message: l.pagesRollbackMessage(key.project, pagesDeploymentName(context, d)),
    confirmLabel: l.pagesRollbackConfirm,
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  try {
    await ref.read(pagesProjectProvider(key).notifier).rollback(d.id);
    if (context.mounted) showEpToast(context, l.pagesRollbackDone(d.displayId));
    return true;
  } on CfException catch (e) {
    if (context.mounted) showEpToast(context, describeError(context, e, permission: Capability.pages.permission));
    return false;
  }
}

enum _DeployAction { open, retry, rollback, copy }

/// Long-press menu on a deployment strip.
Future<void> showPagesDeploymentActions(
  BuildContext context,
  WidgetRef ref,
  PagesKey key,
  PagesDeployment d,
  PagesProjectInfo? project,
) async {
  final l = context.l10n;
  final choice = await showEpActionSheet<_DeployAction>(
    context,
    title: pagesDeploymentName(context, d),
    actions: [
      if (d.url != null) EpSheetAction(label: l.pagesOpenDeployment, value: _DeployAction.open, icon: EpIcon.external),
      EpSheetAction(label: l.pagesRetry, value: _DeployAction.retry, icon: EpIcon.refresh),
      if (canRollbackPages(d, project))
        EpSheetAction(label: l.pagesRollbackAction, value: _DeployAction.rollback, icon: EpIcon.undo, destructive: true),
      EpSheetAction(label: l.pagesCopyId, value: _DeployAction.copy, icon: EpIcon.copy),
    ],
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case _DeployAction.open:
      await openExternal(d.url!);
    case _DeployAction.retry:
      await retryPagesDeployment(context, ref, key, d);
    case _DeployAction.rollback:
      await rollbackPagesDeployment(context, ref, key, d);
    case _DeployAction.copy:
      await copyWithToast(context, d.id);
  }
}
