import 'package:go_router/go_router.dart';

import '../../core/live/live_refresh.dart';
import '../../core/providers.dart';
import 'data/compute_providers.dart';

import '../registrar/presentation/registrar_screen.dart';
import 'presentation/compute_screen.dart';
import 'presentation/pages_deployment_screen.dart';
import 'presentation/pages_project_screen.dart';
import 'presentation/worker_detail_screen.dart';
import 'presentation/worker_logs_screen.dart';
import 'presentation/zone_routes_screen.dart';

/// The Compute tab (Workers, Pages and Registrar).
final GoRoute computeRoute = GoRoute(
  path: '/compute',
  builder: (c, s) => LivePoll(
    tier: LiveTier.medium,
    onTick: (ref) => ref.read(computeOverviewProvider(ref.read(activeAccountProvider)!.id).notifier).refresh(),
    child: const ComputeScreen(),
  ),
  routes: [
    GoRoute(
      path: 'workers/:script',
      builder: (c, s) => LivePoll(
        tier: LiveTier.medium,
        onTick: (ref) => ref.invalidate(workerDetailProvider),
        child: WorkerDetailScreen(script: s.pathParameters['script']!),
      ),
      routes: [
        GoRoute(path: 'logs', builder: (c, s) => WorkerLogsScreen(script: s.pathParameters['script']!)),
      ],
    ),
    GoRoute(
      path: 'pages/:project',
      builder: (c, s) => LivePoll(
        tier: LiveTier.medium,
        onTick: (ref) => ref.invalidate(pagesProjectProvider),
        child: PagesProjectScreen(project: s.pathParameters['project']!),
      ),
      routes: [
        GoRoute(
          path: 'deployments/:deploymentId',
          builder: (c, s) => PagesDeploymentScreen(
            project: s.pathParameters['project']!,
            deploymentId: s.pathParameters['deploymentId']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: 'registrar',
      builder: (c, s) => LivePoll(
        tier: LiveTier.medium,
        onTick: (ref) => ref.read(computeOverviewProvider(ref.read(activeAccountProvider)!.id).notifier).refresh(),
        child: const RegistrarScreen(),
      ),
    ),
  ],
);

/// Routes under /domains/:zoneId owned by the compute feature.
final List<RouteBase> zoneComputeRoutes = [
  GoRoute(path: 'routes', builder: (c, s) => ZoneWorkerRoutesScreen(zoneId: s.pathParameters['zoneId']!)),
];
