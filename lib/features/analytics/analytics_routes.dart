import 'package:go_router/go_router.dart';
import '../../core/live/live_refresh.dart';
import 'data/traffic_providers.dart';

import 'presentation/traffic_screen.dart';

/// Routes under /domains/:zoneId owned by the analytics feature.
final List<RouteBase> analyticsRoutes = [
  GoRoute(
    path: 'analytics',
    builder: (c, s) => LivePoll(
      tier: LiveTier.slow,
      // Only the range on screen is alive (autoDispose).
      onTick: (ref) => ref.invalidate(zoneTrafficProvider),
      child: TrafficScreen(zoneId: s.pathParameters['zoneId']!),
    ),
  ),
];
