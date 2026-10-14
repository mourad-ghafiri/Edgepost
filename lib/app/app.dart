import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n.dart';
import '../core/live/live_refresh.dart';
import '../core/providers.dart';
import '../core/security/app_lock.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/appearance.dart';
import '../features/mail/background/mail_sync_task.dart';
import 'account_switcher.dart';
import 'router.dart';

class EdgepostApp extends ConsumerStatefulWidget {
  const EdgepostApp({super.key});

  @override
  ConsumerState<EdgepostApp> createState() => _EdgepostAppState();
}

class _EdgepostAppState extends ConsumerState<EdgepostApp> {
  late final RootRoutes _rootRoutes = ref.read(rootRoutesProvider);

  @override
  void initState() {
    super.initState();
    pendingNotificationRoute.addListener(_openFromNotification);
    _rootRoutes.covered.addListener(_openFromNotification);
    ref.listenManual(vaultProvider.select((v) => v.hasValue), (_, _) => _openFromNotification());
    WidgetsBinding.instance.addPostFrameCallback((_) => _openFromNotification());
  }

  @override
  void dispose() {
    pendingNotificationRoute.removeListener(_openFromNotification);
    _rootRoutes.covered.removeListener(_openFromNotification);
    super.dispose();
  }

  /// A tapped notification opens its route in its own account (switching
  /// first). It waits for the accounts to load, and for a full-screen flow
  /// (a draft, an account being added) to close rather than throw it away.
  void _openFromNotification() {
    final payload = pendingNotificationRoute.value;
    if (payload == null || payload.isEmpty) return;
    final vault = ref.read(vaultProvider);
    if (!vault.hasValue || _rootRoutes.covered.value) return;
    pendingNotificationRoute.value = null;
    final accounts = vault.value!;
    if (accounts.accounts.isEmpty) return;
    final uri = Uri.parse(payload);
    final account = accounts.accountById(uri.queryParameters['account']);
    if (account == null) {
      // The account was removed since.
      ref.read(routerProvider).go('/today');
      return;
    }
    final query = {...uri.queryParameters}..remove('account');
    final route = Uri(path: uri.path, queryParameters: query.isEmpty ? null : query).toString();
    switchAccountIn(ProviderScope.containerOf(context, listen: false), account.id, then: route);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final platform = Theme.of(context).platform;
    return MaterialApp.router(
      onGenerateTitle: (c) => c.l10n.appName,
      debugShowCheckedModeBanner: false,
      theme: buildEpTheme(platform, Brightness.light),
      darkTheme: buildEpTheme(platform, Brightness.dark),
      themeMode: ref.watch(appearanceProvider).themeMode,
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => AppLockGate(child: LiveRefreshScope(child: child ?? const SizedBox.shrink())),
    );
  }
}
