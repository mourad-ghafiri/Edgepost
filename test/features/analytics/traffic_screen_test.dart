import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/theme/tokens.dart';
import 'package:edgepost/features/analytics/presentation/traffic_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_cf.dart';
import 'analytics_harness.dart';

const _platforms = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android});

/// Answers both datasets from the query's own variables: day i of the window
/// gets 1000·(i+1) requests, 60% cached; every hour gets 100 requests.
FakeCfAdapter _api({bool empty = false, String? error}) {
  final api = FakeCfAdapter();
  api.on('POST', '/graphql', (call) {
    if (error != null) {
      return FakeReply(200, {
        'data': null,
        'errors': [
          {'message': error},
        ],
      });
    }
    final body = call.body as Map;
    final query = body['query'] as String;
    final vars = body['variables'] as Map;
    final hourly = query.contains('httpRequests1hGroups');
    final groups = <Map<String, Object>>[];
    if (!empty) {
      if (hourly) {
        final start = DateTime.parse(vars['since'] as String);
        for (var i = 0; i < 24; i++) {
          final t = start.add(Duration(hours: i));
          groups.add({
            'dimensions': {'datetime': t.toIso8601String()},
            'sum': {'requests': 100, 'bytes': 100000, 'cachedRequests': 50, 'cachedBytes': 50000, 'threats': 0, 'pageViews': 10},
            'uniq': {'uniques': 5},
          });
        }
      } else {
        final start = DateTime.parse(vars['since'] as String);
        final end = DateTime.parse(vars['until'] as String);
        var i = 0;
        for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1)), i++) {
          groups.add({
            'dimensions': {'date': '${d.year}-${'${d.month}'.padLeft(2, '0')}-${'${d.day}'.padLeft(2, '0')}'},
            'sum': {
              'requests': 1000 * (i + 1),
              'bytes': 1000000 * (i + 1),
              'cachedRequests': 600 * (i + 1),
              'cachedBytes': 500000 * (i + 1),
              'threats': 0,
              'pageViews': 100,
            },
            'uniq': {'uniques': 10},
          });
        }
      }
    }
    return FakeReply(200, {
      'data': {
        'viewer': {
          'zones': [
            {'zoneTag': 'z1', hourly ? 'httpRequests1hGroups' : 'httpRequests1dGroups': groups},
          ],
        },
      },
    });
  });
  return api;
}

void main() {
  testWidgets('7 days: headline strip, legend and a described chart', (tester) async {
    final semantics = tester.ensureSemantics();
    final api = _api();
    await pumpEp(tester, api: api, child: const TrafficScreen(zoneId: 'z1'));

    expect(find.text('Traffic'), findsOneWidget);
    expect(find.text('example.com'), findsOneWidget);
    expect(find.text('Last 7 days · UTC'), findsOneWidget);
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('28K'), findsOneWidget);
    expect(find.text('28 MB'), findsOneWidget);
    expect(find.text('60%'), findsOneWidget);
    expect(find.text('70'), findsOneWidget);
    expect(find.text('Not cached'), findsOneWidget);
    expect(find.text('Served from cache'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp(r'^Requests per day, Last 7 days · UTC\. 28,000 requests in all, 60% served from cache\. Busiest: 7,000 requests')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Requests'), findsOneWidget);
    expect(api.calls.single.path, '/graphql');
    semantics.dispose();
  }, variant: _platforms);

  testWidgets('switching to 24 hours runs the hourly query', (tester) async {
    final api = _api();
    await pumpEp(tester, api: api, child: const TrafficScreen(zoneId: 'z1'));
    await tester.tap(find.text('24 hours'));
    await tester.pumpAndSettle();

    expect(((api.calls.last.body as Map)['query'] as String), contains('httpRequests1hGroups'));
    expect(find.text('Requests per hour'), findsOneWidget);
    expect(find.text('Last 24 hours · UTC'), findsOneWidget);
    expect(find.text('2.4K'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
  }, variant: _platforms);

  testWidgets('no traffic shows the empty state', (tester) async {
    await pumpEp(tester, api: _api(empty: true), child: const TrafficScreen(zoneId: 'z1'));
    expect(find.text('No traffic in this range'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  }, variant: _platforms);

  testWidgets('a range beyond the plan explains itself and offers a shorter one', (tester) async {
    final api = _api(error: 'cannot request data older than 259200s');
    await pumpEp(tester, api: api, child: const TrafficScreen(zoneId: 'z1'));

    expect(find.text("This range isn't available on your plan"), findsOneWidget);
    expect(find.text('Show 24 hours'), findsOneWidget);
    await tester.tap(find.text('Show 24 hours'));
    await tester.pumpAndSettle();
    expect(((api.calls.last.body as Map)['query'] as String), contains('httpRequests1hGroups'));
  }, variant: _platforms);

  testWidgets('a token without Analytics Read names the permission and calls nothing', (tester) async {
    final api = _api();
    await pumpEp(
      tester,
      api: api,
      credential: testCredential(capabilities: {Capability.zones: true, Capability.analytics: false}),
      child: const TrafficScreen(zoneId: 'z1'),
    );
    expect(find.textContaining(Capability.analytics.permission), findsOneWidget);
    expect(api.calls, isEmpty);
  }, variant: _platforms);

  testWidgets('other errors offer a retry', (tester) async {
    final api = _api(error: 'query exceeds budget');
    await pumpEp(tester, api: api, child: const TrafficScreen(zoneId: 'z1'));
    expect(find.text('query exceeds budget'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  }, variant: _platforms);

  testWidgets('renders in dark mode with the dark chart tones', (tester) async {
    await pumpEp(tester, api: _api(), brightness: Brightness.dark, child: const TrafficScreen(zoneId: 'z1'));
    expect(find.byType(BarChart), findsOneWidget);
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final rod = chart.data.barGroups.last.barRods.single;
    expect(rod.color, EpColors.dark.tint);
    expect(rod.rodStackItems.first.color, const Color(0xFF7C8394), reason: 'the cached share, in slate');
    expect(tester.takeException(), isNull);
  }, variant: _platforms);
}
