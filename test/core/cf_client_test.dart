import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/accounts/token_verifier.dart';
import 'package:edgepost/core/cloudflare/cf_errors.dart';
import 'package:edgepost/core/cloudflare/rate_limiter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_cf.dart';

void main() {
  group('CfClient', () {
    test('decodes the v4 envelope and pages through results', () async {
      final api = FakeCfAdapter();
      api.on('GET', '/zones', (call) {
        final page = int.parse(call.query['page'] ?? '1');
        return FakeReply.ok(
          [
            {'id': 'z$page', 'name': 'example$page.com'},
          ],
          resultInfo: {'page': page, 'per_page': 1, 'total_pages': 3, 'count': 1, 'total_count': 3},
        );
      });
      final rows = await fakeClient(api).getAll('/zones', perPage: 1);
      expect(rows.map((r) => r['id']), ['z1', 'z2', 'z3']);
      expect(api.calls, hasLength(3));
    });

    test('maps 403 to a permission error', () async {
      final api = FakeCfAdapter()..on('GET', '/zones/z/dns_records', (_) => FakeReply.error(403, 10000, 'Authentication error'));
      await expectLater(
        fakeClient(api).get('/zones/z/dns_records'),
        throwsA(isA<CfApiException>().having((e) => e.isPermissionDenied, 'permission', true)),
      );
    });

    test('maps 401 to an auth error', () async {
      final api = FakeCfAdapter()..on('GET', '/user/tokens/verify', (_) => FakeReply.error(401, 1000, 'Invalid API Token'));
      await expectLater(fakeClient(api).get('/user/tokens/verify'), throwsA(isA<CfAuthException>()));
    });

    test('429 blocks the limiter for retry-after', () async {
      final api = FakeCfAdapter()
        ..on('GET', '/zones', (_) => const FakeReply(429, {'success': false, 'errors': []}, headers: {
              'retry-after': ['120'],
            }));
      final client = fakeClient(api);
      await expectLater(client.get('/zones'), throwsA(isA<CfRateLimitedException>()));
      expect(client.limiter.delayBeforeNext().inSeconds, greaterThan(100));
    });

    test('graphql returns data and surfaces errors', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/graphql', (call) {
          final q = (call.body as Map)['query'] as String;
          if (q.contains('bad')) {
            return const FakeReply(200, {
              'data': null,
              'errors': [
                {'message': 'unknown field bad'},
              ],
            });
          }
          return const FakeReply(200, {
            'data': {'viewer': {'zones': <Object>[]}},
            'errors': null,
          });
        });
      final client = fakeClient(api);
      expect(await client.graphql('{ viewer { zones { zoneTag } } }'), contains('viewer'));
      await expectLater(client.graphql('{ bad }'), throwsA(isA<CfApiException>()));
    });
  });

  group('RateLimiter', () {
    test('refuses once the window budget is spent', () async {
      var now = DateTime(2026, 10, 12, 9);
      final limiter = RateLimiter(budget: 2, window: const Duration(minutes: 5), clock: () => now);
      expect(await limiter.acquire(), isTrue);
      expect(await limiter.acquire(), isTrue);
      expect(await limiter.acquire(maxWait: Duration.zero), isFalse);
      now = now.add(const Duration(minutes: 6));
      expect(await limiter.acquire(), isTrue);
    });
  });

  group('TokenVerifier', () {
    test('user token: verify then list accounts', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/user/tokens/verify', {'id': 't', 'status': 'active'})
        ..reply('GET', '/accounts', [
          {'id': 'a1', 'name': 'Personal'},
        ], resultInfo: {'page': 1, 'total_pages': 1});
      final check = await TokenVerifier(fakeClient(api)).verify();
      expect(check.kind, TokenKind.user);
      expect(check.accounts.single.name, 'Personal');
    });

    test('account token: falls back to the account verify endpoint', () async {
      final api = FakeCfAdapter()
        ..on('GET', '/user/tokens/verify', (_) => FakeReply.error(401, 1000, 'Invalid API Token'))
        ..reply('GET', '/accounts', [
          {'id': 'a1', 'name': 'Studio'},
        ], resultInfo: {'page': 1, 'total_pages': 1})
        ..reply('GET', '/accounts/a1/tokens/verify', {'id': 't', 'status': 'active', 'expires_on': '2027-01-01T00:00:00Z'});
      final check = await TokenVerifier(fakeClient(api)).verify();
      expect(check.kind, TokenKind.account);
      expect(check.expiresOn, DateTime.utc(2027));
    });

    test('rejects a disabled token', () async {
      final api = FakeCfAdapter()..reply('GET', '/user/tokens/verify', {'id': 't', 'status': 'disabled'});
      await expectLater(TokenVerifier(fakeClient(api)).verify(), throwsA(isA<CfAuthException>()));
    });
  });
}
