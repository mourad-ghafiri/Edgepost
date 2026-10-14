import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accounts/clients.dart';
import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../zones/data/zones_providers.dart';
import '../../zones/presentation/zone_strip.dart';
import '../data/purge.dart';
import '../data/zone_controls_providers.dart';
import '../data/zone_settings_repository.dart';
import 'choice_page.dart';

/// Permission needed to pause a zone. Not one of the probed capabilities, so
/// it is named here for the error message.
const kZoneEditPermission = 'Zone · Zone · Edit';

/// Fallback when Under Attack mode is turned off and the earlier level is
/// unknown.
const _defaultSecurityLevel = 'medium';

/// SSL, cache and security controls for one domain.
class ZoneControlsScreen extends ConsumerStatefulWidget {
  const ZoneControlsScreen({super.key, required this.zoneId});
  final String zoneId;

  @override
  ConsumerState<ZoneControlsScreen> createState() => _ZoneControlsScreenState();
}

class _ZoneControlsScreenState extends ConsumerState<ZoneControlsScreen> {
  final Set<String> _saving = {};
  bool _purging = false;
  bool _pausing = false;

  String get _id => widget.zoneId;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final zone = ref.watch(zoneByIdProvider(_id));
    if (zone == null) {
      return EpPage(title: l.controlsTitle, largeTitle: false, slivers: const [EpFill(child: EpLoading())]);
    }
    final controlsAsync = ref.watch(zoneControlsProvider(_id));
    final dnssecAsync = ref.watch(dnssecProvider(_id));
    final synced = controlsAsync.value;
    final ssl = synced?.data[SettingId.ssl]?.text;
    final weakSsl = ssl == 'off' || ssl == 'flexible';

    return EpPage(
      title: l.controlsTitle,
      largeTitle: false,
      previousPageTitle: zone.name,
      subtitle: synced == null ? null : SyncLine(synced: synced),
      onRefresh: _refresh,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.lg, EpSpace.lg, 0),
            child: ZoneStrip(
              zone: zone,
              reason: zoneAttentionReason(context, zone) ??
                  (weakSsl ? l.controlsSslWeakReason(_sslChoices(l).labelOf(ssl)) : null),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: controlsAsync.when(
            loading: () => _loadingSection(l.controlsSectionEncryption),
            error: (e, _) => _errorSection(
              l.controlsSectionEncryption,
              e,
              Capability.zoneSettings.permission,
              () => ref.invalidate(zoneControlsProvider(_id)),
            ),
            data: (s) => _encryption(context, s.data, weakSsl),
          ),
        ),
        SliverToBoxAdapter(child: _cache(context, zone, controlsAsync.value)),
        if (controlsAsync.value != null)
          SliverToBoxAdapter(child: _security(context, zone, controlsAsync.value!.data)),
        SliverToBoxAdapter(child: _cloudflare(context, zone)),
        SliverToBoxAdapter(
          child: dnssecAsync.when(
            loading: () => _loadingSection(l.controlsSectionDnssec),
            error: (e, _) => _errorSection(
              l.controlsSectionDnssec,
              e,
              Capability.dns.permission,
              () => ref.invalidate(dnssecProvider(_id)),
            ),
            data: (d) => _dnssec(context, d),
          ),
        ),
      ],
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _encryption(BuildContext context, ZoneControls s, bool weakSsl) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final ssl = _sslChoices(l);
    final current = s[SettingId.ssl]?.text;
    return EpSection(
      header: l.controlsSectionEncryption,
      footer: weakSsl ? l.controlsSslWeakWarning : null,
      children: [
        _pickerTile(
          context,
          s,
          id: SettingId.ssl,
          title: l.controlsSslMode,
          choices: ssl,
          footer: l.controlsSslWeakWarning,
          detail: current == null
              ? null
              : Text(
                  ssl.detailOf(current) ?? '',
                  style: weakSsl ? TextStyle(color: c.attention, fontWeight: FontWeight.w600) : null,
                ),
        ),
        _switchTile(context, s, SettingId.alwaysUseHttps, l.controlsAlwaysHttps, l.controlsAlwaysHttpsDetail),
        _switchTile(context, s, SettingId.httpsRewrites, l.controlsHttpsRewrites, l.controlsHttpsRewritesDetail),
        _pickerTile(
          context,
          s,
          id: SettingId.minTls,
          title: l.controlsMinTls,
          choices: [
            Choice('1.0', l.controlsMinTlsOption('1.0'), detail: l.controlsMinTls10Detail),
            Choice('1.1', l.controlsMinTlsOption('1.1'), detail: l.controlsMinTls11Detail),
            Choice('1.2', l.controlsMinTlsOption('1.2'), detail: l.controlsMinTls12Detail),
            Choice('1.3', l.controlsMinTlsOption('1.3'), detail: l.controlsMinTls13Detail),
          ],
        ),
        _pickerTile(
          context,
          s,
          id: SettingId.tls13,
          title: l.controlsTls13,
          choices: [
            Choice('on', l.controlsTls13On, detail: l.controlsTls13OnDetail),
            Choice('zrt', l.controlsTls13Zrt, detail: l.controlsTls13ZrtDetail),
            Choice('off', l.controlsTls13Off, detail: l.controlsTls13OffDetail),
          ],
        ),
      ],
    );
  }

  Widget _cache(BuildContext context, Zone zone, Synced<ZoneControls>? synced) {
    final l = context.l10n;
    final dev = synced?.data[SettingId.devMode];
    final issue = synced?.data.issues[SettingId.devMode];
    return EpSection(
      header: l.controlsSectionCache,
      children: [
        EpTile(
          title: Text(l.controlsPurgeEverything),
          subtitle: Text(l.controlsPurgeEverythingDetail),
          destructive: true,
          trailing: _purging ? const _Spinner() : null,
          showChevron: false,
          onTap: _purging ? null : () => _purgeEverything(zone),
        ),
        EpTile(
          title: Text(l.controlsPurgeUrls),
          subtitle: Text(l.controlsPurgeUrlsDetail),
          onTap: () => context.push('/domains/${zone.id}/controls/purge-urls'),
        ),
        if (synced != null)
          _DevModeTile(
            setting: dev,
            syncedAt: synced.syncedAt,
            busy: _saving.contains(SettingId.devMode),
            unavailable: dev == null
                ? _issueText(context, issue)
                : (!dev.editable ? l.controlsNotEditable : null),
            onChanged: dev == null || !dev.editable
                ? null
                : (on) => _apply(SettingId.devMode, on ? 'on' : 'off', l.controlsDevMode),
          ),
      ],
    );
  }

  Widget _security(BuildContext context, Zone zone, ZoneControls s) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final level = s[SettingId.securityLevel];
    final issue = s.issues[SettingId.securityLevel];
    final underAttack = level?.text == SettingValues.underAttack;
    final canEdit = level != null && level.editable;
    final levels = _levelChoices(l);
    final unavailable = level == null ? _issueText(context, issue) : (!level.editable ? l.controlsNotEditable : null);

    return EpSection(
      header: l.controlsSectionSecurity,
      footer: l.controlsSecurityLevelFooter,
      children: [
        EpSwitchTile(
          title: l.controlsUnderAttack,
          subtitle: unavailable ?? l.controlsUnderAttackDetail,
          value: underAttack,
          busy: _saving.contains(SettingId.securityLevel),
          onChanged: canEdit ? (on) => _toggleUnderAttack(zone, on, s) : null,
        ),
        if (underAttack)
          EpTile(
            title: Text(l.controlsSecurityLevel, style: TextStyle(color: c.inkMuted)),
            subtitle: Text(l.controlsSecurityLevelLocked),
            additionalInfo: Text(levels.labelOf(s.levelBeforeAttack ?? _defaultSecurityLevel)),
          )
        else
          _pickerTile(context, s, id: SettingId.securityLevel, title: l.controlsSecurityLevel, choices: levels),
      ],
    );
  }

  Widget _cloudflare(BuildContext context, Zone zone) {
    final l = context.l10n;
    final c = EpColors.of(context);
    return EpSection(
      header: l.controlsSectionCloudflare,
      children: [
        if (zone.paused)
          EpTile(
            leading: EpIconView(EpIcon.play, color: c.tint),
            title: Text(l.controlsResume),
            subtitle: Text(l.controlsResumeDetail),
            showChevron: false,
            trailing: _pausing ? const _Spinner() : null,
            onTap: _pausing ? null : () => _setPaused(zone, false),
          )
        else
          EpTile(
            leading: EpIconView(EpIcon.pause, color: c.attention),
            title: Text(l.controlsPause),
            subtitle: Text(l.controlsPauseDetail),
            destructive: true,
            showChevron: false,
            trailing: _pausing ? const _Spinner() : null,
            onTap: _pausing ? null : () => _setPaused(zone, true),
          ),
      ],
    );
  }

  Widget _dnssec(BuildContext context, DnssecInfo d) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final (label, color, footer) = switch (d.status) {
      'active' => (l.controlsDnssecActive, c.ok, l.controlsDnssecFooterActive),
      'pending' => (l.controlsDnssecPending, c.caution, l.controlsDnssecFooterPending),
      'pending-disabled' => (l.controlsDnssecPendingDisabled, c.caution, l.controlsDnssecFooterDisabled),
      'error' => (l.controlsDnssecError, c.attention, l.controlsDnssecFooterError),
      _ => (l.controlsDnssecDisabled, c.inkMuted, l.controlsDnssecFooterDisabled),
    };
    final showRecord = d.hasRecord && d.status != 'disabled';
    return EpSection(
      header: l.controlsSectionDnssec,
      footer: footer,
      children: [
        EpTile(
          title: Text(l.controlsDnssecStatus),
          additionalInfo: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
        ),
        if (showRecord) ...[
          _copyTile(context, l.controlsDnssecDs, d.ds!),
          if (d.digest != null) _copyTile(context, l.controlsDnssecDigest, d.digest!),
          if (d.keyTag != null) _copyTile(context, l.controlsDnssecKeyTag, '${d.keyTag}'),
          if (d.algorithm != null)
            _copyTile(context, l.controlsDnssecAlgorithm, d.keyType == null ? d.algorithm! : '${d.algorithm} · ${d.keyType}'),
          if (d.digestType != null)
            _copyTile(
              context,
              l.controlsDnssecDigestType,
              d.digestAlgorithm == null ? d.digestType! : '${d.digestType} · ${d.digestAlgorithm}',
            ),
          if (d.publicKey != null) _copyTile(context, l.controlsDnssecPublicKey, d.publicKey!),
        ],
      ],
    );
  }

  // ── Tiles ─────────────────────────────────────────────────────────────────

  Widget _switchTile(BuildContext context, ZoneControls s, String id, String title, String detail) {
    final l = context.l10n;
    final setting = s[id];
    final unavailable = setting == null ? _issueText(context, s.issues[id]) : (!setting.editable ? l.controlsNotEditable : null);
    return EpSwitchTile(
      title: title,
      subtitle: unavailable ?? detail,
      value: setting?.isOn ?? false,
      busy: _saving.contains(id),
      onChanged: setting == null || !setting.editable ? null : (on) => _apply(id, on ? 'on' : 'off', title),
    );
  }

  Widget _pickerTile(
    BuildContext context,
    ZoneControls s, {
    required String id,
    required String title,
    required List<Choice<String>> choices,
    String? footer,
    Widget? detail,
  }) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final setting = s[id];
    final current = setting?.text;
    final saving = _saving.contains(id);
    final unavailable = setting == null ? _issueText(context, s.issues[id]) : (!setting.editable ? l.controlsNotEditable : null);
    final enabled = setting != null && setting.editable && !saving;
    return EpTile(
      title: Text(title, style: enabled || saving ? null : TextStyle(color: c.inkMuted)),
      subtitle: unavailable != null ? Text(unavailable) : detail,
      additionalInfo: saving ? const _Spinner() : Text(current == null ? '—' : choices.labelOf(current)),
      showChevron: enabled,
      onTap: !enabled
          ? null
          : () async {
              final picked = await pushChoicePage<String>(
                context,
                title: title,
                choices: choices,
                selected: current,
                footer: footer,
              );
              if (picked != null && picked != current) await _apply(id, picked, title);
            },
    );
  }

  Widget _copyTile(BuildContext context, String label, String value) {
    final c = EpColors.of(context);
    return EpTile(
      title: Text(label),
      subtitle: Text(value, style: EpType.data(context, size: 13, color: c.ink)),
      trailing: EpIconView(EpIcon.copy, color: c.tint, semanticLabel: context.l10n.controlsCopyValue(label)),
      onTap: () => copyWithToast(context, value),
    );
  }

  Widget _loadingSection(String header) => EpSection(
        header: header,
        children: const [Padding(padding: EdgeInsets.all(EpSpace.xl), child: EpLoading())],
      );

  Widget _errorSection(String header, Object error, String permission, VoidCallback retry) => EpSection(
        header: header,
        children: [
          Padding(
            padding: const EdgeInsets.all(EpSpace.lg),
            child: EpErrorView(error: error, permission: permission, onRetry: retry),
          ),
        ],
      );

  String? _issueText(BuildContext context, SettingIssue? issue) {
    if (issue == null) return null;
    final l = context.l10n;
    if (issue.permission) return l.errorPermission(Capability.zoneSettings.permission);
    return l.controlsUnreadable(issue.message.isEmpty ? l.errorGeneric : issue.message);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    await Future.wait<void>([
      ref.read(zoneControlsProvider(_id).notifier).refresh(),
      ref.refresh(dnssecProvider(_id).future).then((_) {}, onError: (Object _) {}),
    ]);
  }

  Future<void> _apply(String id, Object value, String settingName) async {
    setState(() => _saving.add(id));
    try {
      await ref.read(zoneControlsProvider(_id).notifier).apply(id, value);
    } on Object catch (e) {
      if (mounted) {
        final reason = describeError(context, e, permission: Capability.zoneSettings.permission);
        showEpToast(context, context.l10n.controlsSaveFailed(settingName, reason));
      }
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  Future<void> _toggleUnderAttack(Zone zone, bool on, ZoneControls s) async {
    final l = context.l10n;
    if (on) {
      final ok = await showEpConfirm(
        context,
        title: l.controlsUnderAttackOnTitle,
        message: l.controlsUnderAttackOnMessage(zone.name),
        confirmLabel: l.controlsUnderAttackOnConfirm,
        destructive: true,
      );
      if (!ok || !mounted) return;
      await _apply(SettingId.securityLevel, SettingValues.underAttack, l.controlsUnderAttack);
    } else {
      await _apply(SettingId.securityLevel, s.levelBeforeAttack ?? _defaultSecurityLevel, l.controlsUnderAttack);
    }
  }

  static bool _freePlan(Zone z) => z.planName == null || z.planName!.toLowerCase().contains('free');

  Future<void> _purgeEverything(Zone zone) async {
    final l = context.l10n;
    final cooldown = ref.read(purgeCooldownProvider);
    final free = _freePlan(zone);
    final wait = cooldown.waitFor(zone.account.id);
    if (wait > Duration.zero) {
      showEpToast(context, l.controlsPurgeCooldown((wait.inMilliseconds / 1000).ceil()));
      return;
    }
    final ok = await showEpTypedConfirm(
      context,
      title: l.controlsPurgeEverythingTitle,
      message: l.controlsPurgeEverythingMessage(zone.name),
      expected: zone.name,
      confirmLabel: l.controlsPurgeEverythingConfirm,
    );
    if (!ok || !mounted) return;
    setState(() => _purging = true);
    try {
      await ZoneSettingsRepository(ref.zoneClient(zone, Capability.cachePurge)).purgeEverything(zone.id);
      if (free) cooldown.record(zone.account.id);
      if (mounted) showEpToast(context, l.controlsPurgeEverythingDone(zone.name));
    } on Object catch (e) {
      if (!mounted) return;
      if (isPurgeRateLimited(e)) {
        cooldown.exhaust(zone.account.id);
        showEpToast(context, l.controlsPurgeRateLimited);
      } else {
        showEpToast(context, describeError(context, e, permission: Capability.cachePurge.permission));
      }
    } finally {
      if (mounted) setState(() => _purging = false);
    }
  }

  Future<void> _setPaused(Zone zone, bool pause) async {
    final l = context.l10n;
    final ok = pause
        ? await showEpTypedConfirm(
            context,
            title: l.controlsPauseTitle,
            message: l.controlsPauseMessage(zone.name),
            expected: zone.name,
            confirmLabel: l.controlsPauseConfirm,
          )
        : await showEpConfirm(
            context,
            title: l.controlsResumeTitle(zone.name),
            message: l.controlsResumeMessage,
            confirmLabel: l.controlsResumeConfirm,
          );
    if (!ok || !mounted) return;
    setState(() => _pausing = true);
    try {
      final repo = ZoneSettingsRepository(ref.zoneClient(zone, Capability.zones));
      final updated = await repo.setPaused(zone, pause);
      ref.read(zonesProvider(zone.account.id).notifier).upsert(updated);
      if (mounted) showEpToast(context, pause ? l.controlsPauseDone(zone.name) : l.controlsResumeDone(zone.name));
    } on Object catch (e) {
      if (mounted) showEpToast(context, describeError(context, e, permission: kZoneEditPermission));
    } finally {
      if (mounted) setState(() => _pausing = false);
    }
  }
}

// ── Choices ─────────────────────────────────────────────────────────────────

List<Choice<String>> _sslChoices(AppLocalizations l) => [
      Choice('strict', l.controlsSslStrict, detail: l.controlsSslStrictDetail),
      Choice('full', l.controlsSslFull, detail: l.controlsSslFullDetail),
      Choice('flexible', l.controlsSslFlexible, detail: l.controlsSslFlexibleDetail),
      Choice('off', l.controlsSslOff, detail: l.controlsSslOffDetail),
    ];

List<Choice<String>> _levelChoices(AppLocalizations l) => [
      Choice('high', l.controlsSecurityLevelHigh),
      Choice('medium', l.controlsSecurityLevelMedium),
      Choice('low', l.controlsSecurityLevelLow),
      Choice('essentially_off', l.controlsSecurityLevelEssentiallyOff),
      Choice('off', l.controlsSecurityLevelOff),
    ];

extension on List<Choice<String>> {
  String labelOf(String? value) {
    for (final c in this) {
      if (c.value == value) return c.label;
    }
    return value ?? '—';
  }

  String? detailOf(String value) {
    for (final c in this) {
      if (c.value == value) return c.detail;
    }
    return null;
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator.adaptive(strokeWidth: 2));
}

/// Development mode switch with a live countdown to its automatic end.
class _DevModeTile extends StatefulWidget {
  const _DevModeTile({
    required this.setting,
    required this.syncedAt,
    required this.busy,
    required this.onChanged,
    this.unavailable,
  });

  final ZoneSetting? setting;

  /// When [setting] was read; `time_remaining` counts from here.
  final DateTime syncedAt;
  final bool busy;
  final ValueChanged<bool>? onChanged;
  final String? unavailable;

  @override
  State<_DevModeTile> createState() => _DevModeTileState();
}

class _DevModeTileState extends State<_DevModeTile> {
  Timer? _timer;

  DateTime? get _endsAt {
    final s = widget.setting;
    final left = s?.timeRemaining;
    if (s == null || !s.isOn || left == null || left <= 0) return null;
    return widget.syncedAt.add(Duration(seconds: left));
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _DevModeTile old) {
    super.didUpdateWidget(old);
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_endsAt == null) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      final end = _endsAt;
      if (end == null || !DateTime.now().isBefore(end)) t.cancel();
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final s = widget.setting;
    final end = _endsAt;
    final left = end?.difference(DateTime.now());
    final expired = left != null && left <= Duration.zero;
    final on = (s?.isOn ?? false) && !expired;
    final subtitle = widget.unavailable ??
        (on && left != null ? l.controlsDevModeOnDetail(_fmt(left)) : l.controlsDevModeOffDetail);
    return EpSwitchTile(
      title: l.controlsDevMode,
      subtitle: subtitle,
      value: on,
      busy: widget.busy,
      onChanged: widget.onChanged,
    );
  }
}
