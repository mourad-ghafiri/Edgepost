import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

import '../../../core/cloudflare/cf_errors.dart';
import 'compute_api.dart';

/// WebSocket subprotocol the tail endpoint accepts, as used by wrangler
/// (`TRACE_VERSION` in packages/wrangler/src/tail/createTail.ts,
/// https://github.com/cloudflare/workers-sdk).
const String kTailProtocol = 'trace-v1';

enum TailLevel { debug, info, log, warn, error }

TailLevel _level(Object? v) => switch (v) {
      'debug' => TailLevel.debug,
      'info' => TailLevel.info,
      'warn' => TailLevel.warn,
      'error' => TailLevel.error,
      _ => TailLevel.log,
    };

/// `console.*` output captured during one invocation.
class TailLog {
  const TailLog({required this.level, required this.message, this.timestamp});
  final TailLevel level;
  final String message;
  final DateTime? timestamp;
}

class TailException {
  const TailException({required this.name, required this.message, this.timestamp});
  final String name;
  final String message;
  final DateTime? timestamp;
}

enum TailEventKind { request, scheduled, alarm, email, queue, rpc, tail, info, unknown }

/// One trace message from the tail socket: an invocation with its logs and
/// exceptions, or (kind [TailEventKind.info]) a note about the tail itself.
/// Shape: wrangler's `TailEventMessage` and the Tail Workers `TailItem`
/// (https://developers.cloudflare.com/workers/runtime-apis/handlers/tail/).
class TailEvent {
  const TailEvent({
    required this.kind,
    required this.outcome,
    this.timestamp,
    this.scriptName,
    this.method,
    this.url,
    this.status,
    this.cron,
    this.detail,
    this.infoType,
    this.logs = const [],
    this.exceptions = const [],
  });

  final TailEventKind kind;

  /// ok · canceled · exception · exceededCpu · exceededMemory · unknown
  final String outcome;
  final DateTime? timestamp;
  final String? scriptName;
  final String? method;
  final String? url;
  final int? status;
  final String? cron;

  /// Event-specific summary (queue name, email route, RPC method, info text).
  final String? detail;

  /// For [TailEventKind.info]: `overload`, `overload-stop`…
  final String? infoType;
  final List<TailLog> logs;
  final List<TailException> exceptions;

  bool get failed => outcome != 'ok' || exceptions.isNotEmpty;

  /// Parses one socket frame (text or UTF-8 bytes). Returns null for frames
  /// that aren't trace messages.
  static TailEvent? parse(Object? frame) {
    final Object? decoded;
    try {
      final text = frame is String ? frame : (frame is List<int> ? utf8.decode(frame, allowMalformed: true) : null);
      if (text == null) return null;
      decoded = jsonDecode(text);
    } on FormatException {
      return null;
    }
    return decoded is Map<String, dynamic> ? fromJson(decoded) : null;
  }

  static TailEvent fromJson(Map<String, dynamic> j) {
    final event = j['event'] is Map<String, dynamic> ? j['event'] as Map<String, dynamic> : null;
    var kind = TailEventKind.unknown;
    String? method, url, cron, detail, infoType;
    int? status;
    if (event != null) {
      final request = event['request'];
      if (request is Map<String, dynamic>) {
        kind = TailEventKind.request;
        method = (request['method'] as String?)?.toUpperCase();
        url = request['url'] as String?;
        final response = event['response'];
        if (response is Map<String, dynamic>) status = (response['status'] as num?)?.toInt();
      } else if (event['cron'] is String) {
        kind = TailEventKind.scheduled;
        cron = event['cron'] as String;
      } else if (event['mailFrom'] is String) {
        kind = TailEventKind.email;
        detail = '${event['mailFrom']} → ${event['rcptTo'] ?? ''}';
      } else if (event['queue'] is String) {
        kind = TailEventKind.queue;
        detail = '${event['queue']} (${event['batchSize'] ?? 0})';
      } else if (event['rpcMethod'] is String) {
        kind = TailEventKind.rpc;
        detail = event['rpcMethod'] as String;
      } else if (event['consumedEvents'] is List) {
        kind = TailEventKind.tail;
        detail = (event['consumedEvents'] as List)
            .whereType<Map<String, dynamic>>()
            .map((e) => '${e['scriptName'] ?? ''}')
            .where((s) => s.isNotEmpty)
            .join(', ');
      } else if (event['type'] is String && event['message'] is String) {
        kind = TailEventKind.info;
        infoType = event['type'] as String;
        detail = event['message'] as String;
      } else if (event['scheduledTime'] != null) {
        kind = TailEventKind.alarm;
      }
    }
    return TailEvent(
      kind: kind,
      outcome: '${j['outcome'] ?? 'unknown'}',
      timestamp: _ms(j['eventTimestamp']),
      scriptName: j['scriptName'] as String?,
      method: method,
      url: url,
      status: status,
      cron: cron,
      detail: detail,
      infoType: infoType,
      logs: [
        for (final l in (j['logs'] as List? ?? const []).whereType<Map<String, dynamic>>())
          TailLog(level: _level(l['level']), message: _message(l['message']), timestamp: _ms(l['timestamp'])),
      ],
      exceptions: [
        for (final e in (j['exceptions'] as List? ?? const []).whereType<Map<String, dynamic>>())
          TailException(
            name: '${e['name'] ?? 'Error'}',
            message: _message(e['message']),
            timestamp: _ms(e['timestamp']),
          ),
      ],
    );
  }

  static DateTime? _ms(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true).toLocal() : null;

  /// `console.log("a", {b: 1})` arrives as `["a", {"b": 1}]`.
  static String _message(Object? v) {
    if (v is String) return v;
    if (v is List) return v.map((e) => e is String ? e : jsonEncode(e)).join(' ');
    if (v == null) return '';
    return jsonEncode(v);
  }
}

/// The socket half of a tail, abstracted so tests can drive it.
abstract class TailSocket {
  Future<void> get ready;
  Stream<Object?> get stream;
  void send(String message);
  Future<void> close();
}

class _ChannelSocket implements TailSocket {
  _ChannelSocket(this._channel);
  final IOWebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;
  @override
  Stream<Object?> get stream => _channel.stream;
  @override
  void send(String message) => _channel.sink.add(message);
  @override
  Future<void> close() => _channel.sink.close();
}

typedef TailConnector = TailSocket Function(Uri url);

/// Connects with the `trace-v1` subprotocol. No Authorization header: the
/// tail URL itself carries the access grant.
TailSocket connectTailSocket(Uri url) => _ChannelSocket(
      IOWebSocketChannel.connect(url, protocols: const [kTailProtocol], connectTimeout: const Duration(seconds: 15)),
    );

enum TailStatus { connecting, live, paused, ended, stopped, failed }

/// Drives one live-log session: create the tail, stream events, pause,
/// clear, stop, and always clean up the tail on Cloudflare.
class TailController extends ChangeNotifier {
  TailController({
    required this.api,
    required this.accountId,
    required this.script,
    TailConnector? connector,
    this.maxEvents = 500,
  }) : _connect = connector ?? connectTailSocket;

  final ComputeApi api;
  final String accountId;
  final String script;
  final int maxEvents;
  final TailConnector _connect;

  final List<TailEvent> events = [];
  final List<TailEvent> _held = [];
  TailStatus status = TailStatus.stopped;
  Object? error;
  DateTime? expiresAt;

  /// Events received while paused, shown as a count until resumed.
  int get heldCount => _held.length;

  TailHandle? _handle;
  TailSocket? _socket;
  StreamSubscription<Object?>? _sub;
  bool _disposed = false;
  int _session = 0;

  bool get active => status == TailStatus.connecting || status == TailStatus.live || status == TailStatus.paused;

  Future<void> start() async {
    if (_disposed) return;
    await _teardown();
    final session = ++_session;
    _set(TailStatus.connecting);
    error = null;
    try {
      final handle = await api.startTail(accountId, script);
      if (_stale(session)) {
        unawaited(_deleteTail(handle));
        return;
      }
      _handle = handle;
      expiresAt = handle.expiresAt;
      final socket = _connect(Uri.parse(handle.url));
      _socket = socket;
      _sub = socket.stream.listen(
        (frame) => _onFrame(session, frame),
        onError: (Object e) => _onClosed(session, e),
        onDone: () => _onClosed(session, null),
        cancelOnError: true,
      );
      await socket.ready;
      if (_stale(session)) return;
      // Same opening message wrangler sends once the socket is open.
      socket.send(jsonEncode({'debug': false}));
      _set(TailStatus.live);
    } on CfException catch (e) {
      if (_stale(session)) return;
      error = e;
      await _teardown();
      _set(TailStatus.failed);
    } on Object catch (e) {
      if (_stale(session)) return;
      error = e;
      await _teardown();
      _set(TailStatus.failed);
    }
  }

  void pause() {
    if (status == TailStatus.live) _set(TailStatus.paused);
  }

  void resume() {
    if (status != TailStatus.paused) return;
    _append(_held);
    _held.clear();
    _set(TailStatus.live);
  }

  void clear() {
    events.clear();
    _held.clear();
    if (!_disposed) notifyListeners();
  }

  /// Ends the session and deletes the tail.
  Future<void> stop() async {
    _session++;
    await _teardown();
    _set(TailStatus.stopped);
  }

  bool _stale(int session) => _disposed || session != _session;

  void _onFrame(int session, Object? frame) {
    if (_stale(session)) return;
    final e = TailEvent.parse(frame);
    if (e == null) return;
    if (status == TailStatus.paused) {
      _held.add(e);
      if (_held.length > maxEvents) _held.removeAt(0);
      notifyListeners();
      return;
    }
    _append([e]);
    notifyListeners();
  }

  void _append(List<TailEvent> list) {
    events.addAll(list);
    final over = events.length - maxEvents;
    if (over > 0) events.removeRange(0, over);
  }

  void _onClosed(int session, Object? e) {
    if (_stale(session)) return;
    error = e;
    final handle = _handle;
    _handle = null;
    _sub = null;
    _socket = null;
    if (handle != null) unawaited(_deleteTail(handle));
    _set(TailStatus.ended);
  }

  Future<void> _teardown() async {
    final sub = _sub, socket = _socket, handle = _handle;
    _sub = null;
    _socket = null;
    _handle = null;
    // Started together so the socket closes and the tail is deleted right
    // away, even if the subscription is slow to cancel.
    await Future.wait<void>([
      ?sub?.cancel(),
      if (socket != null) _closeQuietly(socket),
      if (handle != null) _deleteTail(handle),
    ]);
  }

  static Future<void> _closeQuietly(TailSocket socket) async {
    try {
      await socket.close();
    } on Object {
      // Closing an already-dead socket is fine.
    }
  }

  Future<void> _deleteTail(TailHandle handle) async {
    try {
      await api.deleteTail(accountId, script, handle.id);
    } on Object {
      // Best effort: Cloudflare expires abandoned tails on its own.
    }
  }

  void _set(TailStatus s) {
    status = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _session++;
    unawaited(_teardown());
    super.dispose();
  }
}
