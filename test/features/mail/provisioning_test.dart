import 'package:dio/dio.dart';
import 'package:edgepost/core/cloudflare/cf_client.dart';
import 'package:edgepost/core/cloudflare/models.dart';
import 'package:edgepost/features/mail/data/mail_client.dart';
import 'package:edgepost/features/mail/data/provisioning.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';

class _RecordingRouting implements MailRouting {
  final calls = <String>[];
  @override
  Future<void> enableRouting(CfClient client, String zoneId) async => calls.add('enable $zoneId');
  @override
  Future<void> setCatchAllToWorker(CfClient client, String zoneId, String workerName) async => calls.add('catchall $zoneId $workerName');
  @override
  Future<void> routeAddressToWorker(CfClient client, String zoneId, String address, String workerName) async =>
      calls.add('route $zoneId $address $workerName');
}

/// Fake mail Worker for the health check and config push.
MailClient _mail(String url, String key, {int failHealth = 0}) {
  var healthCalls = 0;
  final api = FakeCfAdapter()
    ..on('GET', '/v1/health', (_) {
      healthCalls++;
      if (healthCalls <= failHealth) return const FakeReply(404, {'error': {'code': 'not_found', 'message': 'no route'}});
      return const FakeReply(200, {'version': '1.0.0', 'domains': <String>[], 'sendingConfigured': true});
    })
    ..on('PUT', '/v1/config', (c) => FakeReply(200, c.body));
  final dio = Dio(BaseOptions(baseUrl: url, validateStatus: (_) => true))..httpClientAdapter = api;
  return MailClient(baseUrl: url, apiKey: key, accountId: 'acc1', dio: dio);
}

const _bundle = WorkerBundle(
  version: '1.0.0',
  mainModule: 'edgepost-mail.js',
  compatibilityDate: '2026-09-01',
  compatibilityFlags: [],
  source: 'export default { fetch() { return new Response("ok"); } };',
);

Zone _zone(String id, String name) => Zone.fromJson({
      'id': id,
      'name': name,
      'status': 'active',
      'paused': false,
      'account': {'id': 'acc1', 'name': 'Personal'},
    }, reach: const ['cred1']);

void main() {
  late FakeCfAdapter api;
  late _RecordingRouting routing;

  setUp(() {
    api = FakeCfAdapter();
    routing = _RecordingRouting();
    api
      ..reply('GET', '/accounts/acc1/d1/database', <Object>[], resultInfo: {'page': 1, 'total_pages': 1})
      ..reply('POST', '/accounts/acc1/d1/database', {'uuid': 'd1-uuid', 'name': 'edgepost-mail'})
      ..reply('GET', '/accounts/acc1/r2/buckets', {'buckets': <Object>[]})
      ..reply('POST', '/accounts/acc1/r2/buckets', {'name': 'edgepost-mail'})
      ..reply('PUT', '/accounts/acc1/workers/scripts/edgepost-mail', {'id': 'edgepost-mail'})
      ..reply('GET', '/accounts/acc1/workers/subdomain', {'subdomain': 'atelier'})
      ..reply('POST', '/accounts/acc1/workers/scripts/edgepost-mail/subdomain', {'enabled': true, 'previews_enabled': false})
      ..reply('PUT', '/accounts/acc1/workers/scripts/edgepost-mail/schedules', {
        'schedules': [
          {'cron': '17 3 * * *'},
        ],
      })
      ..reply('GET', '/zones/z1/email/sending/subdomains', <Object>[], resultInfo: {'page': 1, 'total_pages': 1})
      ..reply('POST', '/zones/z1/email/sending/subdomains', {'enabled': true, 'name': 'atelier-nord.dev', 'tag': 'sub1'})
      ..reply('GET', '/zones/z1/email/sending/subdomains/sub1/dns', [
        {'type': 'MX', 'name': 'cf-bounce.atelier-nord.dev', 'content': 'route1.mx.cloudflare.net', 'priority': 10},
        {'type': 'TXT', 'name': 'cf-bounce.atelier-nord.dev', 'content': 'v=spf1 include:_spf.mx.cloudflare.net ~all'},
      ])
      ..reply('GET', '/zones/z1/dns_records', [
        {'id': 'r1', 'type': 'TXT', 'name': 'cf-bounce.atelier-nord.dev', 'content': '"v=spf1 include:_spf.mx.cloudflare.net ~all"'},
      ], resultInfo: {'page': 1, 'total_pages': 1})
      ..reply('POST', '/zones/z1/dns_records', {'id': 'r2'});
  });

  MailProvisioner provisioner({int failHealth = 0}) => MailProvisioner(
        client: fakeClient(api),
        accountId: 'acc1',
        bundle: _bundle,
        routing: routing,
        mailClientFactory: (url, key) => _mail(url, key, failHealth: failHealth),
        healthDelay: Duration.zero,
      );

  test('fresh setup creates storage, uploads, publishes, routes and onboards sending', () async {
    final steps = <ProvisionStep>[];
    final service = await provisioner().run(
      [DomainPlan(zone: _zone('z1', 'atelier-nord.dev'))],
      steps.add,
    );

    expect(service.workerUrl, 'https://edgepost-mail.atelier.workers.dev');
    expect(service.d1Id, 'd1-uuid');
    expect(service.domains, ['atelier-nord.dev']);
    expect(service.sendingDomains, ['atelier-nord.dev']);
    expect(service.apiKey.length, greaterThanOrEqualTo(40));
    expect(routing.calls, ['enable z1', 'catchall z1 edgepost-mail']);

    final upload = api.calls.firstWhere((c) => c.method == 'PUT' && c.path.endsWith('/scripts/edgepost-mail'));
    final body = '${upload.body}';
    expect(body, contains('"main_module":"edgepost-mail.js"'));
    expect(body, contains('"database_id":"d1-uuid"'));
    expect(body, contains('"type":"send_email"'));
    expect(body, contains('"type":"secret_text","name":"MAIL_API_KEY"'));
    expect(body, contains('application/javascript+module'));

    final schedule = api.calls.firstWhere((c) => c.path.endsWith('/schedules'));
    expect(schedule.body, [
      {'cron': '17 3 * * *'},
    ]);

    // Sending records are Cloudflare-managed: setup never writes DNS for them.
    expect(api.calls.where((c) => c.method == 'POST' && c.path == '/zones/z1/dns_records'), isEmpty);
    // The SPF TXT exists; the bounce MX isn't published yet, so the step asks for attention.
    final sendingStep = steps.lastWhere((s) => s.id == 'sending');
    expect(sendingStep.state, ProvisionState.attention);
    expect(sendingStep.problem, ProvisionProblem.sendingPending);
    expect(sendingStep.error, 'MX cf-bounce.atelier-nord.dev');

    expect(steps.where((s) => s.state == ProvisionState.failed), isEmpty);
    expect(steps.last.id, 'save');
  });

  test('reuses the existing D1 database and R2 bucket', () async {
    api
      ..reply('GET', '/accounts/acc1/d1/database', [
        {'uuid': 'old-uuid', 'name': 'edgepost-mail'},
      ], resultInfo: {'page': 1, 'total_pages': 1})
      ..reply('GET', '/accounts/acc1/r2/buckets', {
        'buckets': [
          {'name': 'edgepost-mail'},
        ],
      });
    final s = await provisioner().run([DomainPlan(zone: _zone('z1', 'atelier-nord.dev'), enableSending: false)], (_) {});
    expect(s.d1Id, 'old-uuid');
    expect(api.calls.where((c) => c.method == 'POST' && c.path.contains('/d1/')), isEmpty);
    expect(api.calls.where((c) => c.method == 'POST' && c.path.contains('/r2/')), isEmpty);
  });

  test('specific addresses each get a worker rule', () async {
    await provisioner().run([
      DomainPlan(zone: _zone('z1', 'atelier-nord.dev'), choice: RoutingChoice.specific, localParts: ['hello', 'billing'], enableSending: false),
    ], (_) {});
    expect(routing.calls, [
      'enable z1',
      'route z1 hello@atelier-nord.dev edgepost-mail',
      'route z1 billing@atelier-nord.dev edgepost-mail',
    ]);
  });

  test('missing workers.dev subdomain stops with an explained step', () async {
    api.reply('GET', '/accounts/acc1/workers/subdomain', {'subdomain': null});
    final steps = <ProvisionStep>[];
    await expectLater(provisioner().run([DomainPlan(zone: _zone('z1', 'atelier-nord.dev'))], steps.add), throwsA(isA<ProvisionException>()));
    final failed = steps.lastWhere((s) => s.state == ProvisionState.failed);
    expect(failed.id, 'publish');
    expect(failed.problem, ProvisionProblem.noWorkersSubdomain);
  });

  test('R2 not enabled is reported as such', () async {
    api.on('GET', '/accounts/acc1/r2/buckets', (_) => FakeReply.error(403, 10042, 'Please enable R2 through the Cloudflare Dashboard.'));
    final steps = <ProvisionStep>[];
    await expectLater(provisioner().run([DomainPlan(zone: _zone('z1', 'atelier-nord.dev'))], steps.add), throwsA(isA<ProvisionException>()));
    expect(steps.lastWhere((s) => s.state == ProvisionState.failed).problem, ProvisionProblem.r2Disabled);
  });

  test('waits for a new workers.dev address to answer', () async {
    final s = await provisioner(failHealth: 3).run([DomainPlan(zone: _zone('z1', 'atelier-nord.dev'), enableSending: false)], (_) {});
    expect(s.workerVersion, '1.0.0');
  });

  test('sending onboarding failure does not block receiving', () async {
    api.on('POST', '/zones/z1/email/sending/subdomains', (_) => FakeReply.error(403, 10000, 'Authentication error'));
    final steps = <ProvisionStep>[];
    final s = await provisioner().run([DomainPlan(zone: _zone('z1', 'atelier-nord.dev'))], steps.add);
    expect(s.sendingDomains, isEmpty);
    expect(s.domains, ['atelier-nord.dev']);
    final failed = steps.lastWhere((x) => x.id == 'sending');
    expect(failed.state, ProvisionState.failed);
    expect(failed.error, contains('Authentication error'), reason: "Cloudflare's own words are shown");
  });

  test('records already in the zone satisfy onboarding; an existing DMARC policy counts', () async {
    api
      ..reply('GET', '/zones/z1/email/sending/subdomains', [
        {'enabled': true, 'name': 'atelier-nord.dev', 'tag': 'sub1'},
      ], resultInfo: {'page': 1, 'total_pages': 1})
      ..reply('GET', '/zones/z1/email/sending/subdomains/sub1/dns', [
        {'type': 'MX', 'name': 'cf-bounce.atelier-nord.dev', 'content': 'route1.mx.cloudflare.net', 'priority': 10},
        {'type': 'TXT', 'name': '_dmarc', 'content': 'v=DMARC1; p=none'},
      ])
      ..reply('GET', '/zones/z1/dns_records', [
        {'id': 'r1', 'type': 'MX', 'name': 'cf-bounce.atelier-nord.dev', 'content': 'route1.mx.cloudflare.net.', 'priority': 10},
        {'id': 'r2', 'type': 'TXT', 'name': '_dmarc.atelier-nord.dev', 'content': '"v=DMARC1; p=quarantine; rua=mailto:dmarc@atelier-nord.dev"'},
      ], resultInfo: {'page': 1, 'total_pages': 1});
    final steps = <ProvisionStep>[];
    final s = await provisioner().run([DomainPlan(zone: _zone('z1', 'atelier-nord.dev'))], steps.add);
    expect(steps.lastWhere((x) => x.id == 'sending').state, ProvisionState.done);
    expect(s.sendingDomains, ['atelier-nord.dev']);
    expect(api.calls.where((c) => c.method == 'POST' && c.path.contains('/subdomains')), isEmpty, reason: 'already onboarded');
    expect(api.calls.where((c) => c.method == 'POST' && c.path.endsWith('/dns_records')), isEmpty);
  });

  test('compareVersions orders numerically', () {
    expect(compareVersions('1.10.0', '1.2.0'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.0'), 0);
    expect(compareVersions('0.9.9', '1.0.0'), lessThan(0));
  });
}
