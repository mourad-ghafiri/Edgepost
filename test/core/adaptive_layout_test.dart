import 'package:edgepost/app/nav_keys.dart';
import 'package:edgepost/app/sidebar.dart';
import 'package:edgepost/core/adaptive/ep_icons.dart';
import 'package:edgepost/core/adaptive/ep_page.dart';
import 'package:edgepost/core/adaptive/ep_widgets.dart';
import 'package:edgepost/core/adaptive/layout.dart';
import 'package:edgepost/core/adaptive/popover.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<void> _pump(WidgetTester tester, Size size, Widget child, {TargetPlatform platform = TargetPlatform.iOS}) async {
  tester.view
    ..physicalSize = size * 2
    ..devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      key: UniqueKey(), // a fresh app per size or platform, never a themed transition between them
      theme: buildEpTheme(platform, Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('size classes', () {
    Future<bool> sidebarAt(WidgetTester tester, Size size, {TargetPlatform platform = TargetPlatform.iOS}) async {
      late bool result;
      await _pump(
        tester,
        size,
        Builder(
          builder: (c) {
            result = EpLayout.sidebar(c);
            return const SizedBox();
          },
        ),
        platform: platform,
      );
      return result;
    }

    testWidgets('the sidebar is for big iOS windows; phones and narrow windows keep the tab bar', (tester) async {
      expect(await sidebarAt(tester, const Size(1032, 1376)), isTrue, reason: 'iPad 13" portrait');
      expect(await sidebarAt(tester, const Size(1376, 1032)), isTrue, reason: 'iPad 13" landscape');
      expect(await sidebarAt(tester, const Size(694, 1032)), isTrue, reason: 'half of a 13" iPad in Split View');
      expect(await sidebarAt(tester, const Size(375, 1032)), isFalse, reason: 'Slide Over, a third of the screen');
      expect(await sidebarAt(tester, const Size(440, 956)), isFalse, reason: 'iPhone Pro Max portrait');
      expect(
        await sidebarAt(tester, const Size(956, 440)),
        isFalse,
        reason: 'iPhone Pro Max landscape keeps its tab bar',
      );
      expect(
        await sidebarAt(tester, const Size(1032, 1376), platform: TargetPlatform.android),
        isFalse,
        reason: 'Android has its rail',
      );
    });

    Future<(bool, bool)> dockAndSplitAt(
      WidgetTester tester,
      Size size, {
      TargetPlatform platform = TargetPlatform.iOS,
    }) async {
      late (bool, bool) result;
      await _pump(
        tester,
        size,
        Builder(
          builder: (c) {
            result = (EpLayout.sidebarDocked(c), EpLayout.splits(c));
            return const SizedBox();
          },
        ),
        platform: platform,
      );
      return result;
    }

    testWidgets('the sidebar docks in landscape; in portrait it slides in, so lists keep their split', (
      tester,
    ) async {
      expect(await dockAndSplitAt(tester, const Size(1376, 1032)), (true, true), reason: 'iPad 13" landscape');
      expect(await dockAndSplitAt(tester, const Size(1194, 834)), (true, true), reason: 'iPad 11" landscape');
      expect(await dockAndSplitAt(tester, const Size(1032, 1376)), (false, true), reason: 'iPad 13" portrait');
      expect(await dockAndSplitAt(tester, const Size(834, 1194)), (false, true), reason: 'iPad 11" portrait');
      expect(await dockAndSplitAt(tester, const Size(744, 1133)), (false, true), reason: 'iPad mini portrait');
      expect(await dockAndSplitAt(tester, const Size(694, 1032)), (false, false), reason: 'half a 13" iPad');
      expect(await dockAndSplitAt(tester, const Size(375, 1032)), (false, false), reason: 'Slide Over');
      expect(
        await dockAndSplitAt(tester, const Size(956, 440)),
        (false, true),
        reason: 'iPhone Pro Max landscape: tab bar, inbox and thread side by side',
      );
      expect(
        await dockAndSplitAt(tester, const Size(780, 1200), platform: TargetPlatform.android),
        (false, false),
        reason: 'the rail takes its width first',
      );
      expect(await dockAndSplitAt(tester, const Size(1280, 800), platform: TargetPlatform.android), (false, true));
    });
  });

  group('split', () {
    Widget split(List<bool> seen) => Scaffold(
      body: EpSplit(
        list: (context, inSplit) {
          seen.add(inSplit);
          return const Text('the list');
        },
        detail: const EpSplitPlaceholder(icon: EpIcon.inbox, text: 'Choose one'),
      ),
    );

    testWidgets('list and detail side by side when there is room', (tester) async {
      final seen = <bool>[];
      await _pump(tester, const Size(1100, 800), split(seen));
      expect(find.text('the list'), findsOneWidget);
      expect(find.text('Choose one'), findsOneWidget);
      expect(seen.last, isTrue, reason: 'the list knows it selects instead of pushing');
      expect(tester.getSize(find.text('the list')).width, lessThanOrEqualTo(400));
    });

    testWidgets('the list alone on a phone', (tester) async {
      final seen = <bool>[];
      await _pump(tester, const Size(430, 900), split(seen));
      expect(find.text('Choose one'), findsNothing);
      expect(seen.last, isFalse);
    });

    testWidgets('a narrow window can show something else than the list (a navigator holding it)', (tester) async {
      await _pump(
        tester,
        const Size(430, 900),
        EpSplit(
          list: (context, inSplit) => const Text('the list'),
          detail: const Text('the detail'),
          narrow: const Text('the stack'),
        ),
      );
      expect(find.text('the stack'), findsOneWidget);
      expect(find.text('the list'), findsNothing);
    });
  });

  testWidgets('tab roots under the sidebar show its toggle; other pages keep their back button', (tester) async {
    var shown = true;
    Widget page({required bool root}) => StatefulBuilder(
      builder: (context, setState) => EpSidebarScope(
        shown: shown,
        toggle: () => setState(() => shown = !shown),
        child: EpPage(title: root ? 'Today' : 'Detail', account: root, largeTitle: root, slivers: const []),
      ),
    );
    await _pump(tester, const Size(1032, 1376), ProviderScope(child: page(root: true)));
    final handle = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Hide sidebar'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.sidebar_left));
    await tester.pumpAndSettle();
    expect(shown, isFalse);
    expect(find.bySemanticsLabel('Show sidebar'), findsOneWidget);
    await _pump(tester, const Size(1032, 1376), ProviderScope(child: page(root: false)));
    expect(find.byIcon(CupertinoIcons.sidebar_left), findsNothing);
    handle.dispose();
  });

  testWidgets('an iPad keeps its large title in landscape; an iPhone collapses it, as iOS does', (tester) async {
    Future<double> contentTop(Size size) async {
      await _pump(
        tester,
        size,
        const EpPage(
          title: 'Today',
          slivers: [SliverToBoxAdapter(child: Text('content'))],
        ),
      );
      return tester.getTopLeft(find.text('content')).dy;
    }

    expect(await contentTop(const Size(1376, 1032)), greaterThan(90), reason: 'iPad 13" landscape: large title');
    expect(await contentTop(const Size(956, 440)), lessThan(70), reason: 'iPhone landscape: inline title');
  });

  testWidgets('a segmented control too narrow for its labels becomes a row of pills', (tester) async {
    Widget segmented(double width) => Center(
      child: SizedBox(
        width: width,
        child: EpSegmented<int>(
          segments: const {0: 'Inbox', 1: 'Sent', 2: 'Archive', 3: 'Trash'},
          value: 0,
          onChanged: (_) {},
        ),
      ),
    );
    await _pump(tester, const Size(1032, 1376), segmented(640));
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsOneWidget);
    await _pump(tester, const Size(1032, 1376), segmented(300));
    expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsNothing, reason: 'never "Archiv"');
    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets('a large title flies into the next page\'s back label', (tester) async {
    await _pump(
      tester,
      const Size(393, 852),
      Builder(
        builder: (context) => EpPage(
          title: 'Compute',
          slivers: [
            SliverToBoxAdapter(
              child: CupertinoButton(
                onPressed: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => const EpPage(
                      title: 'contact-form',
                      largeTitle: false,
                      previousPageTitle: 'Compute',
                      slivers: [],
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('menus', () {
    Widget opener(List<String?> picked) => Scaffold(
      body: Center(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked.add(
              await showEpActionSheet<String>(
                context,
                title: 'Move to',
                actions: const [
                  EpSheetAction(label: 'Archive', value: 'archive', icon: EpIcon.archive),
                  EpSheetAction(label: 'Trash', value: 'trash', icon: EpIcon.trash, destructive: true),
                ],
              ),
            ),
            child: const Text('menu'),
          ),
        ),
      ),
    );

    testWidgets('a popover beside the control on an iPad', (tester) async {
      trackPopoverAnchors();
      final picked = <String?>[];
      await _pump(tester, const Size(1032, 1376), opener(picked));
      final button = tester.getCenter(find.text('menu'));
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsNothing);
      final menu = tester.getRect(find.byType(EpPopoverMenu));
      expect(menu.width, closeTo(320, 2)); // inside its hairline
      expect(menu.top, greaterThan(button.dy), reason: 'below the control');
      expect((menu.center.dx - button.dx).abs(), lessThan(1), reason: 'centred on it');
      await tester.tap(find.text('Archive'));
      await tester.pumpAndSettle();
      expect(picked, ['archive']);
      expect(find.byType(EpPopoverMenu), findsNothing);
    });

    testWidgets('an action sheet on an iPhone', (tester) async {
      final picked = <String?>[];
      await _pump(tester, const Size(393, 852), opener(picked));
      await tester.tap(find.text('menu'));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoActionSheet), findsOneWidget);
      expect(find.byType(EpPopoverMenu), findsNothing);
    });
  });

  testWidgets('the sidebar: one row per section, the chosen one selected, counts spoken', (tester) async {
    var chosen = 0;
    await _pump(
      tester,
      const Size(1032, 1376),
      StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: EpSidebar(
            selected: chosen,
            onSelect: (i) => setState(() => chosen = i),
            items: const [
              SidebarItem(icon: CupertinoIcons.sun_max, label: 'Today', count: 4, urgent: true, spoken: '4 need you'),
              SidebarItem(icon: CupertinoIcons.mail, label: 'Mail', count: 3, spoken: '3 unread'),
            ],
          ),
        ),
      ),
    );
    final handle = tester.ensureSemantics();
    expect(find.text('4'), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Today')),
      isSemantics(label: 'Today, 4 need you', isSelected: true, isButton: true),
    );
    await tester.tap(find.text('Mail'));
    await tester.pumpAndSettle();
    expect(chosen, 1);
    expect(tester.getSemantics(find.text('Mail')), isSemantics(label: 'Mail, 3 unread', isSelected: true));
    handle.dispose();
  });

  group('sidebar frame', () {
    Widget frame({required bool docked, bool hidden = false, double overlay = 0}) => Scaffold(
      body: EpSidebarFrame(
        docked: docked,
        dockHidden: hidden,
        overlay: AlwaysStoppedAnimation(overlay),
        onDismiss: () {},
        dismissLabel: 'Hide sidebar',
        sidebar: const ColoredBox(color: Colors.white, child: Text('the sidebar')),
        body: const SizedBox.expand(key: Key('content'), child: Text('the content')),
      ),
    );

    testWidgets('docked beside the content in a wide window', (tester) async {
      await _pump(tester, const Size(1376, 1032), frame(docked: true));
      expect(tester.getTopLeft(find.text('the content')).dx, EpLayout.sidebarWidth);
      await _pump(tester, const Size(1376, 1032), frame(docked: true, hidden: true));
      expect(tester.getTopLeft(find.text('the content')).dx, 0, reason: 'hidden: the content takes the width');
    });

    testWidgets('put away in portrait: the content fills the window, the sidebar slides over it', (tester) async {
      await _pump(tester, const Size(834, 1194), frame(docked: false));
      expect(tester.getSize(find.byKey(const Key('content'))), const Size(834, 1194));
      expect(find.text('the sidebar'), findsNothing);
      await _pump(tester, const Size(834, 1194), frame(docked: false, overlay: 1));
      expect(find.text('the sidebar'), findsOneWidget);
      expect(tester.getTopLeft(find.text('the content')).dx, 0, reason: 'over the content, not beside it');
    });
  });

  testWidgets('a modal task floats as a sheet in a big window, full screen on a phone', (tester) async {
    GoRouter router() => GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => Scaffold(
            body: TextButton(onPressed: () => c.push('/task'), child: const Text('open')),
          ),
        ),
        GoRoute(
          path: '/task',
          pageBuilder: (c, s) => modalPage(c, s, const Scaffold(body: Text('the task'))),
        ),
      ],
    );
    Future<Size> taskAt(Size size) async {
      tester.view
        ..physicalSize = size * 2
        ..devicePixelRatio = 2;
      final r = router();
      await tester.pumpWidget(
        MaterialApp.router(theme: buildEpTheme(TargetPlatform.iOS, Brightness.light), routerConfig: r),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return tester.getSize(find.ancestor(of: find.text('the task'), matching: find.byType(Scaffold)).first);
    }

    addTearDown(tester.view.reset);
    final sheet = await taskAt(const Size(1032, 1376));
    expect(sheet.width, lessThanOrEqualTo(680), reason: 'a sheet, not the whole iPad');
    expect(find.text('open'), findsOneWidget, reason: 'the app stays visible behind it');
    final phone = await taskAt(const Size(430, 900));
    expect(phone.width, 430, reason: 'full screen on a phone');
  });
}
