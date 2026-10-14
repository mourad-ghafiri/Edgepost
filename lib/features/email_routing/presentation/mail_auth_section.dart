import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../data/email_routing_models.dart';
import '../data/email_routing_providers.dart';
import '../data/mail_auth.dart';
import 'routing_widgets.dart';

/// SPF / DKIM / DMARC health for the domain, each with one line of advice and
/// a copyable suggested record when there is a fix to make.
class MailAuthSection extends ConsumerWidget {
  const MailAuthSection({
    super.key,
    required this.zoneId,
    required this.domain,
    required this.routingEnabled,
    this.requiredRecords = const [],
  });

  final String zoneId;
  final String domain;
  final bool routingEnabled;
  final List<RoutingDnsRecord> requiredRecords;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final async = ref.watch(mailAuthProvider(zoneId));
    final header = l.routingAuthHeader;
    return async.when(
      skipLoadingOnReload: true,
      loading: () => EpSection(header: header, children: [EpTile(title: Text(l.loading))]),
      error: (e, _) => EpSection(
        header: header,
        children: [
          EpTile(
            leading: EpIconView(EpIcon.warning, color: EpColors.of(context).caution),
            title: Text(l.routingAuthLoadFailed),
            subtitle: Text(describeError(context, e, permission: Capability.dns.permission), maxLines: 4),
            onTap: () => ref.invalidate(mailAuthProvider(zoneId)),
            trailing: EpIconView(EpIcon.refresh, color: EpColors.of(context).tint, semanticLabel: l.actionRetry),
          ),
        ],
      ),
      data: (s) {
        final inputs = s.data;
        if (!inputs.dnsAvailable) {
          return EpSection(
            header: header,
            children: [
              EpTile(
                leading: EpIconView(EpIcon.key, color: EpColors.of(context).inkMuted),
                title: Text(l.routingAuthNeedsDnsTitle),
                subtitle: Text(l.errorPermission(Capability.dns.permission), maxLines: 5),
              ),
            ],
          );
        }
        final health = evaluateMailAuth(
          inputs,
          zoneName: domain,
          routingEnabled: routingEnabled,
          requiredRecords: requiredRecords,
        );
        return EpSection(
          header: header,
          footer: inputs.emailAuthAvailable ? null : l.routingAuthNoDmarcPermission(Capability.dmarc.permission),
          children: [
            _AuthRow(kind: l.routingAuthSpf, check: health.spf, advice: _spfAdvice(context, health.spf)),
            _AuthRow(kind: l.routingAuthDkim, check: health.dkim, advice: _dkimAdvice(context, health.dkim)),
            _AuthRow(kind: l.routingAuthDmarc, check: health.dmarc, advice: _dmarcAdvice(context, health.dmarc)),
            if (health.foreignMx.isNotEmpty)
              _AuthRow(
                kind: l.routingAuthMx,
                check: const AuthCheck(AuthState.attention, AuthFinding.unavailable),
                advice: l.routingAuthForeignMx(health.foreignMx.join(', ')),
              ),
          ],
        );
      },
    );
  }

  String _spfAdvice(BuildContext context, AuthCheck c) {
    final l = context.l10n;
    return switch (c.finding) {
      AuthFinding.spfOk => c.lookups == null ? l.routingAuthSpfOk : l.routingAuthSpfOkLookups(c.lookups!),
      AuthFinding.spfMissing => routingEnabled ? l.routingAuthSpfMissingRouting : l.routingAuthSpfMissing,
      AuthFinding.spfMultiple => l.routingAuthSpfMultiple,
      AuthFinding.spfNoCloudflare => l.routingAuthSpfNoCloudflare,
      AuthFinding.spfPassAll => l.routingAuthSpfPassAll,
      AuthFinding.spfTooManyLookups => l.routingAuthSpfTooManyLookups(c.lookups ?? 11),
      AuthFinding.spfInvalid => l.routingAuthSpfInvalid(c.detail ?? ''),
      _ => l.routingAuthUnknownAdvice,
    };
  }

  String _dkimAdvice(BuildContext context, AuthCheck c) {
    final l = context.l10n;
    return switch (c.finding) {
      AuthFinding.dkimOk => l.routingAuthDkimOk,
      AuthFinding.dkimMissing => routingEnabled ? l.routingAuthDkimMissingRouting : l.routingAuthDkimMissing,
      AuthFinding.dkimOtherSelectors => l.routingAuthDkimOther(c.detail ?? ''),
      _ => l.routingAuthUnknownAdvice,
    };
  }

  String _dmarcAdvice(BuildContext context, AuthCheck c) {
    final l = context.l10n;
    return switch (c.finding) {
      AuthFinding.dmarcOk => l.routingAuthDmarcOk,
      AuthFinding.dmarcOkNoReports => l.routingAuthDmarcNoReports,
      AuthFinding.dmarcViaCname => l.routingAuthDmarcCname,
      AuthFinding.dmarcMissing => l.routingAuthDmarcMissing,
      AuthFinding.dmarcMultiple => l.routingAuthDmarcMultiple,
      AuthFinding.dmarcPolicyNone => l.routingAuthDmarcNone,
      AuthFinding.dmarcInvalid => l.routingAuthDmarcInvalid,
      AuthFinding.dmarcReportIssue => l.routingAuthDmarcReportIssue(c.detail ?? ''),
      _ => l.routingAuthUnknownAdvice,
    };
  }
}

class _AuthRow extends StatelessWidget {
  const _AuthRow({required this.kind, required this.check, required this.advice});
  final String kind;
  final AuthCheck check;
  final String advice;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final (icon, color, state) = switch (check.state) {
      AuthState.ok => (EpIcon.checkCircle, c.ok, l.routingAuthStateOk),
      AuthState.attention => (EpIcon.warning, c.caution, l.routingAuthStateAttention),
      AuthState.missing => (EpIcon.close, c.attention, l.routingAuthStateMissing),
      AuthState.unknown => (EpIcon.info, c.inkMuted, l.routingAuthStateUnknown),
    };
    final suggestion = check.suggestion;
    return MergeSemantics(
      child: EpTile(
        leading: EpIconView(icon, color: color, semanticLabel: state),
        title: Text.rich(
          TextSpan(children: [
            TextSpan(text: kind),
            TextSpan(text: '  $state', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
          maxLines: 2,
        ),
        subtitle: Text(advice, maxLines: 6),
        trailing: suggestion == null
            ? null
            : CopyIconButton(text: suggestion, label: l.routingAuthCopySuggestion(kind)),
      ),
    );
  }
}
