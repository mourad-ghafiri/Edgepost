import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/cf_errors.dart';
import 'traffic_models.dart';

export 'traffic_models.dart';

/// Traffic from the GraphQL Analytics API (`POST /graphql`).
///
/// - Rollup datasets: `httpRequests1dGroups` (daily, `date_geq`/`date_leq` on
///   `Date`) and `httpRequests1hGroups` (hourly, `datetime_geq`/`datetime_lt`
///   on `Time`), both without sampling.
/// - A zone-scoped query covers at most 10 zones, selected with
///   `zones(filter: {zoneTag_in: [...]})`.
/// - The default budget is 300 queries per 5 minutes per user.
///
/// https://developers.cloudflare.com/analytics/graphql-api/limits/
/// https://developers.cloudflare.com/analytics/graphql-api/features/filtering/
/// https://developers.cloudflare.com/analytics/graphql-api/migration-guides/zone-analytics/
const int kMaxZonesPerQuery = 10;

const _sumFields = 'sum { requests bytes cachedRequests cachedBytes threats pageViews }';

String dailyQuery({required bool many, required int limit}) => '''
query EdgepostDaily(${many ? r'$zoneTags: [string!]' : r'$zoneTag: string!'}, \$since: Date!, \$until: Date!) {
  viewer {
    zones(filter: { ${many ? r'zoneTag_in: $zoneTags' : r'zoneTag: $zoneTag'} }) {
      zoneTag
      httpRequests1dGroups(limit: $limit, filter: { date_geq: \$since, date_leq: \$until }, orderBy: [date_ASC]) {
        dimensions { date }
        $_sumFields
        uniq { uniques }
      }
    }
  }
}''';

const String hourlyQuery = '''
query EdgepostHourly(\$zoneTag: string!, \$since: Time!, \$until: Time!) {
  viewer {
    zones(filter: { zoneTag: \$zoneTag }) {
      zoneTag
      httpRequests1hGroups(limit: 48, filter: { datetime_geq: \$since, datetime_lt: \$until }, orderBy: [datetime_ASC]) {
        dimensions { datetime }
        $_sumFields
        uniq { uniques }
      }
    }
  }
}''';

/// Last [days] UTC days (today included) for every zone in [zoneTags],
/// batched ten zones per query. Zones without traffic come back with a
/// zero-filled series, so callers can index the map by every tag they asked for.
Future<Map<String, ZoneTraffic>> fleetDailyTotals(
  CfClient client,
  List<String> zoneTags, {
  int days = 7,
  DateTime? now,
}) async {
  final out = <String, ZoneTraffic>{};
  final tags = zoneTags.toSet().toList();
  final window = _dailyWindow(days, now ?? DateTime.now());
  for (var i = 0; i < tags.length; i += kMaxZonesPerQuery) {
    final batch = tags.sublist(i, i + kMaxZonesPerQuery > tags.length ? tags.length : i + kMaxZonesPerQuery);
    final data = await _run(client, dailyQuery(many: true, limit: days + 1), {
      'zoneTags': batch,
      'since': _date(window.first),
      'until': _date(window.last),
    });
    final parsed = parseTraffic(data, dataset: 'httpRequests1dGroups', buckets: window);
    for (final tag in batch) {
      out[tag] = parsed[tag] ?? _zeros(window);
    }
  }
  return out;
}

/// One zone over [range]: hourly points for 24 hours, daily points otherwise.
Future<ZoneTraffic> zoneSeries(CfClient client, String zoneTag, TrafficRange range, {DateTime? now}) async {
  final t = (now ?? DateTime.now()).toUtc();
  if (range.hourly) {
    final buckets = _hourlyWindow(t);
    final data = await _run(client, hourlyQuery, {
      'zoneTag': zoneTag,
      'since': _time(buckets.first),
      'until': _time(t),
    });
    return parseTraffic(data, dataset: 'httpRequests1hGroups', buckets: buckets)[zoneTag] ?? _zeros(buckets);
  }
  final buckets = _dailyWindow(range.days, t);
  final data = await _run(client, dailyQuery(many: false, limit: range.days + 1), {
    'zoneTag': zoneTag,
    'since': _date(buckets.first),
    'until': _date(buckets.last),
  });
  return parseTraffic(data, dataset: 'httpRequests1dGroups', buckets: buckets)[zoneTag] ?? _zeros(buckets);
}

/// Parses `data.viewer.zones[]` into per-zone traffic. Totals add up every
/// group; the series has one point per bucket in [buckets], zero-filled.
Map<String, ZoneTraffic> parseTraffic(
  Map<String, dynamic> data, {
  required String dataset,
  required List<DateTime> buckets,
}) {
  final viewer = data['viewer'];
  final zones = viewer is Map<String, dynamic> ? viewer['zones'] : null;
  final out = <String, ZoneTraffic>{};
  if (zones is! List) return out;
  for (final z in zones.whereType<Map<String, dynamic>>()) {
    final tag = '${z['zoneTag']}';
    var requests = 0, bytes = 0, cachedRequests = 0, cachedBytes = 0, threats = 0, uniques = 0, pageViews = 0;
    final byBucket = <DateTime, TrafficPoint>{};
    for (final g in (z[dataset] as List? ?? const []).whereType<Map<String, dynamic>>()) {
      final sum = g['sum'] as Map<String, dynamic>? ?? const {};
      final uniq = g['uniq'] as Map<String, dynamic>? ?? const {};
      final dims = g['dimensions'] as Map<String, dynamic>? ?? const {};
      final r = _int(sum['requests']);
      final b = _int(sum['bytes']);
      final cr = _int(sum['cachedRequests']);
      requests += r;
      bytes += b;
      cachedRequests += cr;
      cachedBytes += _int(sum['cachedBytes']);
      threats += _int(sum['threats']);
      pageViews += _int(sum['pageViews']);
      uniques += _int(uniq['uniques']);
      final t = _bucket(dims);
      if (t != null) {
        final prev = byBucket[t];
        byBucket[t] = TrafficPoint(
          t: t,
          requests: r + (prev?.requests ?? 0),
          cachedRequests: cr + (prev?.cachedRequests ?? 0),
          bytes: b + (prev?.bytes ?? 0),
        );
      }
    }
    out[tag] = ZoneTraffic(
      requests: requests,
      bytes: bytes,
      cachedRequests: cachedRequests,
      cachedBytes: cachedBytes,
      threats: threats,
      uniques: uniques,
      pageViews: pageViews,
      series: [
        for (final t in buckets) byBucket[t] ?? TrafficPoint(t: t, requests: 0, cachedRequests: 0, bytes: 0),
      ],
    );
  }
  return out;
}

/// Maps a GraphQL failure to what the screen can explain: a range the plan
/// doesn't keep, a missing permission, or the error as is. GraphQL answers
/// HTTP 200 with `errors`, so the message text is all there is to go on.
Object mapTrafficError(CfApiException e) {
  final text = e.message.toLowerCase();
  const retention = [
    'older than',
    'notolderthan',
    'retention',
    'too far in the past',
    'maxduration',
    'max duration',
    'time range',
  ];
  const permission = ['not authorized', 'unauthorized', 'permission', 'does not have access', 'access denied', 'authz'];
  if (retention.any(text.contains)) return TrafficRangeUnavailableException(e.message);
  if (!e.isPermissionDenied && permission.any(text.contains)) {
    return CfApiException(statusCode: 403, errors: e.errors, fallback: e.message);
  }
  return e;
}

Future<Map<String, dynamic>> _run(CfClient client, String query, Map<String, dynamic> variables) async {
  try {
    return await client.graphql(query, variables: variables);
  } on CfApiException catch (e) {
    throw mapTrafficError(e);
  }
}

ZoneTraffic _zeros(List<DateTime> buckets) => ZoneTraffic(
      series: [for (final t in buckets) TrafficPoint(t: t, requests: 0, cachedRequests: 0, bytes: 0)],
    );

/// UTC midnights from `days - 1` days ago through today.
List<DateTime> _dailyWindow(int days, DateTime now) {
  final u = now.toUtc();
  final today = DateTime.utc(u.year, u.month, u.day);
  return [for (var i = days - 1; i >= 0; i--) today.subtract(Duration(days: i))];
}

/// The 24 UTC hours ending with the current (partial) hour.
List<DateTime> _hourlyWindow(DateTime now) {
  final u = now.toUtc();
  final hour = DateTime.utc(u.year, u.month, u.day, u.hour);
  return [for (var i = 23; i >= 0; i--) hour.subtract(Duration(hours: i))];
}

DateTime? _bucket(Map<String, dynamic> dims) {
  final dt = dims['datetime'];
  if (dt is String) {
    final p = DateTime.tryParse(dt)?.toUtc();
    return p == null ? null : DateTime.utc(p.year, p.month, p.day, p.hour);
  }
  final d = dims['date'];
  if (d is String) {
    final p = DateTime.tryParse(d);
    return p == null ? null : DateTime.utc(p.year, p.month, p.day);
  }
  return null;
}

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _time(DateTime t) {
  final u = t.toUtc();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${_date(u)}T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

int _int(Object? v) => switch (v) {
      int i => i,
      num n => n.toInt(),
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };
