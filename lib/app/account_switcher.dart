import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/adaptive/ep_widgets.dart';
import '../core/l10n.dart';
import '../core/live/live_refresh.dart';
import '../core/providers.dart';
import '../features/mail/mail_routes.dart' show showLocation;
import 'nav_keys.dart';
import 'router.dart';

/// The account being switched to while the tab shell is torn down and
/// rebuilt; null otherwise. The shell shows a cover instead of its tabs.
final switchingProvider = NotifierProvider<Switching, String?>(Switching.new);

class Switching extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? accountId) => state = accountId;
}

/// Shows [accountId] everywhere: every tab starts again at its root, data
/// refreshes, "Switched to …" shows (unless [announce] is false), then
/// [then] (a deep link, e.g. from a notification) opens.
///
/// The tab shell keeps each tab's stack in its own state (and carries a
/// GlobalKey, so re-keying it would keep them): it's taken out of the tree for
/// a frame instead, which disposes every stack and every screen of the
/// previous account.
///
/// The screen that asks is usually inside that shell, so the switch runs on
/// the provider container (taken from [context] up front), never on the
/// caller's widget ref.
Future<void> switchAccount(BuildContext context, String accountId, {String? then}) =>
    switchAccountIn(ProviderScope.containerOf(context, listen: false), accountId, then: then);

Future<void> switchAccountIn(ProviderContainer ref, String accountId, {String? then, bool announce = true}) async {
  final vault = ref.read(vaultProvider).value;
  if (vault == null || vault.accountById(accountId) == null) return;
  final router = ref.read(routerProvider);
  if (vault.activeId == accountId) {
    if (then != null) showLocation(ref, router, then);
    return;
  }
  // Sheets, dialogs and full-screen flows of the previous account close;
  // the tab under them stays selected, back at its root.
  final tab = _tabRoot(router);
  rootNavigatorKey.currentState?.popUntil((r) => r.isFirst);
  router.go(tab);

  final switching = ref.read(switchingProvider.notifier)..set(accountId);
  await WidgetsBinding.instance.endOfFrame;
  await ref.read(vaultProvider.notifier).activate(accountId);
  switching.set(null);
  await WidgetsBinding.instance.endOfFrame;

  for (final t in LiveTier.values) {
    ref.read(liveTickProvider(t).notifier).tick();
  }
  unawaited(HapticFeedback.selectionClick());
  final ctx = rootContextForToast();
  final name = vault.accountById(accountId)!.name;
  if (announce && ctx != null && ctx.mounted) showEpToast(ctx, ctx.l10n.accountSwitched(name));
  if (then != null) showLocation(ref, router, then);
}

/// The root of the tab on screen, also under a page pushed over the tabs
/// (adding an account, compose).
String _tabRoot(GoRouter router) => switch (router.routerDelegate.currentConfiguration.matches.firstOrNull) {
      ShellRouteMatch(:final matches) => matches.first.matchedLocation,
      _ => '/today',
    };
