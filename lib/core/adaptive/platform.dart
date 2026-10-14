import 'package:flutter/material.dart';

/// True when the screen should speak the Cupertino idiom (iOS hardware or an
/// iOS platform override in tests).
bool isCupertino(BuildContext context) {
  final p = Theme.of(context).platform;
  return p == TargetPlatform.iOS || p == TargetPlatform.macOS;
}

/// True when motion should be replaced by crossfades or instant cuts
/// (iOS Reduce Motion, Android "Remove animations").
bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
