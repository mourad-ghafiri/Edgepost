import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cloudflare/cf_errors.dart';

/// Why a line in the "Purge URLs" field was rejected.
enum PurgeUrlProblem { notUrl, notHttp, otherDomain }

class RejectedUrl {
  const RejectedUrl(this.line, this.problem);
  final String line;
  final PurgeUrlProblem problem;
}

/// Result of checking the multi-line URL field against the zone.
class PurgeUrlCheck {
  const PurgeUrlCheck({required this.urls, required this.rejected});

  /// Valid, de-duplicated URLs in the order entered.
  final List<String> urls;
  final List<RejectedUrl> rejected;

  bool get isEmpty => urls.isEmpty && rejected.isEmpty;
  bool get ok => urls.isNotEmpty && rejected.isEmpty;
}

/// Checks one URL per line. A URL is accepted when it is an absolute http(s)
/// URL whose host is [zoneName] or one of its subdomains: Cloudflare purges by
/// full URL, and URLs outside the zone would be ignored.
PurgeUrlCheck checkPurgeUrls(String input, String zoneName) {
  final zone = zoneName.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  final urls = <String>[];
  final seen = <String>{};
  final rejected = <RejectedUrl>[];
  for (final raw in input.split(RegExp(r'[\r\n]+'))) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final uri = Uri.tryParse(line);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      rejected.add(RejectedUrl(line, PurgeUrlProblem.notUrl));
      continue;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      rejected.add(RejectedUrl(line, PurgeUrlProblem.notHttp));
      continue;
    }
    final host = uri.host.toLowerCase();
    if (host != zone && !host.endsWith('.$zone')) {
      rejected.add(RejectedUrl(line, PurgeUrlProblem.otherDomain));
      continue;
    }
    if (seen.add(line)) urls.add(line);
  }
  return PurgeUrlCheck(urls: urls, rejected: rejected);
}

/// Cloudflare's purge rate-limit error code.
/// https://developers.cloudflare.com/api/resources/cache/methods/purge/
const int kPurgeRateLimitCode = 1134;

bool isPurgeRateLimited(Object error) =>
    error is CfRateLimitedException || (error is CfApiException && error.hasCode(kPurgeRateLimitCode));

/// Client-side guard for "purge everything". On the Free plan Cloudflare
/// allows 5 hostname/tag/prefix/everything purges per minute per account
/// (https://developers.cloudflare.com/cache/how-to/purge-cache/). Rather than
/// letting the user hit a rejection, the app keeps the same budget locally and
/// says how long to wait.
class PurgeCooldown {
  PurgeCooldown({this.limit = 5, this.window = const Duration(minutes: 1), DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final int limit;
  final Duration window;
  final DateTime Function() _clock;
  final Map<String, List<DateTime>> _log = {};

  List<DateTime> _recent(String accountId) {
    final now = _clock();
    final list = _log.putIfAbsent(accountId, () => []);
    list.removeWhere((t) => now.difference(t) >= window);
    return list;
  }

  /// Time left before another purge is allowed, or [Duration.zero].
  Duration waitFor(String accountId) {
    final list = _recent(accountId);
    if (list.length < limit) return Duration.zero;
    final left = window - _clock().difference(list.first);
    return left.isNegative ? Duration.zero : left;
  }

  void record(String accountId) => _recent(accountId).add(_clock());

  /// After Cloudflare rejected a purge, block until the window has passed.
  void exhaust(String accountId) {
    final list = _recent(accountId);
    final now = _clock();
    while (list.length < limit) {
      list.add(now);
    }
  }
}

/// One cooldown for the whole session, shared by every zone screen.
final purgeCooldownProvider = Provider<PurgeCooldown>((ref) => PurgeCooldown());
