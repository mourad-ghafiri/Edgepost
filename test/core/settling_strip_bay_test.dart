import 'package:edgepost/core/strip/strip.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/core/theme/tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _strip(String id) => Strip(key: ValueKey(id), title: id, family: Family.domains, cocked: true, reason: 'Needs a look');

Widget _app(List<Widget> needs) => MaterialApp(
      theme: buildEpTheme(TargetPlatform.android, Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: SettlingStripBay(title: 'Needs you', settledNote: 'Back in line', empty: const Text('All clear'), children: needs),
        ),
      ),
    );

void main() {
  testWidgets('a resolved strip springs back into line, says so, then leaves', (tester) async {
    await tester.pumpWidget(_app([_strip('a.dev'), _strip('b.dev')]));
    expect(find.text('Needs a look'), findsNWidgets(2));

    await tester.pumpWidget(_app([_strip('b.dev')]));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('a.dev'), findsOneWidget, reason: 'still on the board while it settles');
    expect(find.text('Back in line'), findsOneWidget);
    expect(find.text('Needs a look'), findsOneWidget, reason: 'only b.dev is still cocked');

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('a.dev'), findsNothing);
    expect(find.text('Back in line'), findsNothing);

    await tester.pumpWidget(_app(const []));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('All clear'), findsOneWidget);
  });

  testWidgets('a strip cocked again before it left simply stays', (tester) async {
    await tester.pumpWidget(_app([_strip('a.dev')]));
    await tester.pumpWidget(_app(const []));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpWidget(_app([_strip('a.dev')]));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Needs a look'), findsOneWidget);
    expect(find.text('Back in line'), findsNothing);
  });
}
