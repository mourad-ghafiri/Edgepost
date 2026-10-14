import 'package:edgepost/core/live/live_refresh.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<Map<LiveTier, int>> pumpPolls(WidgetTester tester, {bool visible = true}) async {
    final hits = {for (final t in LiveTier.values) t: 0};
    await tester.pumpWidget(ProviderScope(
      child: LiveRefreshScope(
        child: TickerMode(
          enabled: visible,
          child: Column(children: [
            for (final t in LiveTier.values) LivePoll(tier: t, onTick: (_) => hits[t] = hits[t]! + 1, child: const SizedBox()),
          ]),
        ),
      ),
    ));
    return hits;
  }

  testWidgets('each tier ticks at its own pace: 5 s, 60 s, 5 min', (tester) async {
    final hits = await pumpPolls(tester);
    for (var i = 0; i < 300; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(hits[LiveTier.fast], 60);
    expect(hits[LiveTier.medium], 5);
    expect(hits[LiveTier.slow], 1);
  });

  testWidgets('offstage screens (TickerMode off) do not poll', (tester) async {
    final hits = await pumpPolls(tester, visible: false);
    for (var i = 0; i < 61; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(hits.values.every((n) => n == 0), isTrue);
  });

  testWidgets('pauses in the background and refreshes everything on return', (tester) async {
    final hits = await pumpPolls(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    for (var i = 0; i < 120; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(hits.values.every((n) => n == 0), isTrue, reason: 'no polling while paused');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(hits.values.every((n) => n == 1), isTrue, reason: 'every tier fires once on resume');
  });
}
