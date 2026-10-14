import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/adaptive/layout.dart';
import '../core/adaptive/platform.dart';
import '../core/live/live_refresh.dart';
import '../core/providers.dart';
import '../features/accounts/account_detail_screen.dart';
import '../features/accounts/add_account_screen.dart';
import '../features/analytics/analytics_routes.dart';
import '../features/budget/data/billable_usage.dart';
import '../features/budget/presentation/budget_screen.dart';
import '../features/compute/compute_routes.dart';
import '../features/dns/dns_routes.dart';
import '../features/email_routing/email_routing_routes.dart';
import '../features/mail/mail_routes.dart';
import '../features/onboarding/presentation/welcome_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/today/today_screen.dart';
import '../features/zone_controls/zone_controls_routes.dart';
import '../features/zones/data/zones_providers.dart';
import '../features/zones/presentation/domains_screen.dart';
import '../features/zones/presentation/zone_hub_screen.dart';
import 'nav_keys.dart';
import 'shell.dart';

/// Bridges vault changes (first account added, last one removed) into
/// go_router's redirect.
class _VaultListenable extends ChangeNotifier {
  void ping() => notifyListeners();
}

/// The routes on the root navigator, to tell when a full-screen flow
/// (compose, adding an account) covers the tabs: a tapped notification waits
/// for it to close rather than throwing it away.
class RootRoutes extends NavigatorObserver {
  final _routes = <Route<dynamic>>[];

  /// True while a page sits above the tabs (sheets and dialogs don't count).
  final covered = ValueNotifier(false);

  /// go_router also reports the tabs' own navigators here: only the root
  /// navigator's routes count.
  bool _root(Route<dynamic> route) => identical(route.navigator, navigator);

  void _changed() => covered.value = _routes.skip(1).any((r) => r.settings is Page);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_root(route)) return;
    _routes.add(route);
    _changed();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routes.remove(route)) _changed();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (_routes.remove(route)) _changed();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i < 0 || newRoute == null) return;
    _routes[i] = newRoute;
    _changed();
  }
}

final rootRoutesProvider = Provider<RootRoutes>((ref) {
  final routes = RootRoutes();
  ref.onDispose(routes.covered.dispose);
  return routes;
});

/// Refreshes [refresh] for the account on screen.
void Function(WidgetRef) _active(void Function(WidgetRef ref, String accountId) refresh) => (ref) {
  final account = ref.read(activeAccountProvider)?.id;
  if (account != null) refresh(ref, account);
};

/// A domain's hub: beside the list, choosing another domain swaps the
/// column in place; on a phone the hub slides in.
Page<void> _zonePage(BuildContext context, GoRouterState state, Widget child) => EpSplitDetail.of(context)
    ? NoTransitionPage<void>(key: state.pageKey, name: state.name, child: child)
    : isCupertino(context)
    ? CupertinoPage<void>(key: state.pageKey, name: state.name, child: child)
    : MaterialPage<void>(key: state.pageKey, name: state.name, child: child);

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _VaultListenable();
  ref.listen(vaultProvider.select((v) => (v.hasValue, v.value?.accounts.isEmpty)), (_, _) => listenable.ping());
  ref.onDispose(listenable.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/today',
    refreshListenable: listenable,
    observers: [ref.watch(rootRoutesProvider)],
    redirect: (context, state) {
      final vault = ref.read(vaultProvider);
      if (vault.isLoading && !vault.hasValue) return null;
      final empty = vault.value?.accounts.isEmpty ?? true;
      final path = state.uri.path;
      final onWelcome = path.startsWith('/welcome');
      if (empty && !onWelcome) return '/welcome';
      if (!empty && path == '/welcome') return '/today';
      return null;
    },
    routes: [
      GoRoute(
        path: '/welcome',
        builder: (c, s) => const WelcomeScreen(),
        routes: [GoRoute(path: 'token', builder: (c, s) => const AddAccountScreen(onboarding: true))],
      ),
      GoRoute(path: '/accounts/add', pageBuilder: (c, s) => modalPage(c, s, const AddAccountScreen())),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/today',
                builder: (c, s) => const TodayScreen(),
                routes: [
                  GoRoute(
                    path: 'budget',
                    builder: (c, s) => LivePoll(
                      tier: LiveTier.slow,
                      onTick: _active((ref, a) => ref.read(billableUsageProvider(a).notifier).refresh()),
                      child: const BudgetScreen(),
                    ),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              // The list, and in a split the domain's column beside it with
              // its own navigator (see DomainsLayout).
              ShellRoute(
                builder: (c, s, navigator) => LivePoll(
                  tier: LiveTier.medium,
                  onTick: _active((ref, a) => ref.read(zonesProvider(a).notifier).refresh()),
                  child: DomainsLayout(zoneId: s.pathParameters['zoneId'], navigator: navigator),
                ),
                routes: [
                  GoRoute(
                    path: '/domains',
                    builder: (c, s) => const DomainsRoot(),
                    routes: [
                      GoRoute(
                        path: ':zoneId',
                        pageBuilder: (c, s) => _zonePage(
                          c,
                          s,
                          LivePoll(
                            tier: LiveTier.medium,
                            onTick: _active((ref, a) => ref.read(zonesProvider(a).notifier).refresh()),
                            child: ZoneHubScreen(zoneId: s.pathParameters['zoneId']!),
                          ),
                        ),
                        routes: [
                          ...dnsRoutes,
                          ...zoneControlsRoutes,
                          ...analyticsRoutes,
                          ...emailRoutingRoutes,
                          ...zoneComputeRoutes,
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(routes: [mailRoute]),
          StatefulShellBranch(routes: [computeRoute]),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (c, s) => const SettingsScreen(),
                routes: [
                  GoRoute(
                    path: 'account/:id',
                    builder: (c, s) => AccountDetailScreen(accountId: s.pathParameters['id']!),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
