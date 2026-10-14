import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../storage/secure_store.dart';
import '../theme/tokens.dart';

/// Which alert families the user wants (Settings → Notifications).
class AlertPrefs {
  const AlertPrefs({this.mail = false, this.budget = false, this.delivery = false, this.offerDismissed = false});

  factory AlertPrefs.fromSettings(Map<String, dynamic> s) => AlertPrefs(
        mail: s['mail_alerts'] == true,
        budget: s['budget_alerts'] == true,
        delivery: s['delivery_alerts'] == true,
        offerDismissed: s['notif_offer_dismissed'] == true,
      );

  final bool mail;
  final bool budget;
  final bool delivery;

  /// The user answered "Not now" to the inbox offer.
  final bool offerDismissed;

  bool get any => mail || budget || delivery;

  Map<String, dynamic> toSettings() => {'mail_alerts': mail, 'budget_alerts': budget, 'delivery_alerts': delivery};
}

/// Shows one notification; [payload] is the route a tap opens.
typedef AlertSink = Future<void> Function(int id, String title, String body, String payload);

/// Notification ids are offset per account so two accounts' alerts never
/// replace each other.
int accountNotificationBase(String accountId) => (accountId.hashCode & 0x3fff) * 64 + 10000;

/// Local notifications for budget and delivery, each raised once per level
/// and account (not every refresh): the last level reached is kept in
/// settings and resets when the situation goes back to normal.
abstract final class Alerts {
  static const _stateKey = 'alert_state';

  /// Android channel name, set once from the localized strings.
  static String channelName = 'Budget and delivery';

  /// Posts alerts as local notifications, grouped per account.
  static AlertSink localNotifications(FlutterLocalNotificationsPlugin plugin, String accountId) =>
      (id, title, body, payload) => plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails('budget', channelName,
              importance: Importance.high, priority: Priority.high, groupKey: 'budget:$accountId', color: EpColors.light.brand),
          iOS: DarwinNotificationDetails(threadIdentifier: 'budget:$accountId'),
        ),
      );

  /// Returns true when [level] is higher than the last one recorded for
  /// ([accountId], [key]) (and records it). Lower levels reset the record.
  static Future<bool> _escalates(SecureStore store, String accountId, String key, String level, List<String> order) =>
      store.updateSettings((s) {
        final all = Map<String, dynamic>.from((s[_stateKey] as Map?) ?? const {});
        final state = Map<String, dynamic>.from((all[accountId] as Map?) ?? const {});
        final prev = state[key] as String?;
        state[key] = level;
        all[accountId] = state;
        s[_stateKey] = all;
        return order.indexOf(level) > order.indexOf(prev ?? order.first);
      });

  /// Sending budget: alert at 80% and at 100% of the account's limit.
  static Future<void> sendBudget({
    required SecureStore store,
    required AlertSink sink,
    required String accountId,
    required int used,
    required int limit,
    required String title80,
    required String body80,
    required String title100,
    required String body100,
  }) async {
    if (!AlertPrefs.fromSettings(await store.readSettings()).budget || limit <= 0) return;
    final ratio = used / limit;
    final level = ratio >= 1 ? '100' : (ratio >= 0.8 ? '80' : 'ok');
    if (await _escalates(store, accountId, 'send', level, const ['ok', '80', '100'])) {
      await sink(accountNotificationBase(accountId) + 1, level == '100' ? title100 : title80, level == '100' ? body100 : body80,
          '/today/budget?account=$accountId');
    }
  }

  /// First usage cost above zero in an account's billing period.
  static Future<void> usageCost({
    required SecureStore store,
    required AlertSink sink,
    required String accountId,
    required double cost,
    required String periodKey,
    required String title,
    required String body,
  }) async {
    if (!AlertPrefs.fromSettings(await store.readSettings()).budget) return;
    final level = cost > 0.004 ? 'cost:$periodKey' : 'ok';
    if (level != 'ok' && await _escalates(store, accountId, 'cost', level, ['ok', level])) {
      await sink(accountNotificationBase(accountId) + 2, title, body, '/today/budget?account=$accountId');
    }
  }

  /// Delivery rate below Cloudflare's 95% target for a sending domain.
  static Future<void> delivery({
    required SecureStore store,
    required AlertSink sink,
    required String accountId,
    required String domain,
    required bool low,
    required String title,
    required String body,
  }) async {
    if (!AlertPrefs.fromSettings(await store.readSettings()).delivery) return;
    if (await _escalates(store, accountId, 'delivery:$domain', low ? 'low' : 'ok', const ['ok', 'low'])) {
      await sink(accountNotificationBase(accountId) + 8 + (domain.hashCode & 0x1f), title, body, '/mail/health?account=$accountId');
    }
  }
}
