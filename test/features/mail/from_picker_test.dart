import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:edgepost/features/mail/data/mail_providers.dart';
import 'package:edgepost/features/mail/presentation/from_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';

MailService _service(String accountId, List<String> domains) => MailService(
      accountId: accountId,
      workerUrl: 'https://mail-$accountId.example.workers.dev',
      apiKey: 'k',
      workerVersion: '1.0.0',
      domains: domains,
      sendingDomains: domains,
      d1Id: 'd1-$accountId',
      r2Bucket: 'edgepost-mail',
    );

/// Two accounts with mail: the picker opens for the first only.
class _Services extends MailServicesNotifier {
  @override
  Future<Map<String, MailService>> build() async => {
        testAccount.id: _service(testAccount.id, ['atelier-nord.dev', 'brume.studio']),
        otherAccount.id: _service(otherAccount.id, ['ember.works']),
      };
}

class _Identities extends IdentitySettings {
  _Identities(super.accountId);

  @override
  Future<Map<String, Identity>> build() async => accountId == testAccount.id
      ? {'billing@atelier-nord.dev': const Identity('billing@atelier-nord.dev', name: 'Billing desk')}
      : {'hi@ember.works': const Identity('hi@ember.works', name: 'Ember front desk')};
}

/// An address row, by its spoken label (rows under a domain header show only
/// the local part on screen).
Finder _address(String a) =>
    find.byWidgetPredicate((w) => w is Semantics && (w.properties.label == a || (w.properties.label?.endsWith('<$a>') ?? false)));

Future<MailAddress? Function()> _open(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  MailAddress? picked;
  await tester.pumpWidget(ProviderScope(
    retry: (_, _) => null,
    overrides: [
      mailServicesProvider.overrideWith(_Services.new),
      identitySettingsProvider.overrideWith2(_Identities.new),
      mailboxesProvider.overrideWith((ref, accountId) async => accountId == testAccount.id
          ? [
              Mailbox(address: 'billing@atelier-nord.dev', domain: 'atelier-nord.dev', unread: 0, total: 3, accountId: accountId),
              Mailbox(address: 'hello@brume.studio', domain: 'brume.studio', unread: 1, total: 9, accountId: accountId),
            ]
          : [Mailbox(address: 'hi@ember.works', domain: 'ember.works', unread: 2, total: 4, accountId: accountId)]),
    ],
    child: MaterialApp(
      theme: buildEpTheme(platform, Brightness.light),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => picked = await showFromPicker(context, accountId: testAccount.id, current: const MailAddress('hello@brume.studio')),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => picked;
}

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group('From picker on ${platform.name}', () {
      testWidgets('current domain comes first, contact@ heads each domain, names show', (tester) async {
        await _open(tester, platform);
        final contactBrume = tester.getTopLeft(_address('contact@brume.studio')).dy;
        final hello = tester.getTopLeft(_address('hello@brume.studio')).dy;
        final contactNord = tester.getTopLeft(_address('contact@atelier-nord.dev')).dy;
        expect(contactBrume, lessThan(hello));
        expect(hello, lessThan(contactNord), reason: 'the domain being written from is listed first');
        expect(find.text('Billing desk'), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets("lists only the account's own domains and addresses", (tester) async {
        await _open(tester, platform);
        expect(_address('contact@brume.studio'), findsOneWidget);
        expect(_address('contact@ember.works'), findsNothing, reason: 'another account sends through its own service');
        expect(_address('hi@ember.works'), findsNothing);
        expect(find.text('Ember front desk'), findsNothing);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('search narrows by address or name; a typed full address can be used directly', (tester) async {
        final picked = await _open(tester, platform);
        await tester.enterText(find.byType(EditableText).first, 'desk');
        await tester.pumpAndSettle();
        expect(_address('billing@atelier-nord.dev'), findsOneWidget);
        expect(_address('contact@brume.studio'), findsNothing);

        await tester.enterText(find.byType(EditableText).first, 'sales@atelier-nord.dev');
        await tester.pumpAndSettle();
        // The offered row comes after the search field holding the same text.
        await tester.tap(find.text('sales@atelier-nord.dev').last);
        await tester.pumpAndSettle();
        expect(picked()?.address, 'sales@atelier-nord.dev');
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('another address validates the local part before it can be used', (tester) async {
        final picked = await _open(tester, platform);
        await tester.tap(find.text('Another address').first);
        await tester.pumpAndSettle();
        final field = find.byType(EditableText).last;
        await tester.enterText(field, 'Not valid!');
        await tester.pumpAndSettle();
        expect(find.text('Use letters, numbers, dots, dashes or underscores.'), findsOneWidget);
        await tester.enterText(field, 'press');
        await tester.pumpAndSettle();
        await tester.tap(find.text('Use this address'));
        await tester.pumpAndSettle();
        expect(picked()?.address, 'press@brume.studio');
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }
}
