import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/accounts/access.dart';
import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/providers.dart';
import '../../registrar/data/registrar_models.dart';
import '../../zones/data/zones_providers.dart';
import 'compute_api.dart';
import 'compute_models.dart';

export '../../registrar/data/registrar_models.dart' show RegistrarDomainInfo, RegistrationStatus;
export 'compute_models.dart';

enum ComputeKind {
  workers(Capability.workers),
  pages(Capability.pages),
  registrar(Capability.registrar);

  const ComputeKind(this.capability);
  final Capability capability;
}

/// Why a kind of resource is missing for the account.
enum GapReason {
  /// No token reaching the account may list it.
  permission,

  /// Only account-owned tokens reach the account; Registrar doesn't accept them
  /// (https://developers.cloudflare.com/fundamentals/api/get-started/account-owned-tokens/).
  userToken,

  /// The list call failed for another reason (network, 5xx…).
  failed,
}

class ComputeGap {
  const ComputeGap({required this.kind, required this.reason, this.message});

  factory ComputeGap.fromJson(Map<String, dynamic> j) => ComputeGap(
        kind: ComputeKind.values.byName(j['kind'] as String),
        reason: GapReason.values.byName(j['reason'] as String),
        message: j['message'] as String?,
      );

  final ComputeKind kind;
  final GapReason reason;
  final String? message;

  Map<String, dynamic> toJson() => {'kind': kind.name, 'reason': reason.name, 'message': message};
}

/// Everything the Compute tab and Today need for one account, one list call
/// per kind: Workers scripts, Pages projects (with their latest deployment)
/// and Registrar registrations.
class ComputeOverview {
  const ComputeOverview({this.workers = const [], this.pages = const [], this.registrar = const [], this.gaps = const []});

  final List<WorkerScriptInfo> workers;
  final List<PagesProjectInfo> pages;
  final List<RegistrarDomainInfo> registrar;
  final List<ComputeGap> gaps;

  ComputeGap? gapFor(ComputeKind kind) {
    for (final g in gaps) {
      if (g.kind == kind) return g;
    }
    return null;
  }

  /// Registrations expiring within 30 days without auto-renew, or lapsed.
  List<RegistrarDomainInfo> registrarAttention({DateTime? now}) =>
      registrar.where((d) => d.needsAttention(now: now)).toList();

  WorkerScriptInfo? worker(String name) {
    for (final w in workers) {
      if (w.name == name) return w;
    }
    return null;
  }

  PagesProjectInfo? project(String name) {
    for (final p in pages) {
      if (p.name == name) return p;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'workers': workers.map((w) => w.toJson()).toList(),
        'pages': pages.map((p) => p.toJson()).toList(),
        'registrar': registrar.map((r) => r.toJson()).toList(),
        'gaps': gaps.map((g) => g.toJson()).toList(),
      };

  factory ComputeOverview.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> l(String k) => (j[k] as List).cast<Map<String, dynamic>>();
    return ComputeOverview(
      workers: l('workers').map(WorkerScriptInfo.fromJson).toList(),
      pages: l('pages').map(PagesProjectInfo.fromJson).toList(),
      registrar: l('registrar').map(RegistrarDomainInfo.fromJson).toList(),
      gaps: l('gaps').map(ComputeGap.fromJson).toList(),
    );
  }
}

final computeOverviewProvider =
    AsyncNotifierProvider.family<ComputeOverviewNotifier, Synced<ComputeOverview>, String>(ComputeOverviewNotifier.new);

class ComputeOverviewNotifier extends SyncedNotifier<ComputeOverview> {
  ComputeOverviewNotifier(this.accountId);
  final String accountId;

  @override
  void prepare() {
    // Rebuild when which token serves each kind changes.
    ref.watch(accessProvider.select((a) => [for (final k in ComputeKind.values) a.account(accountId, k.capability)].join('|')));
  }

  @override
  String get cacheAccount => accountId;

  @override
  String get cacheKey => 'compute';

  @override
  Future<ComputeOverview> fetch() async {
    final access = ref.read(accessProvider);
    final workers = <WorkerScriptInfo>[];
    final pages = <PagesProjectInfo>[];
    final registrar = <RegistrarDomainInfo>[];
    final gaps = <ComputeGap>[];
    final failures = <Object>[];
    var attempted = 0;

    Future<void> run(ComputeKind kind) async {
      final pick = access.account(accountId, kind.capability);
      if (pick is NoAccess) {
        gaps.add(ComputeGap(kind: kind, reason: pick.reason == NoAccessKind.needsUserToken ? GapReason.userToken : GapReason.permission));
        return;
      }
      attempted++;
      final api = ComputeApi(ref.read(cfClientProvider((pick as Granted).token.id)));
      try {
        switch (kind) {
          case ComputeKind.workers:
            workers.addAll(await api.listScripts(accountId));
          case ComputeKind.pages:
            pages.addAll(await api.listProjects(accountId));
          case ComputeKind.registrar:
            registrar.addAll(await api.registrations(accountId));
        }
      } on CfApiException catch (e) {
        if (e.isPermissionDenied) {
          gaps.add(ComputeGap(kind: kind, reason: GapReason.permission, message: e.message));
        } else {
          failures.add(e);
          gaps.add(ComputeGap(kind: kind, reason: GapReason.failed, message: e.message));
        }
      } on CfAuthException {
        rethrow;
      } on CfException catch (e) {
        failures.add(e);
        gaps.add(ComputeGap(kind: kind, reason: GapReason.failed, message: e.message));
      }
    }

    await Future.wait([for (final k in ComputeKind.values) run(k)]);

    // Nothing came back at all: surface the error so cached data stays on
    // screen marked stale instead of being replaced by an empty board.
    if (attempted > 0 && failures.length == attempted) throw failures.first;

    workers.sort((a, b) => a.name.compareTo(b.name));
    pages.sort((a, b) => a.name.compareTo(b.name));
    registrar.sort((a, b) {
      final ea = a.expiresAt, eb = b.expiresAt;
      if (ea == null && eb == null) return a.name.compareTo(b.name);
      if (ea == null) return 1;
      if (eb == null) return -1;
      return ea.compareTo(eb);
    });
    gaps.sort((a, b) => a.kind.index.compareTo(b.kind.index));
    return ComputeOverview(workers: workers, pages: pages, registrar: registrar, gaps: gaps);
  }

  @override
  Object? encode(ComputeOverview data) => data.toJson();

  @override
  ComputeOverview decode(Object? json) => ComputeOverview.fromJson(json as Map<String, dynamic>);
}

// ---------------------------------------------------------------------------
// Detail screens
// ---------------------------------------------------------------------------

/// One section of a detail screen: its value, or why it couldn't load.
/// A section that is neither (restored from cache) shows as pending.
class Part<T> {
  const Part.ok(T this.value) : error = null;
  const Part.failed(Object this.error) : value = null;
  const Part.pending()
      : value = null,
        error = null;

  final T? value;
  final Object? error;

  static Future<Part<T>> guard<T>(Future<T> Function() load) async {
    try {
      return Part.ok(await load());
    } on CfAuthException {
      rethrow;
    } on CfException catch (e) {
      return Part.failed(e);
    }
  }
}

/// Throws when every part failed for the same non-permission reason, so the
/// screen shows one error (or keeps stale data) instead of a page of errors.
void _throwIfAllFailed(List<Part<Object?>> parts) {
  final failed = parts.where((p) => p.error != null).toList();
  if (failed.isEmpty || failed.length != parts.length) return;
  final first = failed.first.error!;
  // Missing permissions are shown section by section, each naming its own.
  if (first is CfApiException && first.isPermissionDenied) return;
  if (first is CfNoAccessException && first.reason == NoAccessKind.denied) return;
  throw first;
}

typedef WorkerKey = ({String accountId, String script});

class WorkerDetail {
  const WorkerDetail({
    required this.settings,
    required this.subdomain,
    required this.accountSubdomain,
    required this.domains,
    required this.deployments,
    required this.versions,
    required this.secrets,
  });

  final Part<WorkerSettings> settings;
  final Part<WorkerSubdomain> subdomain;

  /// `<name>` in `<script>.<name>.workers.dev`; only fetched when enabled.
  final String? accountSubdomain;
  final Part<List<WorkerCustomDomain>> domains;
  final Part<List<WorkerDeployment>> deployments;
  final Part<List<WorkerVersion>> versions;
  final Part<List<WorkerSecret>> secrets;

  WorkerDeployment? get activeDeployment {
    final d = deployments.value;
    return d == null || d.isEmpty ? null : d.first;
  }

  WorkerVersion? versionById(String id) {
    for (final v in versions.value ?? const <WorkerVersion>[]) {
      if (v.id == id) return v;
    }
    return null;
  }

  String? workersDevUrl(String script) {
    final sub = accountSubdomain;
    if (subdomain.value?.enabled != true || sub == null) return null;
    return 'https://$script.$sub.workers.dev';
  }

  Map<String, dynamic> toJson() => {
        'settings': settings.value?.toJson(),
        'subdomain': subdomain.value?.toJson(),
        'account_subdomain': accountSubdomain,
        'domains': domains.value?.map((d) => d.toJson()).toList(),
        'deployments': deployments.value?.map((d) => d.toJson()).toList(),
        'versions': versions.value?.map((v) => v.toJson()).toList(),
        'secrets': secrets.value?.map((s) => s.toJson()).toList(),
      };

  factory WorkerDetail.fromJson(Map<String, dynamic> j) {
    Part<T> obj<T>(String k, T Function(Map<String, dynamic>) f) =>
        j[k] is Map<String, dynamic> ? Part.ok(f(j[k] as Map<String, dynamic>)) : Part<T>.pending();
    Part<List<T>> list<T>(String k, T Function(Map<String, dynamic>) f) => j[k] is List
        ? Part.ok((j[k] as List).cast<Map<String, dynamic>>().map(f).toList())
        : Part<List<T>>.pending();
    return WorkerDetail(
      settings: obj('settings', WorkerSettings.fromJson),
      subdomain: obj('subdomain', WorkerSubdomain.fromJson),
      accountSubdomain: j['account_subdomain'] as String?,
      domains: list('domains', WorkerCustomDomain.fromJson),
      deployments: list('deployments', WorkerDeployment.fromJson),
      versions: list('versions', WorkerVersion.fromJson),
      secrets: list('secrets', WorkerSecret.fromJson),
    );
  }
}

final workerDetailProvider =
    AsyncNotifierProvider.autoDispose.family<WorkerDetailNotifier, Synced<WorkerDetail>, WorkerKey>(
  WorkerDetailNotifier.new,
);

class WorkerDetailNotifier extends SyncedNotifier<WorkerDetail> {
  WorkerDetailNotifier(this.key);
  final WorkerKey key;

  @override
  void prepare() => ref.watch(accessProvider);

  ComputeApi get _api => ComputeApi(ref.accountClient(key.accountId, Capability.workers));

  @override
  String get cacheAccount => key.accountId;

  @override
  String get cacheKey => 'worker:${key.script}';

  @override
  Future<WorkerDetail> fetch() async {
    final api = _api;
    final a = key.accountId, s = key.script;
    final results = await Future.wait<Part<Object?>>([
      Part.guard(() => api.scriptSettings(a, s)),
      Part.guard(() => api.scriptSubdomain(a, s)),
      Part.guard(() => api.customDomains(a, service: s)),
      Part.guard(() => api.deployments(a, s)),
      Part.guard(() => api.versions(a, s)),
      Part.guard(() => api.secrets(a, s)),
    ]);
    _throwIfAllFailed(results);
    final sub = results[1].value as WorkerSubdomain?;
    String? accountSub;
    if (sub?.enabled == true) {
      try {
        accountSub = await api.accountSubdomain(a);
      } on CfApiException {
        accountSub = null;
      }
    }
    Part<T> cast<T>(Part<Object?> p) =>
        p.value != null ? Part<T>.ok(p.value as T) : (p.error != null ? Part<T>.failed(p.error!) : Part<T>.pending());
    return WorkerDetail(
      settings: cast(results[0]),
      subdomain: cast(results[1]),
      accountSubdomain: accountSub,
      domains: cast(results[2]),
      deployments: cast(results[3]),
      versions: cast(results[4]),
      secrets: cast(results[5]),
    );
  }

  /// Rolls back to [versionId] and reloads deployments.
  Future<void> rollbackTo(String versionId, {bool force = false}) async {
    await _api.rollbackTo(key.accountId, key.script, versionId, force: force);
    await refresh();
  }

  @override
  Object? encode(WorkerDetail data) => data.toJson();

  @override
  WorkerDetail decode(Object? json) => WorkerDetail.fromJson(json as Map<String, dynamic>);
}

typedef PagesKey = ({String accountId, String project});

class PagesProjectDetail {
  const PagesProjectDetail({required this.project, required this.deployments, required this.domains});

  final PagesProjectInfo project;
  final List<PagesDeployment> deployments;
  final Part<List<PagesDomain>> domains;

  Map<String, dynamic> toJson() => {
        'project': project.toJson(),
        'deployments': deployments.map((d) => d.toJson()).toList(),
        'domains': domains.value?.map((d) => d.toJson()).toList(),
      };

  factory PagesProjectDetail.fromJson(Map<String, dynamic> j) => PagesProjectDetail(
        project: PagesProjectInfo.fromJson(j['project'] as Map<String, dynamic>),
        deployments: (j['deployments'] as List).cast<Map<String, dynamic>>().map(PagesDeployment.fromJson).toList(),
        domains: j['domains'] is List
            ? Part.ok((j['domains'] as List).cast<Map<String, dynamic>>().map(PagesDomain.fromJson).toList())
            : const Part.pending(),
      );
}

final pagesProjectProvider =
    AsyncNotifierProvider.autoDispose.family<PagesProjectNotifier, Synced<PagesProjectDetail>, PagesKey>(
  PagesProjectNotifier.new,
);

class PagesProjectNotifier extends SyncedNotifier<PagesProjectDetail> {
  PagesProjectNotifier(this.key);
  final PagesKey key;

  @override
  void prepare() => ref.watch(accessProvider);

  ComputeApi get _api => ComputeApi(ref.accountClient(key.accountId, Capability.pages));

  @override
  String get cacheAccount => key.accountId;

  @override
  String get cacheKey => 'pages:${key.project}';

  @override
  Future<PagesProjectDetail> fetch() async {
    final api = _api;
    final projectF = api.project(key.accountId, key.project);
    final deploymentsF = api.deploymentsOf(key.accountId, key.project);
    final domainsF = Part.guard(() => api.projectDomains(key.accountId, key.project));
    return PagesProjectDetail(project: await projectF, deployments: await deploymentsF, domains: await domainsF);
  }

  Future<PagesDeployment> retry(String deploymentId) async {
    final d = await _api.retry(key.accountId, key.project, deploymentId);
    unawaited(refresh());
    return d;
  }

  Future<PagesDeployment> rollback(String deploymentId) async {
    final d = await _api.rollback(key.accountId, key.project, deploymentId);
    unawaited(refresh());
    return d;
  }

  @override
  Object? encode(PagesProjectDetail data) => data.toJson();

  @override
  PagesProjectDetail decode(Object? json) => PagesProjectDetail.fromJson(json as Map<String, dynamic>);
}

typedef PagesDeploymentKey = ({String accountId, String project, String deploymentId});

class PagesDeploymentDetail {
  const PagesDeploymentDetail({required this.deployment, required this.log});

  final PagesDeployment deployment;
  final Part<PagesBuildLog> log;

  Map<String, dynamic> toJson() => {'deployment': deployment.toJson(), 'log': log.value?.toJson()};

  factory PagesDeploymentDetail.fromJson(Map<String, dynamic> j) => PagesDeploymentDetail(
        deployment: PagesDeployment.fromJson(j['deployment'] as Map<String, dynamic>),
        log: j['log'] is Map<String, dynamic>
            ? Part.ok(PagesBuildLog.fromJson(j['log'] as Map<String, dynamic>))
            : const Part.pending(),
      );
}

final pagesDeploymentProvider = AsyncNotifierProvider.autoDispose
    .family<PagesDeploymentNotifier, Synced<PagesDeploymentDetail>, PagesDeploymentKey>(PagesDeploymentNotifier.new);

class PagesDeploymentNotifier extends SyncedNotifier<PagesDeploymentDetail> {
  PagesDeploymentNotifier(this.key);
  final PagesDeploymentKey key;

  @override
  void prepare() => ref.watch(accessProvider);

  @override
  String get cacheAccount => key.accountId;

  @override
  String get cacheKey => 'pages-deploy:${key.project}:${key.deploymentId}';

  @override
  Future<PagesDeploymentDetail> fetch() async {
    final api = ComputeApi(ref.accountClient(key.accountId, Capability.pages));
    final dF = api.deployment(key.accountId, key.project, key.deploymentId);
    final logF = Part.guard(() => api.buildLog(key.accountId, key.project, key.deploymentId));
    return PagesDeploymentDetail(deployment: await dF, log: await logF);
  }

  @override
  Object? encode(PagesDeploymentDetail data) => data.toJson();

  @override
  PagesDeploymentDetail decode(Object? json) => PagesDeploymentDetail.fromJson(json as Map<String, dynamic>);
}

/// Worker routes and Workers custom domains on one zone.
class ZoneCompute {
  const ZoneCompute({required this.routes, required this.domains});

  final Part<List<WorkerRoute>> routes;
  final Part<List<WorkerCustomDomain>> domains;

  Map<String, dynamic> toJson() => {
        'routes': routes.value?.map((r) => r.toJson()).toList(),
        'domains': domains.value?.map((d) => d.toJson()).toList(),
      };

  factory ZoneCompute.fromJson(Map<String, dynamic> j) => ZoneCompute(
        routes: j['routes'] is List
            ? Part.ok((j['routes'] as List).cast<Map<String, dynamic>>().map(WorkerRoute.fromJson).toList())
            : const Part.pending(),
        domains: j['domains'] is List
            ? Part.ok((j['domains'] as List).cast<Map<String, dynamic>>().map(WorkerCustomDomain.fromJson).toList())
            : const Part.pending(),
      );
}

final zoneComputeProvider =
    AsyncNotifierProvider.autoDispose.family<ZoneComputeNotifier, Synced<ZoneCompute>, String>(ZoneComputeNotifier.new);

class ZoneComputeNotifier extends SyncedNotifier<ZoneCompute> {
  ZoneComputeNotifier(this.zoneId);
  final String zoneId;

  Zone? _zone;

  @override
  void prepare() {
    _zone = ref.watch(stableZoneProvider(zoneId));
    ref.watch(accessProvider);
  }

  @override
  String get cacheAccount => _zone?.account.id ?? (throw StateError('Zone $zoneId is not loaded'));

  @override
  String get cacheKey => 'zone-compute:$zoneId';

  @override
  Future<ZoneCompute> fetch() async {
    final zone = _zone;
    if (zone == null) throw StateError('Zone $zoneId is not loaded');
    final routesF = Part.guard(() => ComputeApi(ref.zoneClient(zone, Capability.workerRoutes)).zoneRoutes(zone.id));
    final domainsF = Part.guard(
      () => ComputeApi(ref.accountClient(zone.account.id, Capability.workers)).customDomains(zone.account.id, zoneId: zone.id),
    );
    final result = ZoneCompute(routes: await routesF, domains: await domainsF);
    _throwIfAllFailed([result.routes, result.domains]);
    return result;
  }

  @override
  Object? encode(ZoneCompute data) => data.toJson();

  @override
  ZoneCompute decode(Object? json) => ZoneCompute.fromJson(json as Map<String, dynamic>);
}
