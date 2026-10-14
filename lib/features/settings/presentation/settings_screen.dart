import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/accounts/account.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/app_info.dart';
import '../../../core/l10n.dart';
import '../../../core/notify/alerts.dart';
import '../../../core/providers.dart';
import '../../../core/security/app_lock.dart';
import '../../../core/theme/appearance.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/account_avatar.dart';
import '../../mail/data/mail_settings.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final vault = ref.watch(vaultProvider).value;
    final accounts = vault?.accounts ?? const <Account>[];
    final lock = ref.watch(appLockEnabledProvider).value ?? false;
    final appearance = ref.watch(appearanceProvider);
    final alerts = ref.watch(notificationPrefsProvider).value ?? const AlertPrefs();
    final info = ref.watch(_packageInfoProvider).value;

    Future<void> setPrefs({bool? mail, bool? budget, bool? delivery}) async {
      final ok = await ref.read(notificationPrefsProvider.notifier).set(mail: mail, budget: budget, delivery: delivery);
      if (!ok && context.mounted) showEpToast(context, l.settingsNotificationsDenied);
    }

    return EpPage(
      title: l.tabSettings,
      account: true,
      slivers: [
        SliverToBoxAdapter(
          child: EpSection(
            // One account reads as "Account"; the list only becomes
            // "Accounts" once there are several.
            header: accounts.length > 1 ? l.accountsTitle : l.accountTitle,
            children: [
              for (final a in accounts)
                EpTile(
                  leading: AccountAvatar(account: a, size: 28),
                  title: Text(a.name),
                  subtitle: vault!.lacksAccess(a.id)
                      ? Text(l.accountNoAccess, style: TextStyle(color: c.caution))
                      : (accounts.length > 1 && a.id == vault.activeId ? Text(l.accountShowing) : null),
                  onTap: () => context.push('/settings/account/${a.id}'),
                ),
              EpTile(
                leading: EpIconView(EpIcon.add, color: c.tint),
                title: Text(l.accountAdd, style: TextStyle(color: c.tint)),
                onTap: () => context.push('/accounts/add'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.settingsMail,
            children: [
              EpTile(
                leading: EpIconView(EpIcon.mail, color: c.tint),
                title: Text(l.settingsMailService),
                onTap: () => context.push('/mail/setup'),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.settingsAppearance,
            footer: appearance == Appearance.system ? l.settingsAppearanceSystemHelp : null,
            children: [
              Padding(
                padding: const EdgeInsets.all(EpSpace.md),
                child: SizedBox(
                  width: double.infinity,
                  child: EpSegmented<Appearance>(
                    segments: {
                      Appearance.light: l.settingsAppearanceLight,
                      Appearance.dark: l.settingsAppearanceDark,
                      Appearance.system: l.settingsAppearanceSystem,
                    },
                    value: appearance,
                    onChanged: (a) => ref.read(appearanceProvider.notifier).set(a),
                  ),
                ),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.settingsNotifications,
            children: [
              EpSwitchTile(
                title: l.settingsNewMailAlerts,
                subtitle: l.settingsNewMailAlertsHelp,
                value: alerts.mail,
                onChanged: (v) => setPrefs(mail: v),
              ),
              EpSwitchTile(
                title: l.settingsBudgetAlerts,
                subtitle: l.settingsBudgetAlertsHelp,
                value: alerts.budget,
                onChanged: (v) => setPrefs(budget: v),
              ),
              EpSwitchTile(
                title: l.settingsDeliveryAlerts,
                subtitle: l.settingsDeliveryAlertsHelp,
                value: alerts.delivery,
                onChanged: (v) => setPrefs(delivery: v),
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.settingsSecurity,
            footer: l.settingsAppLockHelp,
            children: [
              EpSwitchTile(
                title: l.settingsAppLock,
                value: lock,
                onChanged: (v) async {
                  final ok = await ref.read(appLockEnabledProvider.notifier).set(v, reason: l.lockReason);
                  if (!ok && v && context.mounted) showEpToast(context, l.settingsAppLockUnavailable);
                },
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.settingsAbout,
            footer: l.settingsNotAffiliated,
            children: [
              EpTile(
                title: Text(l.settingsVersion),
                additionalInfo: Text(info == null ? '' : '${info.version} (${info.buildNumber})'),
              ),
              // The short version here; the full policy on the website, where
              // both stores link too.
              EpTile(
                title: Text(l.settingsPrivacy),
                subtitle: Text(l.settingsPrivacyBody),
                onTap: () => launchUrl(Uri.parse(AppLinks.privacy), mode: LaunchMode.externalApplication),
              ),
              EpTile(
                title: Text(l.settingsSourceCode),
                additionalInfo: Text(l.settingsSourceCodeLicense),
                onTap: () => launchUrl(Uri.parse(AppLinks.source), mode: LaunchMode.externalApplication),
              ),
              EpTile(
                title: Text(l.settingsContact),
                // The address under the title: too long for the row's end.
                subtitle: const Text(AppLinks.supportEmail),
                onTap: () => launchUrl(Uri(scheme: 'mailto', path: AppLinks.supportEmail)),
              ),
              EpTile(
                title: Text(l.settingsLicenses),
                onTap: () =>
                    showLicensePage(context: context, applicationName: l.appName, applicationVersion: info?.version),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
