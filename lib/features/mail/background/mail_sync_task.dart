import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:workmanager/workmanager.dart';

import '../../../core/accounts/account.dart';
import '../../../core/notify/alerts.dart';
import '../../../core/storage/secure_store.dart';
import '../../../core/theme/tokens.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/mail_client.dart';
import '../data/mail_models.dart';
import '../mail_routes.dart' show threadPath;

/// Background task identifier. Must match `BGTaskSchedulerPermittedIdentifiers`
/// in ios/Runner/Info.plist and the AppDelegate registration.
const kMailSyncTask = 'com.mouradghafiri.edgepost.mailsync';
const _channelId = 'new_mail';

/// Route a tapped notification should open; the app listens and navigates.
final ValueNotifier<String?> pendingNotificationRoute = ValueNotifier(null);

@pragma('vm:entry-point')
void mailSyncDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await MailSyncWorker.run();
    } on Object catch (e) {
      if (kDebugMode) debugPrint('mail sync failed: $e');
    }
    return true; // never ask the OS to retry aggressively; next period will
  });
}

/// One background pass: asks the mail service of every added account for
/// changes since the last pass, posts a local notification for new unread
/// inbound mail, and checks each account's sending budget against its 80% /
/// 100% alerts.
abstract final class MailSyncWorker {
  static Future<int> run({SecureStore? store, FlutterLocalNotificationsPlugin? notifications}) async {
    final s = store ?? SecureStore();
    final settings = await s.readSettings();
    final prefs = AlertPrefs.fromSettings(settings);
    if (!prefs.mail && !prefs.budget) return 0;
    final vault = await s.readVault();
    if (vault == null) return 0;
    final accounts = (vault['accounts'] as List).cast<Map<String, dynamic>>().map(Account.fromJson).toList();
    final plugin = notifications ?? FlutterLocalNotificationsPlugin();
    final l = lookupAppLocalizations(const Locale('en'));
    final n = NumberFormat.decimalPattern();
    await MailSyncScheduler._init(plugin);
    Alerts.channelName = l.alertChannelName;

    // With several accounts, notifications say which one.
    String titled(Account a, String title) => accounts.length > 1 ? '${a.name} · $title' : title;

    final cursors = Map<String, dynamic>.from((settings['mail_sync_cursors'] as Map?) ?? const {});
    var total = 0;
    for (final a in accounts) {
      final j = await s.readMailService(a.id);
      if (j == null) continue;
      final svc = MailService.fromJson(j);
      final client = MailClient(baseUrl: svc.workerUrl, apiKey: svc.apiKey, accountId: svc.accountId);
      final SyncResult r;
      final since = cursors[a.id] as String?;
      try {
        r = await client.sync(since: since);
      } on MailException {
        continue;
      }
      cursors[a.id] = r.cursor;
      final fresh = since == null
          ? const <MessageSummary>[]
          : r.messages.where((m) => !m.outgoing && !m.read && m.folder == MailFolder.inbox).toList();
      if (prefs.mail && fresh.isNotEmpty) {
        await _notify(a, fresh, plugin, titled);
        total += fresh.length;
      }
      if (prefs.budget && r.sendUsage.limit > 0) {
        await Alerts.sendBudget(
          store: s,
          sink: Alerts.localNotifications(plugin, a.id),
          accountId: a.id,
          used: r.sendUsage.used,
          limit: r.sendUsage.limit,
          title80: titled(a, l.alertSend80Title),
          body80: l.alertSend80Body(n.format(r.sendUsage.used), n.format(r.sendUsage.limit)),
          title100: titled(a, l.alertSend100Title),
          body100: l.alertSend100Body,
        );
      }
    }
    await s.updateSettings((latest) => latest['mail_sync_cursors'] = cursors);
    return total;
  }

  static Future<void> _notify(
    Account account,
    List<MessageSummary> fresh,
    FlutterLocalNotificationsPlugin plugin,
    String Function(Account, String) titled,
  ) async {
    final l = lookupAppLocalizations(const Locale('en'));
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        l.mailNotifChannel,
        channelDescription: l.mailNotifChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.email,
        groupKey: 'mail:${account.id}',
        color: EpColors.light.brand,
      ),
      iOS: DarwinNotificationDetails(threadIdentifier: 'mail:${account.id}'),
    );
    if (fresh.length == 1) {
      final m = fresh.single;
      await plugin.show(
        id: m.id.hashCode & 0x7fffffff,
        title: titled(account, m.from.display),
        body: m.subject.isEmpty ? m.snippet : m.subject,
        notificationDetails: details,
        payload: threadPath(m.threadId, focus: m.id, account: account.id),
      );
    } else {
      final senders = fresh.map((m) => m.from.display).toSet().take(4).join(', ');
      await plugin.show(
        id: accountNotificationBase(account.id) + 3,
        title: titled(account, l.mailNotifNewMany(fresh.length)),
        body: senders,
        notificationDetails: details,
        payload: '/mail?account=${account.id}',
      );
    }
  }
}

/// Registers / cancels the periodic check and wires notification taps.
abstract final class MailSyncScheduler {
  static bool _initialized = false;

  static Future<void> _init(FlutterLocalNotificationsPlugin plugin) async {
    if (_initialized) return;
    _initialized = true;
    await plugin.initialize(
      settings: const InitializationSettings(
        // The white Signpost silhouette (res/drawable-*/ic_stat_edgepost.png).
        android: AndroidInitializationSettings('@drawable/ic_stat_edgepost'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (r) => pendingNotificationRoute.value = r.payload,
    );
  }

  /// Wires the background dispatcher and notification taps; safe on every launch.
  static void initialize() {
    if (kIsWeb) return;
    unawaited(() async {
      try {
        await Workmanager().initialize(mailSyncDispatcher);
        final plugin = FlutterLocalNotificationsPlugin();
        await _init(plugin);
        final launch = await plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true) {
          pendingNotificationRoute.value = launch!.notificationResponse?.payload;
        }
      } on Object catch (e) {
        if (kDebugMode) debugPrint('background init failed: $e');
      }
    }());
  }

  /// Asks for notification permission and schedules the periodic check
  /// (the OS decides the actual cadence; 15 minutes is the floor).
  static Future<bool> enable() async {
    final plugin = FlutterLocalNotificationsPlugin();
    await _init(plugin);
    bool? granted;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      granted = await plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      granted = await plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
    if (granted == false) return false;
    await Workmanager().registerPeriodicTask(
      kMailSyncTask,
      kMailSyncTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
    return true;
  }

  static Future<void> disable() => Workmanager().cancelByUniqueName(kMailSyncTask);
}
