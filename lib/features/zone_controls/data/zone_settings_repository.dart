import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/cf_errors.dart';
import '../../../core/cloudflare/models.dart';

/// Zone setting ids this feature reads and writes, one request each.
///
/// The bulk `GET/PATCH /zones/{id}/settings` endpoint is deprecated (EOL
/// 2027-03-31), so every setting goes through its own endpoint:
/// https://developers.cloudflare.com/fundamentals/api/reference/deprecations/
/// https://developers.cloudflare.com/api/resources/zones/subresources/settings/methods/edit/
abstract final class SettingId {
  static const ssl = 'ssl';
  static const alwaysUseHttps = 'always_use_https';
  static const httpsRewrites = 'automatic_https_rewrites';
  static const minTls = 'min_tls_version';
  static const tls13 = 'tls_1_3';
  static const devMode = 'development_mode';
  static const securityLevel = 'security_level';

  static const all = [ssl, alwaysUseHttps, httpsRewrites, minTls, tls13, devMode, securityLevel];
}

/// Allowed values, as listed in the zone settings reference.
abstract final class SettingValues {
  static const ssl = ['off', 'flexible', 'full', 'strict'];
  static const minTls = ['1.0', '1.1', '1.2', '1.3'];
  static const tls13 = ['on', 'off', 'zrt'];

  /// `under_attack` is surfaced as its own switch, not in the level picker.
  static const underAttack = 'under_attack';
}

/// One zone setting: `{id, value, editable, modified_on}` plus
/// `time_remaining` for development mode.
class ZoneSetting {
  const ZoneSetting({
    required this.id,
    required this.value,
    this.editable = true,
    this.modifiedOn,
    this.timeRemaining,
  });

  factory ZoneSetting.fromJson(Map<String, dynamic> j) => ZoneSetting(
        id: '${j['id']}',
        value: j['value'],
        editable: j['editable'] != false,
        modifiedOn: parseCfDate(j['modified_on']),
        // Positive: seconds until dev mode ends; negative: since it ended;
        // `false` when it was never enabled.
        timeRemaining: j['time_remaining'] is num ? (j['time_remaining'] as num).toInt() : null,
      );

  final String id;
  final Object? value;
  final bool editable;
  final DateTime? modifiedOn;
  final int? timeRemaining;

  /// `"on"`/`"off"` settings.
  bool get isOn => value == 'on';
  String get text => value == null ? '' : '$value';

  ZoneSetting copyWith({Object? value, int? timeRemaining, bool clearTime = false}) => ZoneSetting(
        id: id,
        value: value ?? this.value,
        editable: editable,
        modifiedOn: modifiedOn,
        timeRemaining: clearTime ? null : (timeRemaining ?? this.timeRemaining),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'value': value,
        'editable': editable,
        'modified_on': modifiedOn?.toIso8601String(),
        'time_remaining': timeRemaining,
      };
}

/// A setting that couldn't be read, with the reason to show beside it.
class SettingIssue {
  const SettingIssue(this.message, {this.permission = false});

  factory SettingIssue.from(Object error) => switch (error) {
        CfApiException e => SettingIssue(e.message, permission: e.isPermissionDenied),
        CfException e => SettingIssue(e.message),
        _ => const SettingIssue(''),
      };

  factory SettingIssue.fromJson(Map<String, dynamic> j) =>
      SettingIssue('${j['message'] ?? ''}', permission: j['permission'] == true);

  final String message;
  final bool permission;

  Map<String, dynamic> toJson() => {'message': message, 'permission': permission};
}

/// DNSSEC state of a zone (`GET /zones/{id}/dnssec`), read-only here.
/// https://developers.cloudflare.com/api/resources/dns/subresources/dnssec/methods/get/
class DnssecInfo {
  const DnssecInfo({
    required this.status,
    this.ds,
    this.digest,
    this.digestType,
    this.digestAlgorithm,
    this.algorithm,
    this.keyTag,
    this.keyType,
    this.flags,
    this.publicKey,
    this.modifiedOn,
  });

  factory DnssecInfo.fromJson(Map<String, dynamic> j) => DnssecInfo(
        status: '${j['status'] ?? 'disabled'}',
        ds: j['ds'] as String?,
        digest: j['digest'] as String?,
        digestType: j['digest_type']?.toString(),
        digestAlgorithm: j['digest_algorithm'] as String?,
        algorithm: j['algorithm']?.toString(),
        keyTag: (j['key_tag'] as num?)?.toInt(),
        keyType: j['key_type'] as String?,
        flags: (j['flags'] as num?)?.toInt(),
        publicKey: j['public_key'] as String?,
        modifiedOn: parseCfDate(j['modified_on']),
      );

  /// `active`, `pending`, `disabled`, `pending-disabled` or `error`.
  final String status;
  final String? ds;
  final String? digest;
  final String? digestType;
  final String? digestAlgorithm;
  final String? algorithm;
  final int? keyTag;
  final String? keyType;
  final int? flags;
  final String? publicKey;
  final DateTime? modifiedOn;

  bool get hasRecord => ds != null && ds!.isNotEmpty;
}

/// Reads and writes zone controls through the per-setting endpoints, pauses a
/// zone, purges its cache and reads DNSSEC.
class ZoneSettingsRepository {
  const ZoneSettingsRepository(this.client);
  final CfClient client;

  /// Purge requests accept at most 100 URLs on Free, Pro and Business (500 on
  /// Enterprise); 100 is safe on every plan.
  /// https://developers.cloudflare.com/cache/how-to/purge-cache/
  static const maxFilesPerPurge = 100;

  Future<ZoneSetting> get(String zoneId, String settingId) async {
    final res = await client.get('/zones/$zoneId/settings/$settingId');
    return ZoneSetting.fromJson(res.map);
  }

  Future<ZoneSetting> set(String zoneId, String settingId, Object value) async {
    final res = await client.patch('/zones/$zoneId/settings/$settingId', data: {'value': value});
    return ZoneSetting.fromJson(res.map);
  }

  /// Loads [ids] in parallel. Each setting succeeds or fails on its own, so
  /// one plan-restricted setting never hides the others.
  Future<({Map<String, ZoneSetting> settings, Map<String, Object> errors})> getMany(
    String zoneId, [
    List<String> ids = SettingId.all,
  ]) async {
    final settings = <String, ZoneSetting>{};
    final errors = <String, Object>{};
    await Future.wait([
      for (final id in ids)
        get(zoneId, id).then((s) => settings[id] = s).catchError((Object e) {
          errors[id] = e;
          return ZoneSetting(id: id, value: null);
        }),
    ]);
    return (settings: settings, errors: errors);
  }

  /// `PATCH /zones/{id}` with `{paused}`. Returns the updated zone.
  /// https://developers.cloudflare.com/api/resources/zones/methods/edit/
  Future<Zone> setPaused(Zone zone, bool paused) async {
    final res = await client.patch('/zones/${zone.id}', data: {'paused': paused});
    // The result is the full zone; layering it over the known zone keeps the
    // account and plan even if a field is missing from the response.
    return Zone.fromJson({...zone.toJson(), ...res.map}, reach: zone.reach);
  }

  /// `POST /zones/{id}/purge_cache` with `{"purge_everything": true}`.
  /// https://developers.cloudflare.com/api/resources/cache/methods/purge/
  Future<void> purgeEverything(String zoneId) async {
    await client.post('/zones/$zoneId/purge_cache', data: {'purge_everything': true});
  }

  /// Purges [urls] in requests of at most [maxFilesPerPurge]. Returns how many
  /// URLs were accepted before any failure; rethrows the failure.
  Future<int> purgeFiles(String zoneId, List<String> urls, {void Function(int done)? onProgress}) async {
    var done = 0;
    for (final chunk in chunked(urls, maxFilesPerPurge)) {
      await client.post('/zones/$zoneId/purge_cache', data: {'files': chunk});
      done += chunk.length;
      onProgress?.call(done);
    }
    return done;
  }

  Future<DnssecInfo> dnssec(String zoneId) async {
    final res = await client.get('/zones/$zoneId/dnssec');
    return DnssecInfo.fromJson(res.map);
  }
}

/// Splits [items] into consecutive lists of at most [size].
List<List<T>> chunked<T>(List<T> items, int size) => [
      for (var i = 0; i < items.length; i += size)
        items.sublist(i, i + size > items.length ? items.length : i + size),
    ];
