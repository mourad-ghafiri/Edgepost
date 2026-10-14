import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/adaptive/ep_icons.dart';
import '../../../core/adaptive/ep_widgets.dart' show bareInputDecoration;
import '../../../core/adaptive/platform.dart';
import '../../../core/l10n.dart';
import '../../../core/strip/strip.dart' show EpPressable;
import '../../../core/theme/tokens.dart';
import '../data/mail_models.dart';
import '../data/recipient_suggestions.dart';

/// Address entry: typed addresses turn into removable chips on comma, space,
/// return or focus loss. Invalid input stays as text with an error.
///
/// While it has focus it offers [suggestions], one tap each: the people
/// written to most when it's empty, then matches and domain completions as
/// you type. Nothing is ever filled in for you.
class RecipientField extends StatefulWidget {
  const RecipientField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.autofocus = false,
    this.suggestions,
  });

  final String label;
  final List<MailAddress> value;
  final ValueChanged<List<MailAddress>> onChanged;
  final bool autofocus;
  final RecipientSuggestions? suggestions;

  @override
  State<RecipientField> createState() => RecipientFieldState();
}

class RecipientFieldState extends State<RecipientField> {
  final _ctl = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  /// An invisible first character while the field has chips and focus. A
  /// phone keyboard's delete sends nothing in an empty field; deleting this
  /// character is how that press is seen at all (see [_onEdit]).
  static const _anchor = '\u200B';

  /// The text at the last change, to tell a delete of [_anchor] from other
  /// edits.
  String _seen = '';
  bool _syncing = false;

  /// The last chip, selected by a delete in the empty field (as in iOS
  /// Mail): the next delete removes it; typing lets it go.
  bool _lastSelected = false;

  /// What's typed, without the anchor.
  String get _typed => _ctl.text.replaceAll(_anchor, '');

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) {
        commitPending();
        _lastSelected = false;
      }
      _sync();
      setState(() {}); // suggestions show only while focused
    });
    _ctl.addListener(_onEdit);
  }

  @override
  void didUpdateWidget(RecipientField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Chips set from outside (a restored draft): anchor once built.
    if (oldWidget.value.isEmpty != widget.value.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sync();
      });
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (_syncing) return;
    final text = _ctl.text;
    final deletedAnchor = _seen.startsWith(_anchor) && text == _seen.substring(1);
    final typedBefore = _seen.replaceAll(_anchor, '');
    _seen = text;
    var hasChips = widget.value.isNotEmpty;
    if (deletedAnchor && hasChips) {
      hasChips = _deleteBack();
    } else if (_lastSelected && _typed != typedBefore) {
      _lastSelected = false;
    }
    _sync(hasChips: hasChips);
    setState(() {});
  }

  /// Delete in the empty field: selects the last chip, or removes it when
  /// it's selected. Returns whether chips remain.
  bool _deleteBack() {
    if (!_lastSelected) {
      _lastSelected = true;
      return true;
    }
    _lastSelected = false;
    final next = [...widget.value]..removeLast();
    widget.onChanged(next);
    return next.isNotEmpty;
  }

  /// Keeps [_anchor] first while there are chips and focus (and only then),
  /// the caret after it, where it was among the typed characters.
  void _sync({bool? hasChips}) {
    final anchored = (hasChips ?? widget.value.isNotEmpty) && _focus.hasFocus;
    final min = anchored ? 1 : 0;
    final typed = _typed;
    final text = anchored ? '$_anchor$typed' : typed;
    final sel = _ctl.selection;
    final caretOk = !sel.isValid || !sel.isCollapsed || sel.extentOffset >= min;
    if (_ctl.text == text && caretOk) {
      _seen = text;
      return;
    }
    final before = sel.isValid ? _ctl.text.substring(0, sel.extentOffset.clamp(0, _ctl.text.length)) : _ctl.text;
    final caret = min + before.replaceAll(_anchor, '').length;
    _syncing = true;
    _ctl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret.clamp(min, text.length)),
    );
    _syncing = false;
    _seen = text;
  }

  /// Empties what's typed without it reading as an edit.
  void _clearTyped({required bool hasChips}) {
    _syncing = true;
    _ctl.clear();
    _syncing = false;
    _seen = '';
    _sync(hasChips: hasChips);
  }

  /// Turns any typed text into chips. Returns false when text is invalid.
  bool commitPending() {
    final raw = _typed.trim();
    if (raw.isEmpty) {
      if (_error != null) setState(() => _error = null);
      return true;
    }
    final parts = raw.split(RegExp(r'[,;\n]+')).map((s) => s.trim()).where((s) => s.isNotEmpty);
    final added = <MailAddress>[];
    for (final p in parts) {
      final a = MailAddress.tryParse(p);
      if (a == null) {
        setState(() => _error = context.l10n.mailInvalidAddress(p));
        return false;
      }
      added.add(a);
    }
    final next = [...widget.value];
    for (final a in added) {
      if (!next.any(a.sameAs)) next.add(a);
    }
    _lastSelected = false;
    _clearTyped(hasChips: next.isNotEmpty);
    setState(() => _error = null);
    widget.onChanged(next);
    return true;
  }

  /// What Return picks: the top suggestion while the text isn't an address
  /// yet ("lena", "jo@gm"). A whole address is always kept as typed.
  RecipientSuggestion? _returnPick() {
    final s = widget.suggestions;
    final typed = _typed.trim();
    if (s == null || typed.isEmpty || typed.contains(RegExp(r'[,;\s]')) || MailAddress.tryParse(typed) != null) {
      return null;
    }
    return s.forInput(typed).firstOrNull;
  }

  void _submit() {
    final pick = _returnPick();
    if (pick != null) {
      _pick(pick.address);
    } else {
      commitPending();
    }
  }

  /// Adds a suggestion and stays ready for the next one.
  void _pick(MailAddress a) {
    final next = [...widget.value];
    if (!next.any(a.sameAs)) next.add(a);
    _lastSelected = false;
    _clearTyped(hasChips: true);
    setState(() => _error = null);
    widget.onChanged(next);
    _focus.requestFocus();
  }

  void _remove(MailAddress a) {
    final next = [...widget.value]..remove(a);
    _lastSelected = false;
    widget.onChanged(next);
    _sync(hasChips: next.isNotEmpty);
  }

  void _onChanged(String value) {
    final v = value.replaceAll(_anchor, '');
    if (v.endsWith(',') || v.endsWith(';') || (v.endsWith(' ') && v.contains('@') && !v.contains('<'))) {
      commitPending();
    } else if (_error != null) {
      setState(() => _error = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final cupertino = isCupertino(context);
    final input = cupertino
        ? CupertinoTextField.borderless(
            controller: _ctl,
            focusNode: _focus,
            autofocus: widget.autofocus,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            placeholder: widget.value.isEmpty ? context.l10n.mailRecipientsPlaceholder : null,
            padding: const EdgeInsets.symmetric(vertical: 8),
            style: TextStyle(color: c.ink, fontSize: 16),
            onChanged: _onChanged,
            onSubmitted: (_) => _submit(),
          )
        : TextField(
            controller: _ctl,
            focusNode: _focus,
            autofocus: widget.autofocus,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: bareInputDecoration(
              hintText: widget.value.isEmpty ? context.l10n.mailRecipientsPlaceholder : null,
            ),
            onChanged: _onChanged,
            onSubmitted: (_) => _submit(),
          );

    final field = Padding(
      padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg, vertical: EpSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 10, right: EpSpace.sm),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 72),
                  child: Text(widget.label, softWrap: false, style: TextStyle(color: c.inkMuted, fontSize: 15)),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final (i, a) in widget.value.indexed)
                      _Chip(
                        address: a,
                        selected: _lastSelected && i == widget.value.length - 1,
                        onRemove: () => _remove(a),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 140),
                      // Named by its row label even once chips replace the placeholder.
                      child: IntrinsicWidth(
                        child: MergeSemantics(
                          child: Semantics(label: widget.label, child: input),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(left: 72, top: 4),
              child: Text(_error!, style: TextStyle(color: c.attention, fontSize: 13)),
            ),
        ],
      ),
    );
    // One tree whether suggestions show or not: the field keeps its place,
    // so it keeps focus and the keyboard while they come and go as you type.
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [field, ?_offers(context)]);
  }

  /// What [RecipientField.suggestions] offers now, or null.
  Widget? _offers(BuildContext context) {
    final s = widget.suggestions;
    if (s == null || !_focus.hasFocus) return null;
    final typed = _typed;
    if (typed.trim().isEmpty) {
      final picks = s.quickPicks();
      return picks.isEmpty ? null : _QuickPicks(picks: picks, onPick: _pick);
    }
    final items = s.forInput(typed);
    if (items.isEmpty) return null;
    // Return adds the first row while the text isn't an address yet.
    final returnPicksFirst = _returnPick() != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: EpSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final i in items)
            _SuggestionRow(
              item: i,
              typed: typed.trim(),
              onPick: _pick,
              onReturn: returnPicksFirst && identical(i, items.first),
            ),
        ],
      ),
    );
  }
}

/// Where suggestion text starts: under the typed text, past the row label.
const double _textStart = EpSpace.lg + 72 + EpSpace.sm;

/// One line of the people written to most, for an empty field. Scrolls
/// sideways without closing the keyboard.
class _QuickPicks extends StatelessWidget {
  const _QuickPicks({required this.picks, required this.onPick});
  final List<MailAddress> picks;
  final ValueChanged<MailAddress> onPick;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final l = context.l10n;
    return Semantics(
      container: true,
      label: l.mailSuggestedRecipients,
      explicitChildNodes: true,
      // The form closes the keyboard on any drag; this one is sideways.
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(_textStart, 0, EpSpace.lg, EpSpace.xs),
          child: Row(
            children: [
              for (final a in picks)
                Padding(
                  padding: const EdgeInsets.only(right: EpSpace.sm),
                  child: Semantics(
                    button: true,
                    label: l.mailSuggestAdd(a.formatted),
                    excludeSemantics: true,
                    child: EpPressable(
                      onTap: () => onPick(a),
                      radius: EpRadius.pill,
                      // 32 pt pill, 44 pt target.
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 32),
                          padding: const EdgeInsets.only(left: 8, right: 12),
                          decoration: ShapeDecoration(
                            shape: StadiumBorder(side: BorderSide(color: c.hairline)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              EpIconView(EpIcon.add, size: 14, color: c.tint),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 200),
                                child: Text(
                                  a.display,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.ink, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One suggestion while typing: a person (name over address), a completed
/// domain (the part not typed in bold) or a typo fix.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({required this.item, required this.typed, required this.onPick, this.onReturn = false});
  final RecipientSuggestion item;
  final String typed;
  final ValueChanged<MailAddress> onPick;

  /// What the keyboard's Return adds: lightly washed, so that's clear.
  final bool onReturn;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final l = context.l10n;
    final a = item.address;
    const size = 28.0;
    final Widget leading = switch (item.kind) {
      SuggestionKind.contact => CircleAvatar(
        radius: size / 2,
        backgroundColor: c.neutralWash,
        child: Text(
          a.display.characters.first.toUpperCase(),
          style: TextStyle(color: c.ink, fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      SuggestionKind.domain => SizedBox.square(
        dimension: size,
        child: Center(child: EpIconView(EpIcon.mail, size: 18, color: c.inkMuted)),
      ),
      SuggestionKind.correction => SizedBox.square(
        dimension: size,
        child: Center(child: EpIconView(EpIcon.warning, size: 18, color: c.caution)),
      ),
    };
    final title = switch (item.kind) {
      SuggestionKind.domain when a.address.toLowerCase().startsWith(typed.toLowerCase()) => Text.rich(
        TextSpan(
          children: [
            TextSpan(text: a.address.substring(0, typed.length)),
            TextSpan(
              text: a.address.substring(typed.length),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: c.ink, fontSize: 15),
      ),
      _ => Text(
        item.kind == SuggestionKind.contact ? a.display : a.address,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.ink,
          fontSize: 15,
          fontWeight: item.kind == SuggestionKind.correction ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    };
    final String? subtitle = switch (item.kind) {
      SuggestionKind.contact => a.name == null ? null : a.address,
      SuggestionKind.domain => null,
      SuggestionKind.correction => l.mailSuggestTypo(item.typedDomain ?? ''),
    };
    return Semantics(
      button: true,
      label: [l.mailSuggestAdd(a.formatted), ?(item.kind == SuggestionKind.correction ? subtitle : null)].join('. '),
      excludeSemantics: true,
      child: EpPressable(
        onTap: () => onPick(a),
        child: Container(
          color: onReturn ? c.neutralWash : null,
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(_textStart - size - EpSpace.md, 6, EpSpace.lg, 6),
            child: Row(
              children: [
                leading,
                const SizedBox(width: EpSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      title,
                      if (subtitle != null)
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: c.inkMuted, fontSize: 13),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.address, required this.onRemove, this.selected = false});
  final MailAddress address;
  final VoidCallback onRemove;

  /// Picked by the keyboard's delete: the next delete removes it.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return Semantics(
      label: address.formatted,
      button: true,
      selected: selected,
      onTapHint: context.l10n.actionRemove,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRemove,
        // 32 pt chip, 44 pt target.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            constraints: const BoxConstraints(minHeight: 32),
            padding: const EdgeInsets.only(left: 10, right: 6),
            decoration: BoxDecoration(
              color: selected ? c.tint : c.neutralWash,
              borderRadius: BorderRadius.circular(EpRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    address.name ?? address.address,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: selected ? c.onTint : c.ink, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 4),
                EpIconView(EpIcon.close, size: 16, color: selected ? c.onTint : c.inkMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
