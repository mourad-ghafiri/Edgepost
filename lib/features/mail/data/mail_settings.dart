import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notify/alerts.dart';
import '../../../core/providers.dart';
import '../background/mail_sync_task.dart';

/// Which alerts the user turned on (Settings → Notifications). Turning any
/// on asks for notification permission and schedules the background check;
/// turning all off cancels it.
final notificationPrefsProvider = AsyncNotifierProvider<NotificationPrefs, AlertPrefs>(NotificationPrefs.new);

class NotificationPrefs extends AsyncNotifier<AlertPrefs> {
  @override
  Future<AlertPrefs> build() async => AlertPrefs.fromSettings(await ref.read(secureStoreProvider).readSettings());

  /// Returns false when the system refused notification permission.
  Future<bool> set({bool? mail, bool? budget, bool? delivery}) async {
    final cur = state.value ?? const AlertPrefs();
    final next = AlertPrefs(
      mail: mail ?? cur.mail,
      budget: budget ?? cur.budget,
      delivery: delivery ?? cur.delivery,
      offerDismissed: cur.offerDismissed,
    );
    if (next.any) {
      if (!await MailSyncScheduler.enable()) {
        state = AsyncData(cur);
        return false;
      }
    } else {
      await MailSyncScheduler.disable();
    }
    await ref.read(secureStoreProvider).updateSettings((s) => s.addAll(next.toSettings()));
    state = AsyncData(next);
    return true;
  }

  /// "Not now" on the inbox offer: it doesn't come back; Settings keeps the
  /// switches.
  Future<void> dismissOffer() async {
    await ref.read(secureStoreProvider).updateSettings((s) => s['notif_offer_dismissed'] = true);
    final cur = state.value ?? const AlertPrefs();
    state = AsyncData(AlertPrefs(mail: cur.mail, budget: cur.budget, delivery: cur.delivery, offerDismissed: true));
  }
}
