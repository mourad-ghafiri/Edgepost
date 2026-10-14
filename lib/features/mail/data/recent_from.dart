import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import 'mail_models.dart';

/// The last few addresses the user sent from in one account, newest first.
final recentFromProvider = AsyncNotifierProvider.family<RecentFrom, List<MailAddress>, String>(RecentFrom.new);

class RecentFrom extends AsyncNotifier<List<MailAddress>> {
  RecentFrom(this.accountId);
  final String accountId;

  static const _key = 'mail_recent_from';
  static const _max = 5;

  @override
  Future<List<MailAddress>> build() async {
    final s = await ref.read(secureStoreProvider).readSettings();
    return ((s[_key] as Map?)?[accountId] as List? ?? const []).map(MailAddress.fromJson).toList();
  }

  Future<void> remember(MailAddress a) async {
    final next = [a, ...?state.value?.where((x) => !x.sameAs(a))].take(_max).toList();
    state = AsyncData(next);
    final json = next.map((x) => x.toJson()).toList();
    await ref.read(secureStoreProvider).updateSettings((s) {
      final all = Map<String, dynamic>.from((s[_key] as Map?) ?? const {});
      all[accountId] = json;
      s[_key] = all;
    });
  }
}
