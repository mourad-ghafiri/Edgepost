import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../../zones/data/zones_providers.dart';
import '../data/dns_draft.dart';
import '../data/dns_providers.dart';
import '../data/dns_record.dart';
import 'dns_widgets.dart';

enum DnsTemplate { point, verify }

/// Small forms that write common record sets in one step.
class DnsTemplateScreen extends ConsumerStatefulWidget {
  const DnsTemplateScreen({super.key, required this.zoneId, required this.template});
  final String zoneId;
  final DnsTemplate template;

  @override
  ConsumerState<DnsTemplateScreen> createState() => _DnsTemplateScreenState();
}

class _DnsTemplateScreenState extends ConsumerState<DnsTemplateScreen> {
  final _ip = TextEditingController();
  final _name = TextEditingController(text: '@');
  final _value = TextEditingController();
  bool _www = true;
  bool _proxied = true;
  bool _saving = false;
  bool _ipTouched = false;
  bool _valueTouched = false;

  @override
  void dispose() {
    _ip.dispose();
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  bool get _ipValid => DnsValidators.isIPv4(_ip.text) || DnsValidators.isIPv6(_ip.text);

  /// Records the "Point to an IP" template would create.
  List<Map<String, dynamic>> _pointPosts(Zone zone) => [
    {
      'type': DnsValidators.isIPv6(_ip.text) ? 'AAAA' : 'A',
      'name': zone.name,
      'content': _ip.text.trim(),
      'ttl': DnsTypes.autoTtl,
      'proxied': _proxied,
    },
    if (_www)
      {'type': 'CNAME', 'name': 'www.${zone.name}', 'content': zone.name, 'ttl': DnsTypes.autoTtl, 'proxied': _proxied},
  ];

  /// Address records at the apex (and www) that would clash with the new ones.
  List<DnsRecord> _conflicts(Zone zone, List<DnsRecord> records) {
    final names = {zone.name.toLowerCase(), if (_www) 'www.${zone.name.toLowerCase()}'};
    return records.where((r) => DnsTypes.proxiable.contains(r.type) && names.contains(r.name.toLowerCase())).toList();
  }

  DnsDraft _verifyDraft() => DnsDraft(type: 'TXT')
    ..name = _name.text
    ..content = _value.text
    ..proxied = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final point = widget.template == DnsTemplate.point;
    final title = point ? l.dnsTemplatePointTitle : l.dnsTemplateVerifyTitle;
    final zone = ref.watch(zoneByIdProvider(widget.zoneId));
    final async = ref.watch(dnsRecordsProvider(widget.zoneId));
    if (zone != null && dnsAccessDenied(ref, zone)) {
      return EpPage(
        title: title,
        largeTitle: false,
        previousPageTitle: l.dnsTitle,
        slivers: [EpFill(child: dnsPermissionView(ref, zone))],
      );
    }
    if (zone == null || (point && async.value == null)) {
      return EpPage(
        title: title,
        largeTitle: false,
        previousPageTitle: l.dnsTitle,
        slivers: [
          EpFill(
            child: async.hasError && async.value == null
                ? EpErrorView(
                    error: async.error!,
                    permission: Capability.dns.permission,
                    onRetry: () => ref.invalidate(dnsRecordsProvider(widget.zoneId)),
                  )
                : const EpLoading(),
          ),
        ],
      );
    }
    final records = async.value?.data ?? const <DnsRecord>[];
    final valid = point ? _ipValid : _verifyDraft().isValid(zone.name);
    return EpPage(
      title: title,
      largeTitle: false,
      previousPageTitle: l.dnsTitle,
      actions: [
        EpAction(
          icon: EpIcon.check,
          label: l.actionSave,
          onPressed: valid && !_saving ? () => point ? _applyPoint(zone, records) : _applyVerify(zone) : null,
        ),
      ],
      slivers: [
        if (_saving)
          SliverToBoxAdapter(
            child: isCupertino(context)
                ? const Padding(padding: EdgeInsets.all(EpSpace.sm), child: CupertinoActivityIndicator())
                : const LinearProgressIndicator(minHeight: 2),
          ),
        ...point ? _pointForm(zone, records) : _verifyForm(zone),
      ],
    );
  }

  Widget _intro(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, EpSpace.md),
    child: Text(text, style: TextStyle(color: EpColors.of(context).inkMuted, height: 1.4)),
  );

  Widget _recordTile(Map<String, dynamic> r, Zone zone) => EpTile(
    title: Text(
      '${r['type']}  ${DnsNames.relative('${r['name']}', zone.name)}',
      style: EpType.data(context, size: 15),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
    subtitle: Text(
      '${r['content']}',
      style: EpType.data(context, size: 13, color: EpColors.of(context).inkMuted),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    ),
  );

  List<Widget> _pointForm(Zone zone, List<DnsRecord> records) {
    final l = context.l10n;
    final conflicts = _ipValid ? _conflicts(zone, records) : const <DnsRecord>[];
    return [
      SliverToBoxAdapter(child: _intro(l.dnsTemplatePointIntro(zone.name))),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
          child: EpTextField(
            label: l.dnsTemplateIpLabel,
            controller: _ip,
            placeholder: '203.0.113.10',
            helperText: l.dnsTemplateIpHelper,
            errorText: _ipTouched && _ip.text.trim().isNotEmpty && !_ipValid ? l.dnsTemplateErrorIp : null,
            keyboardType: TextInputType.url,
            monospace: true,
            autocorrect: false,
            enabled: !_saving,
            onChanged: (_) => setState(() => _ipTouched = true),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: EpSection(
          header: l.dnsSectionOptions,
          footer: [
            if (_www) l.dnsTemplateIncludeWwwHelp(zone.name),
            _proxied ? l.dnsProxiedOnHelp : l.dnsProxiedOffHelp,
          ].join(' '),
          children: [
            EpSwitchTile(
              title: l.dnsTemplateIncludeWww,
              value: _www,
              onChanged: _saving ? null : (v) => setState(() => _www = v),
            ),
            EpSwitchTile(
              title: l.dnsFieldProxied,
              value: _proxied,
              onChanged: _saving ? null : (v) => setState(() => _proxied = v),
            ),
          ],
        ),
      ),
      if (_ipValid)
        SliverToBoxAdapter(
          child: EpSection(
            header: l.dnsTemplateCreates,
            children: [for (final r in _pointPosts(zone)) _recordTile(r, zone)],
          ),
        ),
      if (conflicts.isNotEmpty)
        SliverToBoxAdapter(
          child: EpSection(
            header: l.dnsTemplateReplaces,
            footer: l.dnsTemplateReplacesFooter,
            children: [for (final r in conflicts) _recordTile(r.toJson(), zone)],
          ),
        ),
    ];
  }

  List<Widget> _verifyForm(Zone zone) {
    final l = context.l10n;
    final d = _verifyDraft();
    final errors = d.validate(zone.name);
    String? err(DnsField f, bool touched) => touched && errors[f] != null ? dnsErrorText(context, errors[f]!) : null;
    return [
      SliverToBoxAdapter(child: _intro(l.dnsTemplateVerifyIntro(zone.name))),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EpTextField(
                label: l.dnsFieldName,
                controller: _name,
                placeholder: l.dnsNamePlaceholder,
                helperText: l.dnsNameHelper(d.fullName(zone.name)),
                errorText: err(DnsField.name, true),
                keyboardType: TextInputType.url,
                monospace: true,
                autocorrect: false,
                enabled: !_saving,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: EpSpace.md),
              EpTextField(
                label: l.dnsFieldValue,
                controller: _value,
                placeholder: 'google-site-verification=…',
                helperText: l.dnsTemplateVerifyHelper,
                errorText: err(DnsField.content, _valueTouched),
                monospace: true,
                autocorrect: false,
                maxLines: 4,
                minLines: 2,
                enabled: !_saving,
                onChanged: (_) => setState(() => _valueTouched = true),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/domains/${widget.zoneId}/dns');
    }
  }

  Future<void> _applyPoint(Zone zone, List<DnsRecord> records) async {
    final l = context.l10n;
    final conflicts = _conflicts(zone, records);
    if (conflicts.isNotEmpty) {
      final ok = await showEpConfirm(
        context,
        title: l.dnsTemplateReplaceTitle(conflicts.length),
        message: l.dnsTemplateReplaceMessage(zone.name),
        confirmLabel: l.dnsTemplateReplace,
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    await _run(
      () => ref
          .read(dnsRecordsProvider(widget.zoneId).notifier)
          .applyBatch(deletes: [for (final r in conflicts) r.id], posts: _pointPosts(zone)),
    );
  }

  Future<void> _applyVerify(Zone zone) =>
      _run(() => ref.read(dnsRecordsProvider(widget.zoneId).notifier).create(_verifyDraft().toBody(zone.name)));

  Future<void> _run(Future<Object?> Function() action) async {
    final l = context.l10n;
    setState(() => _saving = true);
    try {
      await action();
      if (!mounted) return;
      showEpToast(context, l.dnsTemplateApplied);
      _close();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showEpToast(context, l.dnsSaveFailed(describeError(context, e, permission: Capability.dns.permission)));
    }
  }
}
