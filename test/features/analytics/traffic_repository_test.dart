import 'package:edgepost/core/cloudflare/cf_errors.dart';
import 'package:edgepost/features/analytics/data/traffic_repository.dart';
import 'package:edgepost/features/analytics/presentation/format.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';

final _now = DateTime.utc(2026, 10, 12, 9, 30);

Map<String, dynamic> _sum(int requests, {int cached = 0, int bytes = 0, int cachedBytes = 0, int threats = 0, int pageViews = 0}) => {
      'requests': requests,
      'bytes': bytes,
      'cachedRequests': cached,
      'cachedBytes': cachedBytes,
      'threats': threats,
      'pageViews': pageViews,
    };

/// A realistic `httpRequests1dGroups` answer: two zones, one with a gap day,
/// one without any traffic in the window.
const _dailyResponse = {
  'data': {
    'viewer': {
      'zones': [
        {
          'zoneTag': 'z1',
          'httpRequests1dGroups': [
            {
              'dimensions': {'date': '2026-10-06'},
              'sum': {
                'requests': 1200,
                'bytes': 52428800,
                'cachedRequests': 900,
                'cachedBytes': 41943040,
                'threats': 3,
                'pageViews': 410,
              },
              'uniq': {'uniques': 150},
            },
            {
              'dimensions': {'date': '2026-10-08'},
              'sum': {
                'requests': 3400,
                'bytes': 104857600,
                'cachedRequests': 2700,
                'cachedBytes': 83886080,
                'threats': 0,
                'pageViews': 980,
              },
              'uniq': {'uniques': 420},
            },
            {
              'dimensions': {'date': '2026-10-12'},
              'sum': {
                'requests': 400,
                'bytes': 10485760,
                'cachedRequests': 100,
                'cachedBytes': 2097152,
                'threats': 1,
                'pageViews': 90,
              },
              'uniq': {'uniques': 61},
            },
          ],
        },
        {'zoneTag': 'z2', 'httpRequests1dGroups': <Object>[]},
      ],
    },
  },
  'errors': null,
};

void main() {
  group('fleetDailyTotals', () {
    test('queries httpRequests1dGroups for up to 10 zones with date filters', () async {
      final api = FakeCfAdapter()..on('POST', '/graphql', (_) => const FakeReply(200, _dailyResponse));
      await fleetDailyTotals(fakeClient(api), ['z1', 'z2'], now: _now);

      final body = api.calls.single.body as Map;
      final query = body['query'] as String;
      final vars = body['variables'] as Map;
      expect(query, contains('httpRequests1dGroups'));
      expect(query, contains(r'zones(filter: { zoneTag_in: $zoneTags })'));
      expect(query, contains(r'filter: { date_geq: $since, date_leq: $until }'));
      expect(query, contains('orderBy: [date_ASC]'));
      expect(query, contains('limit: 8'));
      expect(query, contains('dimensions { date }'));
      expect(query, contains('sum { requests bytes cachedRequests cachedBytes threats pageViews }'));
      expect(query, contains('uniq { uniques }'));
      expect(query, contains(r'$zoneTags: [string!]'));
      expect(query, contains(r'$since: Date!'));
      expect(vars, {
        'zoneTags': ['z1', 'z2'],
        'since': '2026-10-06',
        'until': '2026-10-12',
      });
    });

    test('parses totals and a zero-filled daily series per zone', () async {
      final api = FakeCfAdapter()..on('POST', '/graphql', (_) => const FakeReply(200, _dailyResponse));
      final out = await fleetDailyTotals(fakeClient(api), ['z1', 'z2'], now: _now);

      final z1 = out['z1']!;
      expect(z1.requests, 5000);
      expect(z1.cachedRequests, 3700);
      expect(z1.bytes, 52428800 + 104857600 + 10485760);
      expect(z1.cachedBytes, 41943040 + 83886080 + 2097152);
      expect(z1.threats, 4);
      expect(z1.pageViews, 1480);
      expect(z1.uniques, 631);
      expect(z1.cachedRatio, closeTo(0.74, 1e-9));
      expect(z1.series, hasLength(7));
      expect(z1.series.first.t, DateTime.utc(2026, 10, 6));
      expect(z1.series.last.t, DateTime.utc(2026, 10, 12));
      expect(z1.series.map((p) => p.requests), [1200, 0, 3400, 0, 0, 0, 400]);
      expect(z1.series[2].cachedRequests, 2700);
      expect(z1.series[2].bytes, 104857600);

      final z2 = out['z2']!;
      expect(z2.isEmpty, isTrue);
      expect(z2.cachedRatio, 0);
      expect(z2.series, hasLength(7));
    });

    test('batches 23 zones into 3 queries of at most 10', () async {
      final batches = <List<String>>[];
      final api = FakeCfAdapter()
        ..on('POST', '/graphql', (call) {
          final tags = ((call.body as Map)['variables'] as Map)['zoneTags'] as List;
          batches.add(tags.cast<String>());
          return FakeReply(200, {
            'data': {
              'viewer': {
                'zones': [
                  for (final t in tags)
                    {
                      'zoneTag': t,
                      'httpRequests1dGroups': [
                        {
                          'dimensions': {'date': '2026-10-12'},
                          'sum': _sum(10, cached: 5),
                          'uniq': {'uniques': 2},
                        },
                      ],
                    },
                ],
              },
            },
          });
        });
      final tags = [for (var i = 0; i < 23; i++) 'zone$i'];
      final out = await fleetDailyTotals(fakeClient(api), tags, now: _now);

      expect(api.calls, hasLength(3));
      expect(batches.map((b) => b.length), [10, 10, 3]);
      expect(batches.expand((b) => b), tags);
      expect(out.keys, unorderedEquals(tags));
      expect(out['zone22']!.requests, 10);
    });

    test('no zones means no query', () async {
      final api = FakeCfAdapter();
      expect(await fleetDailyTotals(fakeClient(api), const []), isEmpty);
      expect(api.calls, isEmpty);
    });
  });

  group('zoneSeries', () {
    test('24h uses httpRequests1hGroups with datetime filters and 24 hourly points', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/graphql', (_) => const FakeReply(200, {
              'data': {
                'viewer': {
                  'zones': [
                    {
                      'zoneTag': 'z1',
                      'httpRequests1hGroups': [
                        {
                          'dimensions': {'datetime': '2026-10-11T10:00:00Z'},
                          'sum': {
                            'requests': 80,
                            'bytes': 1000,
                            'cachedRequests': 60,
                            'cachedBytes': 800,
                            'threats': 0,
                            'pageViews': 20,
                          },
                          'uniq': {'uniques': 9},
                        },
                        {
                          'dimensions': {'datetime': '2026-10-12T09:00:00Z'},
                          'sum': {
                            'requests': 20,
                            'bytes': 400,
                            'cachedRequests': 5,
                            'cachedBytes': 100,
                            'threats': 2,
                            'pageViews': 4,
                          },
                          'uniq': {'uniques': 3},
                        },
                      ],
                    },
                  ],
                },
              },
            }));
      final t = await zoneSeries(fakeClient(api), 'z1', TrafficRange.last24h, now: _now);

      final body = api.calls.single.body as Map;
      final query = body['query'] as String;
      expect(query, contains('httpRequests1hGroups'));
      expect(query, contains(r'zones(filter: { zoneTag: $zoneTag })'));
      expect(query, contains(r'filter: { datetime_geq: $since, datetime_lt: $until }'));
      expect(query, contains('dimensions { datetime }'));
      expect(query, contains('orderBy: [datetime_ASC]'));
      expect(query, contains(r'$since: Time!'));
      expect(body['variables'], {
        'zoneTag': 'z1',
        'since': '2026-10-11T10:00:00Z',
        'until': '2026-10-12T09:30:00Z',
      });

      expect(t.requests, 100);
      expect(t.cachedRequests, 65);
      expect(t.threats, 2);
      expect(t.uniques, 12);
      expect(t.series, hasLength(24));
      expect(t.series.first.t, DateTime.utc(2026, 10, 11, 10));
      expect(t.series.first.requests, 80);
      expect(t.series.last.t, DateTime.utc(2026, 10, 12, 9));
      expect(t.series.last.requests, 20);
      expect(t.series.where((p) => p.requests == 0), hasLength(22));
    });

    test('30d asks one zone for 30 daily points', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/graphql', (_) => const FakeReply(200, {
              'data': {
                'viewer': {'zones': <Object>[]},
              },
            }));
      final t = await zoneSeries(fakeClient(api), 'z1', TrafficRange.last30d, now: _now);

      final body = api.calls.single.body as Map;
      expect(body['query'], contains('httpRequests1dGroups'));
      expect(body['query'], contains('limit: 31'));
      expect(body['variables'], {'zoneTag': 'z1', 'since': '2026-09-13', 'until': '2026-10-12'});
      expect(t.isEmpty, isTrue);
      expect(t.series, hasLength(30));
    });

    test('a range beyond the plan becomes TrafficRangeUnavailableException', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/graphql', (_) => const FakeReply(200, {
              'data': null,
              'errors': [
                {'message': 'cannot request data older than 2678400s (notOlderThan)'},
              ],
            }));
      await expectLater(
        zoneSeries(fakeClient(api), 'z1', TrafficRange.last30d, now: _now),
        throwsA(isA<TrafficRangeUnavailableException>()),
      );
    });

    test('an authorization error becomes a permission error', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/graphql', (_) => const FakeReply(200, {
              'data': null,
              'errors': [
                {'message': 'not authorized for that zone'},
              ],
            }));
      await expectLater(
        zoneSeries(fakeClient(api), 'z1', TrafficRange.last7d, now: _now),
        throwsA(isA<CfApiException>().having((e) => e.isPermissionDenied, 'permission', true)),
      );
    });

    test('other GraphQL errors pass through unchanged', () async {
      final api = FakeCfAdapter()
        ..on('POST', '/graphql', (_) => const FakeReply(200, {
              'data': null,
              'errors': [
                {'message': 'query exceeds budget'},
              ],
            }));
      await expectLater(
        zoneSeries(fakeClient(api), 'z1', TrafficRange.last7d, now: _now),
        throwsA(isA<CfApiException>().having((e) => e.isPermissionDenied, 'permission', false)),
      );
    });
  });

  group('ZoneTraffic', () {
    test('round-trips through JSON for the cache', () {
      final t = ZoneTraffic(
        requests: 10,
        bytes: 2048,
        cachedRequests: 4,
        cachedBytes: 1024,
        threats: 1,
        uniques: 3,
        pageViews: 5,
        series: [TrafficPoint(t: DateTime.utc(2026, 10, 12), requests: 10, cachedRequests: 4, bytes: 2048)],
      );
      final back = ZoneTraffic.fromJson(t.toJson());
      expect(back.toJson(), t.toJson());
      expect(back.cachedRatio, 0.4);
      expect(back.cachedBytes / back.bytes, 0.5);
    });
  });

  group('format', () {
    test('compact counts', () {
      expect(formatCompact(950, locale: 'en'), '950');
      expect(formatCompact(1234, locale: 'en'), '1.2K');
      expect(formatCompact(123456, locale: 'en'), '123K');
      expect(formatCompact(1234567, locale: 'en'), '1.2M');
      expect(formatCount(1234567, locale: 'en'), '1,234,567');
    });

    test('bytes in decimal units', () {
      expect(formatBytes(512, locale: 'en'), '512 B');
      expect(formatBytes(1536, locale: 'en'), '1.5 KB');
      expect(formatBytes(3400000000, locale: 'en'), '3.4 GB');
      expect(formatBytes(123456789012, locale: 'en'), '123 GB');
    });

    test('percent', () {
      expect(formatPercent(0, locale: 'en'), '0%');
      expect(formatPercent(0.045, locale: 'en'), '4.5%');
      expect(formatPercent(0.873, locale: 'en'), '87%');
    });
  });
}
