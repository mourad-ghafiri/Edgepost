import 'package:go_router/go_router.dart';
import '../../core/live/live_refresh.dart';
import 'data/dns_providers.dart';

import 'presentation/dns_editor_screen.dart';
import 'presentation/dns_list_screen.dart';
import 'presentation/dns_mail_check_screen.dart';
import 'presentation/dns_template_screen.dart';
import 'presentation/dns_widgets.dart';

/// Routes under /domains/:zoneId owned by the DNS feature:
/// - `dns`: record list
/// - `dns/new?type=TXT&name=_dmarc&content=…`: new record (all query optional)
/// - `dns/mail-check`: MX / SPF / DMARC / DKIM report
/// - `dns/template/point`, `dns/template/verify`: quick templates
/// - `dns/:recordId`: edit one record
final List<RouteBase> dnsRoutes = [
  GoRoute(
    path: 'dns',
    builder: (c, s) => LivePoll(
      tier: LiveTier.medium,
      onTick: (ref) => ref.read(dnsRecordsProvider(s.pathParameters['zoneId']!).notifier).refresh(),
      child: DnsListScreen(zoneId: s.pathParameters['zoneId']!),
    ),
    routes: [
      GoRoute(
        path: 'new',
        builder: (c, s) => DnsEditorScreen(
          zoneId: s.pathParameters['zoneId']!,
          initialType: s.uri.queryParameters['type'],
          initialName: s.uri.queryParameters['name'],
          initialContent: s.uri.queryParameters['content'],
          openedFromList: s.extra == kDnsEditorFromList,
        ),
      ),
      GoRoute(
        path: 'mail-check',
        builder: (c, s) => DnsMailCheckScreen(zoneId: s.pathParameters['zoneId']!),
      ),
      GoRoute(
        path: 'template/:kind',
        builder: (c, s) => DnsTemplateScreen(
          zoneId: s.pathParameters['zoneId']!,
          template: s.pathParameters['kind'] == 'verify' ? DnsTemplate.verify : DnsTemplate.point,
        ),
      ),
      GoRoute(
        path: ':recordId',
        builder: (c, s) => DnsEditorScreen(
          zoneId: s.pathParameters['zoneId']!,
          recordId: s.pathParameters['recordId'],
          openedFromList: s.extra == kDnsEditorFromList,
        ),
      ),
    ],
  ),
];
