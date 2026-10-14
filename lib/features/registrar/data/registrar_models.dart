import '../../../core/cloudflare/models.dart' show parseCfDate;

/// Lifecycle of a Cloudflare Registrar registration, as reported by
/// `GET /accounts/{account_id}/registrar/registrations`
/// (https://developers.cloudflare.com/api/resources/registrar/subresources/registrations/methods/list/).
enum RegistrationStatus {
  active,
  registrationPending,
  transferPending,
  expired,
  suspended,
  redemptionPeriod,
  pendingDelete,
  unknown;

  static RegistrationStatus parse(Object? v) => switch (v) {
        'active' => active,
        'registration_pending' => registrationPending,
        'transfer_pending' => transferPending,
        'expired' => expired,
        'suspended' => suspended,
        'redemption_period' => redemptionPeriod,
        'pending_delete' => pendingDelete,
        _ => unknown,
      };

  String get wire => switch (this) {
        active => 'active',
        registrationPending => 'registration_pending',
        transferPending => 'transfer_pending',
        expired => 'expired',
        suspended => 'suspended',
        redemptionPeriod => 'redemption_period',
        pendingDelete => 'pending_delete',
        unknown => 'unknown',
      };

  /// The domain is lost or about to be lost regardless of its expiry date.
  bool get critical => this == expired || this == redemptionPeriod || this == pendingDelete || this == suspended;
}

/// A domain registered with Cloudflare Registrar.
class RegistrarDomainInfo {
  const RegistrarDomainInfo({
    required this.name,
    this.expiresAt,
    this.autoRenew = false,
    this.locked = false,
    this.status = RegistrationStatus.unknown,
    this.privacyMode,
    this.createdAt,
  });

  factory RegistrarDomainInfo.fromJson(Map<String, dynamic> j) => RegistrarDomainInfo(
        name: '${j['domain_name']}',
        expiresAt: parseCfDate(j['expires_at']),
        autoRenew: j['auto_renew'] == true,
        locked: j['locked'] == true,
        status: RegistrationStatus.parse(j['status']),
        privacyMode: j['privacy_mode'] as String?,
        createdAt: parseCfDate(j['created_at']),
      );

  final String name;
  final DateTime? expiresAt;
  final bool autoRenew;
  final bool locked;
  final RegistrationStatus status;
  final String? privacyMode;
  final DateTime? createdAt;

  /// Days until [expiresAt] (negative once expired), or null when unknown.
  int? daysLeft({DateTime? now}) {
    final e = expiresAt;
    if (e == null) return null;
    return e.difference(now ?? DateTime.now()).inHours ~/ 24;
  }

  /// Cocked on the board: expiring within 30 days without auto-renew, or
  /// already in a losing state.
  bool needsAttention({DateTime? now}) {
    if (status.critical) return true;
    final d = daysLeft(now: now);
    return d != null && d < 30 && !autoRenew;
  }

  Map<String, dynamic> toJson() => {
        'domain_name': name,
        'expires_at': expiresAt?.toIso8601String(),
        'auto_renew': autoRenew,
        'locked': locked,
        'status': status.wire,
        'privacy_mode': privacyMode,
        'created_at': createdAt?.toIso8601String(),
      };
}
