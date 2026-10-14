import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/adaptive/ep_page.dart';
import 'core/adaptive/popover.dart';
import 'core/storage/secure_store.dart';
import 'core/theme/appearance.dart';
import 'features/accounts/account_button.dart';
import 'features/mail/background/mail_sync_task.dart';

Future<void> main() async => runApp(await bootstrap());

/// Everything the app needs before its first frame, and its root widget (a
/// test can host it in a window of its own size).
Future<Widget> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  trackPopoverAnchors();
  // Inter's licence (SIL OFL 1.1) travels with the font: Settings → Licenses.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const ['Inter'], await rootBundle.loadString('assets/fonts/Inter-OFL.txt'));
  });
  MailSyncScheduler.initialize();
  final appearance = await readAppearance(SecureStore());
  return ProviderScope(
    // Riverpod 3 retries failed providers by default. API errors here are
    // mostly permanent (permissions, 4xx), and retrying burns the token's
    // request budget, so screens offer an explicit "Try again" instead.
    retry: (retryCount, error) => null,
    // The account avatar at the top right of every tab (core widgets don't
    // depend on features).
    overrides: [
      accountButtonProvider.overrideWithValue(const AccountButton()),
      initialAppearanceProvider.overrideWithValue(appearance),
    ],
    child: const EdgepostApp(),
  );
}
