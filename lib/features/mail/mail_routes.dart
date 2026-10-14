import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/nav_keys.dart';
import '../../core/adaptive/layout.dart';
import '../../core/live/live_refresh.dart';
import 'presentation/compose_screen.dart';
import 'presentation/domain_brand_screen.dart';
import 'presentation/mail_home_screen.dart';
import 'presentation/mail_setup_screen.dart';
import 'presentation/sending_health_screen.dart';
import 'presentation/thread_screen.dart';

/// Route of a thread in the active account, scrolled to [focus]. A
/// notification adds the account it belongs to (`account=`).
String threadPath(String threadId, {String? focus, String? account}) => Uri(
  path: '/mail/thread/${Uri.encodeComponent(threadId)}',
  queryParameters: {'focus': ?focus, 'account': ?account},
).toString();

/// The thread a [threadPath] location names, with its focus, or null.
(String, String?)? threadOf(String location) {
  final uri = Uri.parse(location);
  final s = uri.pathSegments;
  if (s.length != 3 || s[0] != 'mail' || s[1] != 'thread') return null;
  return (s[2], uri.queryParameters['focus']);
}

/// A thread waiting to open beside the inbox, taken by the Mail tab.
final threadSelectionProvider = NotifierProvider<ThreadSelection, (String, String?)?>(ThreadSelection.new);

class ThreadSelection extends Notifier<(String, String?)?> {
  @override
  (String, String?)? build() => null;

  void request(String threadId, String? focus) => state = (threadId, focus);

  void clear() => state = null;
}

/// Opens a thread from anywhere: where Mail shows a split, the Mail tab comes
/// forward with the thread beside the inbox; otherwise it is pushed over the
/// tabs, as on a phone.
void openThread(BuildContext context, String threadId, {String? focus}) {
  if (EpLayout.splits(context)) {
    ProviderScope.containerOf(context, listen: false).read(threadSelectionProvider.notifier).request(threadId, focus);
    context.go('/mail');
  } else {
    context.push(threadPath(threadId, focus: focus));
  }
}

/// Shows [location] (a notification's or a banner's route) with [router]:
/// a thread opens as [openThread] does.
void showLocation(ProviderContainer container, GoRouter router, String location) {
  final thread = threadOf(location);
  final context = rootNavigatorKey.currentContext;
  if (thread != null && context != null && EpLayout.splits(context)) {
    container.read(threadSelectionProvider.notifier).request(thread.$1, thread.$2);
    router.go('/mail');
  } else {
    router.go(location);
  }
}

/// A domain's signature and logo, in the active account.
String mailDomainPath(String domain) => '/mail/domain/${Uri.encodeComponent(domain)}';

/// The Mail tab.
final GoRoute mailRoute = GoRoute(
  path: '/mail',
  builder: (c, s) => MailHomeScreen(initialDomain: s.uri.queryParameters['domain']),
  routes: [
    GoRoute(path: 'setup', builder: (c, s) => const MailSetupScreen()),
    GoRoute(
      path: 'health',
      builder: (c, s) => LivePoll(
        tier: LiveTier.slow,
        onTick: (ref) => ref.invalidate(sendingHealthProvider),
        child: const SendingHealthScreen(),
      ),
    ),
    // Above the tabs: the thread's own action bar is the only bar at the
    // bottom (no second row of icons to mis-tap).
    GoRoute(
      path: 'thread/:threadId',
      parentNavigatorKey: rootNavigatorKey,
      builder: (c, s) => ThreadScreen(threadId: s.pathParameters['threadId']!, focusId: s.uri.queryParameters['focus']),
    ),
    // Above the tabs, so compose can open it too; a sheet in a big window.
    GoRoute(
      path: 'domain/:domain',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (c, s) => formPage(c, s, DomainBrandScreen(domain: s.pathParameters['domain']!)),
    ),
    GoRoute(
      path: 'compose',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (c, s) => modalPage(c, s, ComposeScreen(args: s.extra! as ComposeArgs)),
    ),
  ],
);
