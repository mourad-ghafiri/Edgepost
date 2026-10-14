import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/capability_probe.dart';
import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/mail_worker.dart';
import 'mail_client.dart';
import 'mail_models.dart';

/// Development only: points the mail service at the local fake
/// (`--dart-define=MAIL_WORKER_URL=http://127.0.0.1:8789`). Empty in release.
const String kMailWorkerUrlOverride = String.fromEnvironment('MAIL_WORKER_URL');

/// The Worker bundle shipped inside the app (built by tool/build_worker.sh).
class WorkerBundle {
  const WorkerBundle({
    required this.version,
    required this.mainModule,
    required this.compatibilityDate,
    required this.compatibilityFlags,
    required this.source,
  });

  final String version;
  final String mainModule;
  final String compatibilityDate;
  final List<String> compatibilityFlags;
  final String source;

  static Future<WorkerBundle> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    final manifest = jsonDecode(await b.loadString('assets/worker/manifest.json')) as Map<String, dynamic>;
    final main = '${manifest['mainModule']}';
    return WorkerBundle(
      version: '${manifest['version']}',
      mainModule: main,
      compatibilityDate: '${manifest['compatibilityDate']}',
      compatibilityFlags: (manifest['compatibilityFlags'] as List).map((e) => '$e').toList(),
      source: await b.loadString('assets/worker/$main'),
    );
  }
}

/// The mail Worker bundled with this build of the app.
final workerBundleProvider = FutureProvider<WorkerBundle>((ref) => WorkerBundle.load());

/// Compares dotted versions ("1.2.0" < "1.10.0").
int compareVersions(String a, String b) {
  final pa = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final pb = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < max(pa.length, pb.length); i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

enum RoutingChoice { catchAll, specific }

/// What the user picked for one domain.
class DomainPlan {
  const DomainPlan({
    required this.zone,
    this.choice = RoutingChoice.catchAll,
    this.localParts = const [],
    this.enableSending = true,
  });
  final Zone zone;
  final RoutingChoice choice;
  final List<String> localParts;
  final bool enableSending;
}

enum ProvisionState { pending, running, done, attention, failed, skipped }

/// One visible line of the setup checklist.
class ProvisionStep {
  const ProvisionStep(this.id, {this.state = ProvisionState.pending, this.error, this.problem, this.domain});
  final String id;
  final ProvisionState state;
  final String? error;
  final ProvisionProblem? problem;
  final String? domain;

  /// Matches the same checklist line (per-domain steps share an id).
  bool sameLine(ProvisionStep o) => o.id == id && o.domain == domain;
}

/// Why a step failed, in terms the UI can explain.
enum ProvisionProblem { r2Disabled, noWorkersSubdomain, healthTimeout, sendingDns, sendingPending, other }

class ProvisionException implements Exception {
  ProvisionException(this.problem, this.message);
  final ProvisionProblem problem;
  final String message;
  @override
  String toString() => message;
}

/// Email Routing operations the provisioner needs (implemented over the
/// email_routing feature's API helpers).
abstract class MailRouting {
  Future<void> enableRouting(CfClient client, String zoneId);
  Future<void> setCatchAllToWorker(CfClient client, String zoneId, String workerName);
  Future<void> routeAddressToWorker(CfClient client, String zoneId, String address, String workerName);
}

/// Deploys and connects the mail Worker in the user's account. Every step is
/// idempotent: re-running after a failure reuses what already exists.
class MailProvisioner {
  MailProvisioner({
    required this.client,
    required this.accountId,
    required this.bundle,
    required this.routing,
    this.existing,
    MailClient Function(String url, String key)? mailClientFactory,
    this.healthAttempts = 10,
    this.healthDelay = const Duration(seconds: 3),
    this.monthlySendLimit,
  }) : _mailClient = mailClientFactory ?? ((url, key) => MailClient(baseUrl: url, apiKey: key, accountId: accountId));

  final CfClient client;
  final String accountId;
  final WorkerBundle bundle;
  final MailRouting routing;
  final MailService? existing;
  final MailClient Function(String url, String key) _mailClient;
  final int healthAttempts;
  final Duration healthDelay;

  /// Sending budget pushed to the Worker (recipients per rolling 31 days).
  /// Null leaves the Worker's current value (default 3,000) in place.
  final int? monthlySendLimit;

  String get _acc => '/accounts/$accountId';

  static List<ProvisionStep> plan(List<DomainPlan> domains) => [
    const ProvisionStep('d1'),
    const ProvisionStep('r2'),
    const ProvisionStep('upload'),
    const ProvisionStep('publish'),
    const ProvisionStep('schedule'),
    const ProvisionStep('connect'),
    for (final d in domains) ProvisionStep('route', domain: d.zone.name),
    for (final d in domains.where((d) => d.enableSending)) ProvisionStep('sending', domain: d.zone.name),
    const ProvisionStep('save'),
  ];

  /// Runs every step, reporting progress through [onStep]. Returns the saved
  /// service. Sending onboarding failures don't stop the run; anything else does.
  Future<MailService> run(List<DomainPlan> domains, void Function(ProvisionStep step) onStep) async {
    Future<T> step<T>(String id, Future<T> Function() body, {String? domain}) async {
      onStep(ProvisionStep(id, state: ProvisionState.running, domain: domain));
      try {
        final r = await body();
        onStep(ProvisionStep(id, state: ProvisionState.done, domain: domain));
        return r;
      } on Object catch (e) {
        onStep(
          ProvisionStep(
            id,
            state: ProvisionState.failed,
            error: _message(e),
            problem: e is ProvisionException ? e.problem : null,
            domain: domain,
          ),
        );
        rethrow;
      }
    }

    final d1Id = await step('d1', _ensureD1);
    final bucket = await step('r2', _ensureR2);
    final apiKey = existing?.apiKey ?? _randomKey();
    await step('upload', () => _upload(d1Id, bucket, apiKey));
    final url = await step('publish', _publish);
    await step('schedule', _schedule);
    final allDomains = {...?existing?.domains, ...domains.map((d) => d.zone.name)}.toList()..sort();
    await step('connect', () => _connect(url, apiKey, allDomains));

    for (final d in domains) {
      await step('route', () => _route(d), domain: d.zone.name);
    }
    final sending = <String>{...?existing?.sendingDomains};
    for (final d in domains.where((d) => d.enableSending)) {
      onStep(ProvisionStep('sending', state: ProvisionState.running, domain: d.zone.name));
      try {
        final missing = await _onboardSending(d.zone);
        sending.add(d.zone.name);
        onStep(
          missing.isEmpty
              ? ProvisionStep('sending', state: ProvisionState.done, domain: d.zone.name)
              : ProvisionStep(
                  'sending',
                  state: ProvisionState.attention,
                  problem: ProvisionProblem.sendingPending,
                  error: missing.map((r) => '${r['type']} ${r['name']}').join(', '),
                  domain: d.zone.name,
                ),
        );
      } on Object catch (e) {
        // Reported on the step; receiving still works.
        onStep(ProvisionStep('sending', state: ProvisionState.failed, error: _message(e), domain: d.zone.name));
      }
    }

    return step(
      'save',
      () async => MailService(
        accountId: accountId,
        workerUrl: url,
        apiKey: apiKey,
        workerVersion: bundle.version,
        domains: allDomains,
        sendingDomains: sending.toList()..sort(),
        d1Id: d1Id,
        r2Bucket: bucket,
      ),
    );
  }

  /// Re-uploads the bundled Worker with the same bindings and key.
  Future<MailService> update(MailService s) async {
    await _upload(s.d1Id, s.r2Bucket, s.apiKey);
    await _waitHealthy(s.workerUrl, s.apiKey);
    return s.withVersion(bundle.version);
  }

  Future<String> _ensureD1() async {
    // per_page minimum is 10 (https://developers.cloudflare.com/api/resources/d1/subresources/database/methods/list/)
    final list = await client.getAll('$_acc/d1/database', query: {'name': kMailWorkerName}, perPage: 10);
    for (final db in list) {
      if (db['name'] == kMailWorkerName) return '${db['uuid']}';
    }
    final created = await client.post('$_acc/d1/database', data: {'name': kMailWorkerName});
    return '${created.map['uuid']}';
  }

  Future<String> _ensureR2() async {
    try {
      final res = await client.get('$_acc/r2/buckets', query: {'name_contains': kMailWorkerName});
      final buckets = (res.map['buckets'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (buckets.any((b) => b['name'] == kMailWorkerName)) return kMailWorkerName;
      await client.post('$_acc/r2/buckets', data: {'name': kMailWorkerName});
      return kMailWorkerName;
    } on CfApiException catch (e) {
      if (CapabilityProbe.isR2NotEnabled(e)) throw ProvisionException(ProvisionProblem.r2Disabled, e.message);
      rethrow;
    }
  }

  /// Multipart upload: `metadata` + the ES module part
  /// (https://developers.cloudflare.com/workers/configuration/multipart-upload-metadata/).
  /// D1 binding key per https://developers.cloudflare.com/api/resources/workers/subresources/scripts/methods/update/
  Future<void> _upload(String d1Id, String bucket, String apiKey) async {
    final metadata = {
      'main_module': bundle.mainModule,
      'compatibility_date': bundle.compatibilityDate,
      'compatibility_flags': bundle.compatibilityFlags,
      'bindings': [
        {'type': 'd1', 'name': 'DB', 'database_id': d1Id},
        {'type': 'r2_bucket', 'name': 'MAIL', 'bucket_name': bucket},
        {'type': 'send_email', 'name': 'EMAIL'},
        {'type': 'secret_text', 'name': 'MAIL_API_KEY', 'text': apiKey},
      ],
    };
    final form = FormData.fromMap({
      'metadata': MultipartFile.fromString(jsonEncode(metadata), contentType: DioMediaType('application', 'json')),
      bundle.mainModule: MultipartFile.fromString(
        bundle.source,
        filename: bundle.mainModule,
        contentType: DioMediaType('application', 'javascript+module'),
      ),
    });
    await client.put('$_acc/workers/scripts/$kMailWorkerName', data: form);
  }

  Future<String> _publish() async {
    final sub = await client.get('$_acc/workers/subdomain');
    final name = sub.map['subdomain'] as String?;
    if (name == null || name.isEmpty) {
      throw ProvisionException(ProvisionProblem.noWorkersSubdomain, 'No workers.dev subdomain');
    }
    await client.post(
      '$_acc/workers/scripts/$kMailWorkerName/subdomain',
      data: {'enabled': true, 'previews_enabled': false},
    );
    if (kMailWorkerUrlOverride.isNotEmpty) return kMailWorkerUrlOverride;
    return 'https://$kMailWorkerName.$name.workers.dev';
  }

  Future<void> _schedule() => client.put(
    '$_acc/workers/scripts/$kMailWorkerName/schedules',
    data: [
      {'cron': '17 3 * * *'},
    ],
  );

  Future<void> _connect(String url, String apiKey, List<String> domains) async {
    final mail = await _waitHealthy(url, apiKey);
    await mail.putConfig({'domains': domains, 'monthlySendLimit': ?monthlySendLimit});
  }

  Future<MailClient> _waitHealthy(String url, String apiKey) async {
    final mail = _mailClient(url, apiKey);
    Object? last;
    for (var i = 0; i < healthAttempts; i++) {
      try {
        await mail.health();
        return mail;
      } on MailException catch (e) {
        last = e;
        if (e.code == 'unauthorized') rethrow;
      }
      await Future<void>.delayed(healthDelay);
    }
    throw ProvisionException(ProvisionProblem.healthTimeout, '$last');
  }

  Future<void> _route(DomainPlan d) async {
    await routing.enableRouting(client, d.zone.id);
    if (d.choice == RoutingChoice.catchAll) {
      await routing.setCatchAllToWorker(client, d.zone.id, kMailWorkerName);
    } else {
      for (final local in d.localParts) {
        await routing.routeAddressToWorker(client, d.zone.id, '$local@${d.zone.name}', kMailWorkerName);
      }
    }
  }

  /// Onboards the zone to Email Sending (or finds the existing onboarding)
  /// and returns the expected records not yet visible in the zone.
  ///
  /// Read-only for DNS: Cloudflare creates the sending records itself and
  /// keeps them locked, "managed by Email Service for the lifetime of the
  /// domain configuration"
  /// (https://developers.cloudflare.com/email-service/configuration/domains/).
  /// Writing them from here would duplicate or collide with managed records.
  /// API: https://developers.cloudflare.com/api/resources/email_sending/subresources/subdomains/
  Future<List<Map<String, dynamic>>> _onboardSending(Zone zone) async {
    final base = '/zones/${zone.id}/email/sending/subdomains';
    final existing = await client.getAll(base);
    var sub = existing.where((s) => '${s['name']}'.toLowerCase() == zone.name.toLowerCase()).firstOrNull;
    sub ??= (await client.post(base, data: {'name': zone.name})).map;
    final id = '${sub['tag'] ?? sub['id']}';
    final wanted = _records((await client.get('$base/$id/dns')).result);
    if (wanted.isEmpty) return const [];
    final have = await client.getAll('/zones/${zone.id}/dns_records', perPage: 100);
    return [
      for (final w in wanted)
        if (!have.any((h) => sendingRecordSatisfied(h, w, zone.name))) w,
    ];
  }

  /// Whether zone record [have] satisfies expected record [want]. Tolerant on
  /// purpose: an existing DMARC policy or SPF that already includes
  /// Cloudflare counts, since the user may have tuned them.
  static bool sendingRecordSatisfied(Map<String, dynamic> have, Map<String, dynamic> want, String zone) {
    final type = '${want['type']}'.toUpperCase();
    if ('${have['type']}'.toUpperCase() != type) return false;
    if (_fqdn('${have['name']}', zone) != _fqdn('${want['name']}', zone)) return false;
    final hc = _normContent('${have['content']}'), wc = _normContent('${want['content']}');
    if (type == 'TXT' && wc.startsWith('v=dmarc1')) return hc.startsWith('v=dmarc1');
    if (type == 'TXT' && wc.startsWith('v=spf1')) {
      return hc.startsWith('v=spf1') && hc.contains('include:_spf.mx.cloudflare.net');
    }
    return hc == wc;
  }

  static String _fqdn(String n, String zone) {
    final s = n.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    if (s == '@' || s.isEmpty) return zone.toLowerCase();
    return s == zone.toLowerCase() || s.endsWith('.${zone.toLowerCase()}') ? s : '$s.${zone.toLowerCase()}';
  }

  /// Lowercase, no trailing dot, TXT chunks joined, quotes and extra spaces gone.
  static String _normContent(String c) => c
      .replaceAll(RegExp(r'"\s+"'), '')
      .replaceAll('"', '')
      .trim()
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  static List<Map<String, dynamic>> _records(Object? result) => (result as List? ?? const [])
      .whereType<Map<String, dynamic>>()
      .where((r) => r['type'] != null && r['name'] != null)
      .toList();

  static String _randomKey() {
    final r = Random.secure();
    return base64UrlEncode(List<int>.generate(32, (_) => r.nextInt(256))).replaceAll('=', '');
  }

  static String _message(Object e) => switch (e) {
    ProvisionException(:final message) => message,
    CfException(:final message) => message,
    MailException(:final message) => message,
    _ => '$e',
  };
}
