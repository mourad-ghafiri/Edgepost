import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/mail/mail_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  test('a thread route names its thread and the message to show', () {
    expect(threadOf(threadPath('t/1', focus: 'm1')), ('t/1', 'm1'));
    expect(threadOf(threadPath('t1', focus: 'm1', account: 'a1')), ('t1', 'm1'));
    expect(threadOf(threadPath('t1')), ('t1', null));
    expect(threadOf('/mail?account=a1'), isNull);
    expect(threadOf('/mail/domain/example.com'), isNull);
  });

  group('a thread opened from Today', () {
    late ProviderContainer container;

    Future<void> pump(WidgetTester tester, Size size) async {
      tester.view
        ..physicalSize = size * 2
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      container = ProviderContainer();
      addTearDown(container.dispose);
      final router = GoRouter(
        initialLocation: '/today',
        routes: [
          GoRoute(
            path: '/today',
            builder: (c, s) => Scaffold(
              body: TextButton(
                onPressed: () => openThread(c, 't1', focus: 'm1'),
                child: const Text('Lena Varga'),
              ),
            ),
          ),
          GoRoute(
            path: '/mail',
            builder: (c, s) => const Scaffold(body: Text('the inbox')),
            routes: [
              GoRoute(
                path: 'thread/:id',
                builder: (c, s) => const Scaffold(body: Text('the thread alone')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            key: UniqueKey(),
            theme: buildEpTheme(TargetPlatform.iOS, Brightness.light),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lena Varga'));
      await tester.pumpAndSettle();
    }

    testWidgets('opens beside the inbox where Mail shows a split (iPad)', (tester) async {
      await pump(tester, const Size(1032, 1376));
      expect(find.text('the inbox'), findsOneWidget);
      expect(container.read(threadSelectionProvider), ('t1', 'm1'));
    });

    testWidgets('is pushed over the tabs on a phone', (tester) async {
      await pump(tester, const Size(393, 852));
      expect(find.text('the thread alone'), findsOneWidget);
      expect(container.read(threadSelectionProvider), isNull);
    });
  });
}
