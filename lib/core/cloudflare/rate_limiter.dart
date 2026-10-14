import 'dart:async';
import 'dart:collection';

/// Client-side guard for Cloudflare's global budget of 1,200 requests per
/// five minutes per token (https://developers.cloudflare.com/fundamentals/api/reference/limits/).
///
/// Keeps a sliding window of request timestamps and stays under [budget],
/// which is set below the real limit so background refreshes never trip the
/// five-minute block. A 429 seen from the server pauses everything until the
/// server's `retry-after` elapses.
class RateLimiter {
  RateLimiter({this.budget = 1000, this.window = const Duration(minutes: 5), DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final int budget;
  final Duration window;
  final DateTime Function() _now;
  final Queue<DateTime> _stamps = Queue<DateTime>();
  DateTime? _blockedUntil;

  /// Remaining requests in the current window (for diagnostics UI).
  int get remaining {
    _evict();
    return budget - _stamps.length;
  }

  DateTime? get blockedUntil => _blockedUntil;

  /// Duration the caller must wait before the next request, or zero.
  Duration delayBeforeNext() {
    final now = _now();
    if (_blockedUntil != null && now.isBefore(_blockedUntil!)) {
      return _blockedUntil!.difference(now);
    }
    _evict();
    if (_stamps.length < budget) return Duration.zero;
    return _stamps.first.add(window).difference(now);
  }

  /// Waits (up to [maxWait]) for a slot and records the request. Returns false
  /// when the wait would exceed [maxWait]; the caller then surfaces a
  /// rate-limited error instead of hanging the UI.
  Future<bool> acquire({Duration maxWait = const Duration(seconds: 20)}) async {
    var delay = delayBeforeNext();
    if (delay > maxWait) return false;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
      delay = delayBeforeNext();
      if (delay > Duration.zero) return false;
    }
    _stamps.addLast(_now());
    return true;
  }

  /// Called when the server answered 429.
  void blockFor(Duration d) {
    final until = _now().add(d);
    if (_blockedUntil == null || until.isAfter(_blockedUntil!)) _blockedUntil = until;
  }

  void _evict() {
    final cutoff = _now().subtract(window);
    while (_stamps.isNotEmpty && _stamps.first.isBefore(cutoff)) {
      _stamps.removeFirst();
    }
  }
}
