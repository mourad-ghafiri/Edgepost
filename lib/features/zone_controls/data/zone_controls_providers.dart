import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/cloudflare/cf_client.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/providers.dart';
import '../../zones/data/zones_providers.dart';
import 'zone_settings_repository.dart';

/// The zone controls the screen shows, plus the ones that could not be read.
class ZoneControls {
  const ZoneControls({required this.settings, this.issues = const {}, this.levelBeforeAttack});

  factory ZoneControls.fromJson(Map<String, dynamic> j) => ZoneControls(
        settings: {
          for (final e in (j['settings'] as Map<String, dynamic>).entries)
            e.key: ZoneSetting.fromJson(e.value as Map<String, dynamic>),
        },
        issues: {
          for (final e in (j['issues'] as Map<String, dynamic>? ?? const {}).entries)
            e.key: SettingIssue.fromJson(e.value as Map<String, dynamic>),
        },
        levelBeforeAttack: j['level_before_attack'] as String?,
      );

  final Map<String, ZoneSetting> settings;
  final Map<String, SettingIssue> issues;

  /// The security level to restore when Under Attack mode is turned off.
  final String? levelBeforeAttack;

  ZoneSetting? operator [](String id) => settings[id];

  ZoneControls withSetting(ZoneSetting s, {String? levelBeforeAttack}) => ZoneControls(
        settings: {...settings, s.id: s},
        issues: {...issues}..remove(s.id),
        levelBeforeAttack: levelBeforeAttack ?? this.levelBeforeAttack,
      );

  Map<String, dynamic> toJson() => {
        'settings': {for (final e in settings.entries) e.key: e.value.toJson()},
        'issues': {for (final e in issues.entries) e.key: e.value.toJson()},
        'level_before_attack': levelBeforeAttack,
      };
}

/// Zone settings for one zone, cached for an instant first paint and
/// refreshed in the background.
final zoneControlsProvider =
    AsyncNotifierProvider.autoDispose.family<ZoneControlsNotifier, Synced<ZoneControls>, String>(ZoneControlsNotifier.new);

class ZoneControlsNotifier extends SyncedNotifier<ZoneControls> {
  ZoneControlsNotifier(this.zoneId);
  final String zoneId;

  CfClient? _client;
  String? _account;

  @override
  void prepare() {
    // The stable zone: a pause or dev-mode change updates the zone without
    // rebuilding (and refetching) its settings.
    final zone = ref.watch(stableZoneProvider(zoneId));
    _client = zone == null ? null : ref.zoneClient(zone, Capability.zoneSettings);
    _account = zone?.account.id;
  }

  @override
  String get cacheAccount => _account ?? (throw StateError('Zone $zoneId is not loaded'));

  ZoneSettingsRepository get _repo {
    final c = _client;
    if (c == null) throw StateError('Zone $zoneId is not loaded');
    return ZoneSettingsRepository(c);
  }

  @override
  String get cacheKey => 'zone-controls:$zoneId';

  @override
  Future<ZoneControls> fetch() async {
    final r = await _repo.getMany(zoneId);
    if (r.settings.isEmpty && r.errors.isNotEmpty) {
      // Nothing readable: surface the error so the screen can explain it
      // (usually a missing permission).
      throw r.errors.values.first;
    }
    final level = r.settings[SettingId.securityLevel]?.text;
    final previous = state.value?.data.levelBeforeAttack;
    return ZoneControls(
      settings: r.settings,
      issues: {for (final e in r.errors.entries) e.key: SettingIssue.from(e.value)},
      levelBeforeAttack: level != null && level != SettingValues.underAttack ? level : previous,
    );
  }

  @override
  Object? encode(ZoneControls data) => data.toJson();

  @override
  ZoneControls decode(Object? json) => ZoneControls.fromJson(json as Map<String, dynamic>);

  /// Optimistically writes one setting. On failure the previous value comes
  /// back and the error is rethrown for the screen to explain.
  Future<ZoneSetting> apply(String settingId, Object value) async {
    final cur = state.value?.data;
    if (cur == null) throw StateError('Settings not loaded');
    final before = cur[settingId];
    final optimistic = (before ?? ZoneSetting(id: settingId, value: value)).copyWith(value: value);
    final keepLevel = settingId == SettingId.securityLevel && before != null && before.text != SettingValues.underAttack
        ? before.text
        : null;
    _put(cur.withSetting(optimistic, levelBeforeAttack: keepLevel));
    try {
      final saved = await _repo.set(zoneId, settingId, value);
      final now = state.value?.data ?? cur;
      _put(now.withSetting(saved));
      if (settingId == SettingId.devMode) _syncZoneDevMode(saved);
      return saved;
    } on Object {
      final now = state.value?.data ?? cur;
      _put(before == null
          ? ZoneControls(settings: {...now.settings}..remove(settingId), issues: now.issues, levelBeforeAttack: now.levelBeforeAttack)
          : now.withSetting(before));
      rethrow;
    }
  }

  void _put(ZoneControls data) {
    if (!ref.mounted) return;
    setData(data);
  }

  /// Keeps the zone strip's "dev mode" reason in step with the toggle.
  void _syncZoneDevMode(ZoneSetting s) {
    final z = ref.read(zoneByIdProvider(zoneId));
    if (z == null) return;
    final secs = s.isOn ? (s.timeRemaining ?? 3 * 3600) : 0;
    final json = z.toJson()..['development_mode'] = secs;
    ref.read(zonesProvider(z.account.id).notifier).upsert(Zone.fromCache(json));
  }
}

/// DNSSEC status for a zone (read-only).
final dnssecProvider = FutureProvider.autoDispose.family<DnssecInfo, String>((ref, zoneId) async {
  final zone = ref.watch(stableZoneProvider(zoneId));
  if (zone == null) throw StateError('Zone $zoneId is not loaded');
  return ZoneSettingsRepository(ref.zoneClient(zone, Capability.dns)).dnssec(zoneId);
});
