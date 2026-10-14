import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../data/traffic_models.dart';
import 'format.dart';

/// Series colours, both derived from the board tokens.
///
/// Total requests wear the action blue; cached requests a slate grey that
/// holds 3:1 against the card surface in both themes (light #8A93A6 ≈ 3.2:1,
/// dark #7C8394 ≈ 4.6:1) and stays apart from the blue in lightness, so the
/// two series survive colour-vision deficiency.
({Color total, Color cached}) trafficColors(BuildContext context) {
  final c = EpColors.of(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return (total: c.tint, cached: dark ? const Color(0xFF7C8394) : const Color(0xFF8A93A6));
}

/// Requests per bucket as stacked bars: the cached share at the base in slate,
/// the rest in blue, so each bar's height is the total.
class TrafficChart extends StatelessWidget {
  const TrafficChart({super.key, required this.traffic, required this.range, this.height = 200});

  final ZoneTraffic traffic;
  final TrafficRange range;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final colors = trafficColors(context);
    final l = context.l10n;
    final locale = Localizations.localeOf(context).toString();
    final points = traffic.series;
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    final peak = points.fold<int>(0, (m, p) => math.max(m, p.requests));
    final step = _niceStep(peak / 2);
    final maxY = step * 2;
    final axisStyle = EpType.numbers(TextStyle(fontSize: 11, color: c.inkMuted));
    final reservedLeft = 40.0 * scale;

    return LayoutBuilder(
      builder: (context, box) {
        final slot = (box.maxWidth - reservedLeft) / math.max(points.length, 1);
        final barWidth = (slot * 0.62).clamp(2.0, 22.0);
        final radius = Radius.circular(math.min(4, barWidth / 2));
        return SizedBox(
          height: height * math.min(scale, 1.4),
          child: BarChart(
            duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 250),
            BarChartData(
              minY: 0,
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: points[i].requests.toDouble(),
                        width: barWidth,
                        color: colors.total,
                        borderRadius: BorderRadius.vertical(top: radius),
                        rodStackItems: [
                          BarChartRodStackItem(0, points[i].cachedRequests.toDouble(), colors.cached),
                          BarChartRodStackItem(
                            points[i].cachedRequests.toDouble(),
                            points[i].requests.toDouble(),
                            colors.total,
                          ),
                        ],
                      ),
                    ],
                  ),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: step,
                getDrawingHorizontalLine: (_) => FlLine(color: c.hairline, strokeWidth: 1),
              ),
              borderData: FlBorderData(border: Border(bottom: BorderSide(color: c.hairline))),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: step,
                    reservedSize: reservedLeft,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(formatCompact(v, locale: locale), style: axisStyle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 1,
                    reservedSize: 22 * scale,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i < 0 || i >= points.length || !_showLabel(i, points.length)) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        meta: meta,
                        child: Text(_axisLabel(points[i].t, locale), style: axisStyle),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => c.inverse,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  maxContentWidth: 220,
                  tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final p = points[group.x];
                    final ratio = p.requests == 0 ? 0.0 : p.cachedRequests / p.requests;
                    final body = TextStyle(color: c.onInverse, fontSize: 13, fontFeatures: const [FontFeature.tabularFigures()]);
                    return BarTooltipItem(
                      '${_tooltipWhen(p.t, locale)}\n',
                      TextStyle(color: c.onInverse.withValues(alpha: 0.72), fontSize: 12, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.start,
                      children: [
                        TextSpan(text: '${l.trafficTooltipRequests(formatCount(p.requests, locale: locale))}\n', style: body),
                        TextSpan(
                          text: l.trafficTooltipCached(
                            formatCount(p.cachedRequests, locale: locale),
                            formatPercent(ratio, locale: locale),
                          ),
                          style: body,
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Sparse x labels: every 6 hours, every day of a week, every 7th day of a
  /// month counted back from today.
  bool _showLabel(int i, int n) => switch (range) {
        TrafficRange.last24h => points(i).t.hour % 6 == 0,
        TrafficRange.last7d => true,
        TrafficRange.last30d => (n - 1 - i) % 7 == 0,
      };

  TrafficPoint points(int i) => traffic.series[i];

  String _axisLabel(DateTime t, String locale) => switch (range) {
        TrafficRange.last24h => DateFormat.j(locale).format(t),
        TrafficRange.last7d => DateFormat.E(locale).format(t),
        TrafficRange.last30d => DateFormat.MMMd(locale).format(t),
      };

  String _tooltipWhen(DateTime t, String locale) =>
      range.hourly ? DateFormat.MMMd(locale).add_j().format(t) : DateFormat.MMMEd(locale).format(t);

  /// Smallest of 1, 2, 5 × 10ⁿ at or above [v], never below 1.
  static double _niceStep(double v) {
    if (v <= 1) return 1;
    final exp = math.pow(10, (math.log(v) / math.ln10).floor()).toDouble();
    final f = v / exp;
    final nice = f <= 1 ? 1 : (f <= 2 ? 2 : (f <= 5 ? 5 : 10));
    return nice * exp;
  }
}

/// One-sentence description of the chart for screen readers.
String trafficChartSummary(BuildContext context, ZoneTraffic t, TrafficRange range, String rangeLabel) {
  final l = context.l10n;
  final locale = Localizations.localeOf(context).toString();
  var peak = t.series.isEmpty ? null : t.series.first;
  for (final p in t.series) {
    if (p.requests > (peak?.requests ?? -1)) peak = p;
  }
  final when = peak == null
      ? '—'
      : (range.hourly ? DateFormat.MMMd(locale).add_j().format(peak.t) : DateFormat.MMMEd(locale).format(peak.t));
  return l.trafficChartSummary(
    range.hourly ? l.trafficChartHourly : l.trafficChartDaily,
    rangeLabel,
    formatCount(t.requests, locale: locale),
    formatPercent(t.cachedRatio, locale: locale),
    formatCount(peak?.requests ?? 0, locale: locale),
    when,
  );
}
