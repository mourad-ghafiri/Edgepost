import '../../../core/cloudflare/cf_client.dart';
import '../../registrar/data/registrar_models.dart';
import 'compute_models.dart';

/// Result of `POST .../workers/scripts/{script_name}/tails`.
class TailHandle {
  const TailHandle({required this.id, required this.url, this.expiresAt});

  factory TailHandle.fromJson(Map<String, dynamic> j) => TailHandle(
        id: '${j['id'] ?? ''}',
        url: '${j['url'] ?? ''}',
        expiresAt: j['expires_at'] is String ? DateTime.tryParse(j['expires_at'] as String) : null,
      );

  final String id;

  /// WebSocket URL. It grants access to the live stream, so it is never
  /// logged or persisted.
  final String url;
  final DateTime? expiresAt;

  @override
  String toString() => 'TailHandle($id)';
}

/// Workers, Pages and Registrar calls for one credential. Endpoints follow
/// the official API reference:
/// - https://developers.cloudflare.com/api/resources/workers/subresources/scripts/
/// - https://developers.cloudflare.com/api/resources/pages/subresources/projects/
/// - https://developers.cloudflare.com/api/resources/registrar/subresources/registrations/
class ComputeApi {
  const ComputeApi(this.client);
  final CfClient client;

  static String _seg(String s) => Uri.encodeComponent(s);

  String _script(String accountId, String script) => '/accounts/$accountId/workers/scripts/${_seg(script)}';
  String _project(String accountId, String project) => '/accounts/$accountId/pages/projects/${_seg(project)}';

  // Workers ------------------------------------------------------------------

  Future<List<WorkerScriptInfo>> listScripts(String accountId) async {
    final res = await client.get('/accounts/$accountId/workers/scripts');
    return [
      for (final j in res.list) WorkerScriptInfo.fromJson(j),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<WorkerSettings> scriptSettings(String accountId, String script) async =>
      WorkerSettings.fromJson((await client.get('${_script(accountId, script)}/settings')).map);

  Future<WorkerSubdomain> scriptSubdomain(String accountId, String script) async =>
      WorkerSubdomain.fromJson((await client.get('${_script(accountId, script)}/subdomain')).map);

  /// The account's `<name>.workers.dev` subdomain, or null when none is set.
  Future<String?> accountSubdomain(String accountId) async {
    final r = (await client.get('/accounts/$accountId/workers/subdomain')).map;
    final s = r['subdomain'];
    return s is String && s.isNotEmpty ? s : null;
  }

  Future<List<WorkerCustomDomain>> customDomains(String accountId, {String? service, String? zoneId}) async {
    final res = await client.get('/accounts/$accountId/workers/domains', query: {
      'service': ?service,
      'zone_id': ?zoneId,
    });
    return res.list.map(WorkerCustomDomain.fromJson).toList()..sort((a, b) => a.hostname.compareTo(b.hostname));
  }

  Future<List<WorkerRoute>> zoneRoutes(String zoneId) async {
    final res = await client.get('/zones/$zoneId/workers/routes');
    return res.list.map(WorkerRoute.fromJson).toList()..sort((a, b) => a.pattern.compareTo(b.pattern));
  }

  /// Newest first; the first deployment is the one serving traffic.
  Future<List<WorkerDeployment>> deployments(String accountId, String script) async {
    final res = await client.get('${_script(accountId, script)}/deployments');
    final r = res.result;
    final list = r is Map<String, dynamic> ? r['deployments'] : r;
    return (list is List ? list.whereType<Map<String, dynamic>>() : const <Map<String, dynamic>>[])
        .map(WorkerDeployment.fromJson)
        .toList();
  }

  /// Newest first.
  Future<List<WorkerVersion>> versions(String accountId, String script) async {
    final res = await client.get('${_script(accountId, script)}/versions');
    final r = res.result;
    final list = r is Map<String, dynamic> ? r['items'] : r;
    return (list is List ? list.whereType<Map<String, dynamic>>() : const <Map<String, dynamic>>[])
        .map(WorkerVersion.fromJson)
        .toList();
  }

  Future<List<WorkerSecret>> secrets(String accountId, String script) async {
    final res = await client.get('${_script(accountId, script)}/secrets');
    return res.list.map(WorkerSecret.fromJson).toList()..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Sends 100 % of traffic to [versionId]. [force] overrides Cloudflare's
  /// guard against rolling back past a secret change.
  Future<WorkerDeployment> rollbackTo(String accountId, String script, String versionId, {bool force = false}) async {
    final res = await client.post(
      '${_script(accountId, script)}/deployments',
      data: rollbackDeploymentBody(versionId),
      query: force ? {'force': 'true'} : null,
    );
    return WorkerDeployment.fromJson(res.map);
  }

  /// Opens a tail session. The body mirrors wrangler's filter message with no
  /// filters (https://github.com/cloudflare/workers-sdk/tree/main/packages/wrangler/src/tail).
  Future<TailHandle> startTail(String accountId, String script) async {
    final res = await client.post('${_script(accountId, script)}/tails', data: {'filters': <Object>[]});
    return TailHandle.fromJson(res.map);
  }

  Future<void> deleteTail(String accountId, String script, String tailId) async {
    await client.delete('${_script(accountId, script)}/tails/${_seg(tailId)}');
  }

  // Pages --------------------------------------------------------------------

  Future<List<PagesProjectInfo>> listProjects(String accountId) async {
    final rows = await client.getAll('/accounts/$accountId/pages/projects', perPage: 10, maxPages: 20);
    return [
      for (final j in rows) PagesProjectInfo.fromJson(j),
    ]..sort((a, b) => a.name.compareTo(b.name));
  }

  Future<PagesProjectInfo> project(String accountId, String project) async =>
      PagesProjectInfo.fromJson((await client.get(_project(accountId, project))).map);

  /// The most recent deployments (first page only, newest first).
  Future<List<PagesDeployment>> deploymentsOf(String accountId, String project) async {
    final res = await client.get('${_project(accountId, project)}/deployments');
    return res.list.map(PagesDeployment.fromJson).toList();
  }

  Future<PagesDeployment> deployment(String accountId, String project, String deploymentId) async =>
      PagesDeployment.fromJson(
          (await client.get('${_project(accountId, project)}/deployments/${_seg(deploymentId)}')).map);

  Future<PagesBuildLog> buildLog(String accountId, String project, String deploymentId) async => PagesBuildLog.fromJson(
      (await client.get('${_project(accountId, project)}/deployments/${_seg(deploymentId)}/history/logs')).map);

  Future<List<PagesDomain>> projectDomains(String accountId, String project) async {
    final res = await client.get('${_project(accountId, project)}/domains');
    return res.list.map(PagesDomain.fromJson).toList();
  }

  Future<PagesDeployment> retry(String accountId, String project, String deploymentId) async => PagesDeployment.fromJson(
      (await client.post('${_project(accountId, project)}/deployments/${_seg(deploymentId)}/retry')).map);

  Future<PagesDeployment> rollback(String accountId, String project, String deploymentId) async =>
      PagesDeployment.fromJson(
          (await client.post('${_project(accountId, project)}/deployments/${_seg(deploymentId)}/rollback')).map);

  // Registrar ----------------------------------------------------------------

  /// Registered domains via the current Registrar API (cursor pagination;
  /// an empty `result_info.cursor` ends the list). The older
  /// `/registrar/domains` list reached end of life on 2026-09-27.
  Future<List<RegistrarDomainInfo>> registrations(String accountId) async {
    final out = <RegistrarDomainInfo>[];
    String? cursor;
    for (var i = 0; i < 20; i++) {
      final res = await client.get('/accounts/$accountId/registrar/registrations', query: {
        'per_page': 50,
        'sort_by': 'registry_expires_at',
        'direction': 'asc',
        'cursor': ?cursor,
      });
      for (final j in res.list) {
        out.add(RegistrarDomainInfo.fromJson(j));
      }
      final next = res.resultInfo?.cursor;
      if (next == null || next.isEmpty || res.list.isEmpty) break;
      cursor = next;
    }
    return out;
  }
}
