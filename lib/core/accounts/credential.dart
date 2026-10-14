import '../cloudflare/models.dart';

enum TokenKind { user, account }

/// Outcome of probing one capability.
/// - granted: a read succeeded.
/// - denied: Cloudflare explicitly refused for lack of permission.
/// - notEnabled: the permission is fine but the product isn't turned on for
///   the account yet (e.g. R2 before its one-time subscription checkout).
/// - unknown: the check itself failed (network, rate limit, unexpected answer).
/// Only [denied] hides a feature; everything else is attempted and any real
/// error is explained where it happens.
enum CapState { granted, denied, notEnabled, unknown }

/// One API token: a key to one or more Cloudflare accounts. The token string
/// lives in the keychain; [toJson] never includes it.
class Credential {
  const Credential({
    required this.id,
    required this.label,
    required this.kind,
    required this.accounts,
    required this.addedAt,
    required this.token,
    this.expiresOn,
    this.capabilities = const {},
  });

  factory Credential.fromJson(Map<String, dynamic> j, String token) => Credential(
        id: j['id'] as String,
        label: j['label'] as String,
        kind: TokenKind.values.byName(j['kind'] as String),
        accounts: (j['accounts'] as List).cast<Map<String, dynamic>>().map(CfAccount.fromJson).toList(),
        addedAt: DateTime.parse(j['addedAt'] as String),
        expiresOn: parseCfDate(j['expiresOn']),
        capabilities: {
          for (final a in (j['capabilities'] as Map<String, dynamic>).entries)
            a.key: {
              for (final c in (a.value as Map<String, dynamic>).entries)
                Capability.values.byName(c.key): CapState.values.byName(c.value as String),
            },
        },
        token: token,
      );

  final String id;
  final String label;
  final TokenKind kind;

  /// Accounts this token reaches.
  final List<CfAccount> accounts;
  final DateTime addedAt;
  final DateTime? expiresOn;

  /// Last permission check per account id, per capability. Absent means not
  /// checked yet, which behaves like [CapState.unknown].
  final Map<String, Map<Capability, CapState>> capabilities;
  final String token;

  bool reaches(String accountId) => accounts.any((a) => a.id == accountId);

  CapState stateOf(String accountId, Capability c) => capabilities[accountId]?[c] ?? CapState.unknown;

  /// Soft gate: a feature is attempted unless the permission was explicitly
  /// denied. A failed or inconclusive probe never hides anything.
  bool can(String accountId, Capability c) => stateOf(accountId, c) != CapState.denied;

  Credential copyWith({
    String? label,
    List<CfAccount>? accounts,
    Map<String, Map<Capability, CapState>>? capabilities,
  }) =>
      Credential(
        id: id,
        label: label ?? this.label,
        kind: kind,
        accounts: accounts ?? this.accounts,
        addedAt: addedAt,
        expiresOn: expiresOn,
        capabilities: capabilities ?? this.capabilities,
        token: token,
      );

  /// Same token with a new expiry date (null = never expires).
  Credential withExpiry(DateTime? date) => Credential(
        id: id,
        label: label,
        kind: kind,
        accounts: accounts,
        addedAt: addedAt,
        expiresOn: date,
        capabilities: capabilities,
        token: token,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'kind': kind.name,
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'addedAt': addedAt.toIso8601String(),
        'expiresOn': expiresOn?.toIso8601String(),
        'capabilities': {
          for (final a in capabilities.entries) a.key: {for (final c in a.value.entries) c.key.name: c.value.name},
        },
      };
}

/// Features the app can light up, each tied to the token permission it needs.
/// Probed with one cheap read per capability when a token is added.
enum Capability {
  zones('Zone · Zone · Read'),
  dns('Zone · DNS · Edit'),
  zoneSettings('Zone · Zone Settings · Edit'),
  cachePurge('Zone · Cache Purge · Purge'),
  analytics('Zone · Analytics · Read'),
  emailRouting('Zone · Email Routing Rules · Edit'),
  emailAddresses('Account · Email Routing Addresses · Edit'),
  dmarc('Zone · DMARC Management · Read'),
  workers('Account · Workers Scripts · Edit'),
  workerRoutes('Zone · Workers Routes · Edit'),
  pages('Account · Cloudflare Pages · Edit'),
  d1('Account · D1 · Edit'),
  r2('Account · Workers R2 Storage · Edit'),
  registrar('Account · Registrar · Read'),
  billing('Account · Billing · Read');

  const Capability(this.permission);

  /// Permission as shown in the dashboard's token editor:
  /// https://developers.cloudflare.com/fundamentals/api/reference/permissions/
  final String permission;
}
