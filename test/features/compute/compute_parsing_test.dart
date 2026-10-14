import 'package:edgepost/features/compute/data/compute_api.dart';
import 'package:edgepost/features/compute/data/compute_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';
import 'compute_fixtures.dart';

void main() {
  group('Workers parsing', () {
    test('script list item', () {
      final w = WorkerScriptInfo.fromJson(scriptJson('my-worker', routes: 2));
      expect(w.name, 'my-worker');
      expect(w.modifiedOn, DateTime.utc(2026, 10, 10, 8));
      expect(w.compatibilityDate, '2026-09-01');
      expect(w.compatibilityFlags, ['nodejs_compat']);
      expect(w.usageModel, 'standard');
      expect(w.routes.map((r) => r.pattern), ['example.com/api0/*', 'example.com/api1/*']);
      expect(w.handlers, ['fetch', 'scheduled']);
      expect(w.lastDeployedFrom, 'wrangler');
      // Cache round trip.
      final back = WorkerScriptInfo.fromJson(w.toJson());
      expect(back.name, 'my-worker');
      expect(back.routes.length, 2);
      expect(back.modifiedOn, w.modifiedOn);
    });

    test('deployments: result.deployments, first is active', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/accounts/a1/workers/scripts/my-worker/deployments', {
          'deployments': [
            {
              'id': 'bcf48806-b317-4351-9ee7-36e7d557d4de',
              'created_on': '2026-10-11T18:11:19.117Z',
              'source': 'wrangler',
              'strategy': 'percentage',
              'versions': [
                {'version_id': '7f7b0d2b-0000-4b4b-8a8a-000000000012', 'percentage': 90},
                {'version_id': '7f7b0d2b-0000-4b4b-8a8a-000000000011', 'percentage': 10},
              ],
              'annotations': {'workers/message': 'Gradual rollout', 'workers/triggered_by': 'deployment'},
              'author_email': 'dev@example.com',
            },
            {
              'id': '182bd5e5-6e1a-4fe4-a799-aa6d9a6ab26e',
              'created_on': '2026-10-01T18:11:19.117Z',
              'source': 'api',
              'strategy': 'percentage',
              'versions': [
                {'version_id': '7f7b0d2b-0000-4b4b-8a8a-000000000011', 'percentage': 100},
              ],
            },
          ],
        });
      final list = await ComputeApi(fakeClient(api)).deployments('a1', 'my-worker');
      expect(list, hasLength(2));
      final active = list.first;
      expect(active.message, 'Gradual rollout');
      expect(active.triggeredBy, 'deployment');
      expect(active.authorEmail, 'dev@example.com');
      expect(active.percentageOf('7f7b0d2b-0000-4b4b-8a8a-000000000012'), 90);
      expect(active.servesOnly('7f7b0d2b-0000-4b4b-8a8a-000000000012'), isFalse);
      expect(list[1].servesOnly('7f7b0d2b-0000-4b4b-8a8a-000000000011'), isTrue);
    });

    test('versions: result.items with metadata', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/accounts/a1/workers/scripts/my-worker/versions', {
          'items': [
            {
              'id': '7f7b0d2b-0000-4b4b-8a8a-000000000012',
              'number': 12,
              'metadata': {
                'author_email': 'dev@example.com',
                'author_id': '408cbcdfd4dda4617efef40b04d168a1',
                'created_on': '2026-10-11T18:00:00Z',
                'modified_on': '2026-10-11T18:00:00Z',
                'source': 'wrangler',
                'hasPreview': true,
              },
              'annotations': {'workers/message': 'Fix headers', 'workers/tag': 'v1.2.0'},
            },
            {
              'id': '7f7b0d2b-0000-4b4b-8a8a-000000000011',
              'number': 11,
              'metadata': {'created_on': '2026-10-01T18:00:00Z', 'source': 'dash'},
            },
          ],
        });
      final list = await ComputeApi(fakeClient(api)).versions('a1', 'my-worker');
      expect(list.map((v) => v.number), [12, 11]);
      expect(list.first.source, 'wrangler');
      expect(list.first.message, 'Fix headers');
      expect(list.first.tag, 'v1.2.0');
      expect(list.first.shortId, '7f7b0d2b');
      expect(list.first.createdOn, DateTime.utc(2026, 10, 11, 18));
    });

    test('secrets keep names and types only', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/accounts/a1/workers/scripts/my-worker/secrets', [
          {'name': 'MAIL_API_KEY', 'type': 'secret_text', 'text': 'should-never-be-kept'},
          {
            'name': 'SIGNING_KEY',
            'type': 'secret_key',
            'algorithm': {'name': 'HMAC'},
          },
        ]);
      final list = await ComputeApi(fakeClient(api)).secrets('a1', 'my-worker');
      expect(list.map((s) => s.name), ['MAIL_API_KEY', 'SIGNING_KEY']);
      expect(list.map((s) => s.toJson().toString()).join(), isNot(contains('should-never-be-kept')));
    });

    test('subdomain, custom domains and settings', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/accounts/a1/workers/scripts/my-worker/subdomain', {'enabled': true, 'previews_enabled': false})
        ..reply('GET', '/accounts/a1/workers/subdomain', {'subdomain': 'my-subdomain'})
        ..reply('GET', '/accounts/a1/workers/scripts/my-worker/settings', {
          'compatibility_date': '2026-09-01',
          'compatibility_flags': ['nodejs_compat'],
          'logpush': false,
          'bindings': [
            {'name': 'DB', 'type': 'd1'},
          ],
        })
        ..on('GET', '/accounts/a1/workers/domains', (call) {
          expect(call.query['service'], 'my-worker');
          return FakeReply.ok([
            {
              'id': 'dbe10b4bc17c295377eabd600e1787fd',
              'hostname': 'api.example.com',
              'service': 'my-worker',
              'zone_id': '593c9c94de529bbbfaac7c53ced0447d',
              'zone_name': 'example.com',
              'cert_id': '9a7806061c88ada191ed06f989cc3dac',
            },
          ], resultInfo: resultInfo());
        });
      final c = ComputeApi(fakeClient(api));
      final sub = await c.scriptSubdomain('a1', 'my-worker');
      expect(sub.enabled, isTrue);
      expect(sub.previewsEnabled, isFalse);
      expect(await c.accountSubdomain('a1'), 'my-subdomain');
      final settings = await c.scriptSettings('a1', 'my-worker');
      expect(settings.compatibilityDate, '2026-09-01');
      final domains = await c.customDomains('a1', service: 'my-worker');
      expect(domains.single.hostname, 'api.example.com');
      expect(domains.single.zoneName, 'example.com');
    });
  });

  group('Pages parsing', () {
    test('project with latest and canonical deployments', () {
      final p = PagesProjectInfo.fromJson(
        pagesProjectJson(
          'docs-site',
          latest: pagesDeploymentJson(id: 'new', stage: 'build', status: 'failure'),
        ),
      );
      expect(p.name, 'docs-site');
      expect(p.subdomain, 'docs-site.pages.dev');
      expect(p.productionBranch, 'main');
      expect(p.repoOwner, 'example');
      expect(p.latestStatus, DeployStatus.failed);
      expect(p.latestDeployment!.branch, 'main');
      expect(p.latestDeployment!.lastActivity, DateTime.utc(2026, 10, 12, 7, 2, 30));
      expect(p.canonicalDeployment!.status, DeployStatus.success);
      final back = PagesProjectInfo.fromJson(p.toJson());
      expect(back.latestStatus, DeployStatus.failed);
      expect(back.toJson().toString(), isNot(contains('API_KEY')), reason: 'env vars are never cached');
    });

    test('deployment status from latest_stage', () {
      DeployStatus s(String stage, String status) =>
          PagesDeployment.fromJson(pagesDeploymentJson(stage: stage, status: status)).status;
      expect(s('deploy', 'success'), DeployStatus.success);
      expect(s('build', 'failure'), DeployStatus.failed);
      expect(s('build', 'active'), DeployStatus.building);
      expect(s('queued', 'active'), DeployStatus.queued);
      expect(s('deploy', 'canceled'), DeployStatus.canceled);
      expect(s('build', 'success'), DeployStatus.building);
      final d = PagesDeployment.fromJson(pagesDeploymentJson());
      expect(d.commitTitle, 'Update index.html');
      expect(d.stages.map((x) => x.name), ['queued', 'initialize', 'clone_repo', 'build', 'deploy']);
      expect(d.isProduction, isTrue);
      expect(d.displayId, 'f64788e9');
    });

    test('build log and domains', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/accounts/a1/pages/projects/docs-site/deployments/dep-1/history/logs', {
          'data': [
            {'line': 'Cloning repository...', 'ts': '2021-04-20T19:35:29.0749819Z'},
            {'line': 'Success: Finished cloning repository files', 'ts': '2021-04-20T19:35:30.0749819Z'},
          ],
          'includes_container_logs': true,
          'total': 30,
        })
        ..reply('GET', '/accounts/a1/pages/projects/docs-site/domains', [
          {
            'id': '0a6a2d8e-1c1c-4a0d-9d7e-2f6c2f9b1a00',
            'certificate_authority': 'google',
            'created_on': '2026-01-01T00:00:00Z',
            'domain_id': '0a6a2d8e',
            'name': 'docs.example.com',
            'status': 'pending',
            'validation_data': {'method': 'http', 'status': 'pending', 'error_message': 'CNAME not found'},
            'verification_data': {'status': 'pending'},
            'zone_tag': '023e105f4ecef8ad9ca31a8372d0c353',
          },
        ]);
      final c = ComputeApi(fakeClient(api));
      final log = await c.buildLog('a1', 'docs-site', 'dep-1');
      expect(log.lines.first.line, 'Cloning repository...');
      expect(log.total, 30);
      expect(log.includesContainerLogs, isTrue);
      final domains = await c.projectDomains('a1', 'docs-site');
      expect(domains.single.status, 'pending');
      expect(domains.single.errorMessage, 'CNAME not found');
      expect(domains.single.active, isFalse);
    });

    test('project list pages through results', () async {
      final api = FakeCfAdapter()
        ..on('GET', '/accounts/a1/pages/projects', (call) {
          final page = int.parse(call.query['page'] ?? '1');
          return FakeReply.ok([pagesProjectJson('site-$page')], resultInfo: resultInfo(page: page, totalPages: 2));
        });
      final list = await ComputeApi(fakeClient(api)).listProjects('a1');
      expect(list.map((p) => p.name), ['site-1', 'site-2']);
    });
  });
}
