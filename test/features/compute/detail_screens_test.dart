import 'dart:async';

import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/compute/data/tail.dart';
import 'package:edgepost/features/compute/presentation/pages_deployment_screen.dart';
import 'package:edgepost/features/compute/presentation/worker_detail_screen.dart';
import 'package:edgepost/features/compute/presentation/worker_logs_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';
import 'compute_fixtures.dart';

Widget _app(TargetPlatform platform, Widget home, FakeCfAdapter api) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    ...accountOverrides(tokens: [token('user')]),
    cfClientProvider.overrideWith((ref, id) => fakeClient(api)),
    cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
  ],
  child: MaterialApp(
    theme: buildEpTheme(platform, Brightness.light),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  ),
);

Future<void> onPlatform(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

class _Socket implements TailSocket {
  final controller = StreamController<Object?>();
  bool closed = false;

  @override
  Future<void> get ready async {}
  @override
  Stream<Object?> get stream => controller.stream;
  @override
  void send(String message) {}
  @override
  Future<void> close() async {
    closed = true;
    await controller.close();
  }
}

FakeCfAdapter _workerApi() {
  const base = '/accounts/a1/workers/scripts/api-gateway';
  return FakeCfAdapter()
    ..reply('GET', '$base/settings', {
      'compatibility_date': '2026-09-01',
      'compatibility_flags': ['nodejs_compat'],
    })
    ..reply('GET', '$base/subdomain', {'enabled': true, 'previews_enabled': false})
    ..reply('GET', '/accounts/a1/workers/subdomain', {'subdomain': 'my-subdomain'})
    ..reply('GET', '/accounts/a1/workers/domains', [
      {
        'id': 'd1',
        'hostname': 'api.example.com',
        'service': 'api-gateway',
        'zone_id': 'z1',
        'zone_name': 'example.com',
      },
    ])
    ..reply('GET', '$base/deployments', {
      'deployments': [
        {
          'id': 'dep-2',
          'created_on': '2026-10-12T08:00:00Z',
          'source': 'wrangler',
          'strategy': 'percentage',
          'versions': [
            {'version_id': '11111111-0000-4000-8000-000000000012', 'percentage': 100},
          ],
        },
        {
          'id': 'dep-1',
          'created_on': '2026-10-01T08:00:00Z',
          'source': 'api',
          'strategy': 'percentage',
          'versions': [
            {'version_id': '11111111-0000-4000-8000-000000000011', 'percentage': 100},
          ],
        },
      ],
    })
    ..reply('GET', '$base/versions', {
      'items': [
        {
          'id': '11111111-0000-4000-8000-000000000012',
          'number': 12,
          'metadata': {'created_on': '2026-10-12T07:59:00Z', 'source': 'wrangler', 'author_email': 'dev@example.com'},
        },
        {
          'id': '11111111-0000-4000-8000-000000000011',
          'number': 11,
          'metadata': {'created_on': '2026-10-01T07:59:00Z', 'source': 'dash'},
        },
      ],
    })
    ..on('GET', '$base/secrets', (_) => FakeReply.error(403, 10000, 'Authentication error'));
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group(platform.name, () {
      testWidgets(
        'Worker detail shows triggers, deployment, versions and a per-section permission error',
        (tester) => onPlatform(platform, () async {
          await tester.pumpWidget(
            _app(
              platform,
              const WorkerDetailScreen(script: 'api-gateway'),
              _workerApi(),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('https://api-gateway.my-subdomain.workers.dev'), findsOneWidget);
          await tester.scrollUntilVisible(find.text('api.example.com'), 200, scrollable: find.byType(Scrollable).first);
          await tester.scrollUntilVisible(find.text('Serving now'), 200, scrollable: find.byType(Scrollable).first);
          expect(find.text('Version 12'), findsWidgets);
          await tester.scrollUntilVisible(find.text('Version 11').last, 200, scrollable: find.byType(Scrollable).first);
          await tester.scrollUntilVisible(find.textContaining('Workers Scripts'), 200, scrollable: find.byType(Scrollable).first);
          expect(tester.takeException(), isNull);
        }),
      );

      testWidgets(
        'Live logs stream events and delete the tail on leave',
        (tester) => onPlatform(platform, () async {
          final api = FakeCfAdapter()
            ..reply('POST', '/accounts/a1/workers/scripts/api-gateway/tails', {
              'id': 'tail1',
              'url': 'wss://tail.example.test/tail1',
              'expires_at': '2026-10-12T15:00:00Z',
            })
            ..reply('DELETE', '/accounts/a1/workers/scripts/api-gateway/tails/tail1', null);
          final socket = _Socket();
          await tester.pumpWidget(
            _app(
              platform,
              WorkerLogsScreen(script: 'api-gateway', connector: (_) => socket),
              api,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Waiting for api-gateway to run…'), findsOneWidget);

          socket.controller.add(
            '{"outcome":"exception","eventTimestamp":1760259601100,'
            '"logs":[{"message":["boom"],"level":"error","timestamp":1760259601190}],'
            '"exceptions":[{"name":"TypeError","message":"x is undefined","timestamp":1760259601200}],'
            '"event":{"request":{"url":"https://api.example.com/users","method":"GET"},"response":{"status":500}}}',
          );
          await tester.pumpAndSettle();
          expect(find.textContaining('GET https://api.example.com/users → 500', findRichText: true), findsOneWidget);
          expect(find.textContaining('TypeError: x is undefined'), findsOneWidget);

          await tester.pumpWidget(const SizedBox());
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pumpAndSettle();
          expect(socket.closed, isTrue);
          expect(api.calls.where((c) => c.method == 'DELETE'), hasLength(1));
        }),
      );

      testWidgets(
        'Pages deployment shows stages, build log and rollback for an older production deploy',
        (tester) => onPlatform(platform, () async {
          final api = FakeCfAdapter()
            ..reply(
              'GET',
              '/accounts/a1/pages/projects/docs-site',
              pagesProjectJson(
                'docs-site',
                canonical: pagesDeploymentJson(id: 'live-1', shortId: 'live0001'),
              ),
            )
            ..reply('GET', '/accounts/a1/pages/projects/docs-site/deployments', [
              pagesDeploymentJson(id: 'live-1', shortId: 'live0001'),
              pagesDeploymentJson(id: 'old-1', shortId: 'old00001'),
            ])
            ..reply('GET', '/accounts/a1/pages/projects/docs-site/domains', <Object>[])
            ..reply(
              'GET',
              '/accounts/a1/pages/projects/docs-site/deployments/old-1',
              pagesDeploymentJson(id: 'old-1', shortId: 'old00001'),
            )
            ..reply('GET', '/accounts/a1/pages/projects/docs-site/deployments/old-1/history/logs', {
              'data': [
                {'line': 'Cloning repository...', 'ts': '2026-10-12T07:00:01Z'},
                {'line': 'Success: Build command completed', 'ts': '2026-10-12T07:02:00Z'},
              ],
              'includes_container_logs': true,
              'total': 2,
            });
          await tester.pumpWidget(
            _app(
              platform,
              const PagesDeploymentScreen(project: 'docs-site', deploymentId: 'old-1'),
              api,
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Roll back production to this'), findsOneWidget);
          await tester.scrollUntilVisible(find.text('Clone repository'), 200, scrollable: find.byType(Scrollable).first);
          await tester.scrollUntilVisible(find.textContaining('Cloning repository...', findRichText: true), 200, scrollable: find.byType(Scrollable).first);
          expect(tester.takeException(), isNull);
        }),
      );
    });
  }
}
