import 'package:go_router/go_router.dart';
import '../../core/live/live_refresh.dart';
import 'data/zone_controls_providers.dart';

import 'presentation/purge_urls_screen.dart';
import 'presentation/zone_controls_screen.dart';

/// Routes under /domains/:zoneId owned by the zone-controls feature.
final List<RouteBase> zoneControlsRoutes = [
  GoRoute(
    path: 'controls',
    builder: (c, s) => LivePoll(
      tier: LiveTier.medium,
      onTick: (ref) => ref.read(zoneControlsProvider(s.pathParameters['zoneId']!).notifier).refresh(),
      child: ZoneControlsScreen(zoneId: s.pathParameters['zoneId']!),
    ),
    routes: [
      GoRoute(
        path: 'purge-urls',
        builder: (c, s) => PurgeUrlsScreen(zoneId: s.pathParameters['zoneId']!),
      ),
    ],
  ),
];
