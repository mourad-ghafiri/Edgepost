/// Time window for traffic queries.
enum TrafficRange {
  /// Hourly points (`httpRequests1hGroups`).
  last24h(1),

  /// Daily points (`httpRequests1dGroups`).
  last7d(7),

  /// Daily points (`httpRequests1dGroups`).
  last30d(30);

  const TrafficRange(this.days);

  /// Number of calendar days (UTC) covered by daily ranges.
  final int days;

  bool get hourly => this == TrafficRange.last24h;
}

/// One bucket of a traffic series (an hour or a UTC day).
class TrafficPoint {
  const TrafficPoint({required this.t, required this.requests, required this.cachedRequests, required this.bytes});

  factory TrafficPoint.fromJson(Map<String, dynamic> j) => TrafficPoint(
        t: DateTime.parse('${j['t']}'),
        requests: (j['r'] as num).toInt(),
        cachedRequests: (j['c'] as num).toInt(),
        bytes: (j['b'] as num).toInt(),
      );

  /// Start of the bucket, UTC.
  final DateTime t;
  final int requests;
  final int cachedRequests;
  final int bytes;

  Map<String, dynamic> toJson() => {'t': t.toIso8601String(), 'r': requests, 'c': cachedRequests, 'b': bytes};
}

/// Totals and per-period series for one zone over a range.
class ZoneTraffic {
  const ZoneTraffic({
    this.requests = 0,
    this.bytes = 0,
    this.cachedRequests = 0,
    this.cachedBytes = 0,
    this.threats = 0,
    this.uniques = 0,
    this.pageViews = 0,
    this.series = const [],
  });

  factory ZoneTraffic.fromJson(Map<String, dynamic> j) => ZoneTraffic(
        requests: (j['requests'] as num? ?? 0).toInt(),
        bytes: (j['bytes'] as num? ?? 0).toInt(),
        cachedRequests: (j['cachedRequests'] as num? ?? 0).toInt(),
        cachedBytes: (j['cachedBytes'] as num? ?? 0).toInt(),
        threats: (j['threats'] as num? ?? 0).toInt(),
        uniques: (j['uniques'] as num? ?? 0).toInt(),
        pageViews: (j['pageViews'] as num? ?? 0).toInt(),
        series: (j['series'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(TrafficPoint.fromJson)
            .toList(),
      );

  static const empty = ZoneTraffic();

  final int requests;
  final int bytes;
  final int cachedRequests;
  final int cachedBytes;
  final int threats;

  /// Unique visitor IPs, summed per bucket (a visitor seen on two days counts
  /// twice), which is how the rollup datasets report them.
  final int uniques;
  final int pageViews;
  final List<TrafficPoint> series;

  /// Share of requests served from Cloudflare's cache, 0–1.
  double get cachedRatio => requests == 0 ? 0 : cachedRequests / requests;

  /// Share of bytes served from cache, 0–1.

  bool get isEmpty => requests == 0 && bytes == 0;

  Map<String, dynamic> toJson() => {
        'requests': requests,
        'bytes': bytes,
        'cachedRequests': cachedRequests,
        'cachedBytes': cachedBytes,
        'threats': threats,
        'uniques': uniques,
        'pageViews': pageViews,
        'series': series.map((p) => p.toJson()).toList(),
      };
}

/// The plan doesn't keep data that far back (GraphQL `notOlderThan`), or the
/// requested window is wider than the dataset allows.
class TrafficRangeUnavailableException implements Exception {
  const TrafficRangeUnavailableException(this.detail);
  final String detail;

  @override
  String toString() => 'TrafficRangeUnavailableException: $detail';
}
