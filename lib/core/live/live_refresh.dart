import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// How often each kind of data refreshes while the app is on screen.
///
/// Cloudflare allows 1,200 API calls per 5 minutes per token (a 429 blocks the
/// token for 5 minutes) and 300 GraphQL queries per 5 minutes:
/// https://developers.cloudflare.com/fundamentals/api/reference/limits/ and
/// https://developers.cloudflare.com/analytics/graphql-api/limits/
enum LiveTier {
  /// Mail and the sending budget: one call to the user's own mail Worker.
  fast(Duration(seconds: 5)),

  /// Cloudflare lists: zones, DNS, Workers, Pages, routing.
  medium(Duration(seconds: 60)),

  /// Analytics and billing (Cloudflare aggregates these per minute/day).
  slow(Duration(minutes: 5));

  const LiveTier(this.interval);
  final Duration interval;
}

/// Increments once per tier interval while the app is in the foreground.
final liveTickProvider = NotifierProvider.family<LiveTick, int, LiveTier>(LiveTick.new);

class LiveTick extends Notifier<int> {
  LiveTick(this.tier);
  final LiveTier tier;

  @override
  int build() => 0;

  void tick() => state++;
}

/// Drives [liveTickProvider]: one 1-second clock, paused in the background,
/// stretched ×4 when a token's request budget runs low or Cloudflare sent a
/// 429. Resuming the app fires every tier at once so data is fresh on return.
class LiveRefreshScope extends ConsumerStatefulWidget {
  const LiveRefreshScope({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LiveRefreshScope> createState() => _LiveRefreshScopeState();
}

class _LiveRefreshScopeState extends ConsumerState<LiveRefreshScope> with WidgetsBindingObserver {
  Timer? _clock;
  final Map<LiveTier, int> _elapsed = {for (final t in LiveTier.values) t: 0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fireAll();
      _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _clock?.cancel();
      _clock = null;
    }
  }

  void _start() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _second());
  }

  void _fireAll() {
    for (final t in LiveTier.values) {
      _elapsed[t] = 0;
      ref.read(liveTickProvider(t).notifier).tick();
    }
  }

  void _second() {
    final factor = rateBudgetLow() ? 4 : 1;
    for (final t in LiveTier.values) {
      final due = t.interval.inSeconds * (t == LiveTier.fast ? 1 : factor);
      final e = (_elapsed[t] ?? 0) + 1;
      if (e >= due) {
        _elapsed[t] = 0;
        ref.read(liveTickProvider(t).notifier).tick();
      } else {
        _elapsed[t] = e;
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Refreshes on-screen data on a tier's tick. Offstage tabs (TickerMode off)
/// skip ticks, so only what the user is looking at polls Cloudflare.
class LivePoll extends ConsumerStatefulWidget {
  const LivePoll({super.key, required this.tier, required this.onTick, required this.child});

  final LiveTier tier;
  final void Function(WidgetRef ref) onTick;
  final Widget child;

  @override
  ConsumerState<LivePoll> createState() => _LivePollState();
}

class _LivePollState extends ConsumerState<LivePoll> {
  ProviderSubscription<int>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual(liveTickProvider(widget.tier), (_, _) {
      if (!mounted || !TickerMode.valuesOf(context).enabled) return;
      widget.onTick(ref);
    });
  }

  @override
  void dispose() {
    _sub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
