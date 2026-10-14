import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/account_switcher.dart';
import '../../core/adaptive/platform.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/widgets/account_avatar.dart';
import 'account_signals.dart';
import 'switcher_sheet.dart';

/// The active account's avatar at the top right of every tab root. Tap: the
/// accounts. Long-press: back to the previous account. A dot says another
/// account needs the user (red pencil) or has unread mail (tint).
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final vault = ref.watch(vaultProvider).value;
    final account = vault?.active;
    if (account == null) return const SizedBox.shrink();
    final previous = vault!.previous;
    final dot = ref.watch(otherAccountsDotProvider);

    Future<void> back() async {
      if (previous != null) await switchAccount(context, previous.id);
    }

    final avatar = AccountAvatar(account: account, size: isCupertino(context) ? 30 : 32, dot: dot);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: [
        l.accountButtonLabel(account.name),
        if (dot == AvatarDot.needsYou) l.accountOthersNeedYou,
        if (dot == AvatarDot.unread) l.accountOthersUnread,
      ].join('. '),
      hint: l.accountButtonHint,
      customSemanticsActions: {
        if (previous != null) CustomSemanticsAction(label: l.accountSwitchBack(previous.name)): back,
      },
      child: isCupertino(context)
          ? CupertinoButton(
              padding: const EdgeInsets.only(left: 6),
              minimumSize: const Size(44, 44),
              onPressed: () => showAccountSwitcher(context),
              onLongPress: previous == null ? null : back,
              child: avatar,
            )
          : SizedBox(
              width: 48,
              height: 48,
              child: InkResponse(
                radius: 24,
                onTap: () => showAccountSwitcher(context),
                onLongPress: previous == null ? null : back,
                child: Center(child: avatar),
              ),
            ),
    );
  }
}
