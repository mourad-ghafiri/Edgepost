import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/notify/alerts.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../mail/data/mail_live.dart';
import '../../mail/data/mail_models.dart';
import '../../mail/data/mail_providers.dart';
import '../../mail/data/mail_settings.dart';
import '../../mail/presentation/mail_setup_screen.dart' show pickSendLimit;
import '../../mail/presentation/mail_widgets.dart' show describeMailError;
import '../data/billable_usage.dart';
import 'budget_widgets.dart';

/// Where the money goes: this period's usage per service, what the plan
/// includes, and the sending limit that keeps email inside it.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final account = ref.watch(activeAccountProvider)!.id;
    final usage = ref.watch(billableUsageProvider(account));
    final b = ref.watch(budgetSummaryProvider(account));
    final send = ref.watch(mailLiveProvider.select((s) => s.usageByAccount[account]));
    final hasMail = ref.watch(mailServiceProvider(account)) != null;
    final alerts = ref.watch(notificationPrefsProvider).value ?? const AlertPrefs();
    final fmt = NumberFormat.decimalPattern();
    final date = DateFormat.yMMMd();
    final a = usage.value?.data;

    Future<void> pickLimit(SendUsage u) async {
      final v = await pickSendLimit(context, u.limit);
      if (v == null || v == u.limit) return;
      try {
        await ref.read(mailClientProvider(account)).putConfig({'monthlySendLimit': v});
        await ref.read(mailLiveProvider.notifier).sync();
        if (context.mounted) showEpToast(context, l.mailBudgetSaved);
      } on Object catch (e) {
        if (context.mounted) showEpToast(context, describeMailError(context, e));
      }
    }

    return EpPage(
      title: l.budgetScreenTitle,
      largeTitle: false,
      subtitle: usage.value == null ? null : SyncLine(synced: usage.value!),
      onRefresh: () async {
        await ref.read(billableUsageProvider(account).notifier).refresh();
        await ref.read(mailLiveProvider.notifier).sync();
      },
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
            child: BudgetStrip(accountId: account, showHint: false),
          ),
        ),
        if (a != null)
          SliverToBoxAdapter(
            child: EpSection(
              header: a.periodStart != null && a.periodEnd != null
                  ? '${l.budgetServices} · ${l.budgetPeriod(date.format(a.periodStart!.toLocal()), date.format(a.periodEnd!.toLocal()))}'
                  : l.budgetServices,
              footer: l.budgetAlpha,
              children: a.services.isEmpty
                  ? [EpTile(title: Text(l.budgetServicesEmpty))]
                  : [
                      for (final s in a.services)
                        EpTile(
                          title: Text(s.name),
                          subtitle: Text(
                            '${fmt.format(s.quantity)} ${s.unit}'.trim(),
                            style: EpType.numbers(TextStyle(color: c.inkMuted, fontSize: 13)),
                          ),
                          additionalInfo: Text(
                            formatMoney(context, s.cost, a.currency),
                            style: EpType.numbers(TextStyle(color: s.cost > 0.004 ? c.attention : c.inkMuted)),
                          ),
                        ),
                    ],
            ),
          ),
        if (!b.hasBilling || usage.hasError)
          SliverToBoxAdapter(
            child: EpSection(
              children: [
                EpTile(
                  leading: EpIconView(EpIcon.info, color: c.inkMuted),
                  title: Text(
                    usage.hasError ? l.budgetUnavailable(describeError(context, usage.error!)) : l.budgetNoBilling,
                  ),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: EpSection(
            footer: l.budgetAlertsHelp,
            children: [
              EpSwitchTile(
                title: l.budgetAlertsTitle,
                value: alerts.budget,
                onChanged: (v) async {
                  final ok = await ref.read(notificationPrefsProvider.notifier).set(budget: v);
                  if (!ok && context.mounted) showEpToast(context, l.settingsNotificationsDenied);
                },
              ),
            ],
          ),
        ),
        if (hasMail)
          SliverToBoxAdapter(
            child: EpSection(
              header: l.budgetSending,
              children: [
                EpTile(
                  title: Text(l.budgetSendingLimit),
                  subtitle: send == null ? null : Text(l.mailBudgetUsage(fmt.format(send.used), fmt.format(send.limit))),
                  additionalInfo: Text(send == null ? '—' : (send.limit == 0 ? l.mailBudgetOff : fmt.format(send.limit))),
                  onTap: send == null ? null : () => pickLimit(send),
                ),
              ],
            ),
          ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.budgetIncluded,
            footer: l.budgetIncludedSource,
            children: [
              EpTile(title: Text(l.budgetIncWorkers)),
              EpTile(title: Text(l.budgetIncD1)),
              EpTile(title: Text(l.budgetIncR2)),
              EpTile(title: Text(l.budgetIncEmail)),
              EpTile(
                leading: EpIconView(EpIcon.external, color: c.tint),
                title: Text(l.budgetOpenBilling, style: TextStyle(color: c.tint)),
                onTap: () => launchUrl(
                  Uri.parse('https://dash.cloudflare.com/?to=/:account/billing'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
