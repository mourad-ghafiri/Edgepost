import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/accounts/access.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../data/compute_api.dart';
import '../data/tail.dart';

/// Permission the tail endpoint needs
/// (https://developers.cloudflare.com/fundamentals/api/reference/permissions/).
const kWorkersTailPermission = 'Account · Workers Tail · Read';

/// Live `console.*` output and invocations of one Worker, streamed from a
/// tail session. Newest at the bottom; the tail is deleted when the screen
/// closes.
class WorkerLogsScreen extends ConsumerStatefulWidget {
  const WorkerLogsScreen({super.key, required this.script, this.connector});

  final String script;

  /// Test hook: replaces the WebSocket connection.
  final TailConnector? connector;

  @override
  ConsumerState<WorkerLogsScreen> createState() => _WorkerLogsScreenState();
}

class _WorkerLogsScreenState extends ConsumerState<WorkerLogsScreen> {
  final _scroll = ScrollController();
  TailController? _tail;
  int _seen = 0;
  bool _follow = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  /// Creates the session once a token that may tail this account's Workers
  /// is known.
  void _ensureTail() {
    if (_tail != null) return;
    final account = ref.read(activeAccountProvider)!.id;
    final access = ref.read(accessProvider).account(account, Capability.workers);
    if (access is! Granted) return;
    _tail = TailController(
      api: ComputeApi(ref.read(cfClientProvider(access.token.id))),
      accountId: account,
      script: widget.script,
      connector: widget.connector,
    )..addListener(_onTail);
    // After this frame: the controller notifies synchronously, and a rebuild
    // can't be requested while this widget is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tail?.start();
    });
  }

  @override
  void dispose() {
    _tail?.removeListener(_onTail);
    _tail?.dispose(); // closes the socket and deletes the tail
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    _follow = p.maxScrollExtent - p.pixels < 48;
  }

  void _onTail() {
    if (!mounted) return;
    final t = _tail!;
    final grew = t.events.length != _seen;
    _seen = t.events.length;
    setState(() {});
    if (grew && _follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        final end = _scroll.position.maxScrollExtent;
        if (reduceMotion(context)) {
          _scroll.jumpTo(end);
        } else {
          _scroll.animateTo(end, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final account = ref.watch(activeAccountProvider)!.id;
    final access = ref.watch(accessProvider).account(account, Capability.workers);
    _ensureTail();
    final t = _tail;
    if (t == null) {
      return EpPage(
        title: l.workersLogsTitle,
        largeTitle: false,
        slivers: [
          EpFill(
            child: EpErrorView(
              error: CfNoAccessException(Capability.workers.permission, access is NoAccess ? access.reason : NoAccessKind.noToken),
            ),
          ),
        ],
      );
    }
    final paused = t.status == TailStatus.paused;
    return EpPage(
      title: l.workersLogsTitle,
      largeTitle: false,
      previousPageTitle: widget.script,
      scrollController: _scroll,
      subtitle: Semantics(liveRegion: true, child: Text(_statusLine(context, t))),
      actions: [
        if (t.status == TailStatus.live || paused)
          EpAction(
            icon: paused ? EpIcon.play : EpIcon.pause,
            label: paused ? l.workersLogsResume : l.workersLogsPause,
            onPressed: paused ? t.resume : t.pause,
            badge: paused && t.heldCount > 0 ? '${t.heldCount}' : null,
          ),
        EpAction(icon: EpIcon.trash, label: l.workersLogsClear, onPressed: t.events.isEmpty ? null : t.clear),
      ],
      bottomBar: _ControlBar(tail: t),
      slivers: [
        if (t.status == TailStatus.failed && t.events.isEmpty)
          EpFill(
            child: EpErrorView(error: t.error ?? const CfNetworkException(), permission: kWorkersTailPermission, onRetry: t.start),
          )
        else if (t.events.isEmpty)
          EpFill(
            child: EpMessage(
              icon: EpIcon.logs,
              title: t.status == TailStatus.connecting ? l.workersLogsConnecting : l.workersLogsWaiting(widget.script),
              message: l.workersLogsWaitingHint,
            ),
          )
        else
          SliverList.builder(
            itemCount: t.events.length,
            itemBuilder: (context, i) => _EventBlock(event: t.events[i], first: i == 0),
          ),
      ],
    );
  }

  String _statusLine(BuildContext context, TailController t) {
    final l = context.l10n;
    return switch (t.status) {
      TailStatus.connecting => l.workersLogsConnecting,
      TailStatus.live => l.workersLogsLive(t.events.length),
      TailStatus.paused => l.workersLogsPaused(t.heldCount),
      TailStatus.ended => l.workersLogsEnded,
      TailStatus.stopped => l.workersLogsStopped,
      TailStatus.failed => l.workersLogsFailed,
    };
  }
}

class _ControlBar extends StatelessWidget {
  const _ControlBar({required this.tail});
  final TailController tail;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final active = tail.active;
    final message = switch (tail.status) {
      TailStatus.ended => l.workersLogsEndedHint,
      TailStatus.failed when tail.events.isNotEmpty =>
        describeError(context, tail.error ?? const CfNetworkException(), permission: kWorkersTailPermission),
      _ => null,
    };
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.hairline))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.sm, EpSpace.sm, EpSpace.sm),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  message ?? l.workersLogsPrivacy,
                  style: TextStyle(color: message != null ? c.caution : c.inkMuted, fontSize: 13, height: 1.3),
                ),
              ),
              const SizedBox(width: EpSpace.sm),
              active
                  ? EpButton(label: l.workersLogsStop, secondary: true, onPressed: tail.stop)
                  : EpButton(label: l.workersLogsReconnect, onPressed: tail.start),
            ],
          ),
        ),
      ),
    );
  }
}

String tailOutcomeLabel(BuildContext context, String outcome) {
  final l = context.l10n;
  return switch (outcome) {
    'ok' => l.workersOutcomeOk,
    'canceled' => l.workersOutcomeCanceled,
    'exception' => l.workersOutcomeException,
    'exceededCpu' => l.workersOutcomeCpu,
    'exceededMemory' => l.workersOutcomeMemory,
    _ => l.workersOutcomeUnknown,
  };
}

/// The one-line headline of an event (request line, cron, queue…).
String tailHeadline(BuildContext context, TailEvent e) {
  final l = context.l10n;
  return switch (e.kind) {
    TailEventKind.request =>
      '${e.method ?? 'GET'} ${e.url ?? l.workersLogsNoUrl}${e.status != null ? ' → ${e.status}' : ''}',
    TailEventKind.scheduled => l.workersLogsCron(e.cron ?? ''),
    TailEventKind.alarm => l.workersLogsAlarm,
    TailEventKind.email => l.workersLogsEmail(e.detail ?? ''),
    TailEventKind.queue => l.workersLogsQueue(e.detail ?? ''),
    TailEventKind.rpc => l.workersLogsRpc(e.detail ?? ''),
    TailEventKind.tail => l.workersLogsTailEvent(e.detail ?? ''),
    TailEventKind.info => switch (e.infoType) {
        'overload' => l.workersLogsOverload,
        'overload-stop' => l.workersLogsOverloadStop,
        _ => e.detail ?? '',
      },
    TailEventKind.unknown => l.workersLogsEvent,
  };
}

class _EventBlock extends StatelessWidget {
  const _EventBlock({required this.event, required this.first});
  final TailEvent event;
  final bool first;

  static final _time = DateFormat.Hms();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final e = event;
    final mono = EpType.data(context, size: 13);
    final time = e.timestamp == null ? '' : _time.format(e.timestamp!);
    final headline = tailHeadline(context, e);
    final isInfo = e.kind == TailEventKind.info;
    final outcomeBad = !isInfo && e.outcome != 'ok';
    final headColor = isInfo ? c.caution : (outcomeBad || (e.status ?? 0) >= 500 ? c.attention : c.ink);

    Color levelColor(TailLevel lv) => switch (lv) {
          TailLevel.error => c.attention,
          TailLevel.warn => c.caution,
          TailLevel.debug => c.inkMuted,
          _ => c.ink,
        };

    final lines = <Widget>[
      Text.rich(
        TextSpan(children: [
          if (time.isNotEmpty) TextSpan(text: '$time  ', style: TextStyle(color: c.inkMuted)),
          TextSpan(text: headline, style: TextStyle(color: headColor, fontWeight: FontWeight.w600)),
          if (outcomeBad) TextSpan(text: '  ${tailOutcomeLabel(context, e.outcome)}', style: TextStyle(color: c.attention)),
        ]),
        style: EpType.numbers(mono),
      ),
      for (final log in e.logs)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: EpSpace.md),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: '${log.level.name.toUpperCase().padRight(5)} ', style: TextStyle(color: levelColor(log.level))),
              TextSpan(text: log.message, style: TextStyle(color: levelColor(log.level))),
            ]),
            style: mono,
          ),
        ),
      for (final x in e.exceptions)
        Padding(
          padding: const EdgeInsets.only(top: 2, left: EpSpace.md),
          child: Text('${x.name}: ${x.message}', style: mono.copyWith(color: c.attention)),
        ),
    ];

    final plain = [
      '$time $headline',
      for (final log in e.logs) '${log.level.name}: ${log.message}',
      for (final x in e.exceptions) '${x.name}: ${x.message}',
    ].join('\n');

    return MergeSemantics(
      child: Semantics(
        label: [
          headline,
          if (outcomeBad) tailOutcomeLabel(context, e.outcome),
          if (e.logs.isNotEmpty) l.workersLogsLines(e.logs.length),
          if (e.exceptions.isNotEmpty) l.workersLogsExceptions(e.exceptions.length),
        ].join(', '),
        onLongPressHint: l.actionCopy,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => copyWithToast(context, plain),
          child: Container(
            decoration: BoxDecoration(
              border: first ? null : Border(top: BorderSide(color: c.hairline, width: 0.5)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg, vertical: EpSpace.sm),
            child: ExcludeSemantics(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines),
            ),
          ),
        ),
      ),
    );
  }
}
