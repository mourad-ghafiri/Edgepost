import 'dart:async';

import 'package:edgepost/features/mail/data/mail_client.dart';
import 'package:edgepost/features/mail/data/mail_live.dart';
import 'package:edgepost/features/mail/data/mail_models.dart';
import 'package:edgepost/features/mail/data/mail_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';

MailService _service(String accountId) => MailService(
      accountId: accountId,
      workerUrl: 'https://mail.$accountId.test',
      apiKey: 'key-$accountId',
      workerVersion: '1.0.0',
      domains: const [],
      sendingDomains: const [],
      d1Id: 'd1-$accountId',
      r2Bucket: 'r2-$accountId',
    );

/// The mail services as stored; [remove] takes one away (an account
/// removed from the app).
class _Services extends MailServicesNotifier {
  @override
  Future<Map<String, MailService>> build() async => {for (final a in [testAccount, otherAccount]) a.id: _service(a.id)};

  void remove(String accountId) => state = AsyncData({...?state.value}..remove(accountId));
}

/// Answers a sync once [gate] completes.
class _Client extends MailClient {
  _Client(String accountId, this.gate, this.unread) : super(baseUrl: 'https://mail.test', apiKey: 'k', accountId: accountId);
  final Future<void> gate;
  final int unread;
  var calls = 0;

  @override
  Future<SyncResult> sync({String? since}) async {
    calls++;
    await gate;
    return SyncResult(const [], const [], 'c$calls', sendUsage: const SendUsage(used: 0, limit: 3000), unreadTotal: unread);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an account removed while another one syncs is skipped, not an error', () async {
    FlutterSecureStorage.setMockInitialValues({'settings': '{}'});
    final gate = Completer<void>();
    final first = _Client(testAccount.id, gate.future, 2);
    final second = _Client(otherAccount.id, Future.value(), 5);
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        mailServicesProvider.overrideWith(_Services.new),
        mailClientProvider.overrideWith((ref, id) => id == testAccount.id ? first : second),
      ],
    );
    addTearDown(c.dispose);
    await c.read(mailServicesProvider.future);
    c.listen(mailLiveProvider, (_, _) {});

    final sync = c.read(mailLiveProvider.notifier).sync();
    await Future<void>.delayed(Duration.zero);
    // The first account is syncing; the second one goes meanwhile.
    (c.read(mailServicesProvider.notifier) as _Services).remove(otherAccount.id);
    gate.complete();
    await sync;

    expect(second.calls, 0);
    expect(c.read(mailLiveProvider).unreadByAccount, {testAccount.id: 2});
  });
}
