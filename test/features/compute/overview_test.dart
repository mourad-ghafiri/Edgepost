import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/cloudflare/cf_errors.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/features/compute/data/compute_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';
import 'compute_fixtures.dart';

ProviderContainer container(List<Credential> tokens, Map<String, FakeCfAdapter> apis) {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...accountOverrides(tokens: tokens),
      cfClientProvider.overrideWith((ref, id) => fakeClient(apis[id]!)),
      cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

Future<ComputeOverview> load(ProviderContainer c) async => (await c.read(computeOverviewProvider(testAccount.id).future)).data;

const _base = '/accounts/a1';

void main() {
  test('one list call per kind for the account, with attention and a cache round trip', () async {
    final soon = DateTime.now().toUtc().add(const Duration(days: 12)).toIso8601String();
    final later = DateTime.now().toUtc().add(const Duration(days: 200)).toIso8601String();
    final api = FakeCfAdapter()
      ..reply('GET', '$_base/workers/scripts', [scriptJson('cron-jobs', routes: 0), scriptJson('api-gateway')])
      ..reply('GET', '$_base/pages/projects', [
        pagesProjectJson('portfolio'),
        pagesProjectJson('docs-site', latest: pagesDeploymentJson(stage: 'build', status: 'failure')),
      ], resultInfo: resultInfo(count: 2))
      ..reply(
        'GET',
        '$_base/registrar/registrations',
        [
          registrationJson('example.com', expires: later, autoRenew: true),
          registrationJson('example.dev', expires: soon),
          registrationJson('studio.io', expires: soon, autoRenew: true),
        ],
        resultInfo: {'count': 3, 'cursor': '', 'per_page': 50},
      );
    final c = container([token('user')], {'user': api});

    final o = await load(c);

    expect(o.workers.map((w) => w.name), ['api-gateway', 'cron-jobs'], reason: 'sorted by name');
    expect(o.pages.map((p) => p.name), ['docs-site', 'portfolio']);
    expect(o.pages.where((p) => p.latestStatus == DeployStatus.failed).single.name, 'docs-site');
    expect(o.registrar.last.name, 'example.com', reason: 'soonest expiry first');
    expect(o.registrarAttention().single.name, 'example.dev', reason: 'auto-renew on keeps studio.io in line');
    expect(o.gaps, isEmpty);
    expect(o.worker('api-gateway')?.name, 'api-gateway');
    expect(o.project('portfolio')?.name, 'portfolio');
    expect(api.calls.map((x) => x.path).toSet(), {
      '$_base/workers/scripts',
      '$_base/pages/projects',
      '$_base/registrar/registrations',
    });
    expect(api.calls, hasLength(3));

    // Cache round trip keeps everything the Today screen reads.
    final back = ComputeOverview.fromJson(o.toJson());
    expect(back.pages.first.latestStatus, o.pages.first.latestStatus);
    expect(back.registrar.length, 3);
    expect(back.gaps, isEmpty);
  });

  test('an account-owned token: Pages it may not list, Registrar needs a user token', () async {
    final api = FakeCfAdapter()..reply('GET', '$_base/workers/scripts', [scriptJson('client-worker')]);
    final c = container([token('acct', kind: TokenKind.account, caps: {Capability.workers})], {'acct': api});

    final o = await load(c);

    expect(o.workers.single.name, 'client-worker');
    expect(o.gapFor(ComputeKind.workers), isNull);
    expect(o.gapFor(ComputeKind.pages)?.reason, GapReason.permission);
    expect(o.gapFor(ComputeKind.registrar)?.reason, GapReason.userToken);
    expect(o.gaps, hasLength(2));
    expect(api.calls.map((x) => x.path), ['$_base/workers/scripts'], reason: 'nothing is asked of a token that may not');

    final back = ComputeOverview.fromJson(o.toJson());
    expect(back.gaps.map((g) => g.reason), o.gaps.map((g) => g.reason));
  });

  test('each kind is listed once, by the earliest token allowed to', () async {
    // Added first: account-owned, Workers only. Added second: a user token
    // with everything.
    final acctApi = FakeCfAdapter()..reply('GET', '$_base/workers/scripts', [scriptJson('api-gateway')]);
    final userApi = FakeCfAdapter()
      ..reply('GET', '$_base/pages/projects', [pagesProjectJson('portfolio')], resultInfo: resultInfo())
      ..reply('GET', '$_base/registrar/registrations', <Object>[], resultInfo: {'count': 0, 'cursor': ''});
    final c = container(
      [token('acct', kind: TokenKind.account, caps: {Capability.workers}), token('user')],
      {'acct': acctApi, 'user': userApi},
    );

    final o = await load(c);

    expect(o.gaps, isEmpty);
    expect(o.workers.single.name, 'api-gateway');
    expect(o.pages.single.name, 'portfolio');
    expect(acctApi.calls.map((x) => x.path), ['$_base/workers/scripts']);
    expect(userApi.calls.map((x) => x.path).toSet(), {'$_base/pages/projects', '$_base/registrar/registrations'});
  });

  test('no token reaching the account: every kind is a permission gap, no calls', () async {
    final api = FakeCfAdapter();
    final c = container([token('user', accounts: [otherAccount])], {'user': api});

    final o = await load(c);

    expect(o.gaps.map((g) => g.reason), everyElement(GapReason.permission));
    expect(o.gaps, hasLength(ComputeKind.values.length));
    expect(api.calls, isEmpty);
  });

  test('a 403 becomes a gap, other kinds still load', () async {
    final api = FakeCfAdapter()
      ..reply('GET', '$_base/workers/scripts', [scriptJson('api-gateway')])
      ..on('GET', '$_base/pages/projects', (_) => FakeReply.error(403, 10000, 'Authentication error'))
      ..reply('GET', '$_base/registrar/registrations', <Object>[], resultInfo: {'count': 0, 'cursor': ''});
    final c = container([token('user')], {'user': api});
    final o = await load(c);
    expect(o.workers, hasLength(1));
    expect(o.gapFor(ComputeKind.pages)?.reason, GapReason.permission);
    expect(o.gapFor(ComputeKind.registrar), isNull);
  });

  test('registrar follows the cursor until it is empty', () async {
    var calls = 0;
    final api = FakeCfAdapter()
      ..reply('GET', '$_base/workers/scripts', <Object>[])
      ..reply('GET', '$_base/pages/projects', <Object>[], resultInfo: resultInfo(count: 0))
      ..on('GET', '$_base/registrar/registrations', (call) {
        calls++;
        expect(call.query['per_page'], '50');
        if (call.query['cursor'] == null) {
          return FakeReply.ok(
            [registrationJson('a.dev', expires: '2027-01-01T00:00:00Z')],
            resultInfo: {'count': 1, 'cursor': 'eyJ0IjoiMjAyNS0wNi0xNSJ9', 'per_page': 50},
          );
        }
        expect(call.query['cursor'], 'eyJ0IjoiMjAyNS0wNi0xNSJ9');
        return FakeReply.ok(
          [registrationJson('b.dev', expires: '2027-02-01T00:00:00Z')],
          resultInfo: {'count': 1, 'cursor': '', 'per_page': 50},
        );
      });
    final c = container([token('user')], {'user': api});
    final o = await load(c);
    expect(calls, 2);
    expect(o.registrar.map((r) => r.name), ['a.dev', 'b.dev']);
  });

  test('when every call fails the error surfaces instead of an empty board', () async {
    final api = FakeCfAdapter()
      ..on('GET', '$_base/workers/scripts', (_) => FakeReply.error(400, 7000, 'Bad request'))
      ..on('GET', '$_base/pages/projects', (_) => FakeReply.error(400, 7000, 'Bad request'));
    final c = container([token('user', caps: {Capability.workers, Capability.pages})], {'user': api});
    await expectLater(c.read(computeOverviewProvider(testAccount.id).future), throwsA(isA<CfApiException>()));
  });
}
