import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../../zones/data/zones_providers.dart';
import '../data/mail_providers.dart';
import '../data/sending_health.dart';
import 'mail_widgets.dart';

const _days = 7;

/// Health of every domain the account's mail service sends from, one query
/// pair each.
final sendingHealthProvider = FutureProvider.autoDispose.family<List<DomainSendingHealth>, String>((
  ref,
  accountId,
) async {
  final s = await ref.watch(mailServicesProvider.selectAsync((m) => m[accountId]));
  if (s == null) return const [];
  final zones = (await ref.watch(zonesProvider(accountId).future)).data;
  final names = {...s.sendingDomains, ...s.domains};
  final out = <DomainSendingHealth>[];
  for (final z in zones.where((z) => names.contains(z.name))) {
    out.add(await fetchSendingHealth(ref.zoneClient(z, Capability.analytics), z, days: _days));
  }
  // Domains with failures first, then by volume.
  out.sort((a, b) => b.failed != a.failed ? b.failed.compareTo(a.failed) : (b.delivered).compareTo(a.delivered));
  return out;
});

class SendingHealthScreen extends ConsumerWidget {
  const SendingHealthScreen({super.key});

  Future<void> _pause(BuildContext context, WidgetRef ref) async {
    final l = context.l10n;
    final ok = await showEpConfirm(
      context,
      title: l.mailHealthPause,
      message: l.mailHealthPauseBody,
      confirmLabel: l.mailHealthPause,
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(mailClientProvider(ref.read(activeAccountProvider)!.id)).putConfig({'monthlySendLimit': 0});
      if (context.mounted) showEpToast(context, l.mailHealthPaused);
    } on Object catch (e) {
      if (context.mounted) showEpToast(context, describeMailError(context, e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final account = ref.watch(activeAccountProvider)!.id;
    final health = ref.watch(sendingHealthProvider(account));
    return EpPage(
      title: l.mailHealthTitle,
      largeTitle: false,
      onRefresh: () async => ref.invalidate(sendingHealthProvider(account)),
      actions: [EpAction(icon: EpIcon.pause, label: l.mailHealthPause, onPressed: () => _pause(context, ref))],
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
            child: Text(l.mailHealthIntro(_days), style: TextStyle(color: c.inkMuted, height: 1.4)),
          ),
        ),
        ...health.when(
          loading: () => [const EpFill(child: EpLoading())],
          error: (e, _) => [
            EpFill(
              child: EpErrorView(
                error: e,
                permission: Capability.analytics.permission,
                onRetry: () => ref.invalidate(sendingHealthProvider(account)),
              ),
            ),
          ],
          data: (list) => list.isEmpty
              ? [
                  EpFill(
                    child: EpMessage(icon: EpIcon.send, title: l.mailHealthEmpty, message: l.mailHealthEmptyBody),
                  ),
                ]
              : [for (final h in list) SliverToBoxAdapter(child: _DomainHealth(health: h))],
        ),
      ],
    );
  }
}

class _DomainHealth extends StatelessWidget {
  const _DomainHealth({required this.health});
  final DomainSendingHealth health;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final h = health;
    final rate = h.deliveryRate;
    final low = rate != null && rate < 0.95;
    final pct = rate == null ? '—' : NumberFormat.percentPattern().format(rate);
    final problems = h.problems;
    // The strip's callsign names the domain; no bay title repeating it.
    final children = <Widget>[
      Strip(
        title: h.zone.name,
        family: Family.mail,
        cocked: low,
        reason: low ? l.mailHealthLowRate : null,
        fields: [
          StripField(l.mailHealthDelivered, '${h.delivered}', color: c.ok),
          StripField(l.mailHealthFailed, '${h.failed}', color: h.failed > 0 ? c.attention : null),
          StripField(l.mailHealthRate, pct, color: low ? c.attention : null),
        ],
      ),
      if (h.delivered + h.failed == 0 && h.recent.isEmpty)
        _Note(text: l.mailHealthNoSends(h.days))
      else if (problems.isEmpty)
        _Note(text: l.mailHealthAllGood)
      else
        for (final e in problems) _ProblemEvent(event: e),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xl, EpSpace.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 3),
              child: children[i],
            ),
        ],
      ),
    );
  }
}

class _ProblemEvent extends StatelessWidget {
  const _ProblemEvent({required this.event});
  final SendingEvent event;

  String _hint(BuildContext context) {
    final l = context.l10n;
    final e = event;
    final text = '${e.errorCause ?? ''} ${e.errorDetail ?? ''}'.toLowerCase();
    if (e.authFailed ||
        text.contains('dmarc') ||
        text.contains('dkim') ||
        text.contains('spf') ||
        text.contains('auth')) {
      return l.mailHealthHintAuth;
    }
    if (text.contains('5.1.1') ||
        text.contains('unknown') ||
        text.contains('does not exist') ||
        text.contains('no such user') ||
        text.contains('mailbox unavailable')) {
      return l.mailHealthHintUnknownUser;
    }
    if (e.isSpam || text.contains('spam')) return l.mailHealthHintSpam;
    return l.mailHealthHintOther;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final e = event;
    String r(String? v) => v ?? '—';
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(EpRadius.md),
        border: Border.all(color: c.hairline),
      ),
      padding: const EdgeInsets.all(EpSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(e.to, style: const TextStyle(fontSize: 14))),
              Text(mailTime(context, e.at), style: EpType.numbers(TextStyle(color: c.inkMuted, fontSize: 12))),
            ],
          ),
          if (e.subject.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              e.subject,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.ink),
            ),
          ],
          const SizedBox(height: EpSpace.sm),
          // Plain words first; the receiving server's code underneath for
          // whoever needs it.
          Text(
            _hint(context),
            style: TextStyle(color: c.attention, fontSize: 14, fontWeight: FontWeight.w600, height: 1.35),
          ),
          const SizedBox(height: 4),
          Text(
            [e.status, ?e.errorCause, ?e.errorDetail].join(' · '),
            style: EpType.data(context, size: 12, color: c.inkMuted),
          ),
          const SizedBox(height: 2),
          Text(
            l.mailHealthAuth(r(e.spf), r(e.dkim), r(e.dmarc)),
            style: EpType.data(context, size: 12, color: e.authFailed ? c.attention : c.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: EpSpace.sm),
    child: Text(text, style: TextStyle(color: EpColors.of(context).inkMuted)),
  );
}

/// Shortcut row used on the Mail service screen.
class SendingHealthLink extends StatelessWidget {
  const SendingHealthLink({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return EpTile(
      leading: EpIconView(EpIcon.chart, color: EpColors.of(context).tint),
      title: Text(l.mailHealthOpen),
      subtitle: Text(l.mailHealthOpenHelp),
      onTap: onTap,
    );
  }
}
