import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../core/accounts/account.dart';
import '../core/adaptive/ep_icons.dart';
import '../core/adaptive/ep_widgets.dart';
import '../core/adaptive/layout.dart';
import '../core/adaptive/platform.dart';
import '../core/l10n.dart';
import '../core/live/live_refresh.dart';
import '../core/notify/alerts.dart';
import '../core/notify/app_badge.dart';
import '../core/providers.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/account_avatar.dart';
import '../features/accounts/account_signals.dart';
import '../features/budget/data/billable_usage.dart';
import '../features/budget/presentation/budget_widgets.dart';
import '../features/compute/data/compute_providers.dart';
import '../features/mail/data/delivery_watch.dart';
import '../features/mail/data/mail_live.dart';
import '../features/mail/mail_routes.dart';
import '../features/today/attention.dart';
import '../features/zones/data/zones_providers.dart';
import 'account_switcher.dart';
import 'sidebar.dart';

/// Top-level navigation: iOS tab bar, Android navigation bar (compact) or rail (≥ 600 dp).
/// Today carries the active account's "Needs you" count, Mail its unread
/// count. While another account is being opened, a cover replaces the tabs.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with TickerProviderStateMixin {
  static const _tabs = [EpIcon.today, EpIcon.domains, EpIcon.mail, EpIcon.compute, EpIcon.settings];
  static const _mailTab = 2;

  StatefulNavigationShell get shell => widget.shell;

  /// The tabs fade back in after an account switch.
  late final AnimationController _fade;
  late final AppLifecycleListener _lifecycle;
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Budget alerts: one subscription per account.
  final _budgetAlerts = <String, ProviderSubscription<Object?>>{};

  /// Delivery alerts: the account on screen only (its checks use GraphQL).
  ProviderSubscription<Object?>? _deliveryAlerts;

  void _go(int i) {
    if (ref.read(switchingProvider) != null) return; // the tabs are being rebuilt
    shell.goBranch(i, initialLocation: i == shell.currentIndex);
  }

  /// Wide windows: whether the user hid the docked sidebar.
  bool _dockHidden = false;

  /// Narrower sidebar windows: the sidebar slid in over the content.
  bool _overlayOpen = false;
  late final AnimationController _overlay;

  void _toggleSidebar() {
    if (EpLayout.sidebarDocked(context)) {
      setState(() => _dockHidden = !_dockHidden);
    } else {
      _slideSidebar(!_overlayOpen);
    }
  }

  void _slideSidebar(bool open) {
    setState(() => _overlayOpen = open);
    if (reduceMotion(context)) {
      _overlay.value = open ? 1 : 0;
    } else if (open) {
      _overlay.forward();
    } else {
      _overlay.reverse();
    }
  }

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 220), value: 1);
    _overlay = AnimationController(vsync: this, duration: const Duration(milliseconds: 280));
    _listen();
    // Token expiry can change in the dashboard at any time: re-read it on
    // open and whenever the app comes back.
    ref.read(vaultProvider.notifier).refreshExpiry();
    _lifecycle = AppLifecycleListener(onResume: () => ref.read(vaultProvider.notifier).refreshExpiry());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A window that grows wide enough to dock the sidebar drops the slid-in one.
    if (_overlayOpen && EpLayout.sidebarDocked(context)) {
      _overlayOpen = false;
      _overlay.value = 0;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _fade.dispose();
    _overlay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final labels = [l.tabToday, l.tabDomains, l.tabMail, l.tabCompute, l.tabSettings];
    final switching = ref.watch(switchingProvider);
    final active = ref.watch(activeAccountProvider)?.id;
    final unread = active == null ? 0 : ref.watch(mailLiveProvider.select((s) => s.unreadByAccount[active] ?? 0));
    final attention = active == null ? 0 : ref.watch(needsYouProvider(active).select((a) => a.length));
    // Keeps the other accounts' signals live for the avatar's dot: the
    // avatar sits on tab pages, whose listeners pause while offstage.
    ref.watch(otherAccountsDotProvider);
    final counts = [attention, 0, unread, 0, 0];
    String? badgeLabel(int i) => counts[i] == 0 ? null : (i == 0 ? l.tabNeedsYou(counts[i]) : l.tabBadge(counts[i]));

    Widget icon(int i, IconData data, {Color? color}) => _TabBadge(
      count: counts[i],
      color: i == 0 ? c.attention : c.tint,
      textColor: i == 0 ? c.onAttention : c.onTint,
      child: Icon(data, color: color),
    );

    // Taking the shell out of the tree for a frame disposes every tab stack
    // of the previous account (see switchAccountIn). The tabs only exist for
    // an active account: not while the vault loads, nor once the last
    // account is removed (on the way to Welcome).
    final body = switching != null
        ? _SwitchCover(accountId: switching)
        : active == null
        ? ColoredBox(color: c.canvas, child: const SizedBox.expand())
        : FadeTransition(opacity: _fade, child: shell);

    // iPad and other wide windows: a sidebar instead of the tab bar.
    if (EpLayout.sidebar(context)) {
      final docked = EpLayout.sidebarDocked(context);
      final sidebar = EpSidebar(
        selected: shell.currentIndex,
        onSelect: (i) {
          _go(i);
          if (_overlayOpen) _slideSidebar(false);
        },
        items: [
          for (var i = 0; i < _tabs.length; i++)
            SidebarItem(
              icon: _tabs[i].cupertino,
              label: labels[i],
              count: counts[i],
              urgent: i == 0,
              spoken: badgeLabel(i),
            ),
        ],
      );
      return Scaffold(
        body: EpSidebarScope(
          shown: docked ? !_dockHidden : _overlayOpen,
          toggle: _toggleSidebar,
          child: EpSidebarFrame(
            docked: docked,
            dockHidden: _dockHidden,
            overlay: _overlay,
            onDismiss: () => _slideSidebar(false),
            dismissLabel: l.sidebarHide,
            sidebar: sidebar,
            body: body,
          ),
        ),
      );
    }

    if (isCupertino(context)) {
      return Scaffold(
        body: body,
        // Light bar on a hairline; the active tab's glyph is the brand's
        // orange mark, its label stays ink.
        bottomNavigationBar: CupertinoTabBar(
          currentIndex: shell.currentIndex,
          onTap: _go,
          backgroundColor: c.surface.withValues(alpha: 0.94),
          activeColor: c.ink,
          inactiveColor: c.inkMuted,
          border: Border(top: BorderSide(color: c.hairline, width: 0.5)),
          items: [
            for (var i = 0; i < _tabs.length; i++)
              BottomNavigationBarItem(
                icon: Semantics(label: badgeLabel(i), excludeSemantics: true, child: icon(i, _tabs[i].cupertino)),
                activeIcon: Semantics(
                  label: badgeLabel(i),
                  excludeSemantics: true,
                  child: icon(i, _tabs[i].cupertino, color: c.brand),
                ),
                label: labels[i],
              ),
          ],
        ),
      );
    }

    if (MediaQuery.sizeOf(context).width >= EpLayout.railMinWidth) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (var i = 0; i < _tabs.length; i++)
                  NavigationRailDestination(
                    icon: Semantics(label: badgeLabel(i), excludeSemantics: true, child: icon(i, _tabs[i].material)),
                    label: Text(labels[i]),
                  ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.hairline)),
        ),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: _go,
          destinations: [
            for (var i = 0; i < _tabs.length; i++)
              NavigationDestination(
                icon: Semantics(label: badgeLabel(i), excludeSemantics: true, child: icon(i, _tabs[i].material)),
                label: labels[i],
              ),
          ],
        ),
      ),
    );
  }

  /// App-wide side effects of live data: app icon badge, new-mail banner,
  /// budget and delivery notifications, and the other accounts' refresh.
  void _listen() {
    // App icon: unread mail in every account.
    ref.listenManual(mailLiveProvider.select((s) => s.unread), (_, n) => AppBadge.set(n), fireImmediately: true);
    ref.listenManual(mailLiveProvider.select((s) => s.lastArrivals), (_, arrivals) => _newMail(arrivals));
    ref.listenManual(accountsProvider, (_, accounts) => _watchBudgets(accounts), fireImmediately: true);
    ref.listenManual(activeAccountProvider.select((a) => a?.id), (_, id) => _watchDelivery(id), fireImmediately: true);
    ref.listenManual(switchingProvider, (was, now) {
      if (was != null && now == null && mounted && !reduceMotion(context)) _fade.forward(from: 0);
    });
    // What the other accounts' "Needs you" lists come from, every few
    // minutes: REST reads only, and none while a token nears its limit.
    ref.listenManual(liveTickProvider(LiveTier.slow), (_, _) {
      if (rateBudgetLow()) return;
      final active = ref.read(activeAccountProvider)?.id;
      for (final a in ref.read(accountsProvider)) {
        if (a.id == active) continue;
        unawaited(ref.read(zonesProvider(a.id).notifier).refresh());
        unawaited(ref.read(computeOverviewProvider(a.id).notifier).refresh());
        unawaited(ref.read(billableUsageProvider(a.id).notifier).refresh());
      }
    });
  }

  /// A banner for mail that just arrived: the account on screen first (not
  /// while Mail is open), else another account's, whose Open switches there.
  void _newMail(List<NewMailEvent> arrivals) {
    if (arrivals.isEmpty || !mounted) return;
    final l = context.l10n;
    final vault = ref.read(vaultProvider).value;
    final active = vault?.activeId;
    final here = [
      for (final a in arrivals)
        if (a.message.accountId == active) a.message,
    ];
    if (here.isNotEmpty && shell.currentIndex != _mailTab) {
      final m = here.first;
      HapticFeedback.lightImpact();
      showEpToast(
        context,
        here.length == 1 ? l.newMailFrom(m.from.display) : l.mailNotifNewMany(here.length),
        actionLabel: l.newMailOpen,
        onAction: () => here.length == 1 ? openThread(context, m.threadId, focus: m.id) : _go(_mailTab),
      );
      return;
    }
    final first = arrivals.where((a) => a.message.accountId != active).firstOrNull?.message;
    final account = vault?.accountById(first?.accountId);
    if (first == null || account == null) return;
    final theirs = [
      for (final a in arrivals)
        if (a.message.accountId == account.id) a.message,
    ];
    final container = ProviderScope.containerOf(context, listen: false);
    HapticFeedback.lightImpact();
    showEpToast(
      context,
      theirs.length == 1
          ? l.newMailInFrom(account.name, first.from.display)
          : l.newMailInMany(theirs.length, account.name),
      actionLabel: l.newMailOpen,
      onAction: () => switchAccountIn(
        container,
        account.id,
        then: theirs.length == 1 ? threadPath(first.threadId, focus: first.id) : '/mail',
      ),
    );
  }

  /// Alert titles name the account once there are several.
  String _titled(String accountId, String title) {
    final vault = ref.read(vaultProvider).value;
    final a = vault?.accountById(accountId);
    return a != null && vault!.accounts.length > 1 ? '${a.name} · $title' : title;
  }

  void _watchBudgets(List<Account> accounts) {
    final ids = {for (final a in accounts) a.id};
    for (final id in [..._budgetAlerts.keys]) {
      if (!ids.contains(id)) _budgetAlerts.remove(id)!.close();
    }
    for (final id in ids) {
      _budgetAlerts[id] ??= ref.listenManual(
        budgetSummaryProvider(id).select((b) => (b.sent, b.limit, b.cost, b.currency, b.periodEnd)),
        (_, _) => _budgetAlert(id),
      );
    }
  }

  void _budgetAlert(String accountId) {
    if (!mounted) return;
    final l = context.l10n;
    final b = ref.read(budgetSummaryProvider(accountId));
    final store = ref.read(secureStoreProvider);
    final sink = Alerts.localNotifications(_plugin, accountId);
    final n = NumberFormat.decimalPattern();
    Alerts.channelName = l.alertChannelName;
    Alerts.sendBudget(
      store: store,
      sink: sink,
      accountId: accountId,
      used: b.sent,
      limit: b.limit,
      title80: _titled(accountId, l.alertSend80Title),
      body80: l.alertSend80Body(n.format(b.sent), n.format(b.limit)),
      title100: _titled(accountId, l.alertSend100Title),
      body100: l.alertSend100Body,
    );
    if (b.cost case final cost?) {
      Alerts.usageCost(
        store: store,
        sink: sink,
        accountId: accountId,
        cost: cost,
        periodKey: b.periodEnd?.toIso8601String().substring(0, 10) ?? 'current',
        title: _titled(accountId, l.alertCostTitle),
        body: l.alertCostBody(formatMoney(context, cost, b.currency)),
      );
    }
  }

  void _watchDelivery(String? accountId) {
    _deliveryAlerts?.close();
    _deliveryAlerts = accountId == null
        ? null
        : ref.listenManual<List<DomainDelivery>?>(deliveryWatchProvider(accountId).select((d) => d.value?.data), (
            _,
            list,
          ) {
            if (!mounted) return;
            final l = context.l10n;
            final store = ref.read(secureStoreProvider);
            final sink = Alerts.localNotifications(_plugin, accountId);
            final pct = NumberFormat.percentPattern();
            Alerts.channelName = l.alertChannelName;
            for (final d in list ?? const <DomainDelivery>[]) {
              Alerts.delivery(
                store: store,
                sink: sink,
                accountId: accountId,
                domain: d.domain,
                low: d.low,
                title: _titled(accountId, l.alertDeliveryTitle(d.domain)),
                body: l.alertDeliveryBody(d.rate == null ? '—' : pct.format(d.rate)),
              );
            }
          });
  }
}

/// Stands in for the tabs while they're rebuilt for another account: its
/// avatar and name on the ground colour (the tab bar stays).
class _SwitchCover extends ConsumerWidget {
  const _SwitchCover({required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = EpColors.of(context);
    final a = ref.watch(vaultProvider.select((v) => v.value?.accountById(accountId)));
    return SizedBox.expand(
      child: ColoredBox(
        color: c.canvas,
        child: a == null
            ? null
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AccountAvatar(account: a, size: 56),
                    const SizedBox(height: EpSpace.md),
                    Text(a.name, textAlign: TextAlign.center, style: EpType.title(context, size: 22)),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Count badge on a tab icon. Grows in with a short scale when it first
/// appears; no motion when the user asked for less.
class _TabBadge extends StatelessWidget {
  const _TabBadge({required this.count, required this.color, required this.textColor, required this.child});
  final int count;
  final Color color;
  final Color textColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shown = count > 0;
    // Tab bars cap their own labels; an unbounded badge at accessibility
    // sizes would poke out of the bar and get clipped.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Badge(
        isLabelVisible: shown,
        backgroundColor: color,
        textColor: textColor,
        offset: const Offset(8, -2),
        label: AnimatedSwitcher(
          duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 220),
          transitionBuilder: (child, a) => ScaleTransition(
            scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
            child: child,
          ),
          child: Text(count > 99 ? '99+' : '$count', key: ValueKey(count)),
        ),
        child: child,
      ),
    );
  }
}
