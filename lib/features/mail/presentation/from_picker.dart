import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_widgets.dart';
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/theme/tokens.dart';
import '../data/mail_models.dart';
import '../data/mail_providers.dart';
import '../data/recent_from.dart';

/// Opens the "Send from" sheet and returns the chosen address (with its saved
/// display name), or null when dismissed.
Future<MailAddress?> showFromPicker(BuildContext context, {required String accountId, required MailAddress current}) {
  Widget body(ScrollController sc) => _FromPicker(accountId: accountId, current: current, scrollController: sc);
  if (isCupertino(context)) {
    return showCupertinoSheet<MailAddress>(
      context: context,
      showDragHandle: true,
      scrollableBuilder: (ctx, sc) => Material(color: EpColors.of(ctx).canvas, child: body(sc)),
    );
  }
  return showModalBottomSheet<MailAddress>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: EpColors.of(context).canvas,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (ctx, sc) => body(sc),
    ),
  );
}

final _localPart = RegExp(r'^[a-z0-9][a-z0-9._+-]*$');

class _FromPicker extends ConsumerStatefulWidget {
  const _FromPicker({required this.accountId, required this.current, required this.scrollController});
  final String accountId;
  final MailAddress current;
  final ScrollController scrollController;

  @override
  ConsumerState<_FromPicker> createState() => _FromPickerState();
}

class _FromPickerState extends ConsumerState<_FromPicker> {
  final _search = TextEditingController();
  String _query = '';

  /// Domain whose "Another address" row is open.
  String? _otherDomain;
  final _other = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    _other.dispose();
    super.dispose();
  }

  MailAddress _withName(String address, Map<String, Identity> saved) =>
      MailAddress(address, saved[address.toLowerCase()]?.name);

  void _choose(MailAddress a) => Navigator.of(context).pop(a);

  Future<void> _editIdentity(MailAddress a) async {
    final l = context.l10n;
    final saved = ref.read(identitySettingsProvider(widget.accountId)).value?[a.address.toLowerCase()];
    final name = TextEditingController(text: saved?.name ?? a.name ?? '');
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog.adaptive(
        title: Text(l.mailFromNameTitle),
        content: Material(
          type: MaterialType.transparency,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.mailFromNameHelp(a.address), style: TextStyle(color: EpColors.of(ctx).inkMuted, fontSize: 13)),
              const SizedBox(height: EpSpace.md),
              EpTextField(label: l.mailIdentityName, controller: name, autofocus: true),
            ],
          ),
        ),
        actions: isCupertino(ctx)
            ? [
                CupertinoDialogAction(onPressed: () => Navigator.pop(ctx, false), child: Text(l.actionCancel)),
                CupertinoDialogAction(
                  isDefaultAction: true,
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(l.actionSave),
                ),
              ]
            : [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.actionCancel)),
                TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.actionSave)),
              ],
      ),
    );
    if (ok == true) {
      await ref
          .read(identitySettingsProvider(widget.accountId).notifier)
          .put(
            Identity(
              a.address,
              name: name.text.trim().isEmpty ? null : name.text.trim(),
            ),
          );
    }
    name.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final account = widget.accountId;
    final service = ref.watch(mailServiceProvider(account));
    final saved = ref.watch(identitySettingsProvider(account)).value ?? const <String, Identity>{};
    final boxes = ref.watch(mailboxesProvider(account)).value ?? const <Mailbox>[];
    final recents = ref.watch(recentFromProvider(account)).value ?? const <MailAddress>[];

    // Current domain first, then alphabetical.
    final domains = {...?service?.domains.map((d) => d.toLowerCase())}.toList()..sort();
    domains.sort((a, b) => a == widget.current.domain ? -1 : (b == widget.current.domain ? 1 : a.compareTo(b)));

    List<String> addressesOn(String d) {
      final set = <String>{
        'contact@$d',
        for (final b in boxes)
          if (b.domain.toLowerCase() == d) b.address.toLowerCase(),
        for (final k in saved.keys)
          if (k.endsWith('@$d')) k,
        if (widget.current.domain == d) widget.current.address.toLowerCase(),
      };
      final list = set.toList()..sort();
      list.remove('contact@$d');
      return ['contact@$d', ...list];
    }

    final q = _query.trim().toLowerCase();
    bool matches(String a) => q.isEmpty || a.contains(q) || (saved[a]?.name?.toLowerCase().contains(q) ?? false);

    // Typing a full address on one of your domains offers it directly.
    MailAddress? typed;
    if (q.contains('@')) {
      final parts = q.split('@');
      if (parts.length == 2 && domains.contains(parts[1]) && _localPart.hasMatch(parts[0])) typed = MailAddress(q);
    }

    // Under a domain header only the local part is new information; Recent
    // keeps the whole address (allowed to wrap at "@", never mid-domain).
    Widget row(String address, {bool showDomain = false}) {
      final a = _withName(address, saved);
      final selected = a.sameAs(widget.current);
      final at = address.indexOf('@');
      return Semantics(
        selected: selected,
        button: true,
        label: a.formatted,
        excludeSemantics: true,
        child: EpTile(
          leading: EpIconView(selected ? EpIcon.checkCircle : EpIcon.mail, color: selected ? c.tint : c.inkMuted),
          title: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: address.substring(0, at),
                  style: TextStyle(fontSize: 16, color: c.ink, fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: showDomain ? '\u200B${address.substring(at)}' : '@',
                  style: TextStyle(fontSize: 16, color: c.inkMuted),
                ),
              ],
            ),
          ),
          subtitle: a.name == null ? null : Text(a.name!),
          trailing: EpIconButton(
            icon: EpIcon.edit,
            size: 20,
            color: c.inkMuted,
            label: l.mailFromEditFor(address),
            onPressed: () => _editIdentity(a),
          ),
          onTap: () => _choose(a),
        ),
      );
    }

    Widget otherRow(String d) {
      final open = _otherDomain == d;
      if (!open) {
        return EpTile(
          leading: EpIconView(EpIcon.add, color: c.tint),
          title: Text(l.mailFromOtherTitle, style: TextStyle(color: c.tint)),
          onTap: () => setState(() {
            _otherDomain = d;
            _other.clear();
          }),
        );
      }
      final v = _other.text.trim().toLowerCase();
      final valid = _localPart.hasMatch(v);
      return Padding(
        padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.sm, EpSpace.lg, EpSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EpTextField(
              label: l.mailFromOtherTitle,
              controller: _other,
              placeholder: l.mailFromLocalHint,
              autofocus: true,
              autocorrect: false,
              keyboardType: TextInputType.emailAddress,
              helperText: l.mailFromOtherHelp,
              errorText: v.isEmpty || valid ? null : l.mailFromInvalid,
              suffix: Padding(
                padding: const EdgeInsets.only(right: EpSpace.sm),
                child: Text('@$d', style: TextStyle(fontSize: 15, color: c.inkMuted)),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (valid) _choose(_withName('$v@$d', saved));
              },
            ),
            const SizedBox(height: EpSpace.sm),
            EpButton(label: l.mailFromUse, onPressed: valid ? () => _choose(_withName('$v@$d', saved)) : null),
          ],
        ),
      );
    }

    final search = isCupertino(context)
        ? CupertinoSearchTextField(
            controller: _search,
            placeholder: l.mailFromSearch,
            onChanged: (v) => setState(() => _query = v),
          )
        : SearchBar(
            controller: _search,
            hintText: l.mailFromSearch,
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (v) => setState(() => _query = v),
          );

    final sections = <Widget>[
      if (typed != null)
        EpSection(
          children: [
            EpTile(
              leading: EpIconView(EpIcon.send, color: c.tint),
              title: Text(typed.address, style: const TextStyle(fontSize: 16)),
              onTap: () => _choose(_withName(typed!.address, saved)),
            ),
          ],
        ),
      if (q.isEmpty && recents.isNotEmpty)
        EpSection(
          header: l.mailFromRecent,
          children: [for (final r in recents) row(r.address.toLowerCase(), showDomain: true)],
        ),
      for (final d in domains)
        if (addressesOn(d).any(matches) || q.isEmpty)
          EpSection(
            header: d,
            children: [
              for (final a in addressesOn(d).where(matches)) row(a, showDomain: q.isNotEmpty),
              if (q.isEmpty) otherRow(d),
            ],
          ),
    ];

    return CustomScrollView(
      controller: widget.scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, EpSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l.mailFromTitle, style: EpType.title(context, size: 22)),
                const SizedBox(height: EpSpace.md),
                search,
              ],
            ),
          ),
        ),
        if (service == null && ref.watch(mailServicesProvider).isLoading)
          const SliverToBoxAdapter(
            child: Padding(padding: EdgeInsets.all(EpSpace.xl), child: EpLoading()),
          )
        else if (sections.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(EpSpace.xl),
              child: Text(
                l.mailFromNoMatch(_query.trim()),
                textAlign: TextAlign.center,
                style: TextStyle(color: c.inkMuted),
              ),
            ),
          )
        else
          SliverList.list(children: sections),
        // Room for the keyboard so the "Another address" field never sits
        // behind it.
        SliverToBoxAdapter(child: SizedBox(height: EpSpace.xl + MediaQuery.viewInsetsOf(context).bottom)),
      ],
    );
  }
}
