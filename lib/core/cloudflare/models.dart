/// Core Cloudflare resources shared across features. Feature-specific models
/// live next to their feature (`features/<name>/data/`).
library;

DateTime? parseCfDate(Object? v) => v is String && v.isNotEmpty ? DateTime.tryParse(v) : null;

class CfAccount {
  const CfAccount({required this.id, required this.name, this.type});

  factory CfAccount.fromJson(Map<String, dynamic> j) =>
      CfAccount(id: '${j['id']}', name: '${j['name'] ?? j['id']}', type: j['type'] as String?);

  final String id;
  final String name;
  final String? type;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type};

  @override
  bool operator ==(Object other) => other is CfAccount && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum ZoneStatus { active, pending, initializing, moved, deleted, deactivated, unknown }

ZoneStatus parseZoneStatus(Object? s) => switch (s) {
      'active' => ZoneStatus.active,
      'pending' => ZoneStatus.pending,
      'initializing' => ZoneStatus.initializing,
      'moved' => ZoneStatus.moved,
      'deleted' => ZoneStatus.deleted,
      'deactivated' => ZoneStatus.deactivated,
      _ => ZoneStatus.unknown,
    };

/// A domain ("zone"), tagged with the stored tokens that listed it.
class Zone {
  const Zone({
    required this.id,
    required this.name,
    required this.status,
    required this.paused,
    required this.account,
    required this.reach,
    this.planName,
    this.type,
    this.nameServers = const [],
    this.originalNameServers = const [],
    this.originalRegistrar,
    this.createdOn,
    this.activatedOn,
    this.developmentMode = 0,
  });

  factory Zone.fromJson(Map<String, dynamic> j, {required List<String> reach}) => Zone(
        id: '${j['id']}',
        name: '${j['name']}',
        status: parseZoneStatus(j['status']),
        paused: j['paused'] == true,
        account: CfAccount.fromJson(j['account'] as Map<String, dynamic>),
        reach: reach,
        planName: (j['plan'] as Map<String, dynamic>?)?['name'] as String?,
        type: j['type'] as String?,
        nameServers: (j['name_servers'] as List?)?.map((e) => '$e').toList() ?? const [],
        originalNameServers: (j['original_name_servers'] as List?)?.map((e) => '$e').toList() ?? const [],
        originalRegistrar: j['original_registrar'] as String?,
        createdOn: parseCfDate(j['created_on']),
        activatedOn: parseCfDate(j['activated_on']),
        developmentMode: (j['development_mode'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String name;
  final ZoneStatus status;
  final bool paused;
  final CfAccount account;

  /// Ids of the stored tokens that listed this zone (a token can be limited
  /// to some zones).
  final List<String> reach;
  final String? planName;
  final String? type;
  final List<String> nameServers;
  final List<String> originalNameServers;
  final String? originalRegistrar;
  final DateTime? createdOn;
  final DateTime? activatedOn;

  /// Seconds left in development mode (negative or zero when off).
  final int developmentMode;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'status': status.name,
        'paused': paused,
        'account': account.toJson(),
        'plan': {'name': planName},
        'type': type,
        'name_servers': nameServers,
        'original_name_servers': originalNameServers,
        'original_registrar': originalRegistrar,
        'created_on': createdOn?.toIso8601String(),
        'activated_on': activatedOn?.toIso8601String(),
        'development_mode': developmentMode,
        'reach': reach,
      };

  static Zone fromCache(Map<String, dynamic> j) => Zone.fromJson(j, reach: (j['reach'] as List).cast<String>());

  /// Same zone, listed by one more token.
  Zone reachedBy(String tokenId) => reach.contains(tokenId) ? this : Zone.fromCache({...toJson(), 'reach': [...reach, tokenId]});
}
