import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accounts/vault.dart';
import '../cloudflare/cf_errors.dart';
import '../l10n.dart';
import '../theme/tokens.dart';
import 'ep_icons.dart';
import 'layout.dart';
import 'popover.dart';
import 'platform.dart';

/// Grouped section: inset-grouped list on iOS, headed list block on Android.
class EpSection extends StatelessWidget {
  const EpSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    if (isCupertino(context)) {
      // Cards on the page gutter; header and footer text inset to the rows'
      // text, as iOS does.
      const textInset = EdgeInsetsDirectional.only(start: EpSpace.md);
      return _EpSectionScope(
        child: CupertinoListSection.insetGrouped(
          margin: const EdgeInsetsDirectional.fromSTEB(EpSpace.lg, 0, EpSpace.lg, 10),
          header: header == null
              ? null
              : Padding(
                  padding: textInset,
                  child: Semantics(
                    header: true,
                    child: Text(header!.toUpperCase(), style: EpType.groupLabel(context)),
                  ),
                ),
          footer: footer == null
              ? null
              : Padding(
                  padding: textInset,
                  child: Text(footer!, style: TextStyle(color: c.inkMuted, fontSize: 13)),
                ),
          backgroundColor: c.canvas,
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(EpRadius.md),
            border: Border.all(color: c.hairline),
          ),
          separatorColor: c.hairline,
          children: children.isEmpty ? [const SizedBox.shrink()] : children,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: EpSpace.md, bottom: EpSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EpSpace.lg,
                EpSpace.sm,
                EpSpace.lg,
                EpSpace.sm,
              ),
              child: Semantics(header: true, child: Text(header!.toUpperCase(), style: EpType.groupLabel(context))),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
            child: Material(
              color: c.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(EpRadius.md),
                side: BorderSide(color: c.hairline),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) Divider(height: 1, indent: EpSpace.lg, color: c.hairline),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                EpSpace.lg,
                EpSpace.sm,
                EpSpace.lg,
                0,
              ),
              child: Text(
                footer!,
                style: TextStyle(color: c.inkMuted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

/// Marks an [EpSection]'s rows: the section paints their surface (and its
/// hairline border, which an opaque row would cover).
class _EpSectionScope extends InheritedWidget {
  const _EpSectionScope({required super.child});

  static bool within(BuildContext context) => context.getInheritedWidgetOfExactType<_EpSectionScope>() != null;

  @override
  bool updateShouldNotify(_EpSectionScope oldWidget) => false;
}

/// List row in the platform idiom.
class EpTile extends StatelessWidget {
  const EpTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.additionalInfo,
    this.onTap,
    this.onLongPress,
    this.destructive = false,
    this.showChevron,
  });

  final VoidCallback? onLongPress;
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final Widget? additionalInfo;
  final VoidCallback? onTap;
  final bool destructive;
  final bool? showChevron;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final titleWidget = destructive
        ? DefaultTextStyle.merge(
            style: TextStyle(color: c.attention),
            child: title,
          )
        : title;
    final chevron = showChevron ?? (onTap != null && trailing == null);
    if (isCupertino(context)) {
      // CupertinoListTile clips title and subtitle to one line; explanations
      // and large Dynamic Type sizes need room to wrap.
      final tile = CupertinoListTile(
        title: DefaultTextStyle.merge(maxLines: 2, overflow: TextOverflow.ellipsis, child: titleWidget),
        subtitle: subtitle == null
            ? null
            : DefaultTextStyle.merge(maxLines: 4, overflow: TextOverflow.ellipsis, child: subtitle!),
        leading: leading,
        additionalInfo: additionalInfo,
        trailing: trailing ?? (chevron ? const CupertinoListTileChevron() : null),
        onTap: onTap,
        backgroundColor: _EpSectionScope.within(context) ? null : c.surface,
        // Two-line rows (switch explanations) need air above and below.
        padding: subtitle == null ? null : const EdgeInsetsDirectional.fromSTEB(20, 12, 14, 12),
      );
      return onLongPress == null ? tile : GestureDetector(onLongPress: onLongPress, child: tile);
    }
    return ListTile(
      title: titleWidget,
      subtitle: subtitle,
      leading: leading,
      trailing: switch ((additionalInfo, trailing)) {
        (null, final t) => t,
        (final info?, null) => DefaultTextStyle.merge(
          style: TextStyle(color: c.inkMuted),
          child: info,
        ),
        // Both: the status text stays next to the control.
        (final info?, final t?) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DefaultTextStyle.merge(
              style: TextStyle(color: c.inkMuted),
              child: info,
            ),
            const SizedBox(width: EpSpace.sm),
            t,
          ],
        ),
      },
      onTap: onTap,
      onLongPress: onLongPress,
      minTileHeight: 56,
    );
  }
}

/// Switch row: CupertinoSwitch on iOS, Material 3 switch on Android.
class EpSwitchTile extends StatelessWidget {
  const EpSwitchTile({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final control = busy
        ? const SizedBox(
            width: 51,
            height: 31,
            child: Center(child: CircularProgressIndicator.adaptive()),
          )
        : Switch.adaptive(value: value, onChanged: onChanged);
    return MergeSemantics(
      child: EpTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: control,
        onTap: onChanged == null || busy ? null : () => onChanged!(!value),
      ),
    );
  }
}

/// Text input with a visible label in both idioms.
class EpTextField extends StatelessWidget {
  const EpTextField({
    super.key,
    required this.label,
    this.controller,
    this.placeholder,
    this.keyboardType,
    this.monospace = false,
    this.obscure = false,
    this.maxLines = 1,
    this.minLines,
    this.errorText,
    this.helperText,
    this.onChanged,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
    this.autocorrect = true,
    this.enabled = true,
    this.suffix,
  });

  final String label;
  final TextEditingController? controller;
  final String? placeholder;
  final TextInputType? keyboardType;
  final bool monospace;
  final bool obscure;
  final int? maxLines;
  final int? minLines;
  final String? errorText;
  final String? helperText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autocorrect;
  final bool enabled;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final style = monospace ? EpType.data(context, size: 15) : null;
    if (isCupertino(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: c.inkMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          CupertinoTextField(
            controller: controller,
            placeholder: placeholder,
            keyboardType: keyboardType,
            obscureText: obscure,
            maxLines: obscure ? 1 : maxLines,
            minLines: minLines,
            style: style?.copyWith(color: c.ink) ?? TextStyle(color: c.ink, fontSize: 17),
            onChanged: onChanged,
            autofocus: autofocus,
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            autocorrect: autocorrect,
            enabled: enabled,
            suffix: suffix,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(EpRadius.md),
              border: Border.all(
                color: errorText != null ? c.attention : c.hairline,
              ),
            ),
          ),
          if (errorText != null || helperText != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(
                errorText ?? helperText!,
                style: TextStyle(
                  fontSize: 13,
                  color: errorText != null ? c.attention : c.inkMuted,
                ),
              ),
            ),
        ],
      );
    }
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      maxLines: obscure ? 1 : maxLines,
      minLines: minLines,
      style: style,
      onChanged: onChanged,
      autofocus: autofocus,
      textInputAction: textInputAction,
      onSubmitted: onSubmitted,
      autocorrect: autocorrect,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: placeholder,
        errorText: errorText,
        helperText: helperText,
        helperMaxLines: 3,
        errorMaxLines: 3,
        suffixIcon: suffix,
      ),
    );
  }
}

/// A Material text field with no box, for fields that are rows of their own
/// (compose): the theme's outlined, filled boxes are for forms.
/// `InputDecoration.collapsed` clears only `border`, so the theme's enabled
/// and focused outlines would still show.
///
/// [padding] is inside the field, so a one-line row stays a full-height
/// tap target.
InputDecoration bareInputDecoration({String? hintText, EdgeInsetsGeometry padding = EdgeInsets.zero}) =>
    InputDecoration(
      isCollapsed: true,
      hintText: hintText,
      filled: false,
      contentPadding: padding,
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
    );

/// Segmented control: sliding segments on iOS, SegmentedButton on Android.
///
/// With more than four segments, large text, or labels wider than their
/// share of a narrow column (a split's list on an iPhone in landscape),
/// labels would be cut short ("Archiv…"), so it becomes a row of pills that
/// scrolls sideways instead.
/// Not a scrolling segmented control: the sliding one claims every horizontal
/// drag, so a scroller around it could never move.
class EpSegmented<T extends Object> extends StatelessWidget {
  const EpSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.inset = 0,
  });

  final Map<T, String> segments;
  final T value;
  final ValueChanged<T> onChanged;

  /// Side margin. A row of pills scrolls under it, out to the edges, which
  /// shows there is more; give it here rather than padding the control.
  final double inset;

  /// Whether every label fits its share of [width] in the control (its
  /// padding, inset and separators taken off).
  bool _fits(BuildContext context, double width) {
    final share = width / segments.length - 2 * 8 - 12;
    for (final label in segments.values) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      final wide = painter.width > share;
      painter.dispose();
      if (wide) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final forced = segments.length > 4 || MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final padding = EdgeInsets.symmetric(horizontal: inset);
    return LayoutBuilder(
      builder: (context, box) {
        final scroll = forced || (box.hasBoundedWidth && !_fits(context, box.maxWidth - 2 * inset));
        if (!scroll) return Padding(padding: padding, child: _control(context));
        return _pillRow(box, padding);
      },
    );
  }

  Widget _pillRow(BoxConstraints box, EdgeInsets padding) {
    final pills = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, e) in segments.entries.indexed) ...[
          if (i > 0) const SizedBox(width: EpSpace.sm),
          _Pill(label: e.value, selected: e.key == value, onTap: () => onChanged(e.key)),
        ],
      ],
    );
    // Already inside a horizontal scroller: it sizes itself.
    return box.hasBoundedWidth
        ? SingleChildScrollView(scrollDirection: Axis.horizontal, padding: padding, child: pills)
        : Padding(padding: padding, child: pills);
  }

  Widget _control(BuildContext context) {
    if (isCupertino(context)) {
      return CupertinoSlidingSegmentedControl<T>(
        groupValue: value,
        children: {
          for (final e in segments.entries)
            e.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(e.value),
            ),
        },
        onValueChanged: (v) {
          if (v != null) onChanged(v);
        },
      );
    }
    return SegmentedButton<T>(
      segments: [
        for (final e in segments.entries) ButtonSegment<T>(value: e.key, label: Text(e.value)),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

/// One choice in a scrolling [EpSegmented]: a hairline pill, blue when
/// chosen. Tap only, so the row around it scrolls freely.
class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    // One weight either way: choosing never shifts the row.
    final text = Text(
      label,
      maxLines: 1,
      style: TextStyle(color: selected ? c.tint : c.ink, fontSize: 14, fontWeight: FontWeight.w500),
    );
    final side = BorderSide(color: selected ? c.tint.withValues(alpha: 0.45) : c.hairline);
    final fill = selected ? c.tintWash : c.surface;
    // One node either way: the chip makes its own, so merge the group in.
    return MergeSemantics(
      child: Semantics(
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: isCupertino(context)
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size(44, 44),
                onPressed: onTap,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: ShapeDecoration(
                    color: fill,
                    shape: StadiumBorder(side: side),
                  ),
                  child: text,
                ),
              )
            : ChoiceChip(
                label: text,
                selected: selected,
                onSelected: (_) => onTap(),
                showCheckmark: false,
                shape: const StadiumBorder(),
                side: side,
                color: WidgetStatePropertyAll(fill),
              ),
      ),
    );
  }
}

/// Filled primary button in the platform idiom.
class EpButton extends StatelessWidget {
  const EpButton({
    super.key,
    required this.label,
    this.onPressed,
    this.busy = false,
    this.destructive = false,
    this.secondary = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final bool destructive;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final child = busy
        ? const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator.adaptive(strokeWidth: 2),
          )
        : Text(label);
    if (isCupertino(context)) {
      if (secondary) {
        return CupertinoButton(
          onPressed: busy ? null : onPressed,
          child: child,
        );
      }
      return CupertinoButton.filled(
        onPressed: busy ? null : onPressed,
        color: destructive ? c.attention : null,
        child: child,
      );
    }
    if (secondary) {
      return OutlinedButton(onPressed: busy ? null : onPressed, child: child);
    }
    return FilledButton(
      style: destructive
          ? FilledButton.styleFrom(
              backgroundColor: c.attention,
              foregroundColor: c.onAttention,
            )
          : null,
      onPressed: busy ? null : onPressed,
      child: child,
    );
  }
}

/// Borderless text action in the platform idiom: CupertinoButton (44 pt) on
/// iOS, TextButton (48 dp target) on Android. [emphasized] = the preferred
/// choice of a pair.
class EpTextButton extends StatelessWidget {
  const EpTextButton({
    super.key,
    required this.label,
    this.onPressed,
    this.emphasized = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool emphasized;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final color = destructive ? c.attention : c.tint;
    final style = TextStyle(
      color: onPressed == null ? null : color,
      fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
    );
    if (isCupertino(context)) {
      return CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: EpSpace.md),
        minimumSize: const Size(44, 44),
        onPressed: onPressed,
        child: Text(label, style: style),
      );
    }
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: style),
    );
  }
}

/// Icon-only action in the platform idiom with a spoken [label]: a 44 pt
/// CupertinoButton on iOS, an IconButton (48 dp, tooltip) on Android.
class EpIconButton extends StatelessWidget {
  const EpIconButton({super.key, required this.icon, required this.label, this.onPressed, this.color, this.size = 22});

  final EpIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final glyph = EpIconView(icon, size: size, color: onPressed == null ? c.inkMuted : (color ?? c.tint));
    if (isCupertino(context)) {
      return Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: onPressed,
          child: glyph,
        ),
      );
    }
    return IconButton(tooltip: label, onPressed: onPressed, icon: glyph);
  }
}

/// With several accounts, a destructive confirmation says which account it
/// acts in: the same screens look alike from one account to the next.
String? _accountNote(BuildContext context) {
  final container = ProviderScope.containerOf(context, listen: false);
  final vault = container.exists(vaultProvider) ? container.read(vaultProvider).value : null;
  final active = vault?.active;
  return active == null || vault!.accounts.length < 2 ? null : context.l10n.confirmAccount(active.name);
}

/// Yes/no confirmation. Returns true when confirmed. A destructive one names
/// the account (with several) unless it isn't [scoped] to the one on screen.
Future<bool> showEpConfirm(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
  bool destructive = false,
  bool scoped = true,
  Widget? content,
}) async {
  final l = context.l10n;
  final cupertino = isCupertino(context);
  final lines = [?message, if (destructive && scoped) ?_accountNote(context)];
  message = lines.isEmpty ? null : lines.join('\n\n');
  final ok = await showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      title: Text(title),
      content: content == null
          ? (message == null ? null : Text(message))
          // Text fields need a Material ancestor inside the Cupertino dialog.
          : Material(
              type: MaterialType.transparency,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (message != null) ...[Text(message), const SizedBox(height: EpSpace.md)],
                  content,
                ],
              ),
            ),
      actions: cupertino
          ? [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.actionCancel),
              ),
              CupertinoDialogAction(
                isDestructiveAction: destructive,
                isDefaultAction: !destructive,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l.actionCancel),
              ),
              TextButton(
                style: destructive
                    ? TextButton.styleFrom(
                        foregroundColor: EpColors.of(ctx).attention,
                      )
                    : null,
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
    ),
  );
  return ok ?? false;
}

/// High-stakes confirmation: the user types [expected] (usually the domain
/// name) before the destructive action unlocks. Names the account, with
/// several.
Future<bool> showEpTypedConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String expected,
  required String confirmLabel,
}) async {
  final note = _accountNote(context);
  final ok = await showAdaptiveDialog<bool>(
    context: context,
    builder: (ctx) => _TypedConfirmDialog(
      title: title,
      message: note == null ? message : '$message\n\n$note',
      expected: expected,
      confirmLabel: confirmLabel,
    ),
  );
  return ok ?? false;
}

class _TypedConfirmDialog extends StatefulWidget {
  const _TypedConfirmDialog({
    required this.title,
    required this.message,
    required this.expected,
    required this.confirmLabel,
  });
  final String title;
  final String message;
  final String expected;
  final String confirmLabel;

  @override
  State<_TypedConfirmDialog> createState() => _TypedConfirmDialogState();
}

class _TypedConfirmDialogState extends State<_TypedConfirmDialog> {
  final _ctl = TextEditingController();
  bool get _match => _ctl.text.trim().toLowerCase() == widget.expected.toLowerCase();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = EpColors.of(context);
    final cupertino = isCupertino(context);
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: cupertino ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(widget.message),
        const SizedBox(height: 8),
        Text(
          l.typeToConfirm(widget.expected),
          style: TextStyle(color: c.inkMuted, fontSize: 13),
        ),
        const SizedBox(height: 10),
        cupertino
            ? CupertinoTextField(
                controller: _ctl,
                autofocus: true,
                autocorrect: false,
                placeholder: widget.expected,
                onChanged: (_) => setState(() {}),
              )
            : TextField(
                controller: _ctl,
                autofocus: true,
                autocorrect: false,
                decoration: InputDecoration(hintText: widget.expected),
                onChanged: (_) => setState(() {}),
              ),
      ],
    );
    return AlertDialog.adaptive(
      title: Text(widget.title),
      content: content,
      actions: cupertino
          ? [
              CupertinoDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.actionCancel),
              ),
              CupertinoDialogAction(
                isDestructiveAction: true,
                onPressed: _match ? () => Navigator.pop(context, true) : null,
                child: Text(widget.confirmLabel),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l.actionCancel),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: c.attention),
                onPressed: _match ? () => Navigator.pop(context, true) : null,
                child: Text(widget.confirmLabel),
              ),
            ],
    );
  }
}

class EpSheetAction<T> {
  const EpSheetAction({
    required this.label,
    required this.value,
    this.icon,
    this.destructive = false,
  });
  final String label;
  final T value;
  final EpIcon? icon;
  final bool destructive;
}

/// Action sheet on iOS (a popover beside the control in a big window, as on
/// iPad), modal bottom sheet on Android.
Future<T?> showEpActionSheet<T>(
  BuildContext context, {
  String? title,
  String? message,
  required List<EpSheetAction<T>> actions,
}) {
  final l = context.l10n;
  if (isCupertino(context) && EpLayout.sheet(context)) {
    return showEpPopover<T>(
      context,
      builder: (ctx) => EpPopoverMenu(
        title: title,
        message: message,
        rows: [
          for (final a in actions)
            EpPopoverRow(
              label: a.label,
              icon: a.icon,
              destructive: a.destructive,
              onTap: () => Navigator.pop(ctx, a.value),
            ),
        ],
      ),
    );
  }
  if (isCupertino(context)) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: title == null ? null : Text(title),
        message: message == null ? null : Text(message),
        actions: [
          for (final a in actions)
            CupertinoActionSheetAction(
              isDestructiveAction: a.destructive,
              onPressed: () => Navigator.pop(ctx, a.value),
              child: Text(a.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.actionCancel),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    // Over the whole app (navigation bar and banners included), not inside
    // the tab that asked.
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      final c = EpColors.of(ctx);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    EpSpace.xl,
                    0,
                    EpSpace.xl,
                    EpSpace.sm,
                  ),
                  child: Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    EpSpace.xl,
                    0,
                    EpSpace.xl,
                    EpSpace.md,
                  ),
                  child: Text(message, style: TextStyle(color: c.inkMuted)),
                ),
              for (final a in actions)
                ListTile(
                  leading: a.icon == null
                      ? null
                      : Icon(
                          a.icon!.material,
                          color: a.destructive ? c.attention : null,
                        ),
                  title: Text(
                    a.label,
                    style: a.destructive ? TextStyle(color: c.attention) : null,
                  ),
                  onTap: () => Navigator.pop(ctx, a.value),
                ),
              const SizedBox(height: EpSpace.sm),
            ],
          ),
        ),
      );
    },
  );
}

/// Transient feedback with an optional action (e.g. Undo). Snackbar on
/// Android; on iOS a banner over the tab bar, the closest native pattern.
void showEpToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (!isCupertino(context)) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.hideCurrentSnackBar();
    messenger?.showSnackBar(
      SnackBar(
        content: Text(message),
        action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
      ),
    );
    return;
  }
  // The root navigator's overlay, above the tabs. Navigator (unlike
  // Overlay) also accepts the root navigator's own context, which is what
  // feedback that outlives its screen uses.
  final overlay = Navigator.maybeOf(context, rootNavigator: true)?.overlay;
  if (overlay == null) return;
  late OverlayEntry entry;
  Timer? timer;
  void remove() {
    timer?.cancel();
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (ctx) => _IosToast(
      message: message,
      actionLabel: actionLabel,
      onDismiss: remove,
      onAction: onAction == null
          ? null
          : () {
              remove();
              onAction();
            },
    ),
  );
  overlay.insert(entry);
  SemanticsService.sendAnnouncement(
    View.of(context),
    message,
    Directionality.of(context),
  );
  // With VoiceOver on, a toast carrying an action (Undo, Open) stays until
  // it's used or dismissed: a screen reader user can't race a timer.
  final assisted = MediaQuery.maybeAccessibleNavigationOf(context) ?? false;
  if (!(assisted && actionLabel != null)) {
    timer = Timer(Duration(seconds: actionLabel == null ? 3 : 5), remove);
  }
}

class _IosToast extends StatelessWidget {
  const _IosToast({required this.message, required this.onDismiss, this.actionLabel, this.onAction});
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Tap the message (or the screen-reader dismiss action) to close it.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    // Above the tab bar (≈50 pt) plus the home indicator inset, counted once.
    final bottom = MediaQuery.paddingOf(context).bottom + 58;
    return Positioned(
      left: EpSpace.lg,
      right: EpSpace.lg,
      bottom: bottom,
      child: Semantics(
        liveRegion: true,
        onDismiss: onDismiss,
        child: GestureDetector(
          onTap: onDismiss,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.only(left: EpSpace.lg, right: EpSpace.xs),
            decoration: BoxDecoration(
              color: c.inverse,
              borderRadius: BorderRadius.circular(EpRadius.lg),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 18, offset: const Offset(0, 6)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      message,
                      style: TextStyle(
                        color: c.onInverse,
                        fontSize: 15,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ),
                ),
                if (actionLabel != null)
                  CupertinoButton(
                    minimumSize: const Size(44, 44),
                    onPressed: onAction,
                    child: Text(
                      actionLabel!,
                      style: TextStyle(
                        color: c.inverseTint,
                        fontWeight: FontWeight.w600,
                      ),
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

/// Copies [text] and confirms with a toast.
Future<void> copyWithToast(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showEpToast(context, context.l10n.copiedToClipboard);
}

/// Shared empty / error / loading content.
class EpMessage extends StatelessWidget {
  const EpMessage({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final EpIcon icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon.of(context), size: 40, color: c.inkMuted),
        const SizedBox(height: EpSpace.md),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (message != null) ...[
          const SizedBox(height: EpSpace.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              message!,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted, height: 1.4),
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: EpSpace.lg), action!],
      ],
    );
  }
}

/// Maps any error to a message the user can act on.
String describeError(BuildContext context, Object error, {String? permission}) {
  final l = context.l10n;
  if (error is CfApiException && error.isPermissionDenied) {
    return permission == null ? l.errorPermissionGeneric : l.errorPermission(permission);
  }
  if (error is CfNoAccessException) {
    return switch (error.reason) {
      NoAccessKind.noToken => l.errorNoToken,
      NoAccessKind.denied => l.errorPermission(error.permission),
      NoAccessKind.needsUserToken => l.errorNeedsUserToken,
    };
  }
  if (error is CfException) return error.message;
  return l.errorGeneric;
}

class EpErrorView extends StatelessWidget {
  const EpErrorView({
    super.key,
    required this.error,
    this.onRetry,
    this.permission,
  });
  final Object error;
  final VoidCallback? onRetry;
  final String? permission;

  @override
  Widget build(BuildContext context) {
    final isPerm =
        (error is CfApiException && (error as CfApiException).isPermissionDenied) || error is CfNoAccessException;
    return EpMessage(
      icon: isPerm ? EpIcon.key : (error is CfNetworkException ? EpIcon.cloud : EpIcon.warning),
      title: isPerm ? context.l10n.errorPermissionGeneric.split('.').first : describeError(context, error),
      message: isPerm
          ? describeError(
              context,
              error,
              permission:
                  permission ?? (error is CfNoAccessException ? (error as CfNoAccessException).permission : null),
            )
          : null,
      action: onRetry == null
          ? null
          : EpButton(
              label: context.l10n.actionRetry,
              onPressed: onRetry,
              secondary: true,
            ),
    );
  }
}

class EpLoading extends StatelessWidget {
  const EpLoading({super.key});
  @override
  Widget build(BuildContext context) => const Center(child: CircularProgressIndicator.adaptive());
}
