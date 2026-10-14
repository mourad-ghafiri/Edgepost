import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/account_switcher.dart';
import '../../core/accounts/account.dart';
import '../../core/adaptive/ep_icons.dart';
import '../../core/adaptive/ep_widgets.dart';
import '../../core/adaptive/layout.dart';
import '../../core/adaptive/platform.dart';
import '../../core/adaptive/popover.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/strip/strip.dart' show EpPressable;
import '../../core/theme/tokens.dart';
import '../../core/widgets/account_avatar.dart';
import 'account_signals.dart';

/// The accounts, what each has waiting, and "+" to add one. Rows keep the
/// user's order (not active-first), so muscle memory holds.
Future<void> showAccountSwitcher(BuildContext context) {
  const sheet = _SwitcherSheet();
  if (isCupertino(context) && EpLayout.sheet(context)) {
    return showEpPopover<void>(context, width: 380, builder: (ctx) => sheet);
  }
  if (isCupertino(context)) {
    return showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => const _CupertinoCard(child: sheet),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    // Over the whole app (navigation bar and banners included), not inside
    // the tab that asked.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: EpColors.of(context).canvas,
    builder: (ctx) => sheet,
  );
}

/// Content-sized card in the iOS sheet style (a full-height sheet would look
/// empty with one to three accounts).
class _CupertinoCard extends StatelessWidget {
  const _CupertinoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(EpSpace.sm, 0, EpSpace.sm, EpSpace.sm),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.canvas, borderRadius: BorderRadius.circular(EpRadius.lg)),
        child: Material(type: MaterialType.transparency, child: child),
      ),
    );
  }
}

class _SwitcherSheet extends ConsumerWidget {
  const _SwitcherSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final vault = ref.watch(vaultProvider).value;
    final accounts = vault?.accounts ?? const <Account>[];
    final activeId = vault?.activeId;
    final maxList = MediaQuery.sizeOf(context).height * 0.55;

    Future<void> choose(Account a) async {
      final container = ProviderScope.containerOf(context, listen: false);
      Navigator.of(context).pop();
      if (a.id != activeId) await switchAccountIn(container, a.id);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(EpSpace.lg, isCupertino(context) ? EpSpace.md : 0, EpSpace.xs, EpSpace.xs),
          child: Row(
            children: [
              Expanded(
                child: Semantics(header: true, child: Text(l.accountsTitle, style: EpType.title(context, size: 22))),
              ),
              EpIconButton(
                icon: EpIcon.add,
                label: l.accountAdd,
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/accounts/add');
                },
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxList),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final a in accounts)
                  _AccountRow(account: a, active: a.id == activeId, noAccess: vault!.lacksAccess(a.id), onTap: () => choose(a)),
              ],
            ),
          ),
        ),
        Divider(height: 1, thickness: 1, color: c.hairline),
        EpPressable(
          onTap: () {
            Navigator.of(context).pop();
            context.go('/settings');
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg, vertical: EpSpace.md),
              child: Row(
                children: [
                  EpIconView(EpIcon.settings, size: 20, color: c.tint),
                  const SizedBox(width: EpSpace.md),
                  Expanded(child: Text(l.accountsManage, style: TextStyle(color: c.tint, fontSize: 16))),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: EpSpace.sm),
      ],
    );
  }
}

class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.account, required this.active, required this.noAccess, required this.onTap});
  final Account account;
  final bool active;
  final bool noAccess;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final s = ref.watch(accountSignalProvider(account.id));
    final detail = noAccess
        ? l.accountNoAccess
        : [if (s.needsYou > 0) l.tabNeedsYou(s.needsYou), if (s.unread > 0) l.tabBadge(s.unread)].join(' · ');
    return Semantics(
      button: true,
      selected: active,
      excludeSemantics: true,
      label: [account.name, if (detail.isNotEmpty) detail, if (active) l.accountCurrent].join(', '),
      child: EpPressable(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg, vertical: EpSpace.sm),
            child: Row(
              children: [
                AccountAvatar(account: account, size: 36),
                const SizedBox(width: EpSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        account.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.ink, fontSize: 16, fontWeight: active ? FontWeight.w700 : FontWeight.w500),
                      ),
                      if (noAccess)
                        Text(l.accountNoAccess, style: TextStyle(color: c.caution, fontSize: 13)),
                    ],
                  ),
                ),
                if (!noAccess && s.needsYou > 0) _Count(count: s.needsYou, color: c.attention, onColor: c.onAttention),
                if (!noAccess && s.unread > 0) ...[
                  const SizedBox(width: EpSpace.xs),
                  _Count(count: s.unread, color: c.tint, onColor: c.onTint),
                ],
                SizedBox(
                  width: 32,
                  child: active ? Align(alignment: Alignment.centerRight, child: EpIconView(EpIcon.check, size: 20, color: c.tint)) : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small count pill, in the same colours as the tab badges.
class _Count extends StatelessWidget {
  const _Count({required this.count, required this.color, required this.onColor});
  final int count;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 22),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(EpRadius.pill)),
        child: Text(
          count > 99 ? '99+' : '$count',
          textAlign: TextAlign.center,
          textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
          style: TextStyle(color: onColor, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
        ),
      );
}
