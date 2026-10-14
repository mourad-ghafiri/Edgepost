import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/access.dart';
import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/layout.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/adaptive/popover.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../data/dns_draft.dart';
import '../data/dns_record.dart';

/// `extra` passed when the list opens the editor, so the editor hands a
/// delete back to the list (which owns the undo toast).
const String kDnsEditorFromList = 'dns-list';

/// What the editor asks the list to do when it closes.
class DnsEditorResult {
  const DnsEditorResult.delete(this.record);
  final DnsRecord record;
}

/// "Auto", "5 min", "1 h", "1 day"…
String ttlLabel(BuildContext context, int ttl) {
  final l = context.l10n;
  if (ttl == DnsTypes.autoTtl) return l.dnsTtlAuto;
  if (ttl % 86400 == 0) return l.dnsTtlDays(ttl ~/ 86400);
  if (ttl % 3600 == 0) return l.dnsTtlHours(ttl ~/ 3600);
  if (ttl % 60 == 0) return l.dnsTtlMinutes(ttl ~/ 60);
  return l.dnsTtlSeconds(ttl);
}

String dnsErrorText(BuildContext context, DnsFieldError e) {
  final l = context.l10n;
  return switch (e) {
    DnsFieldError.required => l.fieldRequired,
    DnsFieldError.ipv4 => l.dnsErrorIpv4,
    DnsFieldError.ipv6 => l.dnsErrorIpv6,
    DnsFieldError.hostname => l.dnsErrorHostname,
    DnsFieldError.recordName => l.dnsErrorName,
    DnsFieldError.range => l.dnsErrorRange,
    DnsFieldError.flags => l.dnsErrorFlags,
    DnsFieldError.type => l.dnsErrorType,
    DnsFieldError.quotes => l.dnsErrorQuotes,
    DnsFieldError.tooLong => l.dnsErrorTooLong,
  };
}

/// Single choice from a short list: an action sheet on iOS (the current
/// value in bold), a simple dialog with a check mark on Android. Both scroll
/// when the list is long.
Future<T?> showDnsChoice<T>(
  BuildContext context, {
  required String title,
  required List<(T, String)> options,
  required T selected,
}) {
  if (isCupertino(context) && EpLayout.sheet(context)) {
    return showEpPopover<T>(
      context,
      builder: (ctx) => EpPopoverMenu(
        title: title,
        rows: [
          for (final (value, label) in options)
            EpPopoverRow(label: label, checked: value == selected, onTap: () => Navigator.pop(ctx, value)),
        ],
      ),
    );
  }
  if (isCupertino(context)) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final (value, label) in options)
            CupertinoActionSheetAction(
              isDefaultAction: value == selected,
              onPressed: () => Navigator.pop(ctx, value),
              child: Text(label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.l10n.actionCancel),
        ),
      ),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) {
      final c = EpColors.of(ctx);
      return SimpleDialog(
        title: Text(title),
        children: [
          for (final (value, label) in options)
            ListTile(
              selected: value == selected,
              leading: value == selected ? Icon(EpIcon.check.material, color: c.tint) : const SizedBox(width: 24),
              title: Text(label),
              onTap: () => Navigator.pop(ctx, value),
            ),
        ],
      );
    },
  );
}

/// Trailing labels of a record row: proxy state or priority, then TTL.
class DnsRecordMeta extends StatelessWidget {
  const DnsRecordMeta({super.key, required this.record});
  final DnsRecord record;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final small = EpType.numbers(TextStyle(fontSize: 12, height: 1.25, color: c.inkMuted));
    final lines = <Widget>[
      if (record.canProxy)
        Text(
          record.proxied ? l.dnsProxied : l.dnsDnsOnly,
          style: small.copyWith(
            color: record.proxied ? c.tint : c.inkMuted,
            fontWeight: record.proxied ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      if (DnsTypes.usesPriority.contains(record.type) && record.priority != null)
        Text(l.dnsPriorityShort(record.priority!), style: small),
      Text(record.proxied ? l.dnsTtlAuto : ttlLabel(context, record.ttl), style: small),
    ];
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisAlignment: MainAxisAlignment.center,
      children: lines,
    );
    if (!isCupertino(context)) return column;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [column, const SizedBox(width: 6), const CupertinoListTileChevron()],
    );
  }
}

/// True when no token that reaches the zone may read DNS (refused, or none
/// left). An unchecked permission still gets a chance to load.
bool dnsAccessDenied(WidgetRef ref, Zone zone) => ref.watch(accessProvider).zone(zone, Capability.dns) is NoAccess;

/// Permission-missing state naming the token permission to add; retry
/// re-runs the capability probe.
Widget dnsPermissionView(WidgetRef ref, Zone zone) => EpErrorView(
  error: CfApiException(statusCode: 403, errors: const []),
  permission: Capability.dns.permission,
  onRetry: () => recheckAccess(ref, zone.account.id, tokenIds: zone.reach),
);
