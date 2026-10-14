import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/models.dart';

/// One outbound email event from the `emailSendingAdaptive` dataset.
class SendingEvent {
  const SendingEvent({
    required this.at,
    required this.from,
    required this.to,
    required this.subject,
    required this.status,
    this.errorCause,
    this.errorDetail,
    this.spf,
    this.dkim,
    this.dmarc,
    this.isSpam = false,
  });

  factory SendingEvent.fromJson(Map<String, dynamic> j) => SendingEvent(
    at: DateTime.tryParse('${j['datetime']}') ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    from: '${j['from'] ?? ''}',
    to: '${j['to'] ?? ''}',
    subject: '${j['subject'] ?? ''}',
    status: '${j['status'] ?? ''}',
    errorCause: _str(j['errorCause']),
    errorDetail: _str(j['errorDetail']),
    spf: _str(j['spf']),
    dkim: _str(j['dkim']),
    dmarc: _str(j['dmarc']),
    isSpam: j['isSpam'] == true,
  );

  static String? _str(Object? v) => v == null || '$v'.isEmpty ? null : '$v';

  final DateTime at;
  final String from;
  final String to;
  final String subject;
  final String status;
  final String? errorCause;
  final String? errorDetail;
  final String? spf;
  final String? dkim;
  final String? dmarc;
  final bool isSpam;

  bool get isProblem => status != 'delivered' && status != 'sent';

  /// Any authentication check that didn't pass.
  bool get authFailed =>
      [spf, dkim, dmarc].any((r) => r != null && r.toLowerCase() != 'pass' && r.toLowerCase() != 'none');
}

/// Outbound health of one sending domain over the last [days] days.
class DomainSendingHealth {
  const DomainSendingHealth({required this.zone, required this.byStatus, required this.recent, required this.days});

  final Zone zone;

  /// Event counts by status (`delivered`, `deliveryFailed`, …).
  final Map<String, int> byStatus;

  /// Up to 50 most recent events, newest first.
  final List<SendingEvent> recent;
  final int days;

  int get delivered => byStatus['delivered'] ?? 0;
  int get failed => (byStatus['deliveryFailed'] ?? 0) + (byStatus['failed'] ?? 0) + (byStatus['rejected'] ?? 0);

  /// Delivered share of finished sends, or null with nothing finished yet.
  double? get deliveryRate => delivered + failed == 0 ? null : delivered / (delivered + failed);

  List<SendingEvent> get problems => recent.where((e) => e.isProblem).toList();
}

/// Queries the Email Service analytics datasets for one zone. Queries follow
/// https://developers.cloudflare.com/email-service/observability/metrics-analytics/
/// (zone-scoped, `Analytics Read`, 31 days of retention). Read-only and free.
Future<DomainSendingHealth> fetchSendingHealth(CfClient client, Zone zone, {int days = 7, DateTime? now}) async {
  final end = (now ?? DateTime.now()).toUtc();
  final start = end.subtract(Duration(days: days));
  final byStatus = await fetchSendingCounts(client, zone, days: days, now: end);

  final events = await client.graphql(
    r'''
query RecentEmailEvents($zoneTag: string!, $start: Time!, $end: Time!) {
  viewer {
    zones(filter: { zoneTag: $zoneTag }) {
      emailSendingAdaptive(
        filter: { datetime_geq: $start, datetime_leq: $end }
        limit: 50
        orderBy: [datetime_DESC]
      ) {
        datetime
        from
        to
        subject
        status
        eventType
        sendingDomain
        messageId
        errorCause
        errorDetail
        dkim
        dmarc
        spf
        isSpam
      }
    }
  }
}''',
    variables: {'zoneTag': zone.id, 'start': start.toIso8601String(), 'end': end.toIso8601String()},
  );

  return DomainSendingHealth(
    zone: zone,
    byStatus: byStatus,
    recent: _rows(events, 'emailSendingAdaptive').map(SendingEvent.fromJson).toList(),
    days: days,
  );
}

/// Outbound event counts by status for one zone over the last [days] days:
/// one GraphQL query (the cheap half of [fetchSendingHealth]).
Future<Map<String, int>> fetchSendingCounts(CfClient client, Zone zone, {int days = 7, DateTime? now}) async {
  final end = (now ?? DateTime.now()).toUtc();
  final start = end.subtract(Duration(days: days));
  String date(DateTime d) => d.toIso8601String().substring(0, 10);

  final counts = await client.graphql(
    r'''
query EmailSendingByStatus($zoneTag: string!, $start: Date!, $end: Date!) {
  viewer {
    zones(filter: { zoneTag: $zoneTag }) {
      emailSendingAdaptiveGroups(
        filter: { date_geq: $start, date_leq: $end }
        limit: 10000
        orderBy: [date_DESC]
      ) {
        count
        dimensions {
          date
          status
        }
      }
    }
  }
}''',
    variables: {'zoneTag': zone.id, 'start': date(start), 'end': date(end)},
  );
  final byStatus = <String, int>{};
  for (final g in _rows(counts, 'emailSendingAdaptiveGroups')) {
    final status = '${(g['dimensions'] as Map<String, dynamic>)['status']}';
    byStatus[status] = (byStatus[status] ?? 0) + ((g['count'] as num?)?.toInt() ?? 0);
  }
  return byStatus;
}

List<Map<String, dynamic>> _rows(Map<String, dynamic> data, String dataset) {
  final zones = (data['viewer'] as Map<String, dynamic>?)?['zones'] as List? ?? const [];
  if (zones.isEmpty) return const [];
  return ((zones.first as Map<String, dynamic>)[dataset] as List? ?? const []).cast<Map<String, dynamic>>();
}
