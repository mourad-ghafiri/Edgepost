import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/features/budget/data/billable_usage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';

ProviderContainer _container(List<Credential> tokens, FakeCfAdapter api) {
  final c = ProviderContainer(
    retry: (_, _) => null,
    overrides: [
      ...accountOverrides(tokens: tokens, accounts: const [testAccount, otherAccount]),
      cfClientProvider.overrideWith((ref, id) => fakeClient(api)),
      cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('records are summed per service; cost, currency and period come through', () async {
    final api = FakeCfAdapter()
      ..reply('GET', '/accounts/acc1/billable-usage', [
        {
          'ServiceName': 'Workers',
          'ConsumedQuantity': 1200000,
          'ConsumedUnit': 'requests',
          'BilledCost': 0,
          'BillingCurrency': 'USD',
          'BillingPeriodStart': '2026-10-01T00:00:00Z',
          'ChargePeriodStart': '2026-10-01T00:00:00Z',
          'ChargePeriodEnd': '2026-10-12T00:00:00Z',
        },
        {
          'ServiceName': 'Workers',
          'ConsumedQuantity': 300000,
          'ConsumedUnit': 'requests',
          'BilledCost': 0,
          'BillingCurrency': 'USD',
          'ChargePeriodStart': '2026-10-12T00:00:00Z',
          'ChargePeriodEnd': '2026-10-13T00:00:00Z',
        },
        {
          'ServiceName': 'Email Sending',
          'ConsumedQuantity': 4000,
          'ConsumedUnit': 'emails',
          'BilledCost': 0.35,
          'BillingCurrency': 'USD',
          'ChargePeriodStart': '2026-10-01T00:00:00Z',
          'ChargePeriodEnd': '2026-10-13T00:00:00Z',
        },
      ]);
    final u = await fetchAccountUsage(fakeClient(api), 'acc1');
    expect(u.services.map((s) => s.name), ['Email Sending', 'Workers'], reason: 'costliest first');
    expect(u.services.last.quantity, 1500000);
    expect(u.totalCost, closeTo(0.35, 1e-9));
    expect(u.currency, 'USD');
    expect(u.periodStart, DateTime.utc(2026, 10));
    expect(u.periodEnd, DateTime.utc(2026, 10, 13));
  });

  test('an empty period is zero cost, not an error', () async {
    final api = FakeCfAdapter()..reply('GET', '/accounts/acc1/billable-usage', <Object>[]);
    final u = await fetchAccountUsage(fakeClient(api), 'acc1');
    expect(u.services, isEmpty);
    expect(u.totalCost, 0);
  });

  test('cache round-trip keeps every field', () {
    const u = AccountUsage(
      services: [ServiceUsage(name: 'R2', quantity: 2, unit: 'GB-month', cost: 0.015, family: 'Storage')],
      currency: 'EUR',
    );
    final back = AccountUsage.fromJson(u.toJson());
    expect(back.services.single.family, 'Storage');
    expect(back.currency, 'EUR');
    expect(back.totalCost, 0.015);
  });

  group('billableUsageProvider', () {
    test('reads only the account it is for', () async {
      final api = FakeCfAdapter()
        ..reply('GET', '/accounts/a2/billable-usage', [
          {'ServiceName': 'R2', 'ConsumedQuantity': 2, 'ConsumedUnit': 'GB-month', 'BilledCost': 0.03, 'BillingCurrency': 'EUR'},
        ]);
      final c = _container([
        fakeToken(accounts: const [testAccount, otherAccount], caps: {Capability.billing: true}),
      ], api);
      final u = (await c.read(billableUsageProvider(otherAccount.id).future)).data;
      expect(u?.currency, 'EUR');
      expect(u?.totalCost, closeTo(0.03, 1e-9));
      expect(api.calls.map((x) => x.path), ['/accounts/a2/billable-usage']);
    });

    test('no token may read billing: null, and no call', () async {
      final api = FakeCfAdapter();
      final c = _container([fakeToken(caps: {Capability.billing: false})], api);
      expect((await c.read(billableUsageProvider(testAccount.id).future)).data, isNull);
      expect(api.calls, isEmpty);
    });
  });
}
