/// Mail authentication health (SPF, DKIM, DMARC) for one domain, built from
/// its DNS records plus Cloudflare's SPF inspection and DMARC-report status:
/// https://developers.cloudflare.com/api/resources/email_auth/
///
/// Fetching lives in [fetchMailAuthInputs]; [evaluateMailAuth] is pure so the
/// rules are unit-testable.
library;

import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/cf_errors.dart';
import 'email_routing_models.dart';

/// SPF include Email Routing needs on the apex.
const String kCloudflareSpfInclude = 'include:_spf.mx.cloudflare.net';

/// DKIM selector Email Routing publishes.
const String kRoutingDkimSelector = 'cf2024-1';

/// RFC 7208 §4.6.4: more than 10 DNS lookups is a permanent SPF error.
const int kMaxSpfLookups = 10;

/// A DNS record as far as auth checks care.
class AuthDnsRecord {
  const AuthDnsRecord({required this.type, required this.name, required this.content, this.priority});

  factory AuthDnsRecord.fromJson(Map<String, dynamic> j) => AuthDnsRecord(
        type: '${j['type'] ?? ''}',
        name: '${j['name'] ?? ''}',
        content: '${j['content'] ?? ''}',
        priority: (j['priority'] as num?)?.toInt(),
      );

  final String type;
  final String name;
  final String content;
  final int? priority;

  Map<String, dynamic> toJson() => {'type': type, 'name': name, 'content': content, 'priority': priority};
}

/// `GET /zones/{zone_id}/email/auth/spf/inspect`.
class SpfInspection {
  const SpfInspection({this.totalLookups, this.record, this.errors = const []});

  factory SpfInspection.fromJson(Map<String, dynamic> j) => SpfInspection(
        totalLookups: (j['total_lookups'] as num?)?.toInt(),
        record: j['record'] as String?,
        errors: (j['errors'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((e) => SpfInspectError('${e['code'] ?? ''}', '${e['message'] ?? ''}'))
            .toList(),
      );

  final int? totalLookups;
  final String? record;
  final List<SpfInspectError> errors;

  bool get tooManyLookups =>
      (totalLookups ?? 0) > kMaxSpfLookups || errors.any((e) => e.code == 'max_lookups');

  Map<String, dynamic> toJson() => {
        'total_lookups': totalLookups,
        'record': record,
        'errors': [for (final e in errors) {'code': e.code, 'message': e.message}],
      };
}

class SpfInspectError {
  const SpfInspectError(this.code, this.message);
  final String code;
  final String message;
}

/// Raw inputs for the health card. Flags say which sources the token could read.
class MailAuthInputs {
  const MailAuthInputs({
    this.records = const [],
    this.dnsAvailable = true,
    this.spfInspection,
    this.dmarcReportStatus,
    this.emailAuthAvailable = false,
  });

  factory MailAuthInputs.fromJson(Map<String, dynamic> j) => MailAuthInputs(
        records: (j['records'] as List).cast<Map<String, dynamic>>().map(AuthDnsRecord.fromJson).toList(),
        dnsAvailable: j['dns'] == true,
        spfInspection: j['spf'] == null ? null : SpfInspection.fromJson(j['spf'] as Map<String, dynamic>),
        dmarcReportStatus: j['dmarc_status'] as String?,
        emailAuthAvailable: j['email_auth'] == true,
      );

  /// TXT and MX records of the zone.
  final List<AuthDnsRecord> records;
  final bool dnsAvailable;
  final SpfInspection? spfInspection;

  /// `status` of `GET /email/auth/dmarc-reports`; null when DMARC is
  /// correctly configured (the API omits the field) or when not fetched.
  final String? dmarcReportStatus;

  /// Whether the email/auth endpoints answered (DMARC Management permission).
  final bool emailAuthAvailable;

  Map<String, dynamic> toJson() => {
        'records': records.map((r) => r.toJson()).toList(),
        'dns': dnsAvailable,
        'spf': spfInspection?.toJson(),
        'dmarc_status': dmarcReportStatus,
        'email_auth': emailAuthAvailable,
      };
}

/// Reads DNS (TXT + MX) and, when [canEmailAuth], the SPF inspection and the
/// DMARC report status. Missing permissions degrade to "unknown", never throw.
Future<MailAuthInputs> fetchMailAuthInputs(
  CfClient client,
  String zoneId, {
  required bool canDns,
  required bool canEmailAuth,
}) async {
  var dnsOk = canDns;
  final records = <AuthDnsRecord>[];
  if (canDns) {
    try {
      for (final type in const ['TXT', 'MX']) {
        final rows = await client.getAll('/zones/$zoneId/dns_records', query: {'type': type}, perPage: 100);
        records.addAll(rows.map(AuthDnsRecord.fromJson));
      }
    } on CfApiException catch (e) {
      if (!e.isPermissionDenied) rethrow;
      dnsOk = false;
      records.clear();
    }
  }

  SpfInspection? spf;
  String? dmarcStatus;
  var authOk = false;
  if (canEmailAuth) {
    try {
      final res = await client.get('/zones/$zoneId/email/auth/dmarc-reports');
      final r = res.result;
      dmarcStatus = r is Map<String, dynamic> ? r['status'] as String? : null;
      authOk = true;
    } on CfApiException {
      authOk = false;
    }
    if (authOk) {
      try {
        final res = await client.get('/zones/$zoneId/email/auth/spf/inspect');
        final r = res.result;
        if (r is Map<String, dynamic>) spf = SpfInspection.fromJson(r);
      } on CfApiException {
        spf = null;
      }
    }
  }
  return MailAuthInputs(
    records: records,
    dnsAvailable: dnsOk,
    spfInspection: spf,
    dmarcReportStatus: dmarcStatus,
    emailAuthAvailable: authOk,
  );
}

// ---------------------------------------------------------------------------
// Evaluation
// ---------------------------------------------------------------------------

enum AuthState { ok, attention, missing, unknown }

/// Why a check landed where it did; the UI maps each to one line of advice.
enum AuthFinding {
  unavailable,
  spfOk,
  spfMissing,
  spfMultiple,
  spfNoCloudflare,
  spfPassAll,
  spfTooManyLookups,
  spfInvalid,
  dkimOk,
  dkimMissing,
  dkimOtherSelectors,
  dmarcOk,
  dmarcOkNoReports,
  dmarcViaCname,
  dmarcMissing,
  dmarcMultiple,
  dmarcPolicyNone,
  dmarcInvalid,
  dmarcReportIssue,
}

class AuthCheck {
  const AuthCheck(this.state, this.finding, {this.current, this.suggestion, this.lookups, this.detail});

  final AuthState state;
  final AuthFinding finding;

  /// The record found (normalised), if any.
  final String? current;

  /// A record the user can copy to fix the finding.
  final String? suggestion;
  final int? lookups;

  /// Extra machine detail (SPF inspection error message, DMARC status code).
  final String? detail;
}

class MailAuthHealth {
  const MailAuthHealth({required this.spf, required this.dkim, required this.dmarc, this.foreignMx = const []});

  final AuthCheck spf;
  final AuthCheck dkim;
  final AuthCheck dmarc;

  /// MX hosts that aren't Cloudflare's while routing is on (they conflict).
  final List<String> foreignMx;

  int get needsAttention =>
      [spf, dkim, dmarc].where((c) => c.state == AuthState.attention || c.state == AuthState.missing).length;
}

/// TXT content as published: strips the quotes Cloudflare may return and
/// joins split character-strings (`"a" "b"` → `ab`).
String normalizeTxt(String raw) {
  final t = raw.trim();
  if (!t.startsWith('"')) return t;
  final parts = RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches(t).map((m) => m.group(1)!.replaceAll(r'\"', '"'));
  return parts.join();
}

bool _nameIs(String recordName, String fqdn, String zoneName) {
  final n = recordName.trim().toLowerCase().replaceAll(RegExp(r'\.$'), '');
  final want = fqdn.toLowerCase();
  if (n == want) return true;
  final zone = zoneName.toLowerCase();
  if (want == zone) return n == '@' || n.isEmpty;
  // Relative names ("_dmarc") when the record list isn't fully qualified.
  return want.endsWith('.$zone') && n == want.substring(0, want.length - zone.length - 1);
}

final _spfAll = RegExp(r'^[+~?-]?all$', caseSensitive: false);

/// One SPF record from several: unique mechanisms in order, one `all` at the
/// end (the first seen, `~all` if none), plus Cloudflare's include if asked.
String mergeSpf(List<String> records, {bool addCloudflare = false}) {
  final terms = <String>[];
  String? all;
  for (final r in records) {
    for (final t in r.trim().split(RegExp(r'\s+')).skip(1)) {
      if (t.isEmpty) continue;
      if (_spfAll.hasMatch(t)) {
        all ??= t.toLowerCase();
      } else if (!terms.any((x) => x.toLowerCase() == t.toLowerCase())) {
        terms.add(t);
      }
    }
  }
  if (addCloudflare && !terms.any((t) => t.toLowerCase() == kCloudflareSpfInclude)) {
    terms.add(kCloudflareSpfInclude);
  }
  return ['v=spf1', ...terms, all ?? '~all'].join(' ');
}

/// Parses `p=` from a DMARC record; null when absent.
String? dmarcPolicy(String record) {
  for (final part in record.split(';')) {
    final kv = part.trim().split('=');
    if (kv.length == 2 && kv[0].trim().toLowerCase() == 'p') return kv[1].trim().toLowerCase();
  }
  return null;
}

/// Applies the SPF / DKIM / DMARC rules to [inputs].
///
/// [requiredRecords] (from `GET /email/routing/dns`) supply Cloudflare's own
/// values for suggestions when routing needs them.
MailAuthHealth evaluateMailAuth(
  MailAuthInputs inputs, {
  required String zoneName,
  required bool routingEnabled,
  List<RoutingDnsRecord> requiredRecords = const [],
}) {
  if (!inputs.dnsAvailable) {
    const unknown = AuthCheck(AuthState.unknown, AuthFinding.unavailable);
    return const MailAuthHealth(spf: unknown, dkim: unknown, dmarc: unknown);
  }
  final zone = zoneName.toLowerCase();
  final txt = inputs.records.where((r) => r.type.toUpperCase() == 'TXT').toList();
  final mx = inputs.records.where((r) => r.type.toUpperCase() == 'MX' && _nameIs(r.name, zone, zone)).toList();

  return MailAuthHealth(
    spf: _spf(txt, inputs.spfInspection, zone, routingEnabled, requiredRecords),
    dkim: _dkim(txt, zone, routingEnabled, requiredRecords),
    dmarc: _dmarc(txt, zone, inputs),
    foreignMx: routingEnabled
        ? [
            for (final r in mx)
              if (!r.content.toLowerCase().replaceAll(RegExp(r'\.$'), '').endsWith('mx.cloudflare.net')) r.content,
          ]
        : const [],
  );
}

AuthCheck _spf(
  List<AuthDnsRecord> txt,
  SpfInspection? inspection,
  String zone,
  bool routingEnabled,
  List<RoutingDnsRecord> required,
) {
  final spf = [
    for (final r in txt)
      if (_nameIs(r.name, zone, zone) && normalizeTxt(r.content).toLowerCase().startsWith('v=spf1')) normalizeTxt(r.content),
  ];
  String? requiredSpf;
  for (final r in required) {
    final c = normalizeTxt(r.content);
    if (r.type.toUpperCase() == 'TXT' && c.toLowerCase().startsWith('v=spf1')) requiredSpf = c;
  }

  if (spf.isEmpty) {
    return AuthCheck(
      AuthState.missing,
      AuthFinding.spfMissing,
      suggestion: routingEnabled ? (requiredSpf ?? 'v=spf1 $kCloudflareSpfInclude ~all') : null,
    );
  }
  if (spf.length > 1) {
    // RFC 7208 §3.2: more than one SPF record is a permanent error.
    return AuthCheck(
      AuthState.attention,
      AuthFinding.spfMultiple,
      current: spf.join('\n'),
      suggestion: mergeSpf(spf, addCloudflare: routingEnabled),
    );
  }
  final record = spf.single;
  final terms = record.toLowerCase().split(RegExp(r'\s+'));
  final lookups = inspection?.totalLookups;
  if (inspection != null && inspection.tooManyLookups) {
    return AuthCheck(AuthState.attention, AuthFinding.spfTooManyLookups, current: record, lookups: lookups);
  }
  final hardError = inspection?.errors
      .where((e) => const {'invalid_spf', 'invalid_mechanism', 'loop_detected', 'invalid_domain'}.contains(e.code))
      .firstOrNull;
  if (hardError != null) {
    return AuthCheck(AuthState.attention, AuthFinding.spfInvalid,
        current: record, lookups: lookups, detail: hardError.message.isEmpty ? hardError.code : hardError.message);
  }
  if (routingEnabled && !terms.contains(kCloudflareSpfInclude)) {
    return AuthCheck(
      AuthState.attention,
      AuthFinding.spfNoCloudflare,
      current: record,
      lookups: lookups,
      suggestion: mergeSpf([record], addCloudflare: true),
    );
  }
  if (terms.contains('+all') || terms.contains('all')) {
    return AuthCheck(
      AuthState.attention,
      AuthFinding.spfPassAll,
      current: record,
      lookups: lookups,
      suggestion: record.replaceAll(RegExp(r'(^|\s)\+?all(\s|$)', caseSensitive: false), r' ~all ').trim().replaceAll(RegExp(r'\s+'), ' '),
    );
  }
  return AuthCheck(AuthState.ok, AuthFinding.spfOk, current: record, lookups: lookups);
}

AuthCheck _dkim(List<AuthDnsRecord> txt, String zone, bool routingEnabled, List<RoutingDnsRecord> required) {
  final routingName = '$kRoutingDkimSelector._domainkey.$zone';
  for (final r in txt) {
    if (_nameIs(r.name, routingName, zone)) {
      return AuthCheck(AuthState.ok, AuthFinding.dkimOk, current: normalizeTxt(r.content));
    }
  }
  String? suggestion;
  for (final r in required) {
    if (r.type.toUpperCase() == 'TXT' && r.name.toLowerCase().contains('._domainkey')) {
      suggestion = normalizeTxt(r.content);
    }
  }
  final others = txt.where((r) => r.name.toLowerCase().contains('._domainkey')).toList();
  if (!routingEnabled && others.isNotEmpty) {
    return AuthCheck(AuthState.ok, AuthFinding.dkimOtherSelectors,
        detail: others.map((r) => r.name.split('._domainkey').first).toSet().join(', '));
  }
  return AuthCheck(routingEnabled ? AuthState.attention : AuthState.missing, AuthFinding.dkimMissing,
      suggestion: suggestion);
}

AuthCheck _dmarc(List<AuthDnsRecord> txt, String zone, MailAuthInputs inputs) {
  final records = [
    for (final r in txt)
      if (_nameIs(r.name, '_dmarc.$zone', zone) && normalizeTxt(r.content).toLowerCase().startsWith('v=dmarc1'))
        normalizeTxt(r.content),
  ];
  final status = inputs.dmarcReportStatus;
  const starter = 'v=DMARC1; p=none';

  if (records.isEmpty) {
    // DMARC published through a CNAME is healthy: the reports API resolves it
    // and omits `status` when DMARC is correctly configured.
    if (inputs.emailAuthAvailable && status == null) {
      return const AuthCheck(AuthState.ok, AuthFinding.dmarcViaCname);
    }
    return const AuthCheck(AuthState.missing, AuthFinding.dmarcMissing, suggestion: starter);
  }
  if (records.length > 1) {
    return AuthCheck(AuthState.attention, AuthFinding.dmarcMultiple, current: records.join('\n'), suggestion: records.first);
  }
  final record = records.single;
  final policy = dmarcPolicy(record);
  if (policy == null || !const {'none', 'quarantine', 'reject'}.contains(policy)) {
    return AuthCheck(AuthState.attention, AuthFinding.dmarcInvalid, current: record, suggestion: starter);
  }
  if (policy == 'none') {
    return AuthCheck(
      AuthState.attention,
      AuthFinding.dmarcPolicyNone,
      current: record,
      suggestion: record.replaceFirst(RegExp(r'p\s*=\s*none', caseSensitive: false), 'p=quarantine'),
    );
  }
  if (status != null && status != 'missing-dmarc-rua' && status != 'missing-dmarc-report') {
    return AuthCheck(AuthState.attention, AuthFinding.dmarcReportIssue, current: record, detail: status);
  }
  if (status == 'missing-dmarc-rua') {
    return AuthCheck(AuthState.ok, AuthFinding.dmarcOkNoReports, current: record, detail: status);
  }
  return AuthCheck(AuthState.ok, AuthFinding.dmarcOk, current: record);
}
