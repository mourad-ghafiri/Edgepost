// End-to-end flow against the local fake API (tool/fake_cf_api/server.dart):
// onboarding → budget → every tab → zone tools → mail setup → read → reply →
// From sheet → sending health → a message arriving live (banner + badge) →
// a second account (avatar → + → token reaching both → choose) → its mail
// setup → long-press back → mail arriving in the other account (banner, dot,
// switcher counts, Open switches).
//
//   dart run tool/fake_cf_api/server.dart &
//   flutter drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/app_flow_test.dart -d <device> \
//     --dart-define=CF_API_BASE=http://127.0.0.1:8789/client/v4 \
//     --dart-define=MAIL_WORKER_URL=http://127.0.0.1:8789
//   (Android emulator: 10.0.2.2 instead of 127.0.0.1)
import 'dart:io';

import 'package:edgepost/core/adaptive/ep_widgets.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/features/accounts/account_button.dart';
import 'package:edgepost/main.dart' as app;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Edgepost end to end', (tester) async {
    Future<void> settle([int ms = 2500]) async {
      for (var t = 0; t < ms; t += 100) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    late final String prefix;
    var converted = false;
    Future<void> shot(String name) async {
      await settle(800);
      if (Platform.isAndroid && !converted) {
        await binding.convertFlutterSurfaceToImage();
        converted = true;
        await settle(300);
      }
      await binding.takeScreenshot('$prefix/$name');
    }

    Future<void> tapText(String text, {bool upper = false}) async {
      final f = find.text(upper ? text.toUpperCase() : text);
      // Lazily built lists: scroll until the target exists.
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(f, 400, scrollable: find.byType(Scrollable).first);
      }
      // Centre the target so it never sits under a translucent bar.
      final ctx = tester.element(f.first);
      if (Scrollable.maybeOf(ctx) != null) {
        await Scrollable.ensureVisible(ctx, alignment: 0.5);
        await settle(400);
      }
      await tester.tap(f.first, warnIfMissed: false);
      await settle();
    }

    /// A tab: the bar's label (the last match; a page can show the same word,
    /// e.g. Settings' "Mail" section on Android).
    Future<void> tapTab(String label) async {
      await tester.tap(find.text(label).last);
      await settle();
    }

    app.main();
    await settle(4000);
    // The app's own appearance (light by default), not the phone's.
    final dark = Theme.of(tester.element(find.byType(Navigator).first)).brightness == Brightness.dark;
    final large = tester.binding.platformDispatcher.textScaleFactor > 1.15;
    prefix = '${Platform.isIOS ? 'ios' : 'android'}-${dark ? 'dark' : 'light'}${large ? '-large' : ''}';

    // Onboarding (skipped when a token is already stored: the tab bar shows).
    // At large text the welcome button sits below the fold; tapText scrolls.
    if (find.text('Domains').evaluate().isEmpty) {
      await shot('00-welcome');
      await tapText('Add a Cloudflare API token');
      await tester.enterText(find.byType(EditableText).at(1), 'demo-token-not-real');
      await tester.tap(find.text('Verify and add'));
      await settle(5000);
      await shot('00b-token-added');
      await tapText('Done');
      await settle(3000);
    }

    // A previous run's second account goes first (this also covers
    // removing an account, the one on screen included).
    final avatar = find.byType(AccountButton);
    final container = ProviderScope.containerOf(tester.element(avatar.first), listen: false);
    String active() => container.read(activeAccountProvider)!.name;
    if (container.read(accountsProvider).length > 1) {
      await tapTab('Settings');
      await tapText('Studio Ember');
      await settle(2000);
      await tapText('Remove from Edgepost');
      await tester.tap(find.text('Remove').last);
      await settle(5000);
      await tapTab('Today');
    }
    expect(container.read(accountsProvider).map((a) => a.name), ['Atelier Nord']);

    await shot('01-today');
    // The Budget card (its title; a calm budget sits under a "BUDGET" header).
    for (var i = 0; i < 10 && find.text('Budget').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await settle(300);
    }
    final budgetStrip = find.text('Budget').last;
    await Scrollable.ensureVisible(tester.element(budgetStrip), alignment: 0.5);
    await settle(400);
    await tester.tap(budgetStrip);
    await settle(2500);
    await shot('01b-budget');
    await tester.pageBack();
    await settle();

    await tapText('Domains');
    await shot('02-domains');
    await tapText('atelier-nord.dev');
    await shot('03-zone-hub');
    for (final (label, name) in const [
      ('DNS records', '04-dns'),
      ('SSL, cache & security', '05-controls'),
      ('Traffic', '06-traffic'),
      ('Email routing', '07-email-routing'),
    ]) {
      await tapText(label);
      await settle(2500);
      await shot(name);
      if (label == 'DNS records') {
        // The type filter scrolls under a real drag (no programmatic
        // scrolling) to the types past the screen edge.
        await tester.drag(find.text('CNAME'), const Offset(-250, 0));
        await settle(800);
        await tester.tap(find.text('TXT'));
        await settle(800);
        await shot('04b-dns-filter');
      }
      await tester.pageBack();
      await settle();
    }

    await tapText('Compute');
    await shot('08-compute');

    await tapText('Mail');
    if (find.text('Set up mailbox').evaluate().isNotEmpty) {
      await shot('09-mail-empty');
      await tapText('Set up mailbox');
      await shot('10-mail-setup');
      await tapText('atelier-nord.dev');
      await tapText('fieldnotes.blog');
      await tapText('Deploy and connect');
      await settle(8000);
      await shot('11-mail-setup-done');
      await tapText('Open inbox');
    }
    await settle(3000);
    await shot('12-inbox');

    await tapText('Lena Varga');
    await settle(3000);
    await shot('13-thread');
    // The thread toolbar's Reply: a semantics label on iOS, a tooltip on Android.
    final reply = find.bySemanticsLabel('Reply');
    await tester.tap(reply.evaluate().isNotEmpty ? reply.last : find.byTooltip('Reply').last);
    await settle(3000);
    await shot('14-reply');
    final body = find.byWidgetPredicate((w) => w is EditableText && w.maxLines == null);
    await tester.enterText(body.first, 'Paid today. Thanks for the smooth launch!');
    await settle(500);
    await shot('15-reply-typed');
    final send = find.byWidgetPredicate(
      (w) => (w is Text && w.data == 'Send') || (w is Tooltip && w.message == 'Send'),
    );
    await tester.tap(send.first);
    await settle(3000);
    await shot('16-after-send');

    // New message (from the inbox): the From sheet.
    await tester.pageBack();
    await settle();
    final compose = find.bySemanticsLabel('New message');
    await tester.tap(compose.evaluate().isNotEmpty ? compose.last : find.text('New message').last);
    await settle(3000);
    await shot('16b-compose-new');
    // Recipient suggestions: the people written to most (above), then the
    // domain completed as it's typed.
    final toField = find.byType(EditableText).first;
    await tester.enterText(toField, 'jo@gm');
    await settle(800);
    await shot('16d-compose-suggest');
    expect(find.text('jo@gmail.com', findRichText: true), findsOneWidget);
    await tester.enterText(toField, '');
    await settle(500);
    await tester.tap(find.text('From').first);
    await settle(2500);
    await shot('16c-from-sheet');
    Navigator.of(tester.element(find.text('Send from'))).pop();
    await settle(1500);
    // iOS: "Cancel" text button; Android: close icon with a "Cancel" tooltip.
    await tester.tap(
      find.byWidgetPredicate((w) => (w is Text && w.data == 'Cancel') || (w is Tooltip && w.message == 'Cancel')).first,
    );
    await settle(1500);

    await tapTab('Settings');
    await shot('17-settings');
    // Appearance: dark on demand, then back to the default.
    await tapText('Dark');
    await settle(800);
    await shot('17b-appearance-dark');
    await tapText('Light');
    await settle(800);
    await tester.scrollUntilVisible(find.text('Mail service'), -300, scrollable: find.byType(Scrollable).first);
    await settle(400);
    await tapText('Mail service');
    await settle(3000);
    await tapText('Sending health');
    await settle(3000);
    await shot('19-health');
    await tester.pageBack();
    await settle();

    // A domain's signature (its logo is seeded by the fake API): set once,
    // on every message from the domain, editable per message.
    await tapText('atelier-nord.dev');
    await settle(2500);
    await shot('19b-domain-brand');
    await tester.enterText(find.byType(EditableText).first, 'Mourad Ghafiri\nAtelier Nord · atelier-nord.dev');
    await settle(800);
    await shot('19c-domain-brand-edited');
    await tapText('Save');
    await settle(2500);
    await tester.pageBack();
    await settle();

    await tapTab('Mail');
    final newMessage = find.bySemanticsLabel('New message');
    await tester.tap(newMessage.evaluate().isNotEmpty ? newMessage.last : find.text('New message').last);
    await settle(3000);
    await shot('19d-compose-signature');
    await tester.tap(
      find.byWidgetPredicate((w) => (w is Text && w.data == 'Cancel') || (w is Tooltip && w.message == 'Cancel')).first,
    );
    await settle(1500);

    // A message lands while the user is elsewhere: banner + Mail tab badge
    // within one fast tick (5 s).
    const worker = String.fromEnvironment('MAIL_WORKER_URL', defaultValue: 'http://127.0.0.1:8789');
    Future<void> arrive([String query = '']) async {
      final http = HttpClient();
      await (await http.postUrl(Uri.parse('$worker/_demo/arrive$query'))).close();
      http.close();
    }

    await arrive();
    await settle(7000);
    await shot('18-new-mail');

    // ---- A second account ----------------------------------------------
    await settle(5000); // the banner times out
    await shot('19b-single-account');

    await tester.tap(avatar.first);
    await settle(1500);
    await shot('20-switcher');
    await tester.tap(find.byWidgetPredicate((w) => w is EpIconButton && w.label == 'Add account'));
    await settle(2500);
    await shot('21-add-account');
    // The fake API: a token containing "agency" reaches both accounts.
    await tester.enterText(find.byType(EditableText).at(1), 'demo-agency-token');
    await tapText('Verify and add');
    await settle(3000);
    await shot('22-choose-accounts');
    await tapText('Add 1 account');
    await settle(6000);
    await shot('23-account-added');
    await tapText('Done');
    await settle(4000);
    expect(active(), 'Studio Ember');
    await tapTab('Today');
    await settle(2000);
    await shot('24-ember-today');

    await tapTab('Mail');
    if (find.text('Set up mailbox').evaluate().isNotEmpty) {
      await tapText('Set up mailbox');
      await shot('25-ember-mail-setup');
      await tapText('studio-ember.com');
      await tapText('Deploy and connect');
      await settle(8000);
      await tapText('Open inbox');
    }
    await settle(3000);
    await shot('26-ember-inbox');

    // Long-press: back to the account shown before.
    await tester.longPress(avatar.first);
    await settle(4000);
    expect(active(), 'Atelier Nord');
    await tapTab('Today');
    await settle(2000);
    await shot('27-back-to-nord');
    // The other account, waiting at the end of Today.
    await tester.scrollUntilVisible(find.text('OTHER ACCOUNTS'), 500, scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
    await settle(1000);
    await shot('31-other-accounts-bay');

    // Mail lands in the account not on screen: banner naming it, a dot on
    // the avatar, its count in the switcher; Open switches there.
    await arrive('?account=ember');
    final banner = find.textContaining('New mail in Studio Ember');
    for (var i = 0; i < 40 && banner.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await shot('28-other-account-banner');
    await tester.tap(find.text('Open').last);
    await settle(5000);
    expect(active(), 'Studio Ember');
    await shot('29-opened-in-ember');

    await tester.pageBack(); // the thread → the inbox, a tab root
    await settle();
    await tester.tap(avatar.first);
    await settle(1500);
    await shot('30-switcher-counts');
    Navigator.of(tester.element(find.text('Accounts').last)).pop();
    await settle(1500);

    // An account not on screen, in Settings.
    await tapTab('Settings');
    await tapText('Atelier Nord');
    await settle(2500);
    await shot('32-account-detail');
    await tester.scrollUntilVisible(find.text('Remove from Edgepost'), 500, scrollable: find.byType(Scrollable).first);
    await settle(800);
    await shot('32b-account-detail-end');
    await tester.pageBack();
    await settle();

    // Its mail Worker deleted in the Cloudflare dashboard: the app says so
    // within a sync and sets it up again.
    final http = HttpClient();
    await (await http.postUrl(Uri.parse('$worker/_demo/remove-mail?account=ember'))).close();
    http.close();
    await tapTab('Mail');
    final gone = find.text('Your mail service is gone');
    for (var i = 0; i < 60 && gone.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(gone, findsOneWidget);
    await shot('33-mail-service-gone');
    await tapText('Set up again');
    await settle(2500);
    await tapText('studio-ember.com');
    await tapText('Deploy and connect');
    await settle(8000);
    await tapText('Open inbox');
    await settle(3000);
    expect(gone, findsNothing);
    await shot('34-mail-set-up-again');
  });
}
