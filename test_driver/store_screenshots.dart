import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves the captures of integration_test/store_screenshots_test.dart under
/// `build/screenshots/raw/<device>/` for tool/store_screenshots.py.
Future<void> main() => integrationDriver(
  onScreenshot: (name, bytes, [args]) async {
    final file = File('build/screenshots/raw/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    return true;
  },
);
