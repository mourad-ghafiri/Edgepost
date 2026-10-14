import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/storage/cache_store.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/core/theme/tokens.dart';
import 'package:edgepost/features/mail/data/mail_client.dart';
import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:edgepost/features/mail/data/mail_providers.dart';
import 'package:edgepost/features/mail/data/reply_builder.dart';
import 'package:edgepost/features/mail/presentation/compose_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';

final _service = MailService(
  accountId: testAccount.id,
  workerUrl: 'https://edgepost-mail.atelier.workers.dev',
  apiKey: 'k',
  workerVersion: '1.0.0',
  domains: const ['atelier-nord.dev'],
  sendingDomains: const ['atelier-nord.dev'],
  d1Id: 'd1',
  r2Bucket: 'edgepost-mail',
);

final _parentJson = <String, dynamic>{
  'id': 'm1',
  'threadId': 't1',
  'folder': 'inbox',
  'direction': 'in',
  'mailbox': 'hello@atelier-nord.dev',
  'domain': 'atelier-nord.dev',
  'from': {'name': 'Lena Varga', 'address': 'lena@varga.studio'},
  'to': [
    {'name': null, 'address': 'hello@atelier-nord.dev'},
  ],
  'cc': [
    {'name': 'Sam', 'address': 'sam@client.co'},
  ],
  'replyTo': <Object>[],
  'subject': 'Invoice 2026-118',
  'snippet': 'Please find the invoice attached.',
  'date': '2026-10-12T07:42:00Z',
  'receivedAt': '2026-10-12T07:42:03Z',
  'messageId': '<abc@varga.studio>',
  'inReplyTo': null,
  'references': <String>[],
  'read': true,
  'starred': false,
  'hasAttachments': false,
  'size': 2048,
  'text': 'Hi,\nPlease find the invoice attached.\nLena',
  'html': null,
  'attachments': <Object>[],
};

class _Services extends MailServicesNotifier {
  @override
  Future<Map<String, MailService>> build() async => {_service.accountId: _service};
}

class _Identities extends IdentitySettings {
  _Identities(super.accountId);

  @override
  Future<Map<String, Identity>> build() async => {
    'hello@atelier-nord.dev': const Identity('hello@atelier-nord.dev', name: 'Atelier Nord'),
  };
}

/// An in-memory picked file of [size] bytes.
final class _MemFile extends PlatformFile {
  _MemFile(this.name, int size) : _bytes = Uint8List(size);
  @override
  final String name;
  final Uint8List _bytes;
  @override
  Uri get uri => Uri.file('/tmp/$name');
  @override
  get xFile => throw UnimplementedError(); // unused by the compose screen
  @override
  int? lengthSync() => _bytes.length;
  @override
  Future<int?> length() async => _bytes.length;
  @override
  Future<Uint8List> readAsBytes() async => _bytes;
  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

Future<void> _pumpCompose(
  WidgetTester tester,
  TargetPlatform platform,
  FakeCfAdapter mailApi,
  ComposeMode mode, {
  List<PlatformFile> pick = const [],
}) async {
  debugDefaultTargetPlatformOverride = platform;
  if (!mailApi.routes.containsKey('GET /v1/brands')) {
    mailApi.on(
      'GET',
      '/v1/brands',
      (_) => const FakeReply(200, {
        'brands': [
          {'domain': 'atelier-nord.dev', 'signature': '', 'logo': null},
        ],
      }),
    );
  }
  if (!mailApi.routes.containsKey('GET /v1/contacts')) {
    mailApi.on('GET', '/v1/contacts', (_) => const FakeReply(200, {'contacts': <Object>[]}));
  }
  final dio = Dio(BaseOptions(baseUrl: _service.workerUrl, validateStatus: (_) => true))..httpClientAdapter = mailApi;
  final client = MailClient(baseUrl: _service.workerUrl, apiKey: 'k', accountId: testAccount.id, dio: dio);
  final parent = MessageDetail.fromJson(_parentJson, accountId: testAccount.id);
  final tmp = Directory.systemTemp.createTempSync('ek-compose');

  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: '/compose',
        builder: (c, s) => ComposeScreen(
          args: ComposeArgs(accountId: testAccount.id, mode: mode, parent: parent.summary),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        mailServicesProvider.overrideWith(_Services.new),
        identitySettingsProvider.overrideWith2(_Identities.new),
        mailboxesProvider.overrideWith(
          (ref, accountId) async => [
            Mailbox(
              address: 'hello@atelier-nord.dev',
              domain: 'atelier-nord.dev',
              unread: 0,
              total: 3,
              accountId: accountId,
            ),
          ],
        ),
        messageDetailProvider.overrideWith((ref, arg) async => parent),
        mailClientProvider.overrideWith((ref, accountId) => client),
        attachmentPickerProvider.overrideWithValue((_) async => pick),
        cacheStoreProvider.overrideWithValue(CacheStore(root: () async => tmp)),
      ],
      child: MaterialApp.router(
        theme: buildEpTheme(platform, Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/compose');
  await tester.pumpAndSettle();
}

/// What's typed in a recipient field, without the invisible character that
/// lets the keyboard's delete reach the chips.
String _typedIn(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(field).controller.text.replaceAll('\u200B', '');

/// iOS shows a "Send" text button in the nav bar; Android an icon with a tooltip.
Finder _send() =>
    find.byWidgetPredicate((w) => (w is Text && w.data == 'Send') || (w is Tooltip && w.message == 'Send'));

void main() {
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    group('Reply on ${platform.name}', () {
      testWidgets('prefills the reply and sends it threaded, from the receiving address', (tester) async {
        FakeCall? sent;
        final mailApi = FakeCfAdapter()
          ..on('POST', '/v1/send', (call) {
            sent = call;
            return FakeReply(200, {
              'message': {
                ..._parentJson,
                'id': 'm2',
                'direction': 'out',
                'folder': 'sent',
                'subject': 'Re: Invoice 2026-118',
              },
              'providerMessageId': '<x@cf>',
            });
          });
        await _pumpCompose(tester, platform, mailApi, ComposeMode.reply);

        expect(find.text('Lena Varga'), findsOneWidget, reason: 'recipient chip');
        expect(find.text('Re: Invoice 2026-118'), findsOneWidget);
        // The From row may break the address at "@" (zero-width space).
        expect(
          find.byWidgetPredicate(
            (w) => w is RichText && w.text.toPlainText().replaceAll('\u200B', '').contains('hello@atelier-nord.dev'),
          ),
          findsWidgets,
          reason: 'From = address it landed on',
        );

        // The message body (the signature below it is multiline too).
        final bodyField = find.byWidgetPredicate((w) => w is EditableText && w.maxLines == null).first;
        await tester.enterText(bodyField, 'Paid today, thanks!');
        await tester.pump();

        await tester.tap(_send());
        await tester.pumpAndSettle();

        expect(sent, isNotNull);
        final body = sent!.body as Map;
        expect(body['inReplyTo'], 'm1');
        expect((body['from'] as Map)['address'], 'hello@atelier-nord.dev');
        expect((body['from'] as Map)['name'], 'Atelier Nord');
        expect((body['to'] as List).single['address'], 'lena@varga.studio');
        expect(body['cc'], isEmpty, reason: 'plain Reply does not copy Cc');
        expect(body['subject'], 'Re: Invoice 2026-118');
        expect(body['text'], startsWith('Paid today, thanks!'));
        expect(body['text'], contains('> Please find the invoice attached.'));
        expect(find.text('home'), findsOneWidget, reason: 'closes after sending');
        await tester.pump(const Duration(seconds: 6)); // let the "Sent" banner expire
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('Reply all keeps the other recipients in Cc', (tester) async {
        FakeCall? sent;
        final mailApi = FakeCfAdapter()
          ..on('POST', '/v1/send', (call) {
            sent = call;
            return FakeReply(200, {
              'message': {..._parentJson, 'id': 'm3', 'direction': 'out', 'folder': 'sent'},
              'providerMessageId': '<y@cf>',
            });
          });
        await _pumpCompose(tester, platform, mailApi, ComposeMode.replyAll);
        await tester.tap(_send());
        await tester.pumpAndSettle();
        final body = sent!.body as Map;
        expect((body['cc'] as List).map((a) => a['address']), ['sam@client.co']);
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('a refused recipient explains Workers Paid / onboarding', (tester) async {
        final mailApi = FakeCfAdapter()
          ..on(
            'POST',
            '/v1/send',
            (_) => const FakeReply(403, {
              'error': {'code': 'recipient_not_allowed', 'message': 'nope', 'providerCode': 'E_RECIPIENT_NOT_ALLOWED'},
            }),
          );
        await _pumpCompose(tester, platform, mailApi, ComposeMode.reply);
        await tester.tap(_send());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('Workers Paid'), findsOneWidget);
        expect(find.text('home'), findsNothing, reason: 'stays open so nothing is lost');
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('a 3 MB file is attached and sent base64-encoded, with a client message id', (tester) async {
        FakeCall? sent;
        final mailApi = FakeCfAdapter()
          ..on('POST', '/v1/send', (call) {
            sent = call;
            return FakeReply(200, {
              'message': {..._parentJson, 'id': 'm4', 'direction': 'out', 'folder': 'sent'},
              'providerMessageId': '<z@cf>',
            });
          });
        await _pumpCompose(tester, platform, mailApi, ComposeMode.reply, pick: [_MemFile('plan.pdf', 3 * 1024 * 1024)]);

        await tester.scrollUntilVisible(find.text('Attach files'), 200, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Attach files'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('File'));
        await tester.pumpAndSettle();
        expect(find.textContaining('plan.pdf'), findsOneWidget, reason: 'attachment chip');
        expect(find.textContaining('of 5 MB as sent'), findsOneWidget, reason: 'size meter counts the encoded size');

        await tester.tap(_send());
        await tester.pumpAndSettle();
        final body = sent!.body as Map;
        final att = (body['attachments'] as List).single as Map;
        expect(att['filename'], 'plan.pdf');
        expect(att['mimeType'], 'application/pdf');
        expect(base64Decode(att['contentBase64'] as String).length, 3 * 1024 * 1024);
        expect(body['clientMessageId'], isA<String>().having((s) => s.length, 'length', greaterThanOrEqualTo(16)));
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('a 4 MB file is refused before it is read: it would be over 5 MB as sent', (tester) async {
        final mailApi = FakeCfAdapter();
        await _pumpCompose(
          tester,
          platform,
          mailApi,
          ComposeMode.reply,
          pick: [_MemFile('video.mov', 4 * 1024 * 1024)],
        );
        await tester.scrollUntilVisible(find.text('Attach files'), 200, scrollable: find.byType(Scrollable).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Attach files'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Photo or video'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.textContaining('video.mov is too big'), findsOneWidget);
        expect(mailApi.calls.where((c) => c.path == '/v1/send'), isEmpty, reason: 'nothing sent');
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets("the domain's signature and logo go with the reply; edits stay with this message", (tester) async {
        FakeCall? sent;
        final mailApi = FakeCfAdapter()
          ..on(
            'GET',
            '/v1/brands',
            (_) => const FakeReply(200, {
              'brands': [
                {
                  'domain': 'atelier-nord.dev',
                  'signature': 'Mourad\natelier-nord.dev',
                  'logo': {
                    'type': 'image/png',
                    'size': 1200,
                    'width': 480,
                    'height': 96,
                    'updatedAt': '2026-10-13T00:00:00Z',
                  },
                },
              ],
            }),
          )
          ..on('GET', '/v1/brands/atelier-nord.dev/logo', (_) => const FakeReply(200, 'png'))
          ..on('POST', '/v1/send', (call) {
            sent = call;
            return FakeReply(200, {
              'message': {..._parentJson, 'id': 'm5', 'direction': 'out', 'folder': 'sent'},
              'providerMessageId': '<s@cf>',
            });
          });
        await _pumpCompose(tester, platform, mailApi, ComposeMode.reply);

        final fields = find.byWidgetPredicate((w) => w is EditableText && w.maxLines == null);
        expect(
          tester.widget<EditableText>(fields.at(1)).controller.text,
          'Mourad\natelier-nord.dev',
          reason: 'prefilled',
        );
        await tester.enterText(fields.first, 'Paid today, thanks!');
        await tester.enterText(fields.at(1), 'Mourad, on the road');
        await tester.pump();

        await tester.tap(_send());
        await tester.pumpAndSettle();
        final body = sent!.body as Map;
        expect(body['text'], startsWith('Paid today, thanks!\n\n-- \nMourad, on the road\n\n'));
        expect(body['html'], contains('cid:logo@edgepost'));
        expect(body['brandLogo'], isTrue);
        expect(mailApi.calls.where((c) => c.method == 'PUT'), isEmpty, reason: "the domain's default is untouched");
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('a per-message edit says so and Reset brings the default back; a tap alone is no edit', (
        tester,
      ) async {
        final mailApi = FakeCfAdapter()
          ..on(
            'GET',
            '/v1/brands',
            (_) => const FakeReply(200, {
              'brands': [
                {'domain': 'atelier-nord.dev', 'signature': 'Mourad', 'logo': null},
              ],
            }),
          );
        await _pumpCompose(tester, platform, mailApi, ComposeMode.reply);
        final signature = find.byWidgetPredicate((w) => w is EditableText && w.maxLines == null).at(1);
        expect(find.text('Changes here are for this message only.'), findsOneWidget);

        await tester.tap(signature);
        await tester.pump();
        expect(find.text('Reset'), findsNothing, reason: 'placing the caret changes nothing');

        await tester.enterText(signature, 'Mourad, on the road');
        await tester.pump();
        expect(find.text('Changed for this message only.'), findsOneWidget);
        await tester.ensureVisible(find.text('Reset'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset'));
        await tester.pump();
        expect(tester.widget<EditableText>(signature).controller.text, 'Mourad');
        expect(find.text('Reset'), findsNothing);
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('the logo can be left out of one message', (tester) async {
        FakeCall? sent;
        final mailApi = FakeCfAdapter()
          ..on(
            'GET',
            '/v1/brands',
            (_) => const FakeReply(200, {
              'brands': [
                {
                  'domain': 'atelier-nord.dev',
                  'signature': '',
                  'logo': {
                    'type': 'image/png',
                    'size': 1200,
                    'width': 480,
                    'height': 96,
                    'updatedAt': '2026-10-13T00:00:00Z',
                  },
                },
              ],
            }),
          )
          ..on('GET', '/v1/brands/atelier-nord.dev/logo', (_) => const FakeReply(200, 'png'))
          ..on('POST', '/v1/send', (call) {
            sent = call;
            return FakeReply(200, {
              'message': {..._parentJson, 'id': 'm6', 'direction': 'out', 'folder': 'sent'},
              'providerMessageId': '<t@cf>',
            });
          });
        await _pumpCompose(tester, platform, mailApi, ComposeMode.reply);
        await tester.enterText(find.byWidgetPredicate((w) => w is EditableText && w.maxLines == null).first, 'Thanks');
        await tester.tap(find.byWidgetPredicate((w) => w is Switch || w is CupertinoSwitch).first);
        await tester.pump();
        await tester.tap(_send());
        await tester.pumpAndSettle();
        final body = sent!.body as Map;
        expect(body['brandLogo'], isFalse);
        expect('${body['html']}', isNot(contains('cid:')));
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('compose fields are rows, not boxes: no outline from the form theme', (tester) async {
        await _pumpCompose(tester, platform, FakeCfAdapter(), ComposeMode.forward);
        final decorators = tester.widgetList<InputDecorator>(find.byType(InputDecorator)).toList();
        expect(decorators, isNotEmpty);
        for (final d in decorators) {
          expect(
            (d.decoration.enabledBorder, d.decoration.focusedBorder, d.decoration.filled),
            (InputBorder.none, InputBorder.none, false),
          );
        }
        final subject = find.descendant(
          of: find.ancestor(of: find.text('Subject'), matching: find.byType(Row)).first,
          matching: find.byType(TextField),
        );
        expect(tester.getSize(subject).height, greaterThanOrEqualTo(48), reason: 'a full-height tap target');
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      }, skip: platform != TargetPlatform.android); // iOS fields are Cupertino

      testWidgets('typing on through "@" keeps the field focused while suggestions come and go', (tester) async {
        await _pumpCompose(tester, platform, FakeCfAdapter(), ComposeMode.forward);
        final to = find.byType(EditableText).first;
        await tester.enterText(to, 'zz');
        await tester.pump();
        // Keystrokes as the keyboard sends them: no tap that would refocus.
        for (final typed in ['zz@', 'zz@g', 'zz@gm', 'zz@gmail.com', 'zz@gmail.co']) {
          tester.testTextInput.updateEditingValue(
            TextEditingValue(
              text: typed,
              selection: TextSelection.collapsed(offset: typed.length),
            ),
          );
          await tester.pump();
          final field = tester.widget<EditableText>(to);
          expect(field.focusNode.hasFocus, isTrue, reason: 'still typing "$typed"');
          expect(field.controller.text, typed);
          expect(tester.testTextInput.isVisible, isTrue, reason: 'keyboard stays up at "$typed"');
        }
        expect(find.text('zz@gmail.com', findRichText: true), findsOneWidget, reason: 'still offered while typing');

        // Return: a whole address is kept as typed ("zz@gmail.co" is one);
        // a partial one takes the top suggestion.
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(text: 'jo@gm', selection: TextSelection.collapsed(offset: 5)),
        );
        await tester.pump();
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text('jo@gmail.com'), findsOneWidget, reason: 'now a chip');
        expect(_typedIn(tester, to), isEmpty);
        expect(tester.widget<EditableText>(to).focusNode.hasFocus, isTrue, reason: 'ready for the next one');
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('the keyboard delete selects the last recipient, then removes it; typing lets it go', (tester) async {
        await _pumpCompose(tester, platform, FakeCfAdapter(), ComposeMode.forward);
        final to = find.byType(EditableText).first;
        await tester.enterText(to, 'ann@example.com,');
        await tester.pump();
        await tester.enterText(to, 'bob@example.com,');
        await tester.pump();
        expect(find.text('ann@example.com'), findsOneWidget);
        expect(find.text('bob@example.com'), findsOneWidget);
        Color? inkOf(String chip) => tester.widget<Text>(find.text(chip)).style?.color;
        final c = EpColors.light;

        // A delete as a phone keyboard sends it, in the empty field.
        Future<void> delete() async {
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0)),
          );
          await tester.pump();
        }

        await delete();
        expect(inkOf('bob@example.com'), c.onTint, reason: 'selected first');
        expect(find.text('bob@example.com'), findsOneWidget);
        await delete();
        expect(find.text('bob@example.com'), findsNothing, reason: 'removed on the second delete');
        expect(find.text('ann@example.com'), findsOneWidget);

        await delete();
        expect(inkOf('ann@example.com'), c.onTint);
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(text: '\u200Bc', selection: TextSelection.collapsed(offset: 2)),
        );
        await tester.pump();
        expect(inkOf('ann@example.com'), c.ink, reason: 'typing lets it go');
        expect(_typedIn(tester, to), 'c');
        expect(tester.widget<EditableText>(to).focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('suggests people written to, completes domains and fixes a typo, one tap each', (tester) async {
        FakeCall? sent;
        final recent = DateTime.now().toUtc().subtract(const Duration(days: 1)).toIso8601String();
        final mailApi = FakeCfAdapter()
          ..on(
            'GET',
            '/v1/contacts',
            (_) => FakeReply(200, {
              'contacts': [
                {'address': 'lena.berg@gmail.com', 'name': 'Lena Berg', 'count': 3, 'lastSent': recent},
                {'address': 'helene.martin@orange.fr', 'name': 'Hélène Martin', 'count': 1, 'lastSent': recent},
              ],
            }),
          )
          ..on('POST', '/v1/send', (call) {
            sent = call;
            return FakeReply(200, {
              'message': {..._parentJson, 'id': 'm7', 'direction': 'out', 'folder': 'sent'},
              'providerMessageId': '<u@cf>',
            });
          });
        await _pumpCompose(tester, platform, mailApi, ComposeMode.forward);
        final to = find.byType(EditableText).first;

        // Empty and focused: the people written to most, one tap away.
        expect(find.text('Lena Berg'), findsOneWidget);
        await tester.tap(find.text('Lena Berg'));
        await tester.pumpAndSettle();
        expect(find.text('Lena Berg'), findsOneWidget, reason: 'now a recipient chip, no longer offered');
        expect(find.text('Hélène Martin'), findsOneWidget, reason: 'the next one offered');

        // A name, accents or not.
        await tester.enterText(to, 'hele');
        await tester.pumpAndSettle();
        expect(find.text('helene.martin@orange.fr'), findsOneWidget);
        await tester.tap(find.text('Hélène Martin'));
        await tester.pumpAndSettle();

        // The domain after "@", completed.
        await tester.enterText(to, 'jo@gm');
        await tester.pumpAndSettle();
        await tester.tap(find.text('jo@gmail.com', findRichText: true));
        await tester.pumpAndSettle();

        // A mistyped provider, offered fixed (never changed on its own).
        await tester.enterText(to, 'kim@gmial.com');
        await tester.pumpAndSettle();
        expect(find.text('Did you mean this? You typed gmial.com'), findsOneWidget);
        await tester.tap(find.text('kim@gmail.com'));
        await tester.pumpAndSettle();
        expect(_typedIn(tester, to), isEmpty);

        await tester.tap(_send());
        await tester.pumpAndSettle();
        final body = sent!.body as Map;
        expect((body['to'] as List).map((a) => (a as Map)['address']), [
          'lena.berg@gmail.com',
          'helene.martin@orange.fr',
          'jo@gmail.com',
          'kim@gmail.com',
        ]);
        expect(((body['to'] as List).first as Map)['name'], 'Lena Berg');
        await tester.pump(const Duration(seconds: 6));
        debugDefaultTargetPlatformOverride = null;
      });
    });
  }
}
