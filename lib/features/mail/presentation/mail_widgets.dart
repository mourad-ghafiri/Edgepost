import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../data/mail_client.dart';
import '../data/mail_models.dart';
import '../data/mail_providers.dart';

/// Short mail timestamp: "09:42", "Yesterday", "Mon", "12 Oct", "12/10/2025".
String mailTime(BuildContext context, DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final local = t.toLocal();
  final locale = Localizations.localeOf(context).toLanguageTag();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat.Hm(locale).format(local);
  if (diff == 1) return context.l10n.mailYesterday;
  if (diff < 7) return DateFormat.E(locale).format(local);
  if (local.year == n.year) return DateFormat.MMMd(locale).format(local);
  return DateFormat.yMd(locale).format(local);
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// A message on the board: sky holder, sender as callsign, subject and
/// snippet underneath, the domain address it landed on as a data field.
class MessageStrip extends StatelessWidget {
  const MessageStrip({
    super.key,
    required this.message,
    this.onTap,
    this.onLongPress,
    this.showMailbox = true,
    this.selected = false,
  });

  final MessageSummary message;

  /// Open beside the inbox (an iPad split).
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showMailbox;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final m = message;
    final who = m.outgoing ? l.mailToPrefix(m.to.isEmpty ? '' : m.to.first.display) : m.from.display;
    final subject = m.subject.trim().isEmpty ? l.mailNoSubject : m.subject;
    final time = mailTime(context, m.date);
    // The full address it landed on (several domains share "contact@"),
    // on the callsign line so it never truncates to a bare local part.
    final landed = showMailbox ? (m.outgoing ? l.mailFromAddress(m.mailbox) : l.mailToAddress(m.mailbox)) : null;
    return Strip(
      title: who,
      family: Family.mail,
      caption: landed == null ? time : '$time · $landed',
      emphasis: !m.read,
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      // Always reserve the dot's slot so sender names line up.
      leading: _UnreadDot(color: m.read ? Colors.transparent : c.tint),
      semanticLabel: [
        if (!m.read) l.mailUnread,
        who,
        subject,
        if (m.snippet.isNotEmpty) m.snippet,
        ?landed,
        time,
        if (m.starred) l.mailStarred,
        if (m.hasAttachments) l.mailHasAttachment,
      ].join(', '),
      detail: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: m.read ? FontWeight.w500 : FontWeight.w700, color: c.ink),
                ),
                if (m.snippet.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    m.snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.inkMuted, fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          if (m.starred || m.hasAttachments) ...[
            const SizedBox(width: EpSpace.sm),
            Column(
              children: [
                if (m.starred) EpIconView(EpIcon.starFill, size: 16, color: c.caution),
                if (m.hasAttachments) EpIconView(EpIcon.attach, size: 16, color: c.inkMuted),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Human message for a mail service error, naming the recovery.
String describeMailError(BuildContext context, Object e, {String? fromDomain}) {
  final l = context.l10n;
  if (e is! MailException) return l.errorGeneric;
  return switch (e.code) {
    'recipient_not_allowed' => l.mailErrRecipientNotAllowed,
    'sender_domain_not_onboarded' => l.mailErrSenderDomain(fromDomain ?? ''),
    'sender_not_allowed' => l.mailErrSenderNotAllowed,
    'recipient_suppressed' => l.mailErrSuppressed,
    'sending_limit' => l.mailErrSendingLimit,
    'monthly_send_limit' => l.mailErrMonthlyLimit,
    'content_too_large' => l.mailErrTooLarge,
    'delivery_failed' => l.mailErrDelivery,
    'invalid_message' || 'too_many_recipients' => l.mailErrInvalid(e.message),
    'network' => l.mailErrOffline,
    'timeout' || 'send_in_progress' => l.mailErrTimeout,
    'service_unavailable' => l.mailErrUnavailable(e.status),
    'service_missing' => l.mailErrServiceMissing,
    _ => e.message,
  };
}

/// Technical detail for an error sheet: code, provider code and HTTP status.
String? mailErrorDetails(Object e) {
  if (e is! MailException) return null;
  return [
    e.code,
    ?e.providerCode,
    if (e.status > 0) 'HTTP ${e.status}',
    if (e.message.isNotEmpty) e.message,
  ].join(' · ');
}

/// The account's mail Worker was deleted from Cloudflare (e.g. in the
/// dashboard): its address answers 404 without the Worker's JSON.
bool isMailServiceMissing(Object? e) => e is MailException && e.code == 'service_missing';

/// Forgets the gone mail service on this device (and its cached mail), then
/// opens setup. Setup reuses whatever is left in the account (routing,
/// sending onboarding) and recreates the rest.
Future<void> setUpMailAgain(BuildContext context, WidgetRef ref, String accountId) async {
  await ref.read(mailServicesProvider.notifier).forget(accountId);
  if (context.mounted) await context.push('/mail/setup');
}

/// Says the mail service is gone and offers to set it up again.
class MailServiceMissing extends ConsumerWidget {
  const MailServiceMissing({super.key, required this.accountId});
  final String accountId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return EpMessage(
      icon: EpIcon.warning,
      title: l.mailServiceMissingTitle,
      message: l.mailServiceMissingBody,
      action: EpButton(label: l.mailServiceSetUpAgain, onPressed: () => setUpMailAgain(context, ref, accountId)),
    );
  }
}
