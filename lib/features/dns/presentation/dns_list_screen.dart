import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/accounts/credential.dart';
import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_page.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/cloudflare/models.dart';
import '../../../core/l10n.dart';
import '../../../core/providers.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/sync_line.dart';
import '../../zones/data/zones_providers.dart';
import '../data/dns_providers.dart';
import '../data/dns_record.dart';
import '../data/dns_repository.dart';
import 'dns_widgets.dart';

enum DnsTypeFilter { all, address, cname, mx, txt, other }

enum _More { point, verify, mailCheck, export, import }

enum _RowAction { copyName, copyContent, edit, delete }

/// Every record of one zone, grouped by type.
class DnsListScreen extends ConsumerStatefulWidget {
  const DnsListScreen({super.key, required this.zoneId});
  final String zoneId;

  @override
  ConsumerState<DnsListScreen> createState() => _DnsListScreenState();
}

class _DnsListScreenState extends ConsumerState<DnsListScreen> {
  final _search = TextEditingController();
  DnsTypeFilter _filter = DnsTypeFilter.all;
  bool _busy = false;

  String get _base => '/domains/${widget.zoneId}/dns';
  DnsNotifier get _notifier => ref.read(dnsRecordsProvider(widget.zoneId).notifier);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final zone = ref.watch(zoneByIdProvider(widget.zoneId));
    if (zone == null) {
      final account = ref.watch(activeAccountProvider)?.id;
      final loading = account == null || ref.watch(zonesProvider(account)).isLoading;
      return EpPage(
        title: l.dnsTitle,
        largeTitle: false,
        slivers: [
          EpFill(
            child: loading
                ? const EpLoading()
                : EpMessage(icon: EpIcon.domains, title: l.dnsZoneMissingTitle, message: l.dnsZoneMissingMessage),
          ),
        ],
      );
    }

    if (dnsAccessDenied(ref, zone)) {
      return EpPage(
        title: l.dnsTitle,
        largeTitle: false,
        previousPageTitle: zone.name,
        slivers: [EpFill(child: dnsPermissionView(ref, zone))],
      );
    }

    final async = ref.watch(dnsRecordsProvider(widget.zoneId));
    final synced = async.value;
    final hasRecords = synced != null && synced.data.isNotEmpty;

    return EpPage(
      title: l.dnsTitle,
      largeTitle: false,
      previousPageTitle: zone.name,
      subtitle: Wrap(
        spacing: 6,
        children: [
          Text(zone.name),
          if (synced != null) ...[const Text('·'), SyncLine(synced: synced)],
        ],
      ),
      onRefresh: () => _notifier.refresh(),
      actions: [
        EpAction(
          icon: EpIcon.more,
          label: l.dnsMoreActions,
          onPressed: synced == null || _busy ? null : () => _more(zone, synced.data),
        ),
      ],
      primaryAction: EpAction(icon: EpIcon.add, label: l.dnsAddRecord, onPressed: _busy ? null : () => _add()),
      slivers: [
        if (hasRecords) SliverToBoxAdapter(child: _controls(context)),
        if (_busy)
          SliverToBoxAdapter(
            child: isCupertino(context)
                ? const Padding(padding: EdgeInsets.all(EpSpace.sm), child: CupertinoActivityIndicator())
                : const LinearProgressIndicator(minHeight: 2),
          ),
        ...async.when(
          loading: () => [const EpFill(child: EpLoading())],
          error: (e, _) => [
            EpFill(
              child: EpErrorView(
                error: e,
                permission: Capability.dns.permission,
                onRetry: () => ref.invalidate(dnsRecordsProvider(widget.zoneId)),
              ),
            ),
          ],
          data: (s) => _list(context, zone, s.data),
        ),
      ],
    );
  }

  Widget _controls(BuildContext context) {
    final l = context.l10n;
    final search = isCupertino(context)
        ? CupertinoSearchTextField(
            controller: _search,
            placeholder: l.dnsSearchPlaceholder,
            onChanged: (_) => setState(() {}),
          )
        : SearchBar(
            controller: _search,
            hintText: l.dnsSearchPlaceholder,
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (_) => setState(() {}),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.xs, EpSpace.lg, EpSpace.md), child: search),
        // Six types: a row of pills that scrolls out to the screen edges.
        EpSegmented<DnsTypeFilter>(
          inset: EpSpace.lg,
          segments: {
            DnsTypeFilter.all: l.dnsFilterAll,
            DnsTypeFilter.address: l.dnsFilterAddress,
            DnsTypeFilter.cname: 'CNAME',
            DnsTypeFilter.mx: 'MX',
            DnsTypeFilter.txt: 'TXT',
            DnsTypeFilter.other: l.dnsFilterOther,
          },
          value: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
      ],
    );
  }

  bool _matchesFilter(DnsRecord r) => switch (_filter) {
    DnsTypeFilter.all => true,
    DnsTypeFilter.address => r.type == 'A' || r.type == 'AAAA',
    DnsTypeFilter.cname => r.type == 'CNAME',
    DnsTypeFilter.mx => r.type == 'MX',
    DnsTypeFilter.txt => r.type == 'TXT',
    DnsTypeFilter.other => !const {'A', 'AAAA', 'CNAME', 'MX', 'TXT'}.contains(r.type),
  };

  List<Widget> _list(BuildContext context, Zone zone, List<DnsRecord> records) {
    final l = context.l10n;
    if (records.isEmpty) {
      return [
        EpFill(
          child: EpMessage(
            icon: EpIcon.dns,
            title: l.dnsEmptyTitle,
            message: l.dnsEmptyMessage,
            action: EpButton(label: l.dnsAddRecord, onPressed: _add),
          ),
        ),
      ];
    }
    final q = _search.text.trim().toLowerCase();
    final shown = records
        .where(_matchesFilter)
        .where(
          (r) =>
              q.isEmpty ||
              r.name.toLowerCase().contains(q) ||
              r.content.toLowerCase().contains(q) ||
              DnsNames.relative(r.name, zone.name).contains(q),
        )
        .toList();
    if (shown.isEmpty) {
      return [
        EpFill(
          child: EpMessage(
            icon: EpIcon.search,
            title: q.isNotEmpty ? l.emptySearch(_search.text.trim()) : l.dnsFilterEmpty,
          ),
        ),
      ];
    }
    final groups = <String, List<DnsRecord>>{};
    for (final r in shown) {
      groups.putIfAbsent(r.type, () => []).add(r);
    }
    return [
      SliverList.list(
        children: [
          for (final g in groups.entries)
            EpSection(
              key: ValueKey('dns-section-${g.key}'),
              header: l.dnsSectionHeader(g.key, g.value.length),
              children: [for (final r in g.value) _row(context, zone, r)],
            ),
        ],
      ),
    ];
  }

  Widget _row(BuildContext context, Zone zone, DnsRecord r) {
    final l = context.l10n;
    final c = EpColors.of(context);
    return Semantics(
      key: ValueKey(r.id),
      onLongPressHint: l.dnsRowHint,
      child: GestureDetector(
        onLongPress: () => _rowActions(zone, r),
        child: EpTile(
          title: Text(
            DnsNames.relative(r.name, zone.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EpType.data(context, size: 15),
          ),
          subtitle: Text(
            r.content,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EpType.data(context, size: 13, color: c.inkMuted),
          ),
          trailing: DnsRecordMeta(record: r),
          onTap: () => _edit(r),
        ),
      ),
    );
  }

  void _add([String? type]) =>
      context.push(type == null ? '$_base/new' : '$_base/new?type=$type', extra: kDnsEditorFromList);

  Future<void> _edit(DnsRecord r) async {
    final result = await context.push<Object?>('$_base/${r.id}', extra: kDnsEditorFromList);
    if (!mounted) return;
    if (result is DnsEditorResult) await _deleteWithUndo(result.record);
  }

  Future<void> _rowActions(Zone zone, DnsRecord r) async {
    final l = context.l10n;
    final action = await showEpActionSheet<_RowAction>(
      context,
      title: '${r.type} · ${DnsNames.relative(r.name, zone.name)}',
      actions: [
        EpSheetAction(label: l.dnsActionCopyName, value: _RowAction.copyName, icon: EpIcon.copy),
        EpSheetAction(label: l.dnsActionCopyContent, value: _RowAction.copyContent, icon: EpIcon.copy),
        EpSheetAction(label: l.actionEdit, value: _RowAction.edit, icon: EpIcon.edit),
        EpSheetAction(label: l.actionDelete, value: _RowAction.delete, icon: EpIcon.trash, destructive: true),
      ],
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _RowAction.copyName:
        await copyWithToast(context, r.name);
      case _RowAction.copyContent:
        await copyWithToast(context, r.content);
      case _RowAction.edit:
        await _edit(r);
      case _RowAction.delete:
        final ok = await showEpConfirm(
          context,
          title: l.dnsDeleteTitle,
          message: l.dnsDeleteMessage(r.type, r.name),
          confirmLabel: l.actionDelete,
          destructive: true,
        );
        if (ok && mounted) await _deleteWithUndo(r);
    }
  }

  /// Optimistic delete with an Undo that re-creates the record.
  Future<void> _deleteWithUndo(DnsRecord r) async {
    final l = context.l10n;
    final notifier = _notifier;
    try {
      // Leaves the list at once; the toast follows Cloudflare's answer.
      await notifier.delete(r);
      if (!mounted) return;
      showEpToast(context, l.dnsDeleted, actionLabel: l.actionUndo, onAction: () => _restore(notifier, r));
    } on Object catch (e) {
      if (!mounted) return;
      showEpToast(context, l.dnsDeleteFailed(describeError(context, e, permission: Capability.dns.permission)));
    }
  }

  Future<void> _restore(DnsNotifier notifier, DnsRecord r) async {
    try {
      await notifier.restore(r);
      if (mounted) showEpToast(context, context.l10n.dnsRestored);
    } on Object catch (e) {
      if (!mounted) return;
      showEpToast(
        context,
        context.l10n.dnsRestoreFailed(describeError(context, e, permission: Capability.dns.permission)),
      );
    }
  }

  Future<void> _more(Zone zone, List<DnsRecord> records) async {
    final l = context.l10n;
    final choice = await showEpActionSheet<_More>(
      context,
      actions: [
        EpSheetAction(label: l.dnsMenuPointToIp, value: _More.point, icon: EpIcon.link),
        EpSheetAction(label: l.dnsMenuVerifyTxt, value: _More.verify, icon: EpIcon.checkCircle),
        EpSheetAction(label: l.dnsMenuMailCheck, value: _More.mailCheck, icon: EpIcon.mail),
        EpSheetAction(label: l.dnsMenuExport, value: _More.export, icon: EpIcon.share),
        EpSheetAction(label: l.dnsMenuImport, value: _More.import, icon: EpIcon.upload),
      ],
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _More.point:
        await context.push('$_base/template/point');
      case _More.verify:
        await context.push('$_base/template/verify');
      case _More.mailCheck:
        await context.push('$_base/mail-check');
      case _More.export:
        await _export(zone);
      case _More.import:
        await _import(zone);
    }
  }

  Rect? _shareOrigin() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _export(Zone zone) async {
    final l = context.l10n;
    setState(() => _busy = true);
    try {
      final text = await _notifier.exportBind();
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(Uint8List.fromList(utf8.encode(text)), mimeType: 'text/plain')],
          fileNameOverrides: ['${zone.name}.txt'],
          subject: l.dnsExportSubject(zone.name),
          sharePositionOrigin: _shareOrigin(),
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        showEpToast(context, l.dnsExportFailed(describeError(context, e, permission: Capability.dns.permission)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import(Zone zone) async {
    final l = context.l10n;
    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(type: FileType.any);
    } on Object {
      if (mounted) showEpToast(context, l.dnsImportOpenFailed);
      return;
    }
    if (file == null || !mounted) return;
    final size = await file.length() ?? 0;
    if (!mounted) return;
    if (size > DnsRepository.maxImportBytes) {
      showEpToast(context, l.dnsImportTooLarge((size / 1024).ceil()));
      return;
    }
    final proxied = await showEpActionSheet<bool>(
      context,
      title: l.dnsImportTitle(file.name),
      message: l.dnsImportMessage(zone.name),
      actions: [
        EpSheetAction(label: l.dnsImportDnsOnly, value: false),
        EpSheetAction(label: l.dnsImportProxied, value: true),
      ],
    );
    if (proxied == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      if (bytes.length > DnsRepository.maxImportBytes) {
        if (mounted) showEpToast(context, l.dnsImportTooLarge((bytes.length / 1024).ceil()));
        return;
      }
      final result = await _notifier.importBind(bytes, filename: file.name, proxied: proxied);
      if (mounted) showEpToast(context, l.dnsImportDone(result.added, result.parsed));
    } on DnsImportThrottled catch (e) {
      if (mounted) showEpToast(context, l.dnsImportThrottled(e.wait.inSeconds.clamp(1, 60)));
    } on Object catch (e) {
      if (mounted) {
        showEpToast(context, l.dnsImportFailed(describeError(context, e, permission: Capability.dns.permission)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
