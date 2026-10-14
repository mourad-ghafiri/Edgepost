import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/strip/strip.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/email_routing/email_routing_routes.dart';
import 'package:edgepost/features/zones/data/zones_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import 'routing_fixtures.dart';

const zoneId = 'z1';
const accountId = 'a1';
const routing = '/zones/$zoneId/email/routing';
const addresses = '/accounts/$accountId/email/routing/addresses';

final zone = fakeZone(id: zoneId);

final credential = fakeToken(caps: {
  Capability.zones: true,
  Capability.dns: true,
  Capability.emailRouting: true,
  Capability.emailAddresses: true,
  Capability.dmarc: true,
});

/// A zone with routing in [enabled] state, two address rules (one forwarding
/// to an unverified destination) and a catch-all into the mailbox.
FakeCfAdapter fakeRoutingApi({bool enabled = true}) {
  var on = enabled;
  final api = FakeCfAdapter()
    ..on('GET', routing, (_) => FakeReply.ok(settingsJson(enabled: on, status: on ? 'ready' : 'unconfigured')))
    ..reply('GET', '$routing/rules', [
      catchAllJson(type: 'worker', value: 'edgepost-mail'),
      forwardRuleJson(id: 'r1', to: 'hello@example.com', dest: 'me@gmail.com'),
      forwardRuleJson(id: 'r2', to: 'billing@example.com', dest: 'pending@gmail.com'),
      workerRuleJson(id: 'r3', to: 'support@example.com'),
    ], resultInfo: pageInfo(4))
    ..reply('GET', '$routing/rules/catch_all', catchAllJson(type: 'worker', value: 'edgepost-mail'))
    ..reply('GET', '$routing/dns', routingDnsJson())
    ..on('POST', '$routing/dns', (_) {
      on = true;
      return FakeReply.ok(settingsJson());
    })
    ..on('DELETE', '$routing/dns', (_) {
      on = false;
      return FakeReply.ok(settingsJson(enabled: false, status: 'unconfigured'));
    })
    ..on('POST', '$routing/rules', (c) => FakeReply.ok({...(c.body as Map<String, dynamic>), 'id': 'new1'}))
    ..reply('GET', addresses, [
      addressJson(id: 'd1', email: 'me@gmail.com'),
      addressJson(id: 'd2', email: 'pending@gmail.com', verified: null),
    ], resultInfo: pageInfo(2))
    ..on('GET', '/zones/$zoneId/dns_records', (c) => FakeReply.ok(
          c.query['type'] == 'TXT'
              ? [
                  {'type': 'TXT', 'name': 'example.com', 'content': '"v=spf1 include:_spf.mx.cloudflare.net ~all"'},
                  {'type': 'TXT', 'name': 'cf2024-1._domainkey.example.com', 'content': 'v=DKIM1; p=KEY'},
                  {'type': 'TXT', 'name': '_dmarc.example.com', 'content': 'v=DMARC1; p=none'},
                ]
              : [
                  {'type': 'MX', 'name': 'example.com', 'content': 'route1.mx.cloudflare.net', 'priority': 12},
                ],
          resultInfo: pageInfo(3),
        ))
    ..reply('GET', '/zones/$zoneId/email/auth/dmarc-reports', {'enabled': false, 'status': 'missing-dmarc-rua'})
    ..reply('GET', '/zones/$zoneId/email/auth/spf/inspect',
        {'domain': 'example.com', 'record': 'v=spf1', 'total_lookups': 2, 'components': <Object>[]});
  return api;
}

Widget app(FakeCfAdapter api, TargetPlatform platform, String location, {double textScale = 1}) {
  final router = GoRouter(
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/domains/:zoneId',
        builder: (c, s) => const Scaffold(body: Text('zone hub')),
        routes: emailRoutingRoutes,
      ),
    ],
  );
  final client = fakeClient(api);
  return ProviderScope(
    retry: (_, _) => null,
    overrides: [
      ...accountOverrides(tokens: [credential]),
      zoneByIdProvider.overrideWith((ref, id) => zone),
      cfClientProvider.overrideWith((ref, id) => client),
      cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
    ],
    child: MaterialApp.router(
      theme: buildEpTheme(platform, Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  );
}

/// Runs [body] with the platform override set, always resetting it.
void platformTest(String description, Future<void> Function(WidgetTester tester, TargetPlatform platform) body) {
  for (final platform in const [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('$description (${platform.name})', (tester) async {
      tester.view.physicalSize = const Size(1170, 7500);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester, platform);
        // Let toasts and snackbars time out so no timer outlives the test.
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}

Future<void> enterField(WidgetTester tester, int index, String text) async {
  await tester.enterText(find.byType(EditableText).at(index), text);
  await tester.pump();
}

/// Section headers render uppercase on iOS (grouped-list style); match either case.
Finder _header(String text) =>
    find.byWidgetPredicate((w) => w is Text && w.data?.toLowerCase() == text.toLowerCase());

void main() {
  group('Email routing screen', () {
    platformTest('shows status strip, rules, catch-all and auth health', (tester, platform) async {
      final api = fakeRoutingApi();
      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email'));
      await tester.pumpAndSettle();

      // On the status card (iOS also names the domain on the back button).
      expect(find.descendant(of: find.byType(Strip), matching: find.text('example.com')), findsOneWidget);
      expect(find.text('Ready'), findsOneWidget);
      expect(find.text('4'), findsNothing); // the catch-all isn't counted as a rule
      expect(find.text('3'), findsOneWidget);
      // One rule forwards to an unverified destination: the strip is cocked.
      expect(find.text('1 rule waits on an unverified destination and can\'t deliver yet.'), findsOneWidget);

      expect(find.text('hello@example.com'), findsOneWidget);
      expect(find.textContaining('me@gmail.com'), findsOneWidget);
      expect(find.textContaining('Edgepost mailbox'), findsWidgets);
      expect(find.textContaining('Destination not verified'), findsOneWidget);
      expect(find.text('Catch-all'), findsWidgets, reason: 'the status card\'s value label and its row');
      expect(find.text('1 waiting for verification'), findsOneWidget);

      expect(_header('Mail authentication'), findsOneWidget);
      expect(find.textContaining('Uses 2 of 10 DNS lookups'), findsOneWidget);
      expect(find.textContaining('Policy is none'), findsOneWidget);
      expect(find.text('Turn off Email Routing'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    platformTest('off: shows the records, confirms, then enables via POST /dns', (tester, platform) async {
      final api = fakeRoutingApi(enabled: false);
      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email'));
      await tester.pumpAndSettle();

      expect(find.text('Off'), findsWidgets);
      expect(find.textContaining('Routing is off.'), findsOneWidget);
      expect(find.text('route1.mx.cloudflare.net\nPriority 12'), findsOneWidget);

      await tester.tap(find.text('Turn on routing'));
      await tester.pumpAndSettle();
      expect(find.text('Turn on routing for example.com?'), findsOneWidget);
      expect(find.textContaining('example.com MX 12 route1.mx.cloudflare.net'), findsOneWidget);

      await tester.tap(find.text('Turn on routing').last);
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.method == 'POST' && c.path == '$routing/dns'), hasLength(1));
      expect(find.text('Ready'), findsOneWidget);
    });

    platformTest('disable needs the domain typed', (tester, platform) async {
      final api = fakeRoutingApi();
      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Turn off Email Routing'));
      await tester.pumpAndSettle();
      expect(find.text('Turn off Email Routing?'), findsOneWidget);

      // Confirm stays disabled until the domain is typed.
      await tester.tap(find.text('Turn off Email Routing').last);
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.method == 'DELETE'), isEmpty);

      await tester.enterText(find.byType(EditableText).last, 'example.com');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off Email Routing').last);
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.method == 'DELETE' && c.path == '$routing/dns'), hasLength(1));
    });

    platformTest('large text sizes lay out without overflow', (tester, platform) async {
      final api = fakeRoutingApi();
      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email', textScale: 2));
      await tester.pumpAndSettle();
      expect(find.text('hello@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email/rule/new', textScale: 2));
      await tester.pumpAndSettle();
      expect(find.text('@example.com'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    platformTest('permission missing shows the exact permission', (tester, platform) async {
      final api = FakeCfAdapter()..on('GET', routing, (_) => FakeReply.error(403, 10000, 'Authentication error'));
      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email'));
      await tester.pumpAndSettle();
      expect(find.textContaining(Capability.emailRouting.permission), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });

  group('Rule editor', () {
    platformTest('validates the local part before saving', (tester, platform) async {
      final api = fakeRoutingApi();
      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email/rule/new'));
      await tester.pumpAndSettle();

      expect(find.text('@example.com'), findsOneWidget);
      await enterField(tester, 0, 'two words');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Use letters, numbers'), findsOneWidget);

      await enterField(tester, 0, 'hello');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('This address already has a rule. Edit that one instead.'), findsOneWidget);
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });

    platformTest('mailbox rule posts a worker action for edgepost-mail', (tester, platform) async {
      final api = fakeRoutingApi();
      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email/rule/new'));
      await tester.pumpAndSettle();

      await enterField(tester, 0, 'sales');
      expect(find.text('Mail to sales@example.com'), findsOneWidget);
      await tester.tap(find.text('Mailbox'));
      await tester.pumpAndSettle();
      expect(find.textContaining('edgepost-mail Worker'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final post = api.calls.singleWhere((c) => c.method == 'POST');
      expect(post.path, '$routing/rules');
      expect(post.body, {
        'actions': [
          {
            'type': 'worker',
            'value': ['edgepost-mail'],
          },
        ],
        'matchers': [
          {'type': 'literal', 'field': 'to', 'value': 'sales@example.com'},
        ],
        'enabled': true,
      });
      // Popped back to the routing screen, which lists the new rule.
      expect(find.text('sales@example.com'), findsOneWidget);
    });

    platformTest('forward rule picks a destination; pending ones are flagged', (tester, platform) async {
      final api = fakeRoutingApi();
      await tester.pumpWidget(app(api, platform, '/domains/$zoneId/email/rule/new'));
      await tester.pumpAndSettle();

      await enterField(tester, 0, 'press');
      expect(find.text('Waiting for verification'), findsOneWidget);
      await tester.tap(find.text('pending@gmail.com'));
      await tester.pumpAndSettle();
      expect(find.textContaining("pending@gmail.com isn't verified yet"), findsOneWidget);
      await tester.tap(find.text('me@gmail.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final post = api.calls.singleWhere((c) => c.method == 'POST');
      expect((post.body as Map)['actions'], [
        {
          'type': 'forward',
          'value': ['me@gmail.com'],
        },
      ]);
    });
  });
}
