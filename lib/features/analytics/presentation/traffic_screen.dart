import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../zones/data/zones_providers.dart';
import '../data/traffic_providers.dart';
import 'format.dart';
import 'traffic_board.dart';
import 'traffic_chart.dart';

/// Requests, bandwidth, cache share, threats and visitors for one domain.
class TrafficScreen extends ConsumerStatefulWidget {
  const TrafficScreen({super.key, required this.zoneId, this.initialRange = TrafficRange.last7d});
  final String zoneId;
  final TrafficRange initialRange;

  @override
  ConsumerState<TrafficScreen> createState() => _TrafficScreenState();
}

class _TrafficScreenState extends ConsumerState<TrafficScreen> {
  late TrafficRange _range = widget.initialRange;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final zone = ref.watch(zoneByIdProvider(widget.zoneId));
    if (zone == null) {
      return EpPage(title: l.trafficTitle, largeTitle: false, slivers: const [EpFill(child: EpLoading())]);
    }
    final key = (widget.zoneId, _range);
    final async = ref.watch(zoneTrafficProvider(key));
    final synced = async.value;

    return EpPage(
      title: l.trafficTitle,
      largeTitle: false,
      previousPageTitle: zone.name,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => ref.read(zoneTrafficProvider(key).notifier).refresh(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, EpSpace.lg),
            child: Center(
              child: EpSegmented<TrafficRange>(
                segments: {for (final r in TrafficRange.values) r: _rangeLabel(l, r)},
                value: _range,
                onChanged: (r) => setState(() => _range = r),
              ),
            ),
          ),
        ),
        ...async.when(
          loading: () => [const EpFill(child: EpLoading())],
          error: (e, _) => [EpFill(child: _error(context, e, key))],
          data: (s) => _content(context, zone, s.data),
        ),
      ],
    );
  }

  List<Widget> _content(BuildContext context, Zone zone, ZoneTraffic t) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final locale = Localizations.localeOf(context).toString();
    if (t.isEmpty) {
      return [
        EpFill(
          child: EpMessage(
            icon: EpIcon.chart,
            title: l.trafficEmptyTitle,
            message: l.trafficEmptyMessage(zone.name),
          ),
        ),
      ];
    }
    final colors = trafficColors(context);
    final chartTitle = _range.hourly ? l.trafficChartHourly : l.trafficChartDaily;
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
          child: TrafficBoard(
            title: zone.name,
            caption: _caption(l, _range),
            fields: [
              BoardField(l.trafficFieldRequests, formatCompact(t.requests, locale: locale),
                  semanticValue: formatCount(t.requests, locale: locale)),
              BoardField(l.trafficFieldBandwidth, formatBytes(t.bytes, locale: locale)),
              BoardField(l.trafficFieldCached, formatPercent(t.cachedRatio, locale: locale)),
              BoardField(l.trafficFieldThreats, formatCompact(t.threats, locale: locale),
                  semanticValue: formatCount(t.threats, locale: locale)),
              BoardField(l.trafficFieldVisitors, formatCompact(t.uniques, locale: locale),
                  semanticValue: formatCount(t.uniques, locale: locale)),
              BoardField(l.trafficFieldPageViews, formatCompact(t.pageViews, locale: locale),
                  semanticValue: formatCount(t.pageViews, locale: locale)),
            ],
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xl, EpSpace.lg, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(chartTitle, style: Theme.of(context).textTheme.titleSmall)),
              const SizedBox(height: EpSpace.sm),
              ExcludeSemantics(
                child: Wrap(
                  spacing: EpSpace.lg,
                  runSpacing: EpSpace.xs,
                  children: [
                    _LegendKey(color: colors.total, label: l.trafficLegendAll),
                    _LegendKey(color: colors.cached, label: l.trafficLegendCached),
                  ],
                ),
              ),
              const SizedBox(height: EpSpace.md),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(EpRadius.md),
                  border: Border.all(color: c.hairline),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(EpSpace.xs, EpSpace.lg, EpSpace.md, EpSpace.sm),
                  child: Semantics(
                    container: true,
                    label: trafficChartSummary(context, t, _range, _caption(l, _range)),
                    child: ExcludeSemantics(child: TrafficChart(traffic: t, range: _range)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  Widget _error(BuildContext context, Object e, (String, TrafficRange) key) {
    final l = context.l10n;
    if (e is TrafficRangeUnavailableException) {
      final shorter = switch (_range) {
        TrafficRange.last30d => TrafficRange.last7d,
        TrafficRange.last7d => TrafficRange.last24h,
        TrafficRange.last24h => null,
      };
      return EpMessage(
        icon: EpIcon.calendar,
        title: l.trafficRangeUnavailableTitle,
        message: l.trafficRangeUnavailableMessage,
        action: shorter == null
            ? null
            : EpButton(
                label: l.trafficShowRange(_rangeLabel(l, shorter)),
                secondary: true,
                onPressed: () => setState(() => _range = shorter),
              ),
      );
    }
    return EpErrorView(
      error: e,
      permission: Capability.analytics.permission,
      onRetry: () => ref.invalidate(zoneTrafficProvider(key)),
    );
  }

  static String _rangeLabel(AppLocalizations l, TrafficRange r) => switch (r) {
        TrafficRange.last24h => l.trafficRange24h,
        TrafficRange.last7d => l.trafficRange7d,
        TrafficRange.last30d => l.trafficRange30d,
      };

  static String _caption(AppLocalizations l, TrafficRange r) => switch (r) {
        TrafficRange.last24h => l.trafficCaption24h,
        TrafficRange.last7d => l.trafficCaption7d,
        TrafficRange.last30d => l.trafficCaption30d,
      };
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(EpRadius.pill)),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 13, color: c.inkMuted)),
      ],
    );
  }
}
