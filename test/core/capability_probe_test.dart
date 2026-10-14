import 'package:edgepost/core/accounts/capability_probe.dart';
import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/cloudflare/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cf.dart';

const _acc = CfAccount(id: 'a1', name: 'Personal');
const _other = CfAccount(id: 'a2', name: 'Studio Ember');

/// A full-access token: every read succeeds.
FakeCfAdapter _fullAccess() => FakeCfAdapter()
  ..reply('GET', '/zones', [
    {'id': 'z1', 'name': 'example.com'},
  ])
  ..reply('GET', '/zones/z1/dns_records', <Object>[])
  ..reply('GET', '/zones/z1/settings/ssl', {'id': 'ssl', 'value': 'full'})
  ..reply('GET', '/zones/z1/email/routing', {'enabled': true, 'status': 'ready'})
  ..reply('GET', '/zones/z1/email/auth/dmarc-reports', {'enabled': false})
  ..reply('GET', '/zones/z1/workers/routes', <Object>[])
  ..on('POST', '/graphql', (_) => const FakeReply(200, {'data': {'viewer': {'zones': <Object>[]}}, 'errors': null}))
  ..reply('GET', '/accounts/a1/email/routing/addresses', <Object>[])
  ..reply('GET', '/accounts/a1/workers/scripts', <Object>[])
  ..reply('GET', '/accounts/a1/pages/projects', <Object>[])
  ..on('GET', '/accounts/a1/d1/database', (call) {
    // The API rejects per_page below 10 (official reference).
    final per = int.parse(call.query['per_page'] ?? '0');
    return per < 10 ? FakeReply.error(400, 7400, 'per_page must be at least 10') : FakeReply.ok(<Object>[]);
  })
  ..reply('GET', '/accounts/a1/r2/buckets', {'buckets': <Object>[]})
  ..reply('GET', '/accounts/a1/registrar/registrations', <Object>[]);

void main() {
  test('a full-access token is granted everything it can read', () async {
    final states = await CapabilityProbe(fakeClient(_fullAccess())).run(_acc.id);
    for (final c in Capability.values.where((c) => c != Capability.cachePurge)) {
      expect(states[c], CapState.granted, reason: c.name);
    }
    expect(states[Capability.cachePurge], CapState.unknown, reason: 'no read endpoint');
  });

  test('D1 is probed with a per_page the API accepts', () async {
    final api = _fullAccess();
    await CapabilityProbe(fakeClient(api)).run(_acc.id);
    final call = api.calls.singleWhere((c) => c.path.endsWith('/d1/database'));
    expect(int.parse(call.query['per_page']!), greaterThanOrEqualTo(10));
  });

  test('R2 without its subscription is "turn on", not "missing permission"', () async {
    final api = _fullAccess()
      ..on('GET', '/accounts/a1/r2/buckets', (_) => FakeReply.error(403, 10042, 'Please enable R2 through the Cloudflare Dashboard.'));
    final states = await CapabilityProbe(fakeClient(api)).run(_acc.id);
    expect(states[Capability.r2], CapState.notEnabled);
  });

  test('only an explicit refusal is "denied"; other failures stay open', () async {
    final api = _fullAccess()
      ..on('GET', '/accounts/a1/workers/scripts', (_) => FakeReply.error(403, 10000, 'Authentication error'))
      ..on('GET', '/accounts/a1/pages/projects', (_) => FakeReply.error(400, 8000000, 'Bad request'))
      ..on('GET', '/zones/z1/email/auth/dmarc-reports', (_) => FakeReply.error(500, 1, 'Internal error'))
      ..on('GET', '/accounts/a1/registrar/registrations', (_) => FakeReply.error(404, 7003, 'Not found'));
    final states = await CapabilityProbe(fakeClient(api)).run(_acc.id);
    expect(states[Capability.workers], CapState.denied);
    expect(states[Capability.pages], CapState.unknown);
    expect(states[Capability.dmarc], CapState.unknown);
    expect(states[Capability.registrar], CapState.granted, reason: '404 proves access');
  });

  test('GraphQL "not authorized" counts as denied', () async {
    final api = _fullAccess()
      ..on('POST', '/graphql', (_) => const FakeReply(200, {
            'data': null,
            'errors': [
              {'message': 'not authorized for that account'},
            ],
          }));
    final states = await CapabilityProbe(fakeClient(api)).run(_acc.id);
    expect(states[Capability.analytics], CapState.denied);
  });

  test('zones are sampled from the account being probed', () async {
    final api = _fullAccess();
    await CapabilityProbe(fakeClient(api)).run(_acc.id);
    final zones = api.calls.firstWhere((c) => c.path == '/zones');
    expect(zones.query['account.id'], _acc.id);
  });

  group('Credential gate', () {
    Credential cred(Map<Capability, CapState> s) => Credential(
          id: 'c',
          label: 'x',
          kind: TokenKind.user,
          accounts: const [_acc, _other],
          addedAt: DateTime(2026),
          token: 't',
          capabilities: {_acc.id: s},
        );

    test('blocks only explicit denials', () {
      final c = cred({Capability.d1: CapState.unknown, Capability.r2: CapState.notEnabled, Capability.workers: CapState.denied});
      expect(c.can(_acc.id, Capability.d1), isTrue);
      expect(c.can(_acc.id, Capability.r2), isTrue);
      expect(c.can(_acc.id, Capability.workers), isFalse);
      expect(c.can(_acc.id, Capability.pages), isTrue, reason: 'never probed → attempted');
    });

    test('permissions are per account', () {
      final c = cred({Capability.workers: CapState.denied});
      expect(c.can(_other.id, Capability.workers), isTrue, reason: 'denied in one account says nothing about another');
      expect(c.stateOf(_other.id, Capability.workers), CapState.unknown);
    });

    test('round-trips through storage', () {
      final c = cred({Capability.d1: CapState.granted, Capability.r2: CapState.notEnabled});
      final back = Credential.fromJson(c.toJson(), 't');
      expect(back.stateOf(_acc.id, Capability.r2), CapState.notEnabled);
      expect(back.stateOf(_acc.id, Capability.pages), CapState.unknown, reason: 'never checked');
      expect(back.accounts.map((a) => a.id), [_acc.id, _other.id]);
      expect(back.token, 't');
    });
  });
}
