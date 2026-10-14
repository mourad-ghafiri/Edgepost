import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'ep_icons.dart';
import 'platform.dart';

/// Where the last touch went down. A popover points at the control that
/// opened it from there, so no caller has to pass the control's rect.
Offset? _lastTouch;

/// Starts noting touches for [showEpPopover]; once, at startup.
void trackPopoverAnchors() {
  GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
    if (event is PointerDownEvent) _lastTouch = event.position;
  });
}

/// A popover beside the control just tapped, as iPadOS presents action
/// sheets and menus in a big window: [width] wide, below the control (above
/// it when there is no room), no dimming; a tap outside closes it.
Future<T?> showEpPopover<T>(BuildContext context, {required WidgetBuilder builder, double width = 320}) =>
    Navigator.of(context, rootNavigator: true).push(
      _PopoverRoute<T>(
        anchor: _lastTouch,
        width: width,
        builder: builder,
        barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      ),
    );

class _PopoverRoute<T> extends PopupRoute<T> {
  _PopoverRoute({required this.anchor, required this.width, required this.builder, required this.barrierLabel});

  final Offset? anchor;
  final double width;
  final WidgetBuilder builder;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final c = EpColors.of(context);
    final padding = MediaQuery.paddingOf(context);
    return CustomSingleChildLayout(
      delegate: _PopoverLayout(anchor: anchor, width: width, padding: padding),
      child: Semantics(
        scopesRoute: true,
        namesRoute: true,
        explicitChildNodes: true,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.raised,
            borderRadius: BorderRadius.circular(EpRadius.lg),
            border: Border.all(color: c.hairline),
            // It floats over the content without a dim, so it needs a shadow
            // to read as above it (the toast is the only other such surface).
            boxShadow: const [BoxShadow(color: Color(0x29000000), blurRadius: 24, offset: Offset(0, 8))],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Builder(builder: builder),
          ),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    );
    if (reduceMotion(context)) return fade;
    return ScaleTransition(
      scale: Tween(begin: 0.96, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: fade,
    );
  }
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout({required this.anchor, required this.width, required this.padding});

  final Offset? anchor;
  final double width;
  final EdgeInsets padding;

  static const _margin = 12.0;
  static const _gap = 14.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final w = (constraints.maxWidth - 2 * _margin).clamp(0.0, width);
    final h = constraints.maxHeight - padding.vertical - 2 * _margin;
    return BoxConstraints(minWidth: w, maxWidth: w, maxHeight: h.clamp(0.0, double.infinity));
  }

  @override
  Offset getPositionForChild(Size size, Size child) {
    final top = padding.top + _margin;
    final bottom = size.height - padding.bottom - _margin;
    final at = anchor;
    if (at == null) return Offset((size.width - child.width) / 2, (size.height - child.height) / 2);
    final x = (at.dx - child.width / 2).clamp(_margin, size.width - child.width - _margin);
    final below = at.dy + _gap;
    final y = below + child.height <= bottom ? below : (at.dy - _gap - child.height).clamp(top, bottom - child.height);
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_PopoverLayout old) => anchor != old.anchor || width != old.width || padding != old.padding;
}

/// One row of a popover menu: its label, then its glyph at the end, as in
/// an iPadOS menu; [checked] marks the current choice.
class EpPopoverRow extends StatefulWidget {
  const EpPopoverRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.destructive = false,
    this.checked = false,
  });

  final String label;
  final VoidCallback onTap;
  final EpIcon? icon;
  final bool destructive;
  final bool checked;

  @override
  State<EpPopoverRow> createState() => _EpPopoverRowState();
}

class _EpPopoverRowState extends State<EpPopoverRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final color = widget.destructive ? c.attention : c.ink;
    final glyph = widget.checked ? EpIcon.check : widget.icon;
    return Semantics(
      button: true,
      selected: widget.checked,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapCancel: () => setState(() => _down = false),
        onTap: () {
          setState(() => _down = false);
          widget.onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          color: _down ? c.neutralWash : null,
          padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 17,
                    fontWeight: widget.checked ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (glyph != null) ...[
                const SizedBox(width: EpSpace.md),
                Icon(glyph.cupertino, size: 20, color: widget.checked ? c.tint : color),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A popover menu: an optional heading, then [rows] split by hairlines,
/// scrolling when they outgrow the window.
class EpPopoverMenu extends StatelessWidget {
  const EpPopoverMenu({super.key, this.title, this.message, required this.rows});

  final String? title;
  final String? message;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final heading = [?title, ?message];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (heading.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.md, EpSpace.lg, EpSpace.md),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.hairline, width: 0.5)),
            ),
            child: Text(
              heading.join('\n'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.inkMuted, fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) Divider(height: 0.5, thickness: 0.5, indent: EpSpace.lg, color: c.hairline),
                  rows[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
