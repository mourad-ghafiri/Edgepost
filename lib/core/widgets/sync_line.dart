import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../providers.dart';
import '../theme/tokens.dart';

/// Live "Synced 4 s ago" under a title, ticking while visible, or
/// "Couldn't refresh…" when the last refresh failed (cached data stays).
class SyncLine extends StatefulWidget {
  const SyncLine({super.key, required this.synced});
  final Synced<Object?> synced;

  @override
  State<SyncLine> createState() => _SyncLineState();
}

class _SyncLineState extends State<SyncLine> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && TickerMode.valuesOf(context).enabled) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final s = widget.synced;
    final when = syncAge(context, s.syncedAt);
    if (s.refreshError != null) {
      return Text(l.syncFailed(when), style: TextStyle(color: c.caution));
    }
    return Text(l.syncedAt(when), style: EpType.numbers(const TextStyle()));
  }
}

/// "just now" under 5 s, then seconds, then the usual relative time.
String syncAge(BuildContext context, DateTime t) {
  final secs = DateTime.now().difference(t).inSeconds;
  if (secs < 5) return context.l10n.timeJustNow;
  if (secs < 60) return context.l10n.timeSecondsAgo(secs);
  return relativeTime(context, t);
}
