import 'package:edgepost/core/notify/alerts.dart';
import 'package:edgepost/core/storage/secure_store.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecureStore store;
  late List<(int, String, String)> shown;
  Future<void> sink(int id, String title, String body, String payload) async => shown.add((id, title, payload));
  List<String> titles() => [for (final s in shown) s.$2];

  Future<void> send(int used, {int limit = 3000, String account = 'a1'}) => Alerts.sendBudget(
        store: store,
        sink: sink,
        accountId: account,
        used: used,
        limit: limit,
        title80: '80 $account',
        body80: '',
        title100: '100 $account',
        body100: '',
      );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'settings': '{"budget_alerts":true,"delivery_alerts":true}'});
    store = SecureStore();
    shown = [];
  });

  test('sending budget alerts once at 80% and once at 100%, not on every refresh', () async {
    await send(1000);
    await send(2400);
    await send(2500);
    await send(2900);
    await send(3000);
    await send(3000);
    expect(titles(), ['80 a1', '100 a1']);
  });

  test('dropping back below 80% re-arms the alert', () async {
    await send(2500);
    await send(100);
    await send(2500);
    expect(titles(), ['80 a1', '80 a1']);
  });

  test('each account has its own levels, notification ids and route', () async {
    await send(2500);
    await send(2500, account: 'a2');
    await send(2600);
    expect(titles(), ['80 a1', '80 a2']);
    expect(shown[0].$1, isNot(shown[1].$1), reason: 'one account must not replace the other one\'s notification');
    expect(shown[0].$3, '/today/budget?account=a1');
    expect(shown[1].$3, '/today/budget?account=a2');
  });

  test('usage cost alerts once per billing period', () async {
    Future<void> cost(double c, String period) =>
        Alerts.usageCost(store: store, sink: sink, accountId: 'a1', cost: c, periodKey: period, title: 'cost $period', body: '');
    await cost(0, '2026-10');
    await cost(0.12, '2026-10');
    await cost(0.40, '2026-10');
    await cost(0.05, '2026-11');
    expect(titles(), ['cost 2026-10', 'cost 2026-11']);
  });

  test('delivery alerts per domain, once until it recovers', () async {
    Future<void> d(String domain, bool low) =>
        Alerts.delivery(store: store, sink: sink, accountId: 'a1', domain: domain, low: low, title: domain, body: '');
    await d('a.dev', true);
    await d('a.dev', true);
    await d('b.dev', true);
    await d('a.dev', false);
    await d('a.dev', true);
    expect(titles(), ['a.dev', 'b.dev', 'a.dev']);
    expect(shown.first.$3, '/mail/health?account=a1');
  });

  test('nothing is shown when the user turned the alerts off', () async {
    FlutterSecureStorage.setMockInitialValues({'settings': '{}'});
    store = SecureStore();
    await send(3000);
    expect(shown, isEmpty);
  });
}
