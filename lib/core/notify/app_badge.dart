import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Sets the iOS app icon badge (unread mail). Android launchers derive their
/// badge from active notifications, so this is iOS-only.
abstract final class AppBadge {
  static const _channel = MethodChannel('edgepost/badge');
  static int? _last;

  static Future<void> set(int count) async {
    if (defaultTargetPlatform != TargetPlatform.iOS || count == _last) return;
    _last = count;
    try {
      await _channel.invokeMethod<void>('set', count);
    } on Object {
      // No permission yet or running in a test: the badge simply stays as is.
    }
  }
}
