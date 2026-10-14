import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/layout.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/strip/strip.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../analytics/data/traffic_providers.dart';
import '../../analytics/presentation/format.dart';
import '../data/zones_providers.dart';
import 'zone_strip.dart';

enum _Filter { all, attention, pinned }

/// The Domains tab. In a split, the list sits beside a column of its own
/// ([navigator]) where the chosen domain's hub opens, and its DNS, traffic
/// and settings push inside that column, as iPad Settings does; in a narrow
/// window, [navigator] alone holds the list, then the hub over it.
class DomainsLayout extends StatelessWidget {
  const DomainsLayout({super.key, required this.zoneId, required this.navigator});

  /// The domain open, from the route.
  final String? zoneId;
  final Widget navigator;

  @override
  Widget build(BuildContext context) => EpSplit(
    list: (context, split) => DomainsScreen(split: true, selected: zoneId),
    detail: navigator,
    narrow: navigator,
  );
}

/// The Domains route's own page: the list in a narrow window; in a split,
/// the detail column's ground before a domain is chosen.
class DomainsRoot extends StatelessWidget {
  const DomainsRoot({super.key});

  @override
  Widget build(BuildContext context) => EpSplitDetail.of(context)
      ? EpSplitPlaceholder(icon: EpIcon.domains, text: context.l10n.domainsSplitPlaceholder)
      : const DomainsScreen();
}

class DomainsScreen extends ConsumerStatefulWidget {
  const DomainsScreen({super.key, this.split = false, this.selected});

  /// Beside the domain's column: a tap opens the domain there.
  final bool split;

  /// The domain open beside the list.
  final String? selected;

  @override
  ConsumerState<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends ConsumerState<DomainsScreen> {
  final _search = TextEditingController();
  _Filter _filter = _Filter.all;

  void _openZone(String id) {
    if (widget.split) {
      context.go('/domains/$id');
    } else {
      context.push('/domains/$id');
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(activeAccountProvider)!.id;
    final zonesAsync = ref.watch(zonesProvider(account));
    final pinned = ref.watch(pinnedZonesProvider(account)).value ?? const <String>{};
    final synced = zonesAsync.value;
    return _page(context, account, zonesAsync, pinned, synced);
  }

  Widget _page(
    BuildContext context,
    String account,
    AsyncValue<Synced<List<Zone>>> zonesAsync,
    Set<String> pinned,
    Synced<List<Zone>>? synced,
  ) {
    final l = context.l10n;
    return EpPage(
      title: l.tabDomains,
      account: true,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: () => Future.wait([
        ref.read(zonesProvider(account).notifier).refresh(),
        ref.read(fleetTrafficProvider(account).notifier).refresh(),
      ]),
      slivers: [
        SliverToBoxAdapter(child: _controls(context)),
        ...zonesAsync.when(
          loading: () => [const EpFill(child: EpLoading())],
          error: (e, _) => [
            EpFill(
              child: EpErrorView(error: e, onRetry: () => ref.invalidate(zonesProvider(account))),
            ),
          ],
          data: (s) => _list(context, s, pinned),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    final l = context.l10n;
    final search = isCupertino(context)
        ? CupertinoSearchTextField(
            controller: _search,
            placeholder: l.searchPlaceholder,
            onChanged: (_) => setState(() {}),
          )
        : SearchBar(
            controller: _search,
            hintText: l.searchPlaceholder,
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (_) => setState(() {}),
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xs, EpSpace.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          search,
          const SizedBox(height: EpSpace.md),
          EpSegmented<_Filter>(
            segments: {
              _Filter.all: l.domainsFilterAll,
              _Filter.attention: l.domainsFilterAttention,
              _Filter.pinned: l.domainsFilterPinned,
            },
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
        ],
      ),
    );
  }

  List<Widget> _list(BuildContext context, Synced<List<Zone>> s, Set<String> pinned) {
    final l = context.l10n;
    final q = _search.text.trim().toLowerCase();
    var zones = s.data.where((z) => q.isEmpty || z.name.contains(q)).toList();
    zones = switch (_filter) {
      _Filter.all => zones,
      _Filter.attention => zones.where((z) => zoneAttentionReason(context, z) != null).toList(),
      _Filter.pinned => zones.where((z) => pinned.contains(z.id)).toList(),
    };
    // Pinned first, then cocked strips, then alphabetical.
    zones.sort((a, b) {
      final pa = pinned.contains(a.id) ? 0 : 1, pb = pinned.contains(b.id) ? 0 : 1;
      if (pa != pb) return pa - pb;
      final aa = zoneAttentionReason(context, a) != null ? 0 : 1, ab = zoneAttentionReason(context, b) != null ? 0 : 1;
      if (aa != ab) return aa - ab;
      return a.name.compareTo(b.name);
    });

    if (s.data.isEmpty) {
      return [
        EpFill(
          child: EpMessage(icon: EpIcon.domains, title: l.domainsEmptyTitle, message: l.domainsEmptyMessage),
        ),
      ];
    }
    if (zones.isEmpty) {
      final msg = q.isNotEmpty
          ? l.emptySearch(_search.text.trim())
          : (_filter == _Filter.attention ? l.domainsAttentionEmpty : l.domainsPinnedEmpty);
      return [
        EpFill(
          child: EpMessage(icon: _filter == _Filter.attention ? EpIcon.checkCircle : EpIcon.search, title: msg),
        ),
      ];
    }

    // Requests over the last 7 days, as Today's Traffic shows them (the
    // same fleet query, shared and cached). Omitted without Analytics access.
    final traffic = ref.watch(fleetTrafficProvider(ref.watch(activeAccountProvider)!.id)).value?.data;

    // Built lazily as they scroll in, so dozens of domains stay smooth
    // through searches and refreshes.
    return [
      SliverStripBay(
        itemCount: zones.length,
        itemBuilder: (context, i) {
          final requests = traffic?[zones[i].id]?.requests;
          return ZoneStrip(
            key: ValueKey(zones[i].id),
            zone: zones[i],
            pinned: pinned.contains(zones[i].id),
            selected: widget.split && widget.selected == zones[i].id,
            onTap: () => _openZone(zones[i].id),
            extraFields: [if (requests != null) StripField(l.domainsFieldRequests, formatCompact(requests), flex: 4)],
          );
        },
      ),
    ];
  }
}
