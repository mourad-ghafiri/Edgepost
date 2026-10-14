import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../../mail/data/mail_live.dart';
import '../data/billable_usage.dart';

/// Everything the Budget strip shows for one account.
class BudgetSummary {
  const BudgetSummary({
    required this.hasBilling,
    required this.billingGranted,
    required this.cost,
    required this.currency,
    required this.sent,
    required this.limit,
    this.periodEnd,
    this.billingError,
  });

  /// A token may read billing and the last fetch worked.
  final bool hasBilling;

  /// A token may read billing (a failed fetch is not a permission problem).
  final bool billingGranted;
  final double? cost;
  final String currency;
  final int sent;
  final int limit;
  final DateTime? periodEnd;
  final Object? billingError;

  double get sendRatio => limit <= 0 ? (sent > 0 ? 1 : 0) : sent / limit;
  bool get sendHigh => limit > 0 && sendRatio >= 0.8;
  bool get costing => (cost ?? 0) > 0.004;
  bool get needsAttention => sendHigh || costing;
  int get left => (limit - sent).clamp(0, limit);

  int? get daysLeft => periodEnd == null ? null : periodEnd!.difference(DateTime.now()).inHours ~/ 24;
}

final budgetSummaryProvider = Provider.family<BudgetSummary, String>((ref, accountId) {
  final usage = ref.watch(billableUsageProvider(accountId));
  final data = usage.value?.data;
  // Usage data that arrived proves access even before a permission check
  // confirmed it; only an account no token may bill gets the hint.
  final granted = data != null || ref.watch(accessProvider.select((a) => a.best(accountId, Capability.billing))) == CapState.granted;
  // Totals as a record: equal values don't rebuild on every 5 s pulse.
  final (sent, limit) = ref.watch(mailLiveProvider.select((s) {
    final u = s.usageByAccount[accountId];
    return (u?.used ?? 0, u?.limit ?? 0);
  }));
  return BudgetSummary(
    hasBilling: data != null && !usage.hasError,
    billingGranted: granted,
    cost: data?.totalCost,
    currency: data?.currency ?? 'USD',
    sent: sent,
    limit: limit,
    periodEnd: data?.periodEnd,
    billingError: usage.error ?? usage.value?.refreshError,
  );
});

String formatMoney(BuildContext context, double amount, String currency) =>
    NumberFormat.simpleCurrency(locale: Localizations.localeOf(context).toLanguageTag(), name: currency).format(amount);

/// The Today strip: what usage costs this period, sends left before the
/// sending limit, and when the period ends. Cocked when sending passes 80% of
/// the limit or usage costs money.
class BudgetStrip extends ConsumerWidget {
  const BudgetStrip({super.key, required this.accountId, this.onTap, this.showHint = true});
  final String accountId;
  final VoidCallback? onTap;

  /// The one-line billing hint under the meter (the Budget screen explains
  /// it in full instead).
  final bool showHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final b = ref.watch(budgetSummaryProvider(accountId));
    final fmt = NumberFormat.decimalPattern();
    final pct = NumberFormat.percentPattern().format(b.sendRatio.clamp(0, 9.99));
    final reason = b.costing
        ? l.budgetReasonCost(formatMoney(context, b.cost!, b.currency))
        : (b.sendHigh ? l.budgetReasonSendCap(pct) : null);
    final meterColor = b.sendRatio >= 1 ? c.attention : (b.sendHigh ? c.caution : c.ok);
    final known = b.limit > 0 || b.sent > 0;
    final cost = b.hasBilling && b.cost != null ? formatMoney(context, b.cost!, b.currency) : '—';
    final left = !known ? '—' : (b.limit == 0 ? l.budgetSendingOff : fmt.format(b.left));
    final hint = !showHint
        ? null
        : (!b.billingGranted ? l.budgetNoBillingShort : (b.billingError != null && !b.hasBilling ? l.budgetUsageUnavailableShort : null));
    return Strip(
      title: l.budgetTitle,
      caption: l.budgetCallsign,
      family: Family.neutral,
      cocked: reason != null,
      reason: reason,
      onTap: onTap,
      semanticLabel: [
        l.budgetTitle,
        if (cost != '—') '${l.budgetUsageCost} $cost',
        if (known) l.budgetSemantic(fmt.format(b.sent), fmt.format(b.limit), fmt.format(b.left)),
        if (b.daysLeft != null) l.budgetDaysLeft(b.daysLeft!.clamp(0, 99)),
        ?reason,
      ].join(', '),
      fields: [
        StripField(l.budgetUsageCost, cost, color: b.costing ? c.attention : null),
        StripField(l.budgetSendsLeft, left, color: b.sendRatio >= 1 ? c.attention : (b.sendHigh ? c.caution : null)),
        if (b.daysLeft != null) StripField(l.budgetPeriodField, l.budgetDaysLeft(b.daysLeft!.clamp(0, 99))),
      ],
      detail: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BudgetMeter(ratio: b.sendRatio.clamp(0, 1).toDouble(), color: meterColor),
          if (known) ...[
            const SizedBox(height: EpSpace.xs),
            Text(
              l.budgetMeterCaption(fmt.format(b.sent), fmt.format(b.limit)),
              style: EpType.numbers(TextStyle(color: c.inkMuted, fontSize: 13)),
            ),
          ],
          if (hint != null) ...[
            const SizedBox(height: EpSpace.xs),
            Text(hint, style: TextStyle(color: c.inkMuted, fontSize: 13)),
          ],
        ],
      ),
    );
  }
}

/// Thin animated meter; fills from the current value, no motion when the
/// user asked for less.
class BudgetMeter extends StatelessWidget {
  const BudgetMeter({super.key, required this.ratio, required this.color});
  final double ratio;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(EpRadius.pill),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: ratio),
        duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 600),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 6, color: color, backgroundColor: c.hairline),
      ),
    );
  }
}
