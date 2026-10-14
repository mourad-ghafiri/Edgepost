import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../storage/secure_store.dart';

/// How the app looks: light unless chosen otherwise in Settings; "system"
/// follows the phone's light or dark setting.
enum Appearance {
  light,
  dark,
  system;

  ThemeMode get themeMode => switch (this) {
    Appearance.light => ThemeMode.light,
    Appearance.dark => ThemeMode.dark,
    Appearance.system => ThemeMode.system,
  };
}

const _settingsKey = 'appearance';

Appearance _parse(Object? value) =>
    Appearance.values.firstWhere((a) => a.name == value, orElse: () => Appearance.light);

/// The stored choice, read before the first frame so a dark choice never
/// opens light first. Light when nothing is stored or the store can't be read.
Future<Appearance> readAppearance(SecureStore store) async {
  try {
    return _parse((await store.readSettings())[_settingsKey]);
  } on Object {
    return Appearance.light;
  }
}

/// What [readAppearance] found at launch (main overrides it).
final initialAppearanceProvider = Provider<Appearance>((ref) => Appearance.light);

final appearanceProvider = NotifierProvider<AppearanceSetting, Appearance>(AppearanceSetting.new);

class AppearanceSetting extends Notifier<Appearance> {
  @override
  Appearance build() => ref.watch(initialAppearanceProvider);

  /// Applies at once, then stores it with the app settings.
  Future<void> set(Appearance appearance) async {
    state = appearance;
    await ref.read(secureStoreProvider).updateSettings((s) => s[_settingsKey] = appearance.name);
  }
}
