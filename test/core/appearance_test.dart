import 'package:edgepost/core/l10n.dart';
import 'package:edgepost/core/providers.dart';
import 'package:edgepost/core/storage/secure_store.dart';
import 'package:edgepost/core/theme/app_theme.dart';
import 'package:edgepost/core/theme/appearance.dart';
import 'package:edgepost/features/settings/presentation/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/accounts.dart';

/// The keychain's settings, in memory.
class _MemSecure extends SecureStore {
  _MemSecure([Map<String, dynamic>? initial]) : settings = {...?initial};
  final Map<String, dynamic> settings;
  @override
  Future<Map<String, dynamic>> readSettings() async => {...settings};
  @override
  Future<void> writeSettings(Map<String, dynamic> s) async => settings
    ..clear()
    ..addAll(s);
  @override
  Future<Map<String, dynamic>?> readMailService(String accountId) async => null;
}

class _Unreadable extends SecureStore {
  @override
  Future<Map<String, dynamic>> readSettings() async => throw StateError('keychain locked');
}

void main() {
  test('the stored choice is read at launch; nothing stored, or anything odd, is light', () async {
    expect(await readAppearance(_MemSecure()), Appearance.light);
    expect(await readAppearance(_MemSecure({'appearance': 'dark'})), Appearance.dark);
    expect(await readAppearance(_MemSecure({'appearance': 'system'})), Appearance.system);
    expect(await readAppearance(_MemSecure({'appearance': 'sepia'})), Appearance.light);
    expect(await readAppearance(_Unreadable()), Appearance.light);
  });

  testWidgets('light by default even when the phone is dark; Settings switches it and keeps the choice', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final secure = _MemSecure();
    await tester.pumpWidget(
      ProviderScope(
        retry: (_, _) => null,
        overrides: [...accountOverrides(), secureStoreProvider.overrideWithValue(secure)],
        // As the app root wires it.
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: buildEpTheme(TargetPlatform.iOS, Brightness.light),
            darkTheme: buildEpTheme(TargetPlatform.iOS, Brightness.dark),
            themeMode: ref.watch(appearanceProvider).themeMode,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Brightness shown() => Theme.of(tester.element(find.byType(SettingsScreen))).brightness;
    expect(shown(), Brightness.light, reason: 'the default, whatever the phone says');

    await tester.scrollUntilVisible(find.text('Dark'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(shown(), Brightness.dark);
    expect(secure.settings['appearance'], 'dark', reason: 'kept for the next launch');

    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    expect(shown(), Brightness.dark, reason: 'the phone is dark');
    expect(find.text("Follows your device's light or dark setting."), findsOneWidget);

    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect(shown(), Brightness.light);
    expect(secure.settings['appearance'], 'light');
  });
}
