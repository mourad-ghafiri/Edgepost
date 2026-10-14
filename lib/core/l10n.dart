import 'package:flutter/widgets.dart';

import '../l10n/gen/app_localizations.dart';

export '../l10n/gen/app_localizations.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// "just now", "4 min ago", "3 h ago", "yesterday"…
String relativeTime(BuildContext context, DateTime t, {DateTime? now}) {
  final l = context.l10n;
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inSeconds < 45) return l.timeJustNow;
  if (d.inMinutes < 60) return l.timeMinutesAgo(d.inMinutes < 1 ? 1 : d.inMinutes);
  if (d.inHours < 24) return l.timeHoursAgo(d.inHours);
  return l.timeDaysAgo(d.inDays);
}
