import 'package:go_router/go_router.dart';
import '../../core/live/live_refresh.dart';
import 'data/email_routing_providers.dart';

import 'presentation/destination_addresses_screen.dart';
import 'presentation/email_routing_screen.dart';
import 'presentation/rule_editor_screen.dart';

/// Routes under /domains/:zoneId owned by the email-routing feature:
///   email                 Email Routing overview
///   email/rule/new        new address rule
///   email/rule/:ruleId    edit an address rule
///   email/addresses       the account's destination addresses
final List<RouteBase> emailRoutingRoutes = [
  GoRoute(
    path: 'email',
    builder: (c, s) => LivePoll(
      tier: LiveTier.medium,
      onTick: (ref) => ref.read(routingOverviewProvider(s.pathParameters['zoneId']!).notifier).refresh(),
      child: EmailRoutingScreen(zoneId: s.pathParameters['zoneId']!),
    ),
    routes: [
      // 'rule/new' is listed before 'rule/:ruleId' so it wins the match.
      GoRoute(
        path: 'rule/new',
        builder: (c, s) => RuleEditorScreen(zoneId: s.pathParameters['zoneId']!),
      ),
      GoRoute(
        path: 'rule/:ruleId',
        builder: (c, s) => RuleEditorScreen(zoneId: s.pathParameters['zoneId']!, ruleId: s.pathParameters['ruleId']),
      ),
      GoRoute(
        path: 'addresses',
        builder: (c, s) => DestinationAddressesScreen(zoneId: s.pathParameters['zoneId']!),
      ),
    ],
  ),
];
