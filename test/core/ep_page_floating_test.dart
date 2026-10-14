import 'package:edgepost/core/adaptive/ep_icons.dart';
import 'package:edgepost/core/adaptive/ep_page.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _both = TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android});

Future<List<int>> _pump(WidgetTester tester, {double keyboard = 0}) async {
  final taps = <int>[];
  tester.view
    ..physicalSize = const Size(1179, 2556)
    ..devicePixelRatio = 3
    ..viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: buildEpTheme(defaultTargetPlatform, Brightness.light),
        home: EpPage(
          title: 'Mail',
          floatingAction: EpAction(icon: EpIcon.compose, label: 'New message', onPressed: () => taps.add(1)),
          slivers: [
            SliverList.list(children: [for (var i = 0; i < 60; i++) SizedBox(height: 64, child: Text('Message $i'))]),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return taps;
}

void main() {
  testWidgets('New message floats at the bottom right, worded, and is not in the top bar', variant: _both, (
    tester,
  ) async {
    final taps = await _pump(tester);
    final label = find.text('New message');
    expect(label, findsOneWidget);
    final rect = tester.getRect(label);
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(rect.center.dx, greaterThan(screen.width / 2), reason: 'right');
    expect(rect.center.dy, greaterThan(screen.height * 0.8), reason: 'bottom');
    expect(
      find.descendant(of: find.byType(CupertinoSliverNavigationBar), matching: find.byIcon(EpIcon.compose.cupertino)),
      findsNothing,
    );
    await tester.tap(label);
    expect(taps, [1]);
  });

  testWidgets('scrolling down leaves just the icon; back up, the words return', variant: _both, (tester) async {
    await _pump(tester);
    await tester.drag(find.text('Message 3'), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('New message'), findsNothing);
    expect(find.bySemanticsLabel('New message'), findsOneWidget, reason: 'still named for screen readers');
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.text('New message'), findsOneWidget);
  });

  testWidgets('out of the way while the keyboard is up', variant: _both, (tester) async {
    final taps = await _pump(tester, keyboard: 900);
    final opacity = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('New message'), matching: find.byType(AnimatedOpacity)),
    );
    expect(opacity.opacity, 0);
    await tester.tap(find.text('New message'), warnIfMissed: false);
    expect(taps, isEmpty);
  });
}
