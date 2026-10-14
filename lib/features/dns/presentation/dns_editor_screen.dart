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

enum _Ctl { rawType, name, content, priority, service, weight, port, target, flags, value, comment }

/// Creates or edits one record with a form shaped by its type.
class DnsEditorScreen extends ConsumerStatefulWidget {
  const DnsEditorScreen({
    super.key,
    required this.zoneId,
    this.recordId,
    this.initialType,
    this.initialName,
    this.initialContent,
    this.openedFromList = false,
  });

  final String zoneId;

  /// Null for a new record.
  final String? recordId;
  final String? initialType;
  final String? initialName;
  final String? initialContent;

  /// When true, a delete is handed back to the list, which shows the undo.
  final bool openedFromList;

  @override
  ConsumerState<DnsEditorScreen> createState() => _DnsEditorScreenState();
}

class _DnsEditorScreenState extends ConsumerState<DnsEditorScreen> {
  final Map<_Ctl, TextEditingController> _ctl = {for (final c in _Ctl.values) c: TextEditingController()};
  final Set<DnsField> _touched = {};
  DnsDraft? _draft;
  DnsRecord? _original;
  bool _saving = false;

  bool get _isNew => widget.recordId == null;

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _init(Zone zone, DnsRecord? record) {
    final DnsDraft d;
    if (record != null) {
      d = DnsDraft.fromRecord(record, zone.name);
      _touched.addAll(DnsField.values);
    } else {
      final t = (widget.initialType ?? 'A').trim().toUpperCase();
      d = DnsDraft(type: t.isEmpty ? 'A' : t, other: t.isNotEmpty && !DnsTypes.editable.contains(t))
        ..name = widget.initialName ?? '@'
        ..content = widget.initialContent ?? '';
      // Cloudflare's dashboard proxies new address records by default.
      d.proxied = d.isProxiable;
      if (widget.initialName != null) _touched.add(DnsField.name);
      if (widget.initialContent != null) _touched.add(DnsField.content);
    }
    _draft = d;
    _original = record;
    _ctl[_Ctl.rawType]!.text = d.other ? d.type : '';
    _ctl[_Ctl.name]!.text = d.name;
    _ctl[_Ctl.content]!.text = d.content;
    _ctl[_Ctl.priority]!.text = d.priority;
    _ctl[_Ctl.service]!.text = d.service;
    _ctl[_Ctl.weight]!.text = d.weight;
    _ctl[_Ctl.port]!.text = d.port;
    _ctl[_Ctl.target]!.text = d.target;
    _ctl[_Ctl.flags]!.text = d.flags;
    _ctl[_Ctl.value]!.text = d.value;
    _ctl[_Ctl.comment]!.text = d.comment;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final title = _isNew ? l.dnsEditorNewTitle : l.dnsEditorEditTitle;
    final zone = ref.watch(zoneByIdProvider(widget.zoneId));
    final async = ref.watch(dnsRecordsProvider(widget.zoneId));

    Widget page(Widget child) => EpPage(
      title: title,
      largeTitle: false,
      previousPageTitle: l.dnsTitle,
      slivers: [EpFill(child: child)],
    );

    if (zone == null) return page(const EpLoading());
    if (dnsAccessDenied(ref, zone)) return page(dnsPermissionView(ref, zone));
    if (_draft == null) {
      if (_isNew) {
        _init(zone, null);
      } else {
        final list = async.value?.data;
        if (list == null) {
          if (async.hasError) {
            return page(
              EpErrorView(
                error: async.error!,
                permission: Capability.dns.permission,
                onRetry: () => ref.invalidate(dnsRecordsProvider(widget.zoneId)),
              ),
            );
          }
          return page(const EpLoading());
        }
        final record = list.where((r) => r.id == widget.recordId).firstOrNull;
        if (record == null) {
          return page(
            EpMessage(icon: EpIcon.search, title: l.dnsRecordMissingTitle, message: l.dnsRecordMissingMessage),
          );
        }
        _init(zone, record);
      }
    }

    final d = _draft!;
    final errors = d.validate(zone.name);
    final valid = errors.isEmpty;
    final cupertino = isCupertino(context);

    return EpPage(
      title: title,
      largeTitle: false,
      previousPageTitle: l.dnsTitle,
      actions: [
        EpAction(icon: EpIcon.check, label: l.actionSave, onPressed: valid && !_saving ? () => _save(zone) : null),
      ],
      slivers: [
        if (_saving)
          SliverToBoxAdapter(
            child: cupertino
                ? const Padding(padding: EdgeInsets.all(EpSpace.sm), child: CupertinoActivityIndicator())
                : const LinearProgressIndicator(minHeight: 2),
          ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.dnsSectionRecord,
            footer: d.isTypeChange ? l.dnsTypeChangeNote(d.originalType!) : null,
            children: [
              EpTile(
                title: Text(l.dnsFieldType),
                additionalInfo: Text(d.other ? l.dnsTypeOther : d.normalizedType),
                onTap: _saving ? null : _pickType,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _fields(d, zone, errors)),
          ),
        ),
        SliverToBoxAdapter(
          child: EpSection(
            header: l.dnsSectionOptions,
            // Explanations live in the footer: iOS list rows clip subtitles to one line.
            footer: d.isProxiable ? (d.proxied ? l.dnsProxiedOnFooter : l.dnsProxiedOffHelp) : null,
            children: [
              if (d.isProxiable)
                EpSwitchTile(
                  title: l.dnsFieldProxied,
                  value: d.proxied,
                  onChanged: _saving ? null : (v) => setState(() => d.proxied = v),
                ),
              EpTile(
                title: Text(l.dnsFieldTtl),
                additionalInfo: Text(ttlLabel(context, d.effectiveTtl)),
                onTap: _saving || (d.isProxiable && d.proxied) ? null : _pickTtl,
              ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, 0),
            child: EpTextField(
              label: l.dnsFieldComment,
              controller: _ctl[_Ctl.comment],
              placeholder: l.dnsCommentPlaceholder,
              maxLines: 3,
              minLines: 1,
              enabled: !_saving,
              onChanged: (v) => setState(() => d.comment = v),
            ),
          ),
        ),
        if (!_isNew)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: EpSpace.lg),
              child: EpSection(
                children: [
                  EpTile(
                    leading: EpIconView(EpIcon.trash, color: EpColors.of(context).attention),
                    title: Text(l.dnsDeleteRecord),
                    destructive: true,
                    showChevron: false,
                    onTap: _saving ? null : _delete,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(
    _Ctl ctl,
    String label, {
    DnsField? field,
    Map<DnsField, DnsFieldError> errors = const {},
    required ValueChanged<String> onChanged,
    String? placeholder,
    String? helper,
    TextInputType? keyboard,
    bool monospace = true,
    int maxLines = 1,
    int? minLines,
    bool enabled = true,
  }) {
    final err = field != null && _touched.contains(field) ? errors[field] : null;
    return Padding(
      padding: const EdgeInsets.only(bottom: EpSpace.md),
      child: EpTextField(
        label: label,
        controller: _ctl[ctl],
        placeholder: placeholder,
        helperText: helper,
        errorText: err == null ? null : dnsErrorText(context, err),
        keyboardType: keyboard,
        monospace: monospace,
        autocorrect: false,
        maxLines: maxLines,
        minLines: minLines,
        enabled: enabled && !_saving,
        onChanged: (v) => setState(() {
          onChanged(v);
          if (field != null) _touched.add(field);
        }),
      ),
    );
  }

  Widget _labeled(String label, Widget child, {String? help}) {
    final c = EpColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: EpSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: c.inkMuted, fontWeight: FontWeight.w600),
            ),
          ),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: child),
          if (help != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(help, style: TextStyle(fontSize: 13, color: c.inkMuted)),
            ),
        ],
      ),
    );
  }

  List<Widget> _fields(DnsDraft d, Zone zone, Map<DnsField, DnsFieldError> errors) {
    final l = context.l10n;
    const number = TextInputType.number;
    const host = TextInputType.url;
    final name = _field(
      _Ctl.name,
      l.dnsFieldName,
      field: DnsField.name,
      errors: errors,
      placeholder: l.dnsNamePlaceholder,
      helper: l.dnsNameHelper(d.fullName(zone.name)),
      keyboard: host,
      onChanged: (v) => d.name = v,
    );
    Widget content(
      String label, {
      String? placeholder,
      String? helper,
      TextInputType? keyboard,
      int maxLines = 1,
      int? minLines,
    }) => _field(
      _Ctl.content,
      label,
      field: DnsField.content,
      errors: errors,
      placeholder: placeholder,
      helper: helper,
      keyboard: keyboard,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: (v) => d.content = v,
    );
    Widget u16(_Ctl ctl, DnsField f, String label, ValueChanged<String> set, {String? helper, String? placeholder}) =>
        _field(
          ctl,
          label,
          field: f,
          errors: errors,
          helper: helper,
          placeholder: placeholder,
          keyboard: number,
          monospace: false,
          onChanged: set,
        );
    Widget target(String label, {String? placeholder, String? helper}) => _field(
      _Ctl.target,
      label,
      field: DnsField.target,
      errors: errors,
      placeholder: placeholder,
      helper: helper,
      keyboard: host,
      onChanged: (v) => d.target = v,
    );

    if (d.other) {
      return [
        _field(
          _Ctl.rawType,
          l.dnsFieldTypeRaw,
          field: DnsField.type,
          errors: errors,
          placeholder: 'TLSA',
          monospace: false,
          onChanged: (v) => d.type = v.trim().toUpperCase(),
        ),
        name,
        _field(
          _Ctl.content,
          l.dnsFieldContent,
          field: DnsField.content,
          errors: errors,
          helper: d.keepsData ? l.dnsOtherDataNote : null,
          maxLines: 6,
          minLines: 2,
          enabled: !d.keepsData,
          onChanged: (v) => d.content = v,
        ),
      ];
    }

    final targetHelp = l.dnsTargetHelper(zone.name);
    switch (d.normalizedType) {
      case 'A':
        return [
          name,
          content(
            l.dnsFieldIpv4,
            placeholder: '203.0.113.10',
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ];
      case 'AAAA':
        return [name, content(l.dnsFieldIpv6, placeholder: '2001:db8::1', keyboard: host)];
      case 'CNAME':
        return [name, content(l.dnsFieldTarget, placeholder: 'target.example.net', helper: targetHelp, keyboard: host)];
      case 'NS':
        return [name, content(l.dnsFieldNameserver, placeholder: 'ns1.example.net', keyboard: host)];
      case 'PTR':
        return [name, content(l.dnsFieldPtr, placeholder: 'host.example.net', keyboard: host)];
      case 'MX':
        return [
          name,
          content(l.dnsFieldMailServer, placeholder: 'mx1.example.net', helper: targetHelp, keyboard: host),
          u16(
            _Ctl.priority,
            DnsField.priority,
            l.dnsFieldPriority,
            (v) => d.priority = v,
            helper: l.dnsPriorityHelper,
            placeholder: '10',
          ),
        ];
      case 'TXT':
        return [
          name,
          content(
            l.dnsFieldContent,
            helper: l.dnsTxtHelper(d.content.trim().length),
            keyboard: TextInputType.multiline,
            maxLines: 8,
            minLines: 3,
          ),
        ];
      case 'SRV':
        return [
          _field(
            _Ctl.service,
            l.dnsFieldService,
            field: DnsField.service,
            errors: errors,
            placeholder: '_sip',
            helper: l.dnsServiceHelper,
            onChanged: (v) => d.service = v,
          ),
          _labeled(
            l.dnsFieldProtocol,
            EpSegmented<String>(
              segments: {for (final p in DnsDraft.srvProtocols) p: p.substring(1).toUpperCase()},
              value: d.proto,
              onChanged: (v) => setState(() => d.proto = v),
            ),
          ),
          name,
          u16(
            _Ctl.priority,
            DnsField.priority,
            l.dnsFieldPriority,
            (v) => d.priority = v,
            helper: l.dnsPriorityHelper,
            placeholder: '10',
          ),
          u16(_Ctl.weight, DnsField.weight, l.dnsFieldWeight, (v) => d.weight = v, placeholder: '5'),
          u16(_Ctl.port, DnsField.port, l.dnsFieldPort, (v) => d.port = v, placeholder: '5060'),
          target(l.dnsFieldTarget, placeholder: 'sip.example.net', helper: l.dnsSrvTargetHelper),
        ];
      case 'CAA':
        return [
          name,
          _labeled(
            l.dnsFieldCaaTag,
            EpSegmented<String>(
              segments: {'issue': l.dnsCaaIssue, 'issuewild': l.dnsCaaIssueWild, 'iodef': l.dnsCaaIodef},
              value: DnsDraft.caaTags.contains(d.tag) ? d.tag : 'issue',
              onChanged: (v) => setState(() => d.tag = v),
            ),
            help: l.dnsCaaTagHelp,
          ),
          _field(
            _Ctl.value,
            l.dnsFieldValue,
            field: DnsField.value,
            errors: errors,
            placeholder: d.tag == 'iodef' ? 'mailto:security@example.com' : 'letsencrypt.org',
            keyboard: host,
            onChanged: (v) => d.value = v,
          ),
          _field(
            _Ctl.flags,
            l.dnsFieldFlags,
            field: DnsField.flags,
            errors: errors,
            helper: l.dnsFlagsHelper,
            keyboard: number,
            monospace: false,
            onChanged: (v) => d.flags = v,
          ),
        ];
      case 'HTTPS':
        return [
          name,
          u16(_Ctl.priority, DnsField.priority, l.dnsFieldPriority, (v) => d.priority = v, placeholder: '1'),
          target(l.dnsFieldTarget, placeholder: '.', helper: targetHelp),
          _field(
            _Ctl.value,
            l.dnsFieldHttpsValue,
            field: DnsField.value,
            errors: errors,
            placeholder: 'alpn="h3,h2"',
            helper: l.dnsHttpsValueHelper,
            onChanged: (v) => d.value = v,
          ),
        ];
      case 'URI':
        return [
          name,
          u16(
            _Ctl.priority,
            DnsField.priority,
            l.dnsFieldPriority,
            (v) => d.priority = v,
            helper: l.dnsPriorityHelper,
            placeholder: '10',
          ),
          u16(_Ctl.weight, DnsField.weight, l.dnsFieldWeight, (v) => d.weight = v, placeholder: '1'),
          target(l.dnsFieldUri, placeholder: 'https://example.com/'),
        ];
    }
    return [name];
  }

  Future<void> _pickType() async {
    final l = context.l10n;
    final d = _draft!;
    final v = await showDnsChoice<String>(
      context,
      title: l.dnsChooseType,
      options: [for (final t in DnsTypes.editable) (t, t), ('', l.dnsTypeOther)],
      selected: d.other ? '' : d.normalizedType,
    );
    if (v == null || !mounted) return;
    setState(() {
      if (v.isEmpty) {
        if (!d.other) {
          d.other = true;
          d.type = _ctl[_Ctl.rawType]!.text.trim().toUpperCase();
        }
      } else {
        final wasProxiable = d.isProxiable;
        d
          ..other = false
          ..type = v;
        if (_isNew && d.isProxiable && !wasProxiable) d.proxied = true;
      }
    });
  }

  Future<void> _pickTtl() async {
    final d = _draft!;
    final options = [...DnsTypes.ttlPresets];
    if (!options.contains(d.ttl)) options.add(d.ttl);
    final v = await showDnsChoice<int>(
      context,
      title: context.l10n.dnsChooseTtl,
      options: [for (final t in options) (t, ttlLabel(context, t))],
      selected: d.ttl,
    );
    if (v != null && mounted) setState(() => d.ttl = v);
  }

  void _close() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/domains/${widget.zoneId}/dns');
    }
  }

  Future<void> _save(Zone zone) async {
    final l = context.l10n;
    final d = _draft!;
    if (!d.isValid(zone.name)) return;
    setState(() => _saving = true);
    final notifier = ref.read(dnsRecordsProvider(widget.zoneId).notifier);
    try {
      final original = _original;
      if (original == null) {
        await notifier.create(d.toBody(zone.name));
      } else {
        await notifier.save(original, d.toBody(zone.name, clearComment: original.comment != null));
      }
      if (!mounted) return;
      showEpToast(context, original == null ? l.dnsCreated : l.dnsSaved);
      _close();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showEpToast(context, l.dnsSaveFailed(describeError(context, e, permission: Capability.dns.permission)));
    }
  }

  Future<void> _delete() async {
    final l = context.l10n;
    final r = _original;
    if (r == null) return;
    final ok = await showEpConfirm(
      context,
      title: l.dnsDeleteTitle,
      message: l.dnsDeleteMessage(r.type, r.name),
      confirmLabel: l.actionDelete,
      destructive: true,
    );
    if (!ok || !mounted) return;
    if (widget.openedFromList && context.canPop()) {
      context.pop(DnsEditorResult.delete(r));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(dnsRecordsProvider(widget.zoneId).notifier).delete(r);
      if (!mounted) return;
      showEpToast(context, l.dnsDeleted);
      _close();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showEpToast(context, l.dnsDeleteFailed(describeError(context, e, permission: Capability.dns.permission)));
    }
  }
}
