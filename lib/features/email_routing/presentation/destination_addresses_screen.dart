import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../zones/data/zones_providers.dart';
import '../data/email_routing_models.dart';
import '../data/email_routing_providers.dart';
import 'add_address_dialog.dart';

/// The account's destination addresses (shared by every domain in it), split
/// into waiting-for-verification and verified.
class DestinationAddressesScreen extends ConsumerWidget {
  const DestinationAddressesScreen({super.key, required this.zoneId});
  final String zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final zone = ref.watch(zoneByIdProvider(zoneId));
    if (zone == null) {
      return EpPage(title: l.routingAddressesTitle, largeTitle: false, slivers: const [EpFill(child: EpLoading())]);
    }
    final account = zone.account.id;
    final async = ref.watch(destinationAddressesProvider(account));
    final synced = async.value;
    Future<void> add() => showAddDestinationDialog(context, account);

    return EpPage(
      title: l.routingAddressesTitle,
      largeTitle: false,
      previousPageTitle: l.routingTitle,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => ref.read(destinationAddressesProvider(account).notifier).refresh(),
      primaryAction: async.hasError && synced == null
          ? null
          : EpAction(icon: EpIcon.add, label: l.routingAddAddress, onPressed: add),
      slivers: async.when(
        loading: () => [const EpFill(child: EpLoading())],
        error: (e, _) => [
          EpFill(
            child: EpErrorView(
              error: e,
              permission: Capability.emailAddresses.permission,
              onRetry: () => ref.invalidate(destinationAddressesProvider(account)),
            ),
          ),
        ],
        data: (s) {
          if (s.data.isEmpty) {
            return [
              EpFill(
                child: EpMessage(
                  icon: EpIcon.mail,
                  title: l.routingAddressesEmptyTitle,
                  message: l.routingAddressesEmptyMessage,
                  action: EpButton(label: l.routingAddAddress, onPressed: add),
                ),
              ),
            ];
          }
          final pending = s.data.where((a) => !a.isVerified).toList();
          final verified = s.data.where((a) => a.isVerified).toList();
          return [
            SliverList.list(children: [
              if (pending.isNotEmpty)
                EpSection(
                  header: l.routingAddressesPendingHeader,
                  footer: l.routingAddressesPendingFooter,
                  children: [for (final a in pending) _AddressRow(zone: zone, address: a)],
                ),
              if (verified.isNotEmpty)
                EpSection(
                  header: l.routingAddressesVerifiedHeader,
                  footer: l.routingAddressesAccountNote(zone.account.name),
                  children: [for (final a in verified) _AddressRow(zone: zone, address: a)],
                ),
              if (verified.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(EpSpace.lg + 4, 0, EpSpace.lg + 4, 0),
                  child: Text(
                    l.routingAddressesAccountNote(zone.account.name),
                    style: TextStyle(fontSize: 13, color: EpColors.of(context).inkMuted),
                  ),
                ),
            ]),
          ];
        },
      ),
    );
  }
}

class _AddressRow extends ConsumerWidget {
  const _AddressRow({required this.zone, required this.address});
  final Zone zone;
  final DestinationAddress address;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final date = DateFormat.yMMMd();
    final when = address.isVerified ? address.verified : address.created;
    final subtitle = address.isVerified
        ? l.routingAddressVerifiedOn(date.format(when!.toLocal()))
        : (when == null ? l.routingAddressWaiting : l.routingAddressWaitingSince(date.format(when.toLocal())));
    return GestureDetector(
      onLongPress: () => _actions(context, ref),
      child: EpTile(
        leading: EpIconView(
          address.isVerified ? EpIcon.checkCircle : EpIcon.timer,
          color: address.isVerified ? c.ok : c.caution,
          semanticLabel: address.isVerified ? l.routingAddressVerified : l.routingAddressWaiting,
        ),
        title: Text(address.email, maxLines: 2, style: EpType.data(context, size: 15)),
        subtitle: Text(subtitle, maxLines: 3),
        onTap: () => _actions(context, ref),
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final choice = await showEpActionSheet<int>(
      context,
      title: address.email,
      actions: [
        EpSheetAction(label: l.actionCopy, value: 0, icon: EpIcon.copy),
        EpSheetAction(label: l.actionDelete, value: 1, icon: EpIcon.trash, destructive: true),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 0:
        await copyWithToast(context, address.email);
      case 1:
        await _delete(context, ref);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final rules = ref.read(routingOverviewProvider(zone.id)).value?.data.rules ?? const <RoutingRule>[];
    final using = rules
        .where((r) =>
            r.action?.type == RuleActionType.forward && r.action?.target?.toLowerCase() == address.email.toLowerCase())
        .length;
    final ok = await showEpConfirm(
      context,
      title: l.routingAddressDeleteTitle(address.email),
      message: using > 0 ? l.routingAddressDeleteUsed(using, zone.name) : l.routingAddressDeleteMessage,
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(destinationAddressesProvider(zone.account.id).notifier).remove(address.id);
      if (context.mounted) showEpToast(context, l.routingAddressDeleted(address.email));
    } on Object catch (e) {
      if (context.mounted) {
        showEpToast(context, describeError(context, e, permission: Capability.emailAddresses.permission));
      }
    }
  }
}
