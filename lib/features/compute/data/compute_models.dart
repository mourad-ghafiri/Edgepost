/// Workers and Pages resources, parsed from the Cloudflare v4 API.
///
/// Every model's `toJson` writes the same keys the API uses, so the on-device
/// cache round-trips through `fromJson`. Secret values and Pages environment
/// variables are never parsed or cached.
library;

import '../../../core/cloudflare/models.dart' show parseCfDate;

List<String> _strings(Object? v) => v is List ? [for (final e in v) '$e'] : const [];

List<Map<String, dynamic>> _maps(Object? v) =>
    v is List ? v.whereType<Map<String, dynamic>>().toList() : const [];

String? _str(Object? v) => v is String && v.isNotEmpty ? v : null;

// ---------------------------------------------------------------------------
// Workers
// ---------------------------------------------------------------------------

/// A route attached to a Worker (`pattern` → `script`).
class WorkerRoute {
  const WorkerRoute({required this.id, required this.pattern, this.script});

  factory WorkerRoute.fromJson(Map<String, dynamic> j) =>
      WorkerRoute(id: '${j['id'] ?? ''}', pattern: '${j['pattern'] ?? ''}', script: _str(j['script']));

  final String id;
  final String pattern;
  final String? script;

  Map<String, dynamic> toJson() => {'id': id, 'pattern': pattern, 'script': script};
}

/// One Worker script, from `GET /accounts/{account_id}/workers/scripts`
/// (https://developers.cloudflare.com/api/resources/workers/subresources/scripts/methods/list/).
class WorkerScriptInfo {
  const WorkerScriptInfo({
    required this.name,
    this.createdOn,
    this.modifiedOn,
    this.compatibilityDate,
    this.compatibilityFlags = const [],
    this.usageModel,
    this.routes = const [],
    this.handlers = const [],
    this.hasAssets = false,
    this.lastDeployedFrom,
  });

  factory WorkerScriptInfo.fromJson(Map<String, dynamic> j) => WorkerScriptInfo(
        name: '${j['id'] ?? ''}',
        createdOn: parseCfDate(j['created_on']),
        modifiedOn: parseCfDate(j['modified_on']),
        compatibilityDate: _str(j['compatibility_date']),
        compatibilityFlags: _strings(j['compatibility_flags']),
        usageModel: _str(j['usage_model']),
        routes: _maps(j['routes']).map(WorkerRoute.fromJson).toList(),
        handlers: _strings(j['handlers']),
        hasAssets: j['has_assets'] == true,
        lastDeployedFrom: _str(j['last_deployed_from']),
      );

  final String name;
  final DateTime? createdOn;
  final DateTime? modifiedOn;
  final String? compatibilityDate;
  final List<String> compatibilityFlags;
  final String? usageModel;
  final List<WorkerRoute> routes;
  final List<String> handlers;
  final bool hasAssets;
  final String? lastDeployedFrom;

  Map<String, dynamic> toJson() => {
        'id': name,
        'created_on': createdOn?.toIso8601String(),
        'modified_on': modifiedOn?.toIso8601String(),
        'compatibility_date': compatibilityDate,
        'compatibility_flags': compatibilityFlags,
        'usage_model': usageModel,
        'routes': routes.map((r) => r.toJson()).toList(),
        'handlers': handlers,
        'has_assets': hasAssets,
        'last_deployed_from': lastDeployedFrom,
      };
}

/// Runtime settings of a script, from
/// `GET /accounts/{account_id}/workers/scripts/{script_name}/settings`.
class WorkerSettings {
  const WorkerSettings({this.compatibilityDate, this.compatibilityFlags = const [], this.usageModel, this.logpush});

  factory WorkerSettings.fromJson(Map<String, dynamic> j) => WorkerSettings(
        compatibilityDate: _str(j['compatibility_date']),
        compatibilityFlags: _strings(j['compatibility_flags']),
        usageModel: _str(j['usage_model']),
        logpush: j['logpush'] is bool ? j['logpush'] as bool : null,
      );

  final String? compatibilityDate;
  final List<String> compatibilityFlags;
  final String? usageModel;
  final bool? logpush;

  Map<String, dynamic> toJson() => {
        'compatibility_date': compatibilityDate,
        'compatibility_flags': compatibilityFlags,
        'usage_model': usageModel,
        'logpush': logpush,
      };
}

/// workers.dev availability of one script
/// (`GET .../scripts/{script_name}/subdomain` → `{enabled, previews_enabled}`).
class WorkerSubdomain {
  const WorkerSubdomain({required this.enabled, required this.previewsEnabled});

  factory WorkerSubdomain.fromJson(Map<String, dynamic> j) =>
      WorkerSubdomain(enabled: j['enabled'] == true, previewsEnabled: j['previews_enabled'] == true);

  final bool enabled;
  final bool previewsEnabled;

  Map<String, dynamic> toJson() => {'enabled': enabled, 'previews_enabled': previewsEnabled};
}

/// A Workers custom domain (`GET /accounts/{account_id}/workers/domains`).
class WorkerCustomDomain {
  const WorkerCustomDomain({
    required this.id,
    required this.hostname,
    required this.service,
    this.zoneId,
    this.zoneName,
    this.environment,
  });

  factory WorkerCustomDomain.fromJson(Map<String, dynamic> j) => WorkerCustomDomain(
        id: '${j['id'] ?? ''}',
        hostname: '${j['hostname'] ?? ''}',
        service: '${j['service'] ?? ''}',
        zoneId: _str(j['zone_id']),
        zoneName: _str(j['zone_name']),
        environment: _str(j['environment']),
      );

  final String id;
  final String hostname;
  final String service;
  final String? zoneId;
  final String? zoneName;
  final String? environment;

  Map<String, dynamic> toJson() => {
        'id': id,
        'hostname': hostname,
        'service': service,
        'zone_id': zoneId,
        'zone_name': zoneName,
        'environment': environment,
      };
}

/// One version's share of traffic inside a deployment.
class VersionSplit {
  const VersionSplit(this.versionId, this.percentage);

  factory VersionSplit.fromJson(Map<String, dynamic> j) =>
      VersionSplit('${j['version_id'] ?? ''}', (j['percentage'] as num?)?.toDouble() ?? 0);

  final String versionId;
  final double percentage;

  Map<String, dynamic> toJson() => {'version_id': versionId, 'percentage': percentage};
}

/// A Worker deployment (`GET .../scripts/{script_name}/deployments` →
/// `result.deployments`; the first one is the one serving traffic).
/// https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/deployments/
class WorkerDeployment {
  const WorkerDeployment({
    required this.id,
    this.createdOn,
    this.source,
    this.strategy = 'percentage',
    this.versions = const [],
    this.message,
    this.triggeredBy,
    this.authorEmail,
  });

  factory WorkerDeployment.fromJson(Map<String, dynamic> j) {
    final ann = j['annotations'] is Map<String, dynamic> ? j['annotations'] as Map<String, dynamic> : const {};
    return WorkerDeployment(
      id: '${j['id'] ?? ''}',
      createdOn: parseCfDate(j['created_on']),
      source: _str(j['source']),
      strategy: '${j['strategy'] ?? 'percentage'}',
      versions: _maps(j['versions']).map(VersionSplit.fromJson).toList(),
      message: _str(ann['workers/message']),
      triggeredBy: _str(ann['workers/triggered_by']),
      authorEmail: _str(j['author_email']),
    );
  }

  final String id;
  final DateTime? createdOn;
  final String? source;
  final String strategy;
  final List<VersionSplit> versions;
  final String? message;
  final String? triggeredBy;
  final String? authorEmail;

  /// True when this deployment sends 100 % of traffic to [versionId].
  bool servesOnly(String versionId) =>
      versions.length == 1 && versions.first.versionId == versionId && versions.first.percentage >= 100;

  double percentageOf(String versionId) =>
      versions.where((v) => v.versionId == versionId).fold(0, (a, v) => a + v.percentage);

  Map<String, dynamic> toJson() => {
        'id': id,
        'created_on': createdOn?.toIso8601String(),
        'source': source,
        'strategy': strategy,
        'versions': versions.map((v) => v.toJson()).toList(),
        'annotations': {
          'workers/message': ?message,
          'workers/triggered_by': ?triggeredBy,
        },
        'author_email': authorEmail,
      };
}

/// An uploaded Worker version (`GET .../scripts/{script_name}/versions` →
/// `result.items`; the first one is the latest).
class WorkerVersion {
  const WorkerVersion({
    required this.id,
    this.number,
    this.createdOn,
    this.source,
    this.authorEmail,
    this.message,
    this.tag,
    this.triggeredBy,
  });

  factory WorkerVersion.fromJson(Map<String, dynamic> j) {
    final meta = j['metadata'] is Map<String, dynamic> ? j['metadata'] as Map<String, dynamic> : const {};
    final ann = j['annotations'] is Map<String, dynamic> ? j['annotations'] as Map<String, dynamic> : const {};
    return WorkerVersion(
      id: '${j['id'] ?? ''}',
      number: (j['number'] as num?)?.toInt(),
      createdOn: parseCfDate(meta['created_on']),
      source: _str(meta['source']),
      authorEmail: _str(meta['author_email']),
      message: _str(ann['workers/message']),
      tag: _str(ann['workers/tag']),
      triggeredBy: _str(ann['workers/triggered_by']),
    );
  }

  final String id;
  final int? number;
  final DateTime? createdOn;
  final String? source;
  final String? authorEmail;
  final String? message;
  final String? tag;
  final String? triggeredBy;

  /// First block of the version UUID, enough to tell versions apart.
  String get shortId => id.split('-').first;

  Map<String, dynamic> toJson() => {
        'id': id,
        'number': number,
        'metadata': {'created_on': createdOn?.toIso8601String(), 'source': source, 'author_email': authorEmail},
        'annotations': {
          'workers/message': ?message,
          'workers/tag': ?tag,
          'workers/triggered_by': ?triggeredBy,
        },
      };
}

/// A secret bound to a script. Only the name and type are kept: Cloudflare
/// never returns secret values, and the app never stores them.
class WorkerSecret {
  const WorkerSecret({required this.name, required this.type});

  factory WorkerSecret.fromJson(Map<String, dynamic> j) =>
      WorkerSecret(name: '${j['name'] ?? ''}', type: '${j['type'] ?? 'secret_text'}');

  final String name;
  final String type;

  Map<String, dynamic> toJson() => {'name': name, 'type': type};
}

/// The body that rolls a Worker back to one version: a percentage deployment
/// sending 100 % of traffic to [versionId].
/// https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/deployments/methods/create/
Map<String, dynamic> rollbackDeploymentBody(String versionId) => {
      'strategy': 'percentage',
      'versions': [
        {'version_id': versionId, 'percentage': 100},
      ],
    };

// ---------------------------------------------------------------------------
// Pages
// ---------------------------------------------------------------------------

/// Board status of a Pages deployment, derived from `latest_stage`.
enum DeployStatus { success, failed, building, queued, canceled, skipped, unknown }

class PagesStage {
  const PagesStage({required this.name, required this.status, this.startedOn, this.endedOn});

  factory PagesStage.fromJson(Map<String, dynamic> j) => PagesStage(
        name: '${j['name'] ?? ''}',
        status: '${j['status'] ?? ''}',
        startedOn: parseCfDate(j['started_on']),
        endedOn: parseCfDate(j['ended_on']),
      );

  /// queued · initialize · clone_repo · build · deploy
  final String name;

  /// success · idle · active · failure · canceled · skipped
  final String status;
  final DateTime? startedOn;
  final DateTime? endedOn;

  Duration? get duration => startedOn != null && endedOn != null ? endedOn!.difference(startedOn!) : null;

  Map<String, dynamic> toJson() => {
        'name': name,
        'status': status,
        'started_on': startedOn?.toIso8601String(),
        'ended_on': endedOn?.toIso8601String(),
      };
}

/// A Pages deployment (`GET .../pages/projects/{project_name}/deployments`).
/// https://developers.cloudflare.com/api/resources/pages/subresources/projects/subresources/deployments/
class PagesDeployment {
  const PagesDeployment({
    required this.id,
    this.shortId,
    this.url,
    this.environment,
    this.createdOn,
    this.modifiedOn,
    this.latestStage,
    this.stages = const [],
    this.branch,
    this.commitHash,
    this.commitMessage,
    this.commitDirty = false,
    this.triggerType,
    this.aliases = const [],
    this.isSkipped = false,
    this.projectName,
  });

  factory PagesDeployment.fromJson(Map<String, dynamic> j) {
    final trigger = j['deployment_trigger'] is Map<String, dynamic>
        ? j['deployment_trigger'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final meta = trigger['metadata'] is Map<String, dynamic>
        ? trigger['metadata'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final latest = j['latest_stage'];
    return PagesDeployment(
      id: '${j['id'] ?? ''}',
      shortId: _str(j['short_id']),
      url: _str(j['url']),
      environment: _str(j['environment']),
      createdOn: parseCfDate(j['created_on']),
      modifiedOn: parseCfDate(j['modified_on']),
      latestStage: latest is Map<String, dynamic> ? PagesStage.fromJson(latest) : null,
      stages: _maps(j['stages']).map(PagesStage.fromJson).toList(),
      branch: _str(meta['branch']),
      commitHash: _str(meta['commit_hash']),
      commitMessage: _str(meta['commit_message']),
      commitDirty: meta['commit_dirty'] == true,
      triggerType: _str(trigger['type']),
      aliases: _strings(j['aliases']),
      isSkipped: j['is_skipped'] == true,
      projectName: _str(j['project_name']),
    );
  }

  final String id;
  final String? shortId;
  final String? url;

  /// `production` or `preview`.
  final String? environment;
  final DateTime? createdOn;
  final DateTime? modifiedOn;
  final PagesStage? latestStage;
  final List<PagesStage> stages;
  final String? branch;
  final String? commitHash;
  final String? commitMessage;
  final bool commitDirty;
  final String? triggerType;
  final List<String> aliases;
  final bool isSkipped;
  final String? projectName;

  bool get isProduction => environment == 'production';

  /// First line of the commit message, for strips.
  String? get commitTitle {
    final m = commitMessage?.trim();
    if (m == null || m.isEmpty) return null;
    return m.split('\n').first.trim();
  }

  String get displayId => shortId ?? id.split('-').first;

  DeployStatus get status {
    if (isSkipped) return DeployStatus.skipped;
    final s = latestStage;
    if (s == null) return DeployStatus.unknown;
    switch (s.status) {
      case 'failure':
        return DeployStatus.failed;
      case 'canceled':
        return DeployStatus.canceled;
      case 'skipped':
        return DeployStatus.skipped;
      case 'success':
        return s.name == 'deploy' ? DeployStatus.success : DeployStatus.building;
      case 'active':
        return s.name == 'queued' ? DeployStatus.queued : DeployStatus.building;
      case 'idle':
        return s.name == 'queued' ? DeployStatus.queued : DeployStatus.building;
    }
    return DeployStatus.unknown;
  }

  /// When the deployment last changed state (its end time when finished).
  DateTime? get lastActivity => latestStage?.endedOn ?? latestStage?.startedOn ?? modifiedOn ?? createdOn;

  Map<String, dynamic> toJson() => {
        'id': id,
        'short_id': shortId,
        'url': url,
        'environment': environment,
        'created_on': createdOn?.toIso8601String(),
        'modified_on': modifiedOn?.toIso8601String(),
        'latest_stage': latestStage?.toJson(),
        'stages': stages.map((s) => s.toJson()).toList(),
        'deployment_trigger': {
          'type': triggerType,
          'metadata': {
            'branch': branch,
            'commit_hash': commitHash,
            'commit_message': commitMessage,
            'commit_dirty': commitDirty,
          },
        },
        'aliases': aliases,
        'is_skipped': isSkipped,
        'project_name': projectName,
      };
}

/// A Pages project (`GET /accounts/{account_id}/pages/projects`).
/// https://developers.cloudflare.com/api/resources/pages/subresources/projects/
class PagesProjectInfo {
  const PagesProjectInfo({
    required this.name,
    this.subdomain,
    this.domains = const [],
    this.productionBranch,
    this.createdOn,
    this.latestDeployment,
    this.canonicalDeployment,
    this.sourceType,
    this.repoOwner,
    this.repoName,
  });

  factory PagesProjectInfo.fromJson(Map<String, dynamic> j) {
    final source = j['source'] is Map<String, dynamic> ? j['source'] as Map<String, dynamic> : const {};
    final config = source['config'] is Map<String, dynamic> ? source['config'] as Map<String, dynamic> : const {};
    final latest = j['latest_deployment'];
    final canonical = j['canonical_deployment'];
    return PagesProjectInfo(
      name: '${j['name'] ?? ''}',
      subdomain: _str(j['subdomain']),
      domains: _strings(j['domains']),
      productionBranch: _str(j['production_branch']) ?? _str(config['production_branch']),
      createdOn: parseCfDate(j['created_on']),
      latestDeployment: latest is Map<String, dynamic> ? PagesDeployment.fromJson(latest) : null,
      canonicalDeployment: canonical is Map<String, dynamic> ? PagesDeployment.fromJson(canonical) : null,
      sourceType: _str(source['type']),
      repoOwner: _str(config['owner']),
      repoName: _str(config['repo_name']),
    );
  }

  final String name;

  /// `<project>.pages.dev`
  final String? subdomain;
  final List<String> domains;
  final String? productionBranch;
  final DateTime? createdOn;
  final PagesDeployment? latestDeployment;

  /// The deployment currently live on production.
  final PagesDeployment? canonicalDeployment;
  final String? sourceType;
  final String? repoOwner;
  final String? repoName;

  DeployStatus? get latestStatus => latestDeployment?.status;

  Map<String, dynamic> toJson() => {
        'name': name,
        'subdomain': subdomain,
        'domains': domains,
        'production_branch': productionBranch,
        'created_on': createdOn?.toIso8601String(),
        'latest_deployment': latestDeployment?.toJson(),
        'canonical_deployment': canonicalDeployment?.toJson(),
        'source': {
          'type': sourceType,
          'config': {'owner': repoOwner, 'repo_name': repoName},
        },
      };
}

/// A custom domain on a Pages project, with its activation state.
class PagesDomain {
  const PagesDomain({required this.id, required this.name, required this.status, this.errorMessage, this.validationMethod});

  factory PagesDomain.fromJson(Map<String, dynamic> j) {
    final validation = j['validation_data'] is Map<String, dynamic> ? j['validation_data'] as Map<String, dynamic> : const {};
    final verification =
        j['verification_data'] is Map<String, dynamic> ? j['verification_data'] as Map<String, dynamic> : const {};
    return PagesDomain(
      id: '${j['id'] ?? ''}',
      name: '${j['name'] ?? ''}',
      status: '${j['status'] ?? ''}',
      errorMessage: _str(validation['error_message']) ?? _str(verification['error_message']),
      validationMethod: _str(validation['method']),
    );
  }

  final String id;
  final String name;

  /// initializing · pending · active · deactivated · blocked · error
  final String status;
  final String? errorMessage;
  final String? validationMethod;

  bool get active => status == 'active';
  bool get failing => status == 'error' || status == 'blocked' || status == 'deactivated';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status,
        'validation_data': {'error_message': errorMessage, 'method': validationMethod},
      };
}

/// One build-log line (`.../deployments/{id}/history/logs` → `result.data`).
class PagesLogLine {
  const PagesLogLine(this.line, this.ts);

  factory PagesLogLine.fromJson(Map<String, dynamic> j) => PagesLogLine('${j['line'] ?? ''}', parseCfDate(j['ts']));

  final String line;
  final DateTime? ts;

  Map<String, dynamic> toJson() => {'line': line, 'ts': ts?.toIso8601String()};
}

class PagesBuildLog {
  const PagesBuildLog({required this.lines, required this.total, this.includesContainerLogs = false});

  factory PagesBuildLog.fromJson(Map<String, dynamic> j) {
    final lines = _maps(j['data']).map(PagesLogLine.fromJson).toList();
    return PagesBuildLog(
      lines: lines,
      total: (j['total'] as num?)?.toInt() ?? lines.length,
      includesContainerLogs: j['includes_container_logs'] == true,
    );
  }

  final List<PagesLogLine> lines;
  final int total;
  final bool includesContainerLogs;

  Map<String, dynamic> toJson() => {
        'data': lines.map((l) => l.toJson()).toList(),
        'total': total,
        'includes_container_logs': includesContainerLogs,
      };
}
