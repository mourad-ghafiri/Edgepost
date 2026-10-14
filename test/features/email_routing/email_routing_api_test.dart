import 'package:edgepost/features/email_routing/data/email_routing_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';
import 'routing_fixtures.dart';

const zoneId = '023e105f4ecef8ad9ca31a8372d0c353';
const rules = '/zones/$zoneId/email/routing/rules';

void main() {
  group('parsing', () {
    test('settings: enabled, status and flags', () {
      final s = RoutingSettings.fromJson(settingsJson());
      expect(s.enabled, isTrue);
      expect(s.status, RoutingStatus.ready);
      expect(s.health, RoutingHealth.ready);
      expect(s.skipWizard, isTrue);
      expect(s.supportSubaddress, isTrue);
      expect(s.created, DateTime.utc(2014, 1, 2, 2, 20));
      expect(s.recordsLocked, isTrue);
    });

    test('settings: every status maps to a strip state', () {
      RoutingHealth h(bool enabled, String status) =>
          RoutingSettings.fromJson(settingsJson(enabled: enabled, status: status)).health;
      expect(h(false, 'unconfigured'), RoutingHealth.off);
      expect(h(false, 'ready'), RoutingHealth.off);
      expect(h(true, 'misconfigured'), RoutingHealth.misconfigured);
      expect(h(true, 'misconfigured/locked'), RoutingHealth.misconfigured);
      expect(h(true, 'unlocked'), RoutingHealth.unlocked);
      expect(RoutingSettings.fromJson(settingsJson(status: 'misconfigured/locked')).status,
          RoutingStatus.misconfiguredLocked);
    });

    test('settings survive the cache round trip', () {
      final s = RoutingSettings.fromJson(RoutingSettings.fromJson(settingsJson(status: 'unlocked')).toJson());
      expect(s.status, RoutingStatus.unlocked);
    });

    test('rule: literal matcher, forward action, metadata', () {
      final r = RoutingRule.fromJson(forwardRuleJson());
      expect(r.id, 'a7e6fb77503c41d8a7f3113c6918f10c');
      expect(r.address, 'test@example.com');
      expect(r.action, const RuleAction.forward('destinationaddress@example.net'));
      expect(r.enabled, isTrue);
      expect(r.priority, 0);
      expect(r.source, 'api');
      expect(r.isCatchAll, isFalse);
    });

    test('rule: worker action to the mailbox Worker', () {
      final r = RoutingRule.fromJson(workerRuleJson(id: 'r2', to: 'hello@example.com'));
      expect(r.action!.type, RuleActionType.worker);
      expect(r.action!.isMailbox, isTrue);
      expect(kMailWorkerName, 'edgepost-mail');
    });

    test('catch-all: matcher type all', () {
      final r = RoutingRule.fromJson(catchAllJson(type: 'drop', value: null));
      expect(r.isCatchAll, isTrue);
      expect(r.address, isNull);
      expect(r.action!.type, RuleActionType.drop);
    });

    test('an unknown action type survives a rewrite', () {
      final r = RoutingRule.fromJson({
        ...forwardRuleJson(),
        'actions': [
          {
            'type': 'quarantine',
            'value': ['x'],
          },
        ],
      });
      expect(r.action!.type, RuleActionType.unknown);
      expect((r.copyWith(enabled: false).toRequestBody()['actions'] as List).single,
          {'type': 'quarantine', 'value': ['x']});
    });

    test('address: verified date, or null while waiting', () {
      final verified = DestinationAddress.fromJson(addressJson());
      expect(verified.isVerified, isTrue);
      expect(verified.verified, DateTime.utc(2014, 1, 2, 2, 20));
      final waiting = DestinationAddress.fromJson(addressJson(verified: null));
      expect(waiting.isVerified, isFalse);
      expect(waiting.email, 'user@example.com');
    });

    test('local part and email validation', () {
      expect(validateLocalPart('hello', domain: 'example.com'), isNull);
      expect(validateLocalPart('first.last+tag', domain: 'example.com'), isNull);
      expect(validateLocalPart('', domain: 'example.com'), LocalPartProblem.empty);
      expect(validateLocalPart('two words', domain: 'example.com'), LocalPartProblem.invalid);
      expect(validateLocalPart('.dot', domain: 'example.com'), LocalPartProblem.invalid);
      expect(validateLocalPart('a..b', domain: 'example.com'), LocalPartProblem.invalid);
      expect(validateLocalPart('a@b', domain: 'example.com'), LocalPartProblem.invalid);
      expect(validateLocalPart('x' * 65, domain: 'example.com'), LocalPartProblem.tooLong);
      expect(isValidEmail('me@gmail.com'), isTrue);
      expect(isValidEmail('me@localhost'), isFalse);
      expect(isValidEmail('not an email'), isFalse);
    });
  });

  group('requests', () {
    test('fetchRoutingSettings reads the settings endpoint', () async {
      final api = FakeCfAdapter()..reply('GET', '/zones/$zoneId/email/routing', settingsJson(status: 'misconfigured'));
      final s = await fetchRoutingSettings(fakeClient(api), zoneId);
      expect(s.status, RoutingStatus.misconfigured);
    });

    test('enable posts to /dns, never the deprecated /enable', () async {
      final api = FakeCfAdapter()..reply('POST', '/zones/$zoneId/email/routing/dns', settingsJson());
      await enableRouting(fakeClient(api), zoneId);
      expect(api.calls.single.method, 'POST');
      expect(api.calls.single.path, '/zones/$zoneId/email/routing/dns');
    });

    test('disable deletes /dns; unlock patches /dns', () async {
      final api = FakeCfAdapter()
        ..reply('DELETE', '/zones/$zoneId/email/routing/dns', settingsJson(enabled: false))
        ..reply('PATCH', '/zones/$zoneId/email/routing/dns', settingsJson(status: 'unlocked'));
      final client = fakeClient(api);
      await disableRouting(client, zoneId);
      await unlockRoutingRecords(client, zoneId);
      expect(api.calls.map((c) => '${c.method} ${c.path}'), [
        'DELETE /zones/$zoneId/email/routing/dns',
        'PATCH /zones/$zoneId/email/routing/dns',
      ]);
      expect(api.calls.any((c) => c.path.endsWith('/enable') || c.path.endsWith('/disable')), isFalse);
    });

    test('required DNS records: documented array and object variant', () async {
      final api = FakeCfAdapter()..reply('GET', '/zones/$zoneId/email/routing/dns', routingDnsJson());
      final list = await fetchRoutingDnsRecords(fakeClient(api), zoneId);
      expect(list.map((r) => r.type), ['MX', 'MX', 'TXT']);
      expect(list.first.priority, 12);
      expect(list.first.line, 'example.com MX 12 route1.mx.cloudflare.net');

      final api2 = FakeCfAdapter()
        ..reply('GET', '/zones/$zoneId/email/routing/dns', {'errors': <Object>[], 'record': routingDnsJson()});
      expect(await fetchRoutingDnsRecords(fakeClient(api2), zoneId), hasLength(3));
    });

    test('create rule body', () async {
      final api = FakeCfAdapter()..on('POST', rules, (c) => FakeReply.ok({...(c.body as Map<String, dynamic>), 'id': 'new1'}));
      final saved = await createRoutingRule(
        fakeClient(api),
        zoneId,
        RoutingRule.forAddress('hello@example.com', const RuleAction.forward('me@gmail.com')),
      );
      expect(api.calls.single.body, {
        'actions': [
          {
            'type': 'forward',
            'value': ['me@gmail.com'],
          },
        ],
        'matchers': [
          {'type': 'literal', 'field': 'to', 'value': 'hello@example.com'},
        ],
        'enabled': true,
      });
      expect(saved.id, 'new1');
    });

    test('update rule keeps name and priority, PUTs by id', () async {
      final api = FakeCfAdapter()..on('PUT', '$rules/r1', (c) => FakeReply.ok({...(c.body as Map<String, dynamic>), 'id': 'r1'}));
      final rule = RoutingRule.fromJson(forwardRuleJson(id: 'r1'));
      await updateRoutingRule(fakeClient(api), zoneId, rule.copyWith(enabled: false));
      final body = api.calls.single.body as Map<String, dynamic>;
      expect(body['enabled'], isFalse);
      expect(body['name'], 'Send to user@example.net rule.');
      expect(body['priority'], 0);
      expect(body.containsKey('source'), isFalse);
    });

    test('catch-all body uses matcher type all', () async {
      final api = FakeCfAdapter()..on('PUT', '$rules/catch_all', (c) => FakeReply.ok(c.body));
      await updateCatchAll(fakeClient(api), zoneId, action: const RuleAction.drop(), enabled: true);
      expect(api.calls.single.body, {
        'actions': [
          {'type': 'drop'},
        ],
        'matchers': [
          {'type': 'all'},
        ],
        'enabled': true,
      });
    });

    test('setCatchAllToWorker sends a worker action with the script name', () async {
      final api = FakeCfAdapter()..on('PUT', '$rules/catch_all', (c) => FakeReply.ok(c.body));
      await setCatchAllToWorker(fakeClient(api), zoneId, kMailWorkerName);
      final body = api.calls.single.body as Map<String, dynamic>;
      expect(body['actions'], [
        {
          'type': 'worker',
          'value': ['edgepost-mail'],
        },
      ]);
      expect(body['matchers'], [
        {'type': 'all'},
      ]);
      expect(body['enabled'], isTrue);
    });

    test('routeAddressToWorker updates the existing literal rule', () async {
      final api = FakeCfAdapter()
        ..reply('GET', rules, [
          catchAllJson(),
          forwardRuleJson(id: 'r1', to: 'Hello@Example.com', enabled: false),
          forwardRuleJson(id: 'r2', to: 'other@example.com'),
        ], resultInfo: pageInfo(3))
        ..on('PUT', '$rules/r1', (c) => FakeReply.ok({...(c.body as Map<String, dynamic>), 'id': 'r1'}));
      await routeAddressToWorker(fakeClient(api), zoneId, 'hello@example.com', 'edgepost-mail');
      expect(api.calls.map((c) => c.method), ['GET', 'PUT']);
      final body = api.calls.last.body as Map<String, dynamic>;
      expect(body['actions'], [
        {
          'type': 'worker',
          'value': ['edgepost-mail'],
        },
      ]);
      expect(body['matchers'], [
        {'type': 'literal', 'field': 'to', 'value': 'Hello@Example.com'},
      ]);
      expect(body['enabled'], isTrue);
      expect(body['name'], 'Send to user@example.net rule.');
    });

    test('routeAddressToWorker creates a rule when none matches', () async {
      final api = FakeCfAdapter()
        ..reply('GET', rules, [forwardRuleJson(id: 'r2', to: 'other@example.com')], resultInfo: pageInfo(1))
        ..on('POST', rules, (c) => FakeReply.ok({...(c.body as Map<String, dynamic>), 'id': 'n1'}));
      await routeAddressToWorker(fakeClient(api), zoneId, 'hello@example.com', 'edgepost-mail');
      expect(api.calls.map((c) => c.method), ['GET', 'POST']);
      expect(api.calls.last.body, {
        'actions': [
          {
            'type': 'worker',
            'value': ['edgepost-mail'],
          },
        ],
        'matchers': [
          {'type': 'literal', 'field': 'to', 'value': 'hello@example.com'},
        ],
        'enabled': true,
      });
    });

    test('rules list leaves the catch-all out and pages through', () async {
      final api = FakeCfAdapter()
        ..on('GET', rules, (c) {
          final page = int.parse(c.query['page'] ?? '1');
          return FakeReply.ok(
            page == 1 ? [catchAllJson(), forwardRuleJson(id: 'r1')] : [forwardRuleJson(id: 'r2', to: 'b@example.com')],
            resultInfo: {'page': page, 'per_page': 50, 'total_pages': 2, 'count': 1, 'total_count': 3},
          );
        });
      final list = await fetchRoutingRules(fakeClient(api), zoneId);
      expect(list.map((r) => r.id), ['r1', 'r2']);
    });

    test('catch-all 404 reads as none', () async {
      final api = FakeCfAdapter();
      expect(await fetchCatchAll(fakeClient(api), zoneId), isNull);
    });

    test('destination addresses: list, create body, delete path', () async {
      const account = '023e105f4ecef8ad9ca31a8372d0c353';
      const base = '/accounts/$account/email/routing/addresses';
      final api = FakeCfAdapter()
        ..reply('GET', base, [addressJson(email: 'z@example.net'), addressJson(id: 'b', email: 'a@example.net', verified: null)],
            resultInfo: pageInfo(2))
        ..on('POST', base, (c) => FakeReply.ok(addressJson(id: 'n', email: 'new@example.net', verified: null)))
        ..reply('DELETE', '$base/n', addressJson(id: 'n'));
      final client = fakeClient(api);
      final list = await fetchDestinationAddresses(client, account);
      expect(list.map((a) => a.email), ['a@example.net', 'z@example.net']);
      final created = await createDestinationAddress(client, account, ' new@example.net ');
      expect(api.calls[1].body, {'email': 'new@example.net'});
      expect(created.isVerified, isFalse);
      await deleteDestinationAddress(client, account, 'n');
      expect(api.calls.last.method, 'DELETE');
    });
  });
}
