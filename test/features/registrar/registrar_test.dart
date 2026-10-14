import 'package:edgepost/core/accounts/credential.dart';
import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/features/registrar/data/registrar_models.dart';
import 'package:edgepost/features/registrar/presentation/registrar_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/accounts.dart';
import '../../support/fake_cf.dart';
import '../../support/memory_cache.dart';

/// A registration in the shape of the official API reference
/// (https://developers.cloudflare.com/api/resources/registrar/subresources/domains/).
Map<String, dynamic> registrationJson(
  String domain, {
  required String expires,
  bool autoRenew = false,
  String status = 'active',
}) => {
  'domain_name': domain,
  'status': status,
  'created_at': '2025-10-27T10:00:00Z',
  'expires_at': expires,
  'auto_renew': autoRenew,
  'privacy_mode': 'redaction',
  'locked': true,
};

void main() {
  final now = DateTime.utc(2026, 10, 12, 9);

  RegistrarDomainInfo parse(Map<String, dynamic> j) => RegistrarDomainInfo.fromJson(j);

  group('RegistrarDomainInfo', () {
    test('parses a registration', () {
      final d = parse(registrationJson('acmecorp.dev', expires: '2026-10-27T10:00:00Z'));
      expect(d.name, 'acmecorp.dev');
      expect(d.expiresAt, DateTime.utc(2026, 10, 27, 10));
      expect(d.autoRenew, isFalse);
      expect(d.locked, isTrue);
      expect(d.status, RegistrationStatus.active);
      expect(d.privacyMode, 'redaction');
      expect(d.daysLeft(now: now), 15);
      final back = RegistrarDomainInfo.fromJson(d.toJson());
      expect(back.name, d.name);
      expect(back.expiresAt, d.expiresAt);
      expect(back.status, d.status);
    });

    test('attention: < 30 days without auto-renew, or a losing status', () {
      expect(parse(registrationJson('a.dev', expires: '2026-10-27T10:00:00Z')).needsAttention(now: now), isTrue);
      expect(
        parse(registrationJson('b.dev', expires: '2026-10-27T10:00:00Z', autoRenew: true)).needsAttention(now: now),
        isFalse,
      );
      expect(parse(registrationJson('c.dev', expires: '2027-06-01T00:00:00Z')).needsAttention(now: now), isFalse);
      expect(
        parse(
          registrationJson('d.dev', expires: '2027-06-01T00:00:00Z', autoRenew: true, status: 'redemption_period'),
        ).needsAttention(now: now),
        isTrue,
      );
      final pending = parse({
        'domain_name': 'e.dev',
        'status': 'transfer_pending',
        'expires_at': null,
        'auto_renew': false,
      });
      expect(pending.expiresAt, isNull);
      expect(pending.needsAttention(now: now), isFalse);
    });
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('Registrar screen explains account-owned tokens (${platform.name})', (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        final api = FakeCfAdapter()..reply('GET', '/accounts/${testAccount.id}/workers/scripts', <Object>[]);
        await tester.pumpWidget(
          ProviderScope(
            retry: (_, _) => null,
            overrides: [
              ...accountOverrides(tokens: [
                fakeToken(id: 'acct', kind: TokenKind.account, caps: {Capability.workers: true, Capability.pages: false}),
              ]),
              cfClientProvider.overrideWith((ref, id) => fakeClient(api)),
              cacheStoreProvider.overrideWithValue(MemoryCacheStore()),
            ],
            child: MaterialApp(
              theme: buildEpTheme(platform, Brightness.light),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const RegistrarScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Registrar needs a user API token'), findsOneWidget);
        expect(find.textContaining('account-owned API tokens'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
