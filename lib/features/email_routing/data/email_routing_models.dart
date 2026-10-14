/// Email Routing resources, shaped after the official API reference:
/// https://developers.cloudflare.com/api/resources/email_routing/
library;

import '../../../core/cloudflare/models.dart';
import '../../../core/mail_worker.dart';

export '../../../core/mail_worker.dart' show kMailWorkerName;

/// Routing rules per domain:
/// https://developers.cloudflare.com/email-service/platform/limits/
const int kMaxRoutingRules = 200;

/// Matcher `value` limit from the rule schema (maxLength 90).
const int kMaxRuleAddressLength = 90;

/// `status` of the Email Routing settings object.
enum RoutingStatus { ready, unconfigured, misconfigured, misconfiguredLocked, unlocked, unknown }

RoutingStatus parseRoutingStatus(Object? s) => switch (s) {
      'ready' => RoutingStatus.ready,
      'unconfigured' => RoutingStatus.unconfigured,
      'misconfigured' => RoutingStatus.misconfigured,
      'misconfigured/locked' => RoutingStatus.misconfiguredLocked,
      'unlocked' => RoutingStatus.unlocked,
      _ => RoutingStatus.unknown,
    };

String? routingStatusWire(RoutingStatus s) => switch (s) {
      RoutingStatus.ready => 'ready',
      RoutingStatus.unconfigured => 'unconfigured',
      RoutingStatus.misconfigured => 'misconfigured',
      RoutingStatus.misconfiguredLocked => 'misconfigured/locked',
      RoutingStatus.unlocked => 'unlocked',
      RoutingStatus.unknown => null,
    };

/// What the status strip says about the domain's routing.
enum RoutingHealth { ready, off, misconfigured, unlocked }

/// `GET /zones/{zone_id}/email/routing`.
class RoutingSettings {
  const RoutingSettings({
    required this.enabled,
    required this.status,
    this.id,
    this.name,
    this.skipWizard,
    this.supportSubaddress,
    this.created,
    this.modified,
  });

  factory RoutingSettings.fromJson(Map<String, dynamic> j) => RoutingSettings(
        id: j['id'] as String?,
        enabled: j['enabled'] == true,
        name: j['name'] as String?,
        status: parseRoutingStatus(j['status']),
        skipWizard: j['skip_wizard'] as bool?,
        supportSubaddress: j['support_subaddress'] as bool?,
        created: parseCfDate(j['created']),
        modified: parseCfDate(j['modified']),
      );

  final String? id;
  final bool enabled;
  final String? name;
  final RoutingStatus status;
  final bool? skipWizard;
  final bool? supportSubaddress;
  final DateTime? created;
  final DateTime? modified;

  RoutingHealth get health {
    if (!enabled) return RoutingHealth.off;
    return switch (status) {
      RoutingStatus.ready => RoutingHealth.ready,
      RoutingStatus.misconfigured || RoutingStatus.misconfiguredLocked => RoutingHealth.misconfigured,
      RoutingStatus.unlocked => RoutingHealth.unlocked,
      RoutingStatus.unconfigured => RoutingHealth.off,
      // Enabled with a status this build doesn't know: trust `enabled`.
      RoutingStatus.unknown => RoutingHealth.ready,
    };
  }

  /// Records are locked while routing is on, except after an explicit unlock.
  bool get recordsLocked => enabled && status != RoutingStatus.unlocked && status != RoutingStatus.misconfigured;

  Map<String, dynamic> toJson() => {
        'id': id,
        'enabled': enabled,
        'name': name,
        'status': routingStatusWire(status),
        'skip_wizard': skipWizard,
        'support_subaddress': supportSubaddress,
        'created': created?.toIso8601String(),
        'modified': modified?.toIso8601String(),
      };
}

enum RuleActionType { forward, worker, drop, unknown }

RuleActionType parseRuleActionType(Object? s) => switch (s) {
      'forward' => RuleActionType.forward,
      'worker' => RuleActionType.worker,
      'drop' => RuleActionType.drop,
      _ => RuleActionType.unknown,
    };

/// `{type, value}`; `value` is currently limited to a single entry.
class RuleAction {
  const RuleAction(this.type, [this.target, String? wireType]) : _wireType = wireType;

  const RuleAction.forward(String address)
      : type = RuleActionType.forward,
        target = address,
        _wireType = null;

  const RuleAction.worker(String script)
      : type = RuleActionType.worker,
        target = script,
        _wireType = null;

  const RuleAction.drop()
      : type = RuleActionType.drop,
        target = null,
        _wireType = null;

  factory RuleAction.fromJson(Map<String, dynamic> j) {
    final values = (j['value'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
    return RuleAction(parseRuleActionType(j['type']), values.isEmpty ? null : values.first, j['type'] as String?);
  }

  final RuleActionType type;

  /// Destination address (forward) or Worker script name (worker).
  final String? target;

  /// The type exactly as Cloudflare sent it, so an action type this build
  /// doesn't know survives a rewrite (e.g. toggling the rule).
  final String? _wireType;

  bool get isMailbox => type == RuleActionType.worker && target == kMailWorkerName;

  Map<String, dynamic> toJson() => {
        'type': switch (type) {
          RuleActionType.forward => 'forward',
          RuleActionType.worker => 'worker',
          RuleActionType.drop => 'drop',
          RuleActionType.unknown => _wireType ?? 'drop',
        },
        if (target != null) 'value': [target],
      };

  @override
  bool operator ==(Object other) => other is RuleAction && other.type == type && other.target == target;

  @override
  int get hashCode => Object.hash(type, target);
}

/// `{type: literal|all, field: to, value}`.
class RuleMatcher {
  const RuleMatcher({required this.type, this.field, this.value});

  const RuleMatcher.to(String address) : this(type: 'literal', field: 'to', value: address);
  const RuleMatcher.all() : this(type: 'all');

  factory RuleMatcher.fromJson(Map<String, dynamic> j) =>
      RuleMatcher(type: '${j['type'] ?? 'literal'}', field: j['field'] as String?, value: j['value'] as String?);

  final String type;
  final String? field;
  final String? value;

  Map<String, dynamic> toJson() => {
        'type': type,
        'field': ?field,
        'value': ?value,
      };
}

/// One address rule or the catch-all.
class RoutingRule {
  const RoutingRule({
    this.id,
    required this.actions,
    required this.matchers,
    this.enabled = true,
    this.name,
    this.priority,
    this.source,
  });

  /// New literal rule for [address].
  factory RoutingRule.forAddress(String address, RuleAction action, {bool enabled = true}) =>
      RoutingRule(actions: [action], matchers: [RuleMatcher.to(address)], enabled: enabled);

  factory RoutingRule.fromJson(Map<String, dynamic> j) => RoutingRule(
        id: (j['id'] ?? j['tag']) as String?,
        actions: (j['actions'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RuleAction.fromJson)
            .toList(),
        matchers: (j['matchers'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(RuleMatcher.fromJson)
            .toList(),
        enabled: j['enabled'] != false,
        name: j['name'] as String?,
        priority: (j['priority'] as num?)?.toInt(),
        source: j['source'] as String?,
      );

  final String? id;
  final List<RuleAction> actions;
  final List<RuleMatcher> matchers;
  final bool enabled;
  final String? name;
  final int? priority;

  /// `api` or `wrangler` (rules a Worker's Wrangler config owns).
  final String? source;

  bool get isCatchAll => matchers.any((m) => m.type == 'all');

  /// Address this rule matches on (`to` literal), or null.
  String? get address {
    for (final m in matchers) {
      if (m.type == 'literal' && (m.field == null || m.field == 'to') && m.value != null) return m.value;
    }
    return null;
  }

  RuleAction? get action => actions.isEmpty ? null : actions.first;

  bool get managedByWrangler => source == 'wrangler';

  RoutingRule copyWith({List<RuleAction>? actions, List<RuleMatcher>? matchers, bool? enabled, String? id}) =>
      RoutingRule(
        id: id ?? this.id,
        actions: actions ?? this.actions,
        matchers: matchers ?? this.matchers,
        enabled: enabled ?? this.enabled,
        name: name,
        priority: priority,
        source: source,
      );

  /// Body for `POST /rules` and `PUT /rules/{id}`. `source` and
  /// `owner_worker_tag` are left out so writes default to `api`.
  Map<String, dynamic> toRequestBody() => {
        'actions': actions.map((a) => a.toJson()).toList(),
        'matchers': matchers.map((m) => m.toJson()).toList(),
        'enabled': enabled,
        if (name != null && name!.isNotEmpty) 'name': name,
        'priority': ?priority,
      };

  Map<String, dynamic> toJson() => {
        'id': id,
        ...toRequestBody(),
        'source': source,
      };
}

/// Account-level destination address. `verified` is null until the owner
/// clicks the link Cloudflare emails.
class DestinationAddress {
  const DestinationAddress({required this.id, required this.email, this.verified, this.created, this.modified});

  factory DestinationAddress.fromJson(Map<String, dynamic> j) => DestinationAddress(
        id: '${j['id'] ?? j['tag']}',
        email: '${j['email']}',
        verified: parseCfDate(j['verified']),
        created: parseCfDate(j['created']),
        modified: parseCfDate(j['modified']),
      );

  final String id;
  final String email;
  final DateTime? verified;
  final DateTime? created;
  final DateTime? modified;

  bool get isVerified => verified != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'verified': verified?.toIso8601String(),
        'created': created?.toIso8601String(),
        'modified': modified?.toIso8601String(),
      };
}

/// A record Email Routing needs (`GET /zones/{zone_id}/email/routing/dns`).
class RoutingDnsRecord {
  const RoutingDnsRecord({required this.type, required this.name, required this.content, this.priority, this.ttl});

  factory RoutingDnsRecord.fromJson(Map<String, dynamic> j) => RoutingDnsRecord(
        type: '${j['type'] ?? ''}',
        name: '${j['name'] ?? ''}',
        content: '${j['content'] ?? ''}',
        priority: (j['priority'] as num?)?.toInt(),
        ttl: (j['ttl'] as num?)?.toInt(),
      );

  final String type;
  final String name;
  final String content;
  final int? priority;
  final int? ttl;

  /// Zone-file style line, for copying.
  String get line => [name, type, ?priority?.toString(), content].join(' ');

  Map<String, dynamic> toJson() => {
        'type': type,
        'name': name,
        'content': content,
        'priority': priority,
        'ttl': ttl,
      };
}

/// Everything the Email screen shows for one zone, fetched and cached together.
class RoutingOverview {
  const RoutingOverview({
    required this.settings,
    required this.rules,
    this.catchAll,
    this.dnsRecords = const [],
  });

  factory RoutingOverview.fromJson(Map<String, dynamic> j) => RoutingOverview(
        settings: RoutingSettings.fromJson(j['settings'] as Map<String, dynamic>),
        rules: (j['rules'] as List).cast<Map<String, dynamic>>().map(RoutingRule.fromJson).toList(),
        catchAll: j['catch_all'] == null ? null : RoutingRule.fromJson(j['catch_all'] as Map<String, dynamic>),
        dnsRecords:
            (j['dns'] as List? ?? const []).cast<Map<String, dynamic>>().map(RoutingDnsRecord.fromJson).toList(),
      );

  final RoutingSettings settings;

  /// Address (literal) rules, catch-all excluded.
  final List<RoutingRule> rules;
  final RoutingRule? catchAll;
  final List<RoutingDnsRecord> dnsRecords;

  RoutingRule? ruleById(String id) {
    for (final r in rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  RoutingOverview copyWith({RoutingSettings? settings, List<RoutingRule>? rules, RoutingRule? catchAll}) =>
      RoutingOverview(
        settings: settings ?? this.settings,
        rules: rules ?? this.rules,
        catchAll: catchAll ?? this.catchAll,
        dnsRecords: dnsRecords,
      );

  Map<String, dynamic> toJson() => {
        'settings': settings.toJson(),
        'rules': rules.map((r) => r.toJson()).toList(),
        'catch_all': catchAll?.toJson(),
        'dns': dnsRecords.map((r) => r.toJson()).toList(),
      };
}

/// Local part rules for a routing address: RFC 5322 atext with single dots,
/// at most 64 characters. Returns null when valid.
enum LocalPartProblem { empty, tooLong, invalid }

LocalPartProblem? validateLocalPart(String local, {required String domain}) {
  final v = local.trim();
  if (v.isEmpty) return LocalPartProblem.empty;
  if (v.length > 64 || v.length + 1 + domain.length > kMaxRuleAddressLength) return LocalPartProblem.tooLong;
  final atext = RegExp(r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*$");
  return atext.hasMatch(v) ? null : LocalPartProblem.invalid;
}

/// Pragmatic check for a destination mailbox: one @, a dotted domain, no spaces.
bool isValidEmail(String email) {
  final v = email.trim();
  if (v.length > kMaxRuleAddressLength) return false;
  return RegExp(r'^[^\s@]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$')
      .hasMatch(v);
}
