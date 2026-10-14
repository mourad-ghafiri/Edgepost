import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/account_switcher.dart';
import '../../core/accounts/credential.dart';
import '../../core/adaptive/ep_icons.dart';
import '../../core/adaptive/ep_page.dart';
import '../../core/adaptive/ep_widgets.dart';
import '../../core/cloudflare/models.dart';
import '../../core/l10n.dart';
import '../../core/live/live_refresh.dart';
import '../../core/providers.dart';
import '../../core/strip/strip.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/account_avatar.dart';
import '../../core/widgets/sync_line.dart';
import '../accounts/account_signals.dart';
import '../analytics/data/traffic_providers.dart';
import '../analytics/presentation/format.dart';
import '../budget/data/billable_usage.dart';
import '../budget/presentation/budget_widgets.dart';
import '../compute/data/compute_providers.dart';
import '../compute/presentation/compute_screen.dart' show pagesPath;
import '../compute/presentation/compute_strips.dart';
import '../email_routing/presentation/routing_widgets.dart' show routingAttentionReason;
import '../mail/data/delivery_watch.dart';
import '../mail/data/mail_live.dart';
import '../mail/data/mail_models.dart';
import '../mail/data/mail_providers.dart';
import '../mail/mail_routes.dart' show openThread;
import '../mail/presentation/mail_widgets.dart'
    show MessageStrip, describeMailError, isMailServiceMissing, setUpMailAgain;
import '../zones/data/zones_providers.dart';
import '../zones/presentation/zone_strip.dart';
import 'attention.dart';

/// The board: what needs the user first, then what arrived, what shipped and
/// how the domains are doing; last, other accounts with something waiting.
/// Every strip opens its subject.
class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final account = ref.watch(activeAccountProvider)!.id;
    final zones = ref.watch(zonesProvider(account));
    final compute = ref.watch(computeOverviewProvider(account)).value?.data;
    final traffic = ref.watch(fleetTrafficProvider(account)).value?.data;
    final servicesAsync = ref.watch(mailServicesProvider);
    final hasMail = servicesAsync.value?[account] != null;
    final inboxAsync = hasMail ? ref.watch(mailListProvider((account, const MailQuery()))) : null;
    // Its service deleted from Cloudflare: no inbox to show, cached or not.
    final mailGone = isMailServiceMissing(inboxAsync?.error) || isMailServiceMissing(inboxAsync?.value?.refreshError);
    final inbox = mailGone ? null : inboxAsync?.value;
    final patches = ref.watch(mailPatchesProvider);
    final needs = ref.watch(needsYouProvider(account));
    final budgetCocked = needs.any((a) => a is BudgetAttention);
    final hasAnalytics =
        ref.watch(accessProvider.select((a) => a.best(account, Capability.analytics))) != CapState.denied;

    Future<void> refresh() async {
      await Future.wait([
        ref.read(zonesProvider(account).notifier).refresh(),
        ref.read(computeOverviewProvider(account).notifier).refresh(),
        ref.read(fleetTrafficProvider(account).notifier).refresh(),
        ref.read(billableUsageProvider(account).notifier).refresh(),
        ref.read(deliveryWatchProvider(account).notifier).refresh(),
        ref.read(mailLiveProvider.notifier).sync(),
        if (hasMail) ref.read(mailListProvider((account, const MailQuery())).notifier).refresh(),
      ]);
      ref.invalidate(mailboxesProvider(account));
    }

    final zoneList = zones.value?.data ?? const <Zone>[];
    final unread = inbox == null
        ? const <MessageSummary>[]
        : applyPatches(inbox.messages, patches, MailFolder.inbox).where((m) => !m.read && !m.outgoing).toList();
    final budget = BudgetStrip(
      key: const ValueKey('budget'),
      accountId: account,
      onTap: () => context.push('/today/budget'),
    );

    final page = EpPage(
      title: l.tabToday,
      account: true,
      subtitle: zones.value == null ? null : SyncLine(synced: zones.value!),
      onRefresh: refresh,
      slivers: [
        if (zones.isLoading && !zones.hasValue)
          const EpFill(child: EpLoading())
        else if (zones.hasError && !zones.hasValue)
          EpFill(
            child: EpErrorView(error: zones.error!, onRetry: () => ref.invalidate(zonesProvider(account))),
          )
        else
          SliverList.list(
            children: [
              // A cocked budget is something that needs the user: it leads
              // "Needs you" (and the tab badge counts it there). A calm one
              // sits after the mail.
              SettlingStripBay(
                title: l.todayNeedsYou,
                settledNote: l.todayBackInLine,
                empty: _Quiet(icon: EpIcon.checkCircle, text: l.todayAllClear),
                children: [for (final a in needs) a is BudgetAttention ? budget : _attentionStrip(context, account, a)],
              ),
              StripBay(
                title: l.todayInbound,
                count: hasMail && !mailGone ? unread.length : null,
                trailing: !hasMail || unread.length <= 5
                    ? null
                    : EpTextButton(label: l.todaySeeAll(unread.length), onPressed: () => context.go('/mail')),
                // Only say "no unread mail" when the inbox actually loaded.
                empty: servicesAsync.isLoading && !servicesAsync.hasValue
                    ? const _Pending()
                    : !hasMail
                    ? EpTile(
                        leading: EpIconView(EpIcon.mail, color: EpColors.of(context).tint),
                        title: Text(l.todaySetUpMail),
                        onTap: () => context.push('/mail/setup'),
                      )
                    : mailGone
                    ? EpTile(
                        leading: EpIconView(EpIcon.warning, color: EpColors.of(context).attention),
                        title: Text(l.mailServiceMissingTitle),
                        subtitle: Text(l.mailServiceSetUpAgain),
                        onTap: () => setUpMailAgain(context, ref, account),
                      )
                    : inbox == null && (inboxAsync?.hasError ?? false)
                    ? _Quiet(icon: EpIcon.cloud, text: describeMailError(context, inboxAsync!.error!), ok: false)
                    : inbox == null
                    ? const _Pending()
                    : _Quiet(icon: EpIcon.inbox, text: l.todayNoUnread),
                children: [
                  for (final m in unread.take(5))
                    MessageStrip(
                      message: m,
                      onTap: () => openThread(context, m.threadId, focus: m.id),
                    ),
                ],
              ),
              if (!budgetCocked) StripBay(title: l.budgetTitle, children: [budget]),
              if (compute != null && compute.pages.isNotEmpty) _deploys(context, compute),
              _traffic(context, zoneList, traffic, hasAnalytics),
              _otherAccounts(context, ref, account),
            ],
          ),
      ],
    );
    // Medium: Cloudflare lists. Slow: analytics and billing. Mail and the
    // sending budget update on the app-wide fast pulse.
    return LivePoll(
      tier: LiveTier.medium,
      onTick: (ref) {
        ref.read(zonesProvider(account).notifier).refresh();
        ref.read(computeOverviewProvider(account).notifier).refresh();
      },
      child: LivePoll(
        tier: LiveTier.slow,
        onTick: (ref) {
          ref.read(fleetTrafficProvider(account).notifier).refresh();
          ref.read(billableUsageProvider(account).notifier).refresh();
          ref.read(deliveryWatchProvider(account).notifier).refresh();
        },
        child: page,
      ),
    );
  }

  /// The strip for one item of "Needs you".
  Widget _attentionStrip(BuildContext context, String accountId, Attention a) {
    final l = context.l10n;
    final date = DateFormat.yMMMd();
    final key = ValueKey(a.key);
    return switch (a) {
      BudgetAttention() => const SizedBox.shrink(),
      ZoneAttention(:final zone) => ZoneStrip(key: key, zone: zone, onTap: () => context.push('/domains/${zone.id}')),
      PagesAttention(:final project) => PagesProjectStrip(
        key: key,
        project: project,
        onTap: () => context.push(pagesPath(project.name)),
      ),
      RegistrarAttention(:final domain) => Strip(
        key: key,
        title: domain.name,
        family: Family.domains,
        cocked: true,
        reason: switch (domain.daysLeft()) {
          final d? when d >= 0 => l.todayReasonRegistrar(d),
          _ => l.todayReasonRegistrarExpired,
        },
        fields: [
          StripField(l.todayFieldExpires, domain.expiresAt == null ? '—' : date.format(domain.expiresAt!.toLocal())),
        ],
        onTap: () => context.push('/compute/registrar'),
      ),
      TokenAttention(:final token) => Strip(
        key: key,
        title: token.label,
        family: Family.neutral,
        cocked: true,
        reason: l.todayReasonTokenExpiry(token.expiresOn!.difference(DateTime.now()).inDays.clamp(0, 999)),
        fields: [StripField(l.todayFieldToken, date.format(token.expiresOn!.toLocal()))],
        onTap: () => context.push('/settings/account/$accountId'),
      ),
      MailUpdateAttention(:final service, :final bundled) => Strip(
        key: key,
        title: l.todayMailServiceCallsign,
        family: Family.mail,
        cocked: true,
        reason: l.todayReasonMailUpdate(bundled),
        fields: [StripField(l.todayFieldMail, service.workerVersion)],
        onTap: () => context.push('/mail/setup'),
      ),
      RoutingAttention(:final zone, :final overview) => ZoneStrip(
        key: key,
        zone: zone,
        reason: routingAttentionReason(context, overview),
        onTap: () => context.push('/domains/${zone.id}/email'),
      ),
      DeliveryAttention(:final zone, :final delivery) => ZoneStrip(
        key: key,
        zone: zone,
        reason: l.todayReasonDelivery(NumberFormat.percentPattern().format(delivery.rate)),
        onTap: () => context.push('/mail/health'),
      ),
    };
  }

  /// One strip per other account with something waiting (none with a
  /// single account); a tap opens that account.
  Widget _otherAccounts(BuildContext context, WidgetRef ref, String active) {
    final l = context.l10n;
    final waiting = [
      for (final a in ref.watch(accountsProvider))
        if (a.id != active) (a, ref.watch(accountSignalProvider(a.id))),
    ].where((e) => e.$2.any).toList();
    if (waiting.isEmpty) return const SizedBox.shrink();
    return StripBay(
      title: l.todayOtherAccounts,
      children: [
        for (final (a, s) in waiting)
          Strip(
            key: ValueKey('account:${a.id}'),
            leading: AccountAvatar(account: a, size: 28),
            title: a.name,
            family: Family.neutral,
            cocked: s.needsYou > 0,
            fields: [
              StripField(l.todayFieldNeedsYou, '${s.needsYou}'),
              StripField(l.todayFieldUnread, '${s.unread}'),
            ],
            onTap: () => switchAccount(context, a.id),
          ),
      ],
    );
  }

  Widget _deploys(BuildContext context, ComputeOverview compute) {
    final l = context.l10n;
    final recent = compute.pages.where((p) => p.latestDeployment != null && !pagesNeedsYou(p)).toList()
      ..sort(
        (a, b) => (b.latestDeployment!.lastActivity ?? DateTime(0)).compareTo(
          a.latestDeployment!.lastActivity ?? DateTime(0),
        ),
      );
    if (recent.isEmpty) return const SizedBox.shrink();
    return StripBay(
      title: l.todayDeploys,
      count: recent.length,
      trailing: recent.length <= 4
          ? null
          : EpTextButton(label: l.todaySeeAll(recent.length), onPressed: () => context.go('/compute')),
      children: [
        for (final p in recent.take(4)) PagesProjectStrip(project: p, onTap: () => context.push(pagesPath(p.name))),
      ],
    );
  }

  Widget _traffic(BuildContext context, List<Zone> zones, Map<String, ZoneTraffic>? traffic, bool hasAnalytics) {
    final l = context.l10n;
    if (!hasAnalytics) {
      return StripBay(
        title: l.todayTraffic,
        empty: _Quiet(icon: EpIcon.chart, text: l.todayNoAnalytics),
        children: const [],
      );
    }
    if (traffic == null || traffic.isEmpty) return const SizedBox.shrink();
    final totals = traffic.values.fold<(int, int, int, int)>((
      0,
      0,
      0,
      0,
    ), (a, t) => (a.$1 + t.requests, a.$2 + t.bytes, a.$3 + t.cachedRequests, a.$4 + t.threats));
    final byZone = {for (final z in zones) z.id: z};
    final top = traffic.entries.where((e) => byZone.containsKey(e.key)).toList()
      ..sort((a, b) => b.value.requests.compareTo(a.value.requests));
    return StripBay(
      title: l.todayTraffic,
      children: [
        Strip(
          title: l.todayFleetCallsign,
          caption: l.todayFleetCaption(traffic.length),
          family: Family.domains,
          fields: [
            StripField(l.todayFieldRequests, formatCompact(totals.$1)),
            StripField(l.todayFieldBandwidth, formatBytes(totals.$2)),
            StripField(l.todayFieldCached, formatPercent(totals.$1 == 0 ? 0 : totals.$3 / totals.$1)),
          ],
        ),
        for (final e in top.take(5))
          ZoneStrip(
            zone: byZone[e.key]!,
            onTap: () => context.push('/domains/${e.key}/analytics'),
            extraFields: [StripField(l.todayFieldRequests, formatCompact(e.value.requests))],
          ),
      ],
    );
  }
}

class _Quiet extends StatelessWidget {
  const _Quiet({required this.icon, required this.text, this.ok = true});
  final EpIcon icon;
  final String text;

  /// Green when it's good news ("all clear"); muted when it's a gap.
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: EpSpace.sm),
      child: Row(
        children: [
          EpIconView(icon, size: 18, color: ok ? c.ok : c.caution),
          const SizedBox(width: EpSpace.sm),
          Expanded(
            child: Text(text, style: TextStyle(color: c.inkMuted)),
          ),
        ],
      ),
    );
  }
}

/// A bay still loading: a small spinner, never a false all-clear.
class _Pending extends StatelessWidget {
  const _Pending();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.symmetric(vertical: EpSpace.md),
    child: Align(alignment: Alignment.centerLeft, child: CircularProgressIndicator.adaptive()),
  );
}
