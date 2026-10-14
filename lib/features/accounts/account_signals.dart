import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/widgets/account_avatar.dart';
import '../mail/data/mail_live.dart';
import '../today/attention.dart';

/// What one account has waiting: items in "Needs you" and unread mail.
class AccountSignal {
  const AccountSignal({required this.needsYou, required this.unread});
  final int needsYou;
  final int unread;

  bool get any => needsYou > 0 || unread > 0;

  @override
  bool operator ==(Object other) => other is AccountSignal && other.needsYou == needsYou && other.unread == unread;

  @override
  int get hashCode => Object.hash(needsYou, unread);
}

final accountSignalProvider = Provider.family<AccountSignal, String>((ref, accountId) => AccountSignal(
      needsYou: ref.watch(needsYouProvider(accountId)).length,
      unread: ref.watch(mailLiveProvider.select((s) => s.unreadByAccount[accountId] ?? 0)),
    ));

/// The dot on the active account's avatar: whether another account needs
/// the user (red pencil) or only has unread mail (tint).
final otherAccountsDotProvider = Provider<AvatarDot>((ref) {
  final active = ref.watch(activeAccountProvider)?.id;
  var dot = AvatarDot.none;
  for (final a in ref.watch(accountsProvider)) {
    if (a.id == active) continue;
    final s = ref.watch(accountSignalProvider(a.id));
    if (s.needsYou > 0) return AvatarDot.needsYou;
    if (s.unread > 0) dot = AvatarDot.unread;
  }
  return dot;
});
