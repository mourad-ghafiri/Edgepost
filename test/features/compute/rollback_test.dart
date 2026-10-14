import 'package:edgepost/core/cloudflare/cf_errors.dart';
import 'package:edgepost/features/compute/data/compute_api.dart';
import 'package:edgepost/features/compute/data/compute_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';
import 'compute_fixtures.dart';

void main() {
  const versionId = '023e105f-2a42-4f8b-a1c1-73f6a2a30c0f';

  Map<String, dynamic> deploymentResult(Object? body) => {
    'id': '182bd5e5-6e1a-4fe4-a799-aa6d9a6ab26e',
    'created_on': '2026-10-12T09:00:00Z',
    'source': 'api',
    'strategy': 'percentage',
    'versions': (body as Map)['versions'],
  };

  test('rollback body is a 100 % percentage deployment', () {
    expect(rollbackDeploymentBody(versionId), {
      'strategy': 'percentage',
      'versions': [
        {'version_id': versionId, 'percentage': 100},
      ],
    });
  });

  test('Worker rollback POSTs the deployment body', () async {
    final api = FakeCfAdapter()
      ..on(
        'POST',
        '/accounts/a1/workers/scripts/my-worker/deployments',
        (call) => FakeReply.ok(deploymentResult(call.body)),
      );
    final d = await ComputeApi(fakeClient(api)).rollbackTo('a1', 'my-worker', versionId);
    final call = api.calls.single;
    expect(call.method, 'POST');
    expect(call.query, isEmpty);
    expect(call.body, {
      'strategy': 'percentage',
      'versions': [
        {'version_id': versionId, 'percentage': 100},
      ],
    });
    expect(d.servesOnly(versionId), isTrue);
  });

  test('forced rollback adds force=true', () async {
    final api = FakeCfAdapter()
      ..on(
        'POST',
        '/accounts/a1/workers/scripts/my-worker/deployments',
        (call) => FakeReply.ok(deploymentResult(call.body)),
      );
    await ComputeApi(fakeClient(api)).rollbackTo('a1', 'my-worker', versionId, force: true);
    expect(api.calls.single.query, {'force': 'true'});
  });

  test('a blocked rollback surfaces the API message', () async {
    final api = FakeCfAdapter()
      ..on(
        'POST',
        '/accounts/a1/workers/scripts/my-worker/deployments',
        (_) => FakeReply.error(400, 10215, 'Secret bindings changed since this version was uploaded'),
      );
    await expectLater(
      ComputeApi(fakeClient(api)).rollbackTo('a1', 'my-worker', versionId),
      throwsA(isA<CfApiException>().having((e) => e.message, 'message', contains('Secret bindings changed'))),
    );
  });

  test('Pages retry and rollback hit the deployment action paths with no body', () async {
    final api = FakeCfAdapter()
      ..on(
        'POST',
        '/accounts/a1/pages/projects/docs-site/deployments/dep-1/retry',
        (_) => FakeReply.ok(pagesDeploymentJson(id: 'dep-2', stage: 'queued', status: 'active')),
      )
      ..on(
        'POST',
        '/accounts/a1/pages/projects/docs-site/deployments/dep-0/rollback',
        (_) => FakeReply.ok(pagesDeploymentJson(id: 'dep-0')),
      );
    final c = ComputeApi(fakeClient(api));
    final retried = await c.retry('a1', 'docs-site', 'dep-1');
    expect(retried.id, 'dep-2');
    expect(retried.status, DeployStatus.queued);
    final rolled = await c.rollback('a1', 'docs-site', 'dep-0');
    expect(rolled.id, 'dep-0');
    expect(api.calls.map((c) => '${c.method} ${c.path}'), [
      'POST /accounts/a1/pages/projects/docs-site/deployments/dep-1/retry',
      'POST /accounts/a1/pages/projects/docs-site/deployments/dep-0/rollback',
    ]);
    expect(api.calls.every((c) => c.body == null || c.body == ''), isTrue);
  });
}
