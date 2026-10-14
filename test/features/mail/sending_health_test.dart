import 'package:edgepost/core/cloudflare/models.dart';
import 'package:edgepost/features/mail/data/sending_health.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';

final _zone = Zone.fromJson({
  'id': 'z1',
  'name': 'example.com',
  'status': 'active',
  'paused': false,
  'account': {'id': 'a1', 'name': 'Personal'},
}, reach: const ['c1']);

void main() {
  test('counts by status, delivery rate and problem events with auth results', () async {
    final queries = <String>[];
    final api = FakeCfAdapter()
      ..on('POST', '/graphql', (call) {
        final body = call.body as Map;
        final q = '${body['query']}';
        queries.add(q);
        expect((body['variables'] as Map)['zoneTag'], 'z1');
        if (q.contains('emailSendingAdaptiveGroups')) {
          return const FakeReply(200, {
            'data': {
              'viewer': {
                'zones': [
                  {
                    'emailSendingAdaptiveGroups': [
                      {'count': 3, 'dimensions': {'date': '2026-10-12', 'status': 'delivered'}},
                      {'count': 2, 'dimensions': {'date': '2026-10-12', 'status': 'deliveryFailed'}},
                      {'count': 1, 'dimensions': {'date': '2026-10-11', 'status': 'delivered'}},
                    ],
                  },
                ],
              },
            },
            'errors': null,
          });
        }
        return const FakeReply(200, {
          'data': {
            'viewer': {
              'zones': [
                {
                  'emailSendingAdaptive': [
                    {
                      'datetime': '2026-10-12T10:00:00Z',
                      'from': 'contact@example.com',
                      'to': 'someone@gmail.com',
                      'subject': 'Hello',
                      'status': 'deliveryFailed',
                      'errorCause': 'rejected',
                      'errorDetail': '550 5.7.26 Unauthenticated email from example.com is not accepted due to its DMARC policy',
                      'spf': 'fail',
                      'dkim': 'fail',
                      'dmarc': 'fail',
                      'isSpam': false,
                    },
                    {
                      'datetime': '2026-10-12T09:00:00Z',
                      'from': 'contact@example.com',
                      'to': 'friend@example.org',
                      'subject': 'Re: Hi',
                      'status': 'delivered',
                      'spf': 'pass',
                      'dkim': 'pass',
                      'dmarc': 'pass',
                    },
                  ],
                },
              ],
            },
          },
          'errors': null,
        });
      });
    final h = await fetchSendingHealth(fakeClient(api), _zone, now: DateTime.utc(2026, 10, 12, 12));
    expect(queries.first, contains('emailSendingAdaptiveGroups'));
    expect(queries.last, contains('emailSendingAdaptive('));
    expect(h.delivered, 4);
    expect(h.failed, 2);
    expect(h.deliveryRate, closeTo(4 / 6, 1e-9));
    expect(h.problems, hasLength(1));
    expect(h.problems.single.authFailed, isTrue);
    expect(h.problems.single.to, 'someone@gmail.com');
  });

  test('no sends means no rate', () async {
    final api = FakeCfAdapter()
      ..on('POST', '/graphql', (_) => const FakeReply(200, {
            'data': {'viewer': {'zones': <Object>[]}},
            'errors': null,
          }));
    final h = await fetchSendingHealth(fakeClient(api), _zone);
    expect(h.deliveryRate, isNull);
    expect(h.problems, isEmpty);
  });
}
