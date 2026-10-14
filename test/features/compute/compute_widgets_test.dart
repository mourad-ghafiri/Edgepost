import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/compute/presentation/compute_screen.dart';
import 'package:edgepost/features/compute/presentation/pages_project_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';
import 'compute_fixtures.dart';

Widget _app(TargetPlatform platform, Widget home, List<Credential> tokens, FakeCfAdapter api) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    ...accountOverrides(tokens: tokens),
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

FakeCfAdapter _computeApi() => FakeCfAdapter()
  ..reply('GET', '/accounts/a1/workers/scripts', [scriptJson('api-gateway', routes: 2)])
  ..reply('GET', '/accounts/a1/pages/projects', [
    pagesProjectJson(
      'docs-site',
      latest: pagesDeploymentJson(stage: 'build', status: 'failure'),
    ),
    pagesProjectJson('portfolio'),
  ], resultInfo: resultInfo(count: 2))
  ..reply(
    'GET',
    '/accounts/a1/registrar/registrations',
    [registrationJson('example.dev', expires: DateTime.now().toUtc().add(const Duration(days: 9)).toIso8601String())],
    resultInfo: {'count': 1, 'cursor': ''},
  );

/// Runs [body] with the platform overridden, resetting it before the test
/// ends (the binding checks foundation debug variables at the end of the body).
Future<void> onPlatform(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group(platform.name, () {
      testWidgets(
        'Compute tab shows the account\'s bays, a cocked failed build and Registrar',
        (tester) => onPlatform(platform, () async {
          await tester.pumpWidget(_app(platform, const ComputeScreen(), [token('user')], _computeApi()));
          await tester.pumpAndSettle();

          expect(find.text('Compute'), findsWidgets);
          // One account: one bay per kind, no account names.
          expect(find.text('WORKERS'), findsOneWidget);
          expect(find.text('PAGES'), findsOneWidget);
          expect(find.text('api-gateway'), findsOneWidget);
          // Failed latest build is cocked with its reason.
          expect(find.textContaining('Last build on main failed'), findsOneWidget);
          // Registrar row summarises what needs the user.
          await tester.scrollUntilVisible(find.text('Registered domains'), 200);
          expect(find.text('1 domain needs you'), findsOneWidget);
          final note = find.textContaining('Cloudflare recommends starting new projects on Workers');
          await tester.scrollUntilVisible(note, 200);
          expect(note, findsOneWidget);
        }),
      );

      testWidgets(
        'an account-owned token: the Pages bay and Registrar explain what is missing',
        (tester) => onPlatform(platform, () async {
          final api = FakeCfAdapter()..reply('GET', '/accounts/a1/workers/scripts', [scriptJson('client-worker')]);
          final tokens = [token('acct', kind: TokenKind.account, caps: {Capability.workers})];
          await tester.pumpWidget(_app(platform, const ComputeScreen(), tokens, api));
          await tester.pumpAndSettle();

          expect(find.text('client-worker'), findsOneWidget);
          // No Pages permission, explained in the bay.
          expect(find.textContaining(Capability.pages.permission), findsOneWidget);
          await tester.scrollUntilVisible(find.text('Registered domains'), 200);
          expect(find.textContaining('account-owned'), findsWidgets);
          expect(api.calls.map((c) => c.path), ['/accounts/a1/workers/scripts']);
        }),
      );

      testWidgets(
        'Compute tab explains missing permissions',
        (tester) => onPlatform(platform, () async {
          final creds = [
            token('user', caps: const {}),
          ];
          await tester.pumpWidget(_app(platform, const ComputeScreen(), creds, FakeCfAdapter()));
          await tester.pumpAndSettle();
          expect(find.text('No access to Workers or Pages'), findsOneWidget);
        }),
      );

      testWidgets(
        'Pages project screen lists domains and deployments',
        (tester) => onPlatform(platform, () async {
          final api = FakeCfAdapter()
            ..reply('GET', '/accounts/a1/pages/projects/docs-site', pagesProjectJson('docs-site'))
            ..reply('GET', '/accounts/a1/pages/projects/docs-site/deployments', [
              pagesDeploymentJson(
                id: 'new-1',
                shortId: 'a1b2c3d4',
                stage: 'build',
                status: 'failure',
                message: 'Break the build',
              ),
              pagesDeploymentJson(),
            ], resultInfo: resultInfo(count: 2))
            ..reply('GET', '/accounts/a1/pages/projects/docs-site/domains', [
              {
                'id': 'd1',
                'name': 'docs.example.com',
                'status': 'active',
                'validation_data': {'status': 'active'},
              },
            ]);
          await tester.pumpWidget(
            _app(platform, const PagesProjectScreen(project: 'docs-site'), [token('user')], api),
          );
          await tester.pumpAndSettle();

          expect(find.text('docs-site'), findsWidgets);
          expect(find.text('docs-site.pages.dev'), findsOneWidget);
          expect(find.text('docs.example.com'), findsOneWidget);
          await tester.scrollUntilVisible(find.text('a1b2c3d4'), 200);
          expect(find.text('Break the build'), findsOneWidget);
          expect(find.text('Failed'), findsWidgets);
          // The canonical deployment is marked live.
          await tester.scrollUntilVisible(find.text('f64788e9'), 200);
          expect(find.textContaining('Live'), findsWidgets);
        }),
      );
    });
  }
}
