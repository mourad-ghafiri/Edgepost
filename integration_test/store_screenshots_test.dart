// The store screenshots: ten screens of the demo account, captured on one
// device per run, against the local fake API (synthetic demo data only).
// Run through tool/store_screenshots.sh, which picks the devices, cleans the
// status bar and files the results; or by hand:
//
//   dart run tool/fake_cf_api/server.dart &
//   flutter drive --driver=test_driver/store_screenshots.dart \
//     --target=integration_test/store_screenshots_test.dart -d <device> \
//     --dart-define=SHOT_DEVICE=iphone-6.9 [--dart-define=SHOT_LANDSCAPE=true] \
//     --dart-define=CF_API_BASE=http://127.0.0.1:8789/client/v4 \
//     --dart-define=MAIL_WORKER_URL=http://127.0.0.1:8789
//   (Android emulator: 10.0.2.2 instead of 127.0.0.1)
//
// The captures land in build/screenshots/raw/<SHOT_DEVICE>/NN-name.png.
// Navigation works with every layout: a phone pushes the thread and the
// domain; a wide window shows them beside the list.
import 'package:edgepost/core/adaptive/layout.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/appearance.dart';
import 'package:edgepost/features/mail/presentation/compose_screen.dart';
import 'package:edgepost/features/onboarding/presentation/welcome_screen.dart';
import 'package:edgepost/main.dart' as app;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _device = String.fromEnvironment('SHOT_DEVICE', defaultValue: 'device');

/// `dark` shoots the app in its dark appearance (the website's dark-mode
/// tour); every run sets its appearance first, and a dark run puts light
/// back at the end.
const _dark = String.fromEnvironment('SHOT_APPEARANCE') == 'dark';

/// Turns the device to landscape for the whole run (the app supports every
/// orientation; the review uses it to check iPad landscape).
const _landscape = bool.fromEnvironment('SHOT_LANDSCAPE');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('store screenshots', (tester) async {
    Future<void> settle([int ms = 2500]) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    var converted = false;
    Future<void> shot(String name) async {
      await settle(1500);
      if (!converted && Theme.of(tester.element(find.byType(Navigator).first)).platform == TargetPlatform.android) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
        await settle(300);
      }
      await binding.takeScreenshot('$_device/$name');
    }

    Future<void> tapText(String text) async {
      final f = find.text(text);
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(f, 400, scrollable: find.byType(Scrollable).first);
      }
      final ctx = tester.element(f.first);
      if (Scrollable.maybeOf(ctx) != null) {
        await Scrollable.ensureVisible(ctx, alignment: 0.4);
        await settle(400);
      }
      await tester.tap(f.first, warnIfMissed: false);
      await settle();
    }

    // The section's label in the tab bar or the sidebar (the last match: a
    // page can show the same word). A sidebar put away (iPad portrait)
    // slides in first, and back out once a section is chosen.
    Future<void> tapSection(String label) async {
      final show = find.bySemanticsLabel('Show sidebar');
      if (show.evaluate().isNotEmpty && find.byType(CupertinoTabBar).evaluate().isEmpty) {
        await tester.tap(show.first);
        await settle(900);
      }
      await tester.tap(find.text(label).last);
      await settle();
    }

    // Back, where the page offers it (a split's detail has none: its list is
    // beside it).
    Future<void> back() async {
      final button = find.byWidgetPredicate((w) => w is CupertinoNavigationBarBackButton || w is BackButton);
      if (button.evaluate().isEmpty) return;
      await tester.pageBack();
      await settle();
    }

    if (_landscape) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
      addTearDown(() => SystemChrome.setPreferredOrientations([]));
    }
    app.main();
    // Up to a minute for a slow emulator: the welcome screen (its button is
    // further down, not built yet), or Today.
    final welcome = find.byType(WelcomeScreen);
    for (var i = 0; i < 60 && welcome.evaluate().isEmpty && find.text('Today').evaluate().isEmpty; i++) {
      await settle(1000);
    }
    await settle(2000);

    // Onboarding, once: a demo token reaches the demo account.
    if (welcome.evaluate().isNotEmpty) {
      await tapText('Add a Cloudflare API token');
      await tester.enterText(find.byType(EditableText).at(1), 'demo-token-not-real');
      await tester.tap(find.text('Verify and add'));
      await settle(5000);
      await tapText('Done');
      await settle(3000);
    }

    // One account on screen: the demo studio.
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp).first), listen: false);
    if (container.read(accountsProvider).length > 1) {
      await tapSection('Settings');
      await tapText('Studio Ember');
      await settle(2000);
      await tapText('Remove from Edgepost');
      await tester.tap(find.text('Remove').last);
      await settle(5000);
    }

    // Mail, set up once on two of its domains.
    await tapSection('Mail');
    if (find.text('Set up mailbox').evaluate().isNotEmpty) {
      await tapText('Set up mailbox');
      await tapText('atelier-nord.dev');
      await tapText('fieldnotes.blog');
      await tapText('Deploy and connect');
      await settle(8000);
      await tapText('Open inbox');
      await settle(3000);
    }
    // The alerts offer is for real use, not for the listing ("Not now" is
    // its close button's spoken label). It can appear a moment after the
    // inbox, so this runs again before the inbox shot.
    Future<void> dismissAlertsOffer() async {
      // A spoken label on iOS, a tooltip on Android.
      for (final notNow in [find.bySemanticsLabel('Not now'), find.byTooltip('Not now')]) {
        if (notNow.evaluate().isNotEmpty) {
          await tester.tap(notNow.first);
          await settle(800);
          return;
        }
      }
    }

    await dismissAlertsOffer();

    // The appearance this run shoots, whatever an earlier run left set.
    final appearance = container.read(appearanceProvider.notifier);
    await appearance.set(_dark ? Appearance.dark : Appearance.light);
    await settle(1500);

    await tapSection('Today');
    await settle(3000);
    await shot('01-today');

    await tapSection('Mail');
    await settle(3000);
    await dismissAlertsOffer();
    await shot('02-inbox');

    await tapText('Lena Varga');
    await settle(3000);
    await shot('03-thread');

    // Replying from the domain: its signature and logo already in place.
    final reply = find.bySemanticsLabel('Reply');
    await tester.tap(reply.evaluate().isNotEmpty ? reply.last : find.byTooltip('Reply').last);
    await settle(3000);
    // The body is compose's first multi-line field (in a sheet, the inbox
    // stays in the tree behind it).
    await tester.enterText(
      find
          .descendant(
            of: find.byType(ComposeScreen),
            matching: find.byWidgetPredicate((w) => w is EditableText && w.maxLines == null),
          )
          .first,
      'Paid this morning. Thanks for the smooth launch, talk Tuesday!',
    );
    // Keyboard down: the domain's signature and logo show under the text.
    FocusManager.instance.primaryFocus?.unfocus();
    await settle(1200);
    await shot('04-reply');
    await tester.tap(
      find.byWidgetPredicate((w) => (w is Text && w.data == 'Cancel') || (w is Tooltip && w.message == 'Cancel')).first,
    );
    await settle(1500);
    await tapText('Discard');
    await settle(1500);
    await back(); // the thread, on a phone

    // On a phone the list; in a split, the list with the domain open beside it.
    await tapSection('Domains');
    await settle(3000);
    final split = find.byType(EpSplitPlaceholder).evaluate().isNotEmpty;
    if (split) {
      await tapText('atelier-nord.dev');
      await settle(2500);
    }
    await shot('05-domains');

    if (!split) {
      await tapText('atelier-nord.dev');
      await settle(2500);
    }
    await tapText('DNS records');
    await settle(2500);
    await shot('06-dns');
    await back();

    await tapText('Traffic');
    await settle(3500);
    await shot('07-traffic');
    await back();

    await tapText('SSL, cache & security');
    await settle(2500);
    await shot('08-controls');
    await back();
    await back(); // the domain, on a phone

    await tapSection('Compute');
    await settle(3000);
    await shot('09-compute');

    // A domain's signature and logo, set once for every message.
    await tapSection('Settings');
    await tapText('Mail service');
    await settle(3000);
    await tapText('atelier-nord.dev');
    await settle(2500);
    await shot('10-signature');
    await back();
    await back();
    if (_dark) await appearance.set(Appearance.light);
    await settle(800);
  });
}
