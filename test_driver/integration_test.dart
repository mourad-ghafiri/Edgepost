import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Saves screenshots from integration_test/app_flow_test.dart under
/// `.impeccable/review/<platform>-<theme>/` for the design review.
Future<void> main() => integrationDriver(
      onScreenshot: (name, bytes, [args]) async {
        final file = File('.impeccable/review/$name.png');
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
        return true;
      },
    );
