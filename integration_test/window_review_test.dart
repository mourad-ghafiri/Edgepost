// Design review of the iPad adaptation at window sizes a simulator can't be
// put in on command: iPadOS ignores an app's orientation request while the
// app supports multitasking, and Split View, Slide Over and Stage Manager
// need a person. The app runs in a box of each window's size instead, with
// that size in its MediaQuery (a window too big for the screen is scaled
// down to fit), so the same run also exercises live resizing. Not a store
// capture: tool/store_screenshots.sh never runs it.
//
//   dart run tool/fake_cf_api/server.dart &
//   flutter drive --driver=test_driver/store_screenshots.dart \
//     --target=integration_test/window_review_test.dart -d <iPad simulator> \
//     --dart-define=CF_API_BASE=http://127.0.0.1:8789/client/v4 \
//     --dart-define=MAIL_WORKER_URL=http://127.0.0.1:8789
//
// Each capture lands in build/screenshots/raw/review/<window>-<screen>.png,
// the window in the top left corner of the device's frame.
import 'package:edgepost/app/sidebar.dart';
import 'package:edgepost/core/adaptive/popover.dart';
import 'package:edgepost/features/mail/presentation/thread_screen.dart';
import 'package:edgepost/main.dart' as app;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// The windows, as logical sizes with their safe-area insets.
const _windows = <(String, Size, EdgeInsets)>[
  ('ipad13-landscape', Size(1376, 1032), EdgeInsets.only(top: 24, bottom: 20)),
  ('ipad11-portrait', Size(834, 1194), EdgeInsets.only(top: 24, bottom: 20)),
  ('ipad13-half', Size(683, 1032), EdgeInsets.only(top: 24, bottom: 20)),
  ('slide-over', Size(375, 1032), EdgeInsets.only(top: 24, bottom: 20)),
  ('iphone-landscape', Size(956, 440), EdgeInsets.only(left: 62, right: 62, bottom: 21)),
];

/// The app in a window of [window]'s size, top left; the screen's own size
/// until a window is set.
class _Window extends StatelessWidget {
  const _Window({required this.window, required this.child});
  final ValueNotifier<(Size, EdgeInsets)?> window;
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: window,
    builder: (context, w, _) {
      final screen = MediaQuery.of(context);
      final (size, insets) = w ?? (screen.size, screen.padding);
      return Align(
        alignment: Alignment.topLeft,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: size,
            child: ClipRect(
              child: MediaQuery(
                data: screen.copyWith(size: size, padding: insets, viewPadding: insets),
                child: child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('window review', (tester) async {
    Future<void> settle([int ms = 2500]) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    var windowName = '';
    Future<void> shot(String name) async {
      await settle(1200);
      await binding.takeScreenshot('review/$windowName-$name');
    }

    Future<void> tapText(String text) async {
      final f = find.text(text);
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(f, 400, scrollable: find.byType(Scrollable).first);
      }
      await tester.tap(f.first, warnIfMissed: false);
      await settle();
    }

    // Everything over the tabs closes; the shell stays.
    Future<void> home() async {
      tester.state<NavigatorState>(find.byType(Navigator).first).popUntil((r) => r.isFirst);
      await settle(1200);
    }

    // A section from the tab bar, or from the sidebar (slid in first when
    // it is put away).
    Future<void> section(String label) async {
      final show = find.byIcon(CupertinoIcons.sidebar_left).hitTestable();
      final tabs = find.byType(CupertinoTabBar);
      // A page pushed in a tab has Back, not the sidebar's button.
      while (show.evaluate().isEmpty && tabs.evaluate().isEmpty && find.text(label).evaluate().isEmpty) {
        await tester.pageBack();
        await settle(1200);
      }
      // Slid in only when put away: in a wide window the button hides it.
      if (show.evaluate().isNotEmpty &&
          tabs.evaluate().isEmpty &&
          find.byType(EpSidebar).hitTestable().evaluate().isEmpty) {
        await tester.tap(show.first);
        await settle(900);
      }
      await tester.tap(find.text(label).last);
      await settle();
    }

    final window = ValueNotifier<(Size, EdgeInsets)?>(null);
    runApp(_Window(window: window, child: await app.bootstrap()));
    await settle(5000);
    // The demo account and its mail were set up by the store screenshots run.
    expect(
      find.text('Add a Cloudflare API token'),
      findsNothing,
      reason: 'run integration_test/store_screenshots_test.dart first',
    );

    for (final (name, size, insets) in _windows) {
      windowName = name;
      await home();
      window.value = (size, insets);
      await settle(1500);

      await section('Today');
      await shot('1-today');

      await section('Mail');
      // Still open from the last window (beside the list, or pushed over it).
      if (find.byType(ThreadScreen).hitTestable().evaluate().isEmpty) await tapText('Lena Varga');
      await settle(2500);
      await shot('2-thread');
      await home();

      await section('Domains');
      await section('Domains'); // again: back to the list
      await tapText('atelier-nord.dev');
      await settle(2500);
      await tapText('DNS records');
      await settle(2500);
      await shot('3-dns');
      await home();

      if (name == 'ipad11-portrait') {
        // A message's menu: a popover at the finger.
        await section('Mail');
        await tester.longPress(find.text('Lena Varga').first);
        await settle(1200);
        expect(find.byType(EpPopoverMenu), findsOneWidget);
        await shot('4-popover');
        await tester.tapAt(const Offset(700, 1000)); // outside it: it closes
        await settle(800);
        expect(find.byType(EpPopoverMenu), findsNothing);
      }
      if (name == 'ipad11-portrait') {
        await tester.tap(find.byIcon(CupertinoIcons.sidebar_left).hitTestable().first);
        await settle(1200);
        await shot('4-sidebar');
        await tester.tap(find.text('Today').last);
        await settle(1200);
      }
    }
    window.value = null;
    await settle(1000);
  });
}
