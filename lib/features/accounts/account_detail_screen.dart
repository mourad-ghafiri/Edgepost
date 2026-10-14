import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/account_switcher.dart';
import '../../app/nav_keys.dart';
import '../../core/accounts/account.dart';
import '../../core/accounts/credential.dart';
import '../../core/adaptive/ep_icons.dart';
import '../../core/adaptive/ep_page.dart';
import '../../core/adaptive/ep_widgets.dart';
import '../../core/l10n.dart';
import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/account_avatar.dart';
import '../mail/data/mail_providers.dart';
import '../onboarding/presentation/capability_list.dart';
import '../today/attention.dart' show tokenExpiresSoon;

/// One account: its name, the API tokens that give access to it (what each
/// may do here, expiry, re-check, replace, remove), its mail service, and
/// removing it from the app (nothing changes in Cloudflare).
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({super.key, required this.accountId});
  final String accountId;

  @override
  ConsumerState<AccountDetailScreen> createState() => _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen> {
  String? _checking;

  @override
  void initState() {
    super.initState();
    // Expiry as Cloudflare has it now (a date edited in the dashboard
    // replaces the one saved when the token was added).
    ref.read(vaultProvider.notifier).refreshExpiry();
  }

  Future<void> _rename(Account a) async {
    final l = context.l10n;
    final ctl = TextEditingController(text: a.nickname ?? '');
    final ok = await showEpConfirm(
      context,
      title: l.accountRename,
      message: l.accountRenameHelp(a.cloudflareName),
      confirmLabel: l.actionSave,
      content: EpTextField(label: l.accountName, controller: ctl, placeholder: a.cloudflareName, autofocus: true),
    );
    if (ok) await ref.read(vaultProvider.notifier).rename(a.id, ctl.text);
    ctl.dispose();
  }

  Future<void> _recheck(Credential t) async {
    final l = context.l10n;
    setState(() => _checking = t.id);
    try {
      await ref.read(vaultProvider.notifier).reprobe(t.id, widget.accountId);
      if (mounted) showEpToast(context, l.settingsTokenRechecked);
    } on Object catch (e) {
      if (mounted) showEpToast(context, describeError(context, e));
    } finally {
      if (mounted) setState(() => _checking = null);
    }
  }

  Future<void> _removeToken(Credential t) async {
    final l = context.l10n;
    final vault = ref.read(vaultProvider).value!;
    final others = [for (final a in vault.accounts) if (a.id != widget.accountId && t.reaches(a.id)) a.name];
    final ok = await showEpConfirm(
      context,
      title: l.settingsTokenRemoveConfirm(t.label),
      message: [l.settingsTokenRemoveBody, if (others.isNotEmpty) l.accountTokenAlsoReaches(others.join(', '))].join('\n\n'),
      confirmLabel: l.actionRemove,
      destructive: true,
      scoped: false,
    );
    if (ok) await ref.read(vaultProvider.notifier).removeToken(t.id);
  }

  Future<void> _remove(Account a) async {
    final l = context.l10n;
    final ok = await showEpConfirm(
      context,
      title: l.accountRemoveConfirm(a.name),
      message: l.accountRemoveBody,
      confirmLabel: l.actionRemove,
      destructive: true,
      scoped: false,
    );
    if (!ok || !mounted) return;
    // This screen may go away during the switch: keep the container.
    final container = ProviderScope.containerOf(context, listen: false);
    final vault = container.read(vaultProvider).value!;
    // The account on screen goes: show another one first, so no screen of
    // the removed account stays alive.
    if (vault.activeId == a.id) {
      final next = vault.previous ?? vault.accounts.where((x) => x.id != a.id).firstOrNull;
      if (next != null) await switchAccountIn(container, next.id, then: '/settings', announce: false);
    } else {
      context.pop();
    }
    await container.read(vaultProvider.notifier).removeAccount(a.id);
    final ctx = rootContextForToast();
    if (ctx != null && ctx.mounted) showEpToast(ctx, l.accountRemoved(a.name));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final vault = ref.watch(vaultProvider).value;
    final a = vault?.accountById(widget.accountId);
    if (vault == null || a == null) {
      return EpPage(title: l.accountTitle, largeTitle: false, slivers: const [EpFill(child: EpLoading())]);
    }
    final tokens = vault.tokensFor(a.id);
    final isActive = vault.activeId == a.id;
    final hasMail = ref.watch(mailServiceProvider(a.id)) != null;
    final date = DateFormat.yMMMd();

    return EpPage(
      title: a.name,
      largeTitle: false,
      previousPageTitle: l.tabSettings,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xl, EpSpace.lg, 0),
            child: Row(
              children: [
                AccountAvatar(account: a, size: 56),
                const SizedBox(width: EpSpace.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, style: EpType.title(context, size: 22)),
                      if (a.nickname != null) ...[
                        const SizedBox(height: 2),
                        Text(l.accountCloudflareName(a.cloudflareName), style: TextStyle(color: c.inkMuted, fontSize: 13)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            children: [
              if (!isActive)
                EpTile(
                  leading: EpIconView(EpIcon.checkCircle, color: c.tint),
                  title: Text(l.accountSwitchTo(a.name), style: TextStyle(color: c.tint)),
                  onTap: () => switchAccount(context, a.id),
                ),
              EpTile(title: Text(l.accountName), additionalInfo: Text(a.name), onTap: () => _rename(a)),
              if (isActive)
                EpTile(
                  title: Text(l.settingsMailService),
                  additionalInfo: Text(hasMail ? l.settingsMailReady : l.settingsMailNotSetUp),
                  onTap: () => context.push('/mail/setup'),
                ),
            ],
          ),
        ),
        if (tokens.isEmpty)
          SliverToBoxAdapter(
            child: EpSection(
              header: l.settingsTokens,
              children: [
                EpTile(
                  leading: EpIconView(EpIcon.warning, color: c.caution),
                  title: Text(l.accountNoAccess),
                  subtitle: Text(l.errorNoToken),
                ),
                EpTile(
                  leading: EpIconView(EpIcon.add, color: c.tint),
                  title: Text(l.settingsTokenAddReplacement, style: TextStyle(color: c.tint)),
                  onTap: () => context.push('/accounts/add'),
                ),
              ],
            ),
          ),
        for (final t in tokens) ...[
          SliverToBoxAdapter(
            child: EpSection(
              header: tokens.length > 1 ? t.label : l.settingsTokens,
              footer: l.settingsTokenExpiryHelp,
              children: [
                if (tokens.length == 1) EpTile(title: Text(t.label)),
                EpTile(
                  title: Text(l.settingsTokenExpiresTitle),
                  additionalInfo: Text(
                    t.expiresOn == null ? l.settingsTokenNoExpiry : date.format(t.expiresOn!.toLocal()),
                    style: tokenExpiresSoon(t) ? TextStyle(color: c.attention, fontWeight: FontWeight.w600) : null,
                  ),
                ),
                EpTile(
                  title: Text(t.kind == TokenKind.user ? l.settingsTokenKindUser : l.settingsTokenKindAccount),
                ),
                if (tokenExpiresSoon(t))
                  EpTile(
                    title: Text(l.settingsTokenAddReplacement, style: TextStyle(color: c.tint)),
                    onTap: () => context.push('/accounts/add'),
                  ),
              ],
            ),
          ),
          SliverToBoxAdapter(child: CapabilityList(header: l.settingsTokenCapabilities, credential: t, accountId: a.id, footer: l.addTokenWriteNote)),
          SliverToBoxAdapter(
            child: EpSection(
              children: [
                EpTile(
                  title: Text(l.settingsTokenRecheck),
                  trailing: _checking == t.id ? const CircularProgressIndicator.adaptive() : null,
                  onTap: _checking != null ? null : () => _recheck(t),
                ),
                EpTile(title: Text(l.settingsTokenRemove), destructive: true, onTap: () => _removeToken(t)),
              ],
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: EpSection(
            footer: l.accountRemoveBody,
            children: [EpTile(title: Text(l.accountRemove), destructive: true, onTap: () => _remove(a))],
          ),
        ),
      ],
    );
  }
}
