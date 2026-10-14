import 'package:dio/dio.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/storage/secure_store.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/mail/data/mail_client.dart';
import 'package:edgepost/features/mail/data/mail_live.dart';
import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:edgepost/features/mail/data/mail_providers.dart';
import 'package:edgepost/features/mail/presentation/mail_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';

const _url = 'https://edgepost-mail.example.workers.dev';

MailClient _client(FakeCfAdapter api) => MailClient(
  baseUrl: _url,
  apiKey: 'k',
  accountId: testAccount.id,
  dio: Dio(BaseOptions(baseUrl: _url, validateStatus: (_) => true))..httpClientAdapter = api,
);

Matcher _code(String code) => isA<MailException>().having((e) => e.code, 'code', code);

final _service = MailService(
  accountId: testAccount.id,
  workerUrl: _url,
  apiKey: 'k',
  workerVersion: '1.0.0',
  domains: const ['atelier-nord.dev'],
  sendingDomains: const ['atelier-nord.dev'],
  d1Id: 'd1',
  r2Bucket: 'edgepost-mail',
);

/// The keychain, in memory.
class _MemSecure extends SecureStore {
  final Map<String, dynamic> settings = {};
  final Map<String, Map<String, dynamic>> services = {};
  @override
  Future<Map<String, dynamic>> readSettings() async => {...settings};
  @override
  Future<void> writeSettings(Map<String, dynamic> s) async => settings
    ..clear()
    ..addAll(s);
  @override
  Future<Map<String, dynamic>?> readMailService(String accountId) async => services[accountId];
  @override
  Future<void> writeMailService(String accountId, Map<String, dynamic> value) async => services[accountId] = value;
  @override
  Future<void> deleteMailService(String accountId) async => services.remove(accountId);
}

class _Services extends MailServicesNotifier {
  final forgotten = <String>[];
  @override
  Future<Map<String, MailService>> build() async => {_service.accountId: _service};
  @override
  Future<void> forget(String accountId) async {
    forgotten.add(accountId);
    state = AsyncData({...?state.value}..remove(accountId));
  }
}

void main() {
  group('a mail service deleted from Cloudflare', () {
    test("a 404 that isn't the Worker's own JSON says the service is gone", () async {
      final api = FakeCfAdapter()..on('GET', '/v1/mailboxes', (_) => const FakeReply(404, 'There is nothing here yet'));
      await expectLater(_client(api).mailboxes(), throwsA(_code('service_missing')));
    });

    test("the Worker's own 404 stays what it says", () async {
      final api = FakeCfAdapter()
        ..on(
          'GET',
          '/v1/mailboxes',
          (_) => const FakeReply(404, {
            'error': {'code': 'not_found', 'message': 'Nothing here'},
          }),
        );
      await expectLater(_client(api).mailboxes(), throwsA(_code('not_found')));
    });

    test('downloads see it too', () async {
      final gone = FakeCfAdapter()..on('GET', '/v1/attachments/a1', (_) => const FakeReply(404, 'Not found'));
      await expectLater(_client(gone).attachment('a1'), throwsA(_code('service_missing')));
      final here = FakeCfAdapter()
        ..on(
          'GET',
          '/v1/attachments/a1',
          (_) => const FakeReply(404, {
            'error': {'code': 'not_found', 'message': 'No such attachment'},
          }),
        );
      await expectLater(_client(here).attachment('a1'), throwsA(_code('http_404')));
    });
  });

  test("forgetting a service drops its cached mail and sync cursor, nothing else's", () async {
    final secure = _MemSecure()
      ..services[testAccount.id] = _service.toJson()
      ..settings['mail_sync_cursors'] = {testAccount.id: '120', otherAccount.id: '7'};
    final cache = MemoryCacheStore();
    await cache.write(testAccount.id, 'mail:list:inbox', [1]);
    await cache.write(testAccount.id, 'mail:contacts', [1]);
    await cache.write(testAccount.id, 'zones', [1]);
    await cache.write(otherAccount.id, 'mail:contacts', [1]);
    final container = ProviderContainer(
      overrides: [
        ...accountOverrides(),
        secureStoreProvider.overrideWithValue(secure),
        cacheStoreProvider.overrideWithValue(cache),
      ],
    );
    addTearDown(container.dispose);
    expect((await container.read(mailServicesProvider.future)).keys, [testAccount.id]);

    await container.read(mailServicesProvider.notifier).forget(testAccount.id);
    expect(container.read(mailServicesProvider).value, isEmpty);
    expect(secure.services, isEmpty);
    expect(cache.entries[testAccount.id]!.keys, ['zones']);
    expect(cache.entries[otherAccount.id]!.keys, ['mail:contacts']);
    expect(secure.settings['mail_sync_cursors'], {otherAccount.id: '7'});
  });

  test('deleted while the app is open: the next sync shows it in the inbox, once', () async {
    var deleted = false;
    FakeReply answer(FakeReply live) => deleted ? const FakeReply(404, 'There is nothing here yet') : live;
    final api = FakeCfAdapter()
      ..on(
        'GET',
        '/v1/sync',
        (_) => answer(
          const FakeReply(200, {
            'messages': <Object>[],
            'deleted': <Object>[],
            'cursor': '12',
            'sendUsage': {'used': 1, 'limit': 3000},
            'unread': {'total': 2},
          }),
        ),
      )
      ..on('GET', '/v1/messages', (_) => answer(const FakeReply(200, {'messages': <Object>[], 'nextCursor': null})));
    final services = _Services();
    final container = ProviderContainer(
      overrides: [
        ...accountOverrides(),
        mailServicesProvider.overrideWith(() => services),
        mailClientProvider.overrideWith((ref, id) => _client(api)),
        secureStoreProvider.overrideWithValue(_MemSecure()),
        cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
      ],
    );
    addTearDown(container.dispose);
    final key = (testAccount.id, const MailQuery());
    final sub = container.listen(mailListProvider(key), (_, _) {});
    addTearDown(sub.close);
    await container.read(mailServicesProvider.future);
    await container.read(mailListProvider(key).future);
    await container.read(mailLiveProvider.notifier).sync();
    expect(container.read(mailLiveProvider).unreadByAccount, {testAccount.id: 2});

    deleted = true;
    await container.read(mailLiveProvider.notifier).sync();
    expect(container.read(mailLiveProvider).unreadByAccount, isEmpty, reason: 'no stale badge');
    for (var i = 0; i < 10 && container.read(mailListProvider(key)).value?.refreshError == null; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    expect(isMailServiceMissing(container.read(mailListProvider(key)).value?.refreshError), isTrue);
  });

  testWidgets('"Set up again" forgets the gone service and opens setup', (tester) async {
    final services = _Services();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, s) => Scaffold(body: MailServiceMissing(accountId: testAccount.id)),
        ),
        GoRoute(
          path: '/mail/setup',
          builder: (c, s) => const Scaffold(body: Text('setup')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [...accountOverrides(), mailServicesProvider.overrideWith(() => services)],
        child: MaterialApp.router(
          theme: buildEpTheme(TargetPlatform.iOS, Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your mail service is gone'), findsOneWidget);
    await tester.tap(find.text('Set up again'));
    await tester.pumpAndSettle();
    expect(services.forgotten, [testAccount.id]);
    expect(find.text('setup'), findsOneWidget);
  });
}
