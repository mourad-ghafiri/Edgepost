import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/live/live_refresh.dart';
import '../../../core/providers.dart';
import 'mail_client.dart';
import 'mail_models.dart';
import 'mail_providers.dart';

/// A message that just arrived while the app was open.
class NewMailEvent {
  const NewMailEvent(this.message, this.at);
  final MessageSummary message;
  final DateTime at;
}

class MailLiveState {
  const MailLiveState({
    this.unreadByAccount = const {},
    this.usageByAccount = const {},
    this.syncedAt,
    this.lastArrivals = const [],
    this.error,
  });

  final Map<String, int> unreadByAccount;
  final Map<String, SendUsage> usageByAccount;
  final DateTime? syncedAt;

  /// Inbound unread messages from the latest sync (for banners).
  final List<NewMailEvent> lastArrivals;
  final Object? error;

  int get unread => unreadByAccount.values.fold(0, (s, n) => s + n);

  MailLiveState copyWith({
    Map<String, int>? unreadByAccount,
    Map<String, SendUsage>? usageByAccount,
    DateTime? syncedAt,
    List<NewMailEvent>? lastArrivals,
    Object? error,
    bool clearError = false,
  }) => MailLiveState(
    unreadByAccount: unreadByAccount ?? this.unreadByAccount,
    usageByAccount: usageByAccount ?? this.usageByAccount,
    syncedAt: syncedAt ?? this.syncedAt,
    lastArrivals: lastArrivals ?? this.lastArrivals,
    error: clearError ? null : (error ?? this.error),
  );
}

/// App-wide mail pulse: every fast tick (5 s, foreground only) asks the mail
/// service of every added account for changes since the last cursor, so
/// other accounts' badges and notifications stay current too. One small Worker request per
/// account, no Cloudflare API usage. Changes refresh the open mail views;
/// counters feed the Mail tab badge and the sending budget.
final mailLiveProvider = NotifierProvider<MailLive, MailLiveState>(MailLive.new);

class MailLive extends Notifier<MailLiveState> {
  static const _cursorKey = 'mail_sync_cursors';

  final Map<String, String> _cursors = {};
  bool _loaded = false;
  bool _inFlight = false;

  @override
  MailLiveState build() {
    ref.listen(liveTickProvider(LiveTier.fast), (_, _) => sync());
    ref.listen(mailServicesProvider, (_, _) => sync());
    unawaited(Future<void>.microtask(sync));
    return const MailLiveState();
  }

  Future<void> sync() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final services = (ref.read(mailServicesProvider).value ?? const <String, MailService>{}).values.toList();
      if (services.isEmpty) {
        if (state.unreadByAccount.isNotEmpty) state = const MailLiveState();
        return;
      }
      final store = ref.read(secureStoreProvider);
      if (!_loaded) {
        final s = await store.readSettings();
        _cursors.addAll(Map<String, String>.from((s[_cursorKey] as Map?) ?? const {}));
        _loaded = true;
      }
      // Only accounts still set up keep their counters (and cursors).
      final live = {for (final svc in services) svc.accountId};
      _cursors.removeWhere((account, _) => !live.contains(account));
      final unread = {
        for (final e in state.unreadByAccount.entries)
          if (live.contains(e.key)) e.key: e.value,
      };
      final usage = {
        for (final e in state.usageByAccount.entries)
          if (live.contains(e.key)) e.key: e.value,
      };
      final arrivals = <NewMailEvent>[];
      final changedThreads = <(String, String)>{};
      var changed = false;
      var cursorMoved = false;
      var newlyGone = false;
      Object? lastError;

      for (final svc in services) {
        // An account removed while an earlier one synced is skipped, and so
        // is the answer of one removed while it synced.
        bool gone() => ref.read(mailServiceProvider(svc.accountId)) == null;
        if (gone()) continue;
        try {
          final client = ref.read(mailClientProvider(svc.accountId));
          final since = _cursors[svc.accountId];
          final r = await client.sync(since: since);
          if (gone()) continue;
          unread[svc.accountId] = r.unreadTotal;
          usage[svc.accountId] = r.sendUsage;
          if (since != null && r.hasChanges) {
            changed = true;
            for (final m in r.messages) {
              changedThreads.add((m.accountId, m.threadId));
              if (!m.outgoing && !m.read && m.folder == MailFolder.inbox) arrivals.add(NewMailEvent(m, DateTime.now()));
            }
          }
          if (r.cursor != since) {
            _cursors[svc.accountId] = r.cursor;
            cursorMoved = true;
          }
        } on MailException catch (e) {
          lastError = e;
          // Deleted from Cloudflare: nothing of it counts any more, and a
          // new Worker set up in its place starts its changes from zero.
          if (e.code == 'service_missing') {
            final hadCount = unread.remove(svc.accountId) != null;
            usage.remove(svc.accountId);
            if (_cursors.remove(svc.accountId) != null) cursorMoved = true;
            // Once: the inbox shows it's gone without a pull to refresh.
            newlyGone |= hadCount;
          }
        }
      }

      // Share the cursor with the background check so it never re-announces
      // mail already seen in the app.
      if (cursorMoved) {
        final current = ref.read(mailServicesProvider).value?.keys.toSet() ?? const <String>{};
        _cursors.removeWhere((account, _) => !current.contains(account));
        final cursors = {..._cursors};
        await store.updateSettings((s) => s[_cursorKey] = cursors);
      }
      if (newlyGone) ref.invalidate(mailListProvider);
      if (changed) {
        ref.invalidate(mailListProvider);
        ref.invalidate(mailboxesProvider);
        for (final t in changedThreads) {
          ref.invalidate(threadProvider(t));
        }
      }
      state = state.copyWith(
        unreadByAccount: unread,
        usageByAccount: usage,
        syncedAt: DateTime.now(),
        lastArrivals: arrivals,
        error: lastError,
        clearError: lastError == null,
      );
    } finally {
      _inFlight = false;
    }
  }
}
