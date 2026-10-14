import 'dart:async';

import 'package:flutter/material.dart';

import '../adaptive/ep_icons.dart';
import '../adaptive/platform.dart';
import '../theme/tokens.dart';

/// One value on a card: a small label over a tabular value.
class StripField {
  const StripField(this.label, this.value, {this.color, this.data = false, this.flex = 3});

  final String label;
  final String value;

  /// A status colour ([EpColors.ok], [EpColors.caution],
  /// [EpColors.attention]): the value shows as a pill in it. Null for plain
  /// ink.
  final Color? color;

  /// Monospace value (addresses, record content, IDs).
  final bool data;
  final int flex;
}

/// The app's card for a domain, a message or a deployment: a family glyph and
/// a title, optional values beneath, optional detail text.
///
/// When [cocked] (it needs the user), the card takes a red hairline, shows its
/// [reason] and sits [EpSpace.nudge] out of line; once resolved it settles
/// back (a crossfade under Reduce Motion).
class Strip extends StatelessWidget {
  const Strip({
    super.key,
    required this.title,
    required this.family,
    this.caption,
    this.detail,
    this.fields = const [],
    this.reason,
    this.cocked = false,
    this.emphasis = false,
    this.selected = false,
    this.onTap,
    this.onLongPress,
    this.semanticLabel,
    this.leading,
  });

  /// Domain name, sender, or script name.
  final String title;
  final Family family;
  final String? caption;

  /// Free text under the title row (e.g. a mail subject).
  final Widget? detail;
  final List<StripField> fields;

  /// Why the card needs the user ("Nameservers not switched").
  final String? reason;
  final bool cocked;

  /// Bolder title, e.g. unread mail.
  final bool emphasis;

  /// The one open beside its list (a split's detail): action blue on its
  /// wash, as selection is drawn everywhere. Needing the user wins.
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String? semanticLabel;

  /// Replaces the family glyph (an unread dot, an account avatar, a pin).
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final motionOff = reduceMotion(context);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final settle = StripSettle.maybeOf(context);
    final settled = settle?.settled ?? false;
    final cocked = this.cocked && !settled;
    final radius = BorderRadius.circular(EpRadius.md);

    final body = _StripBody(
      title: title,
      family: family,
      caption: caption,
      detail: detail,
      fields: fields,
      reason: cocked ? reason : null,
      note: settled ? settle!.note : null,
      motionOff: motionOff,
      emphasis: emphasis,
      stacked: scale > 1.25,
      wrapValues: scale > 1.1,
      leading: leading,
    );

    final card = AnimatedContainer(
      duration: motionOff ? Duration.zero : const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        color: selected && !cocked ? c.tintWash : c.surface,
        borderRadius: radius,
        border: Border.all(color: cocked ? c.attention : (selected ? c.tint : c.hairline)),
      ),
      child: ClipRRect(borderRadius: radius, child: body),
    );

    // A curated label replaces the card's own texts, so a screen reader
    // doesn't read the title and every value a second time.
    final interactive = Semantics(
      container: true,
      button: onTap != null,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      child: EpPressable(onTap: onTap, onLongPress: onLongPress, radius: EpRadius.md, child: card),
    );

    if (motionOff) {
      return Padding(
        padding: EdgeInsets.only(left: cocked ? EpSpace.nudge : 0, right: cocked ? 0 : EpSpace.nudge),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: KeyedSubtree(key: ValueKey(cocked), child: interactive),
        ),
      );
    }
    return TweenAnimationBuilder<double>(
      tween: Tween(end: cocked ? EpSpace.nudge : 0),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, dx, child) => Padding(
        padding: EdgeInsets.only(left: dx.clamp(0, EpSpace.nudge), right: (EpSpace.nudge - dx).clamp(0, EpSpace.nudge)),
        child: child,
      ),
      child: interactive,
    );
  }
}

/// The family glyph: a small neutral square with the family's icon.
class FamilyGlyph extends StatelessWidget {
  const FamilyGlyph({super.key, required this.family, this.icon});

  final Family family;

  /// Another icon in the same square (e.g. a pin on a pinned domain).
  final EpIcon? icon;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    if (family == Family.neutral && icon == null) return const SizedBox.shrink();
    final glyph =
        icon ??
        switch (family) {
          Family.domains => EpIcon.domains,
          Family.mail => EpIcon.mail,
          Family.compute => EpIcon.compute,
          Family.neutral => EpIcon.domains,
        };
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: c.neutralWash, borderRadius: BorderRadius.circular(EpRadius.sm + 1)),
      alignment: Alignment.center,
      child: EpIconView(glyph, size: 16, color: c.inkMuted),
    );
  }
}

class _StripBody extends StatelessWidget {
  const _StripBody({
    required this.title,
    required this.family,
    required this.caption,
    required this.detail,
    required this.fields,
    required this.reason,
    required this.note,
    required this.motionOff,
    required this.emphasis,
    required this.stacked,
    required this.wrapValues,
    required this.leading,
  });

  final String title;
  final Family family;
  final String? caption;
  final Widget? detail;
  final List<StripField> fields;
  final String? reason;

  /// Shown once the card is back in line ("Back in line").
  final String? note;
  final bool motionOff;
  final bool emphasis;
  final bool stacked;

  /// Large text: values wrap instead of truncating (no "2,461 / 3,0…").
  final bool wrapValues;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final lead = leading ?? (family == Family.neutral ? null : FamilyGlyph(family: family));
    final hasBelow = fields.isNotEmpty || detail != null;

    final header = Padding(
      padding: EdgeInsets.fromLTRB(EpSpace.md, EpSpace.md, EpSpace.md, hasBelow ? EpSpace.sm : EpSpace.md),
      child: Row(
        children: [
          if (lead != null) ...[lead, const SizedBox(width: 10)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: EpType.title(context, weight: emphasis ? FontWeight.w700 : FontWeight.w600),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    maxLines: wrapValues ? 3 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: EpType.numbers(TextStyle(fontSize: 13, height: 1.3, color: c.inkMuted)),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    final values = fields.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(EpSpace.md, 0, EpSpace.md, detail == null ? EpSpace.md : EpSpace.sm),
            child: LayoutBuilder(
              builder: (context, box) {
                final flexSum = fields.fold<int>(0, (s, f) => s + f.flex);
                final narrowest = fields.map((f) => box.maxWidth * f.flex / flexSum).reduce((a, b) => a < b ? a : b);
                final cells = [for (final f in fields) _FieldCell(field: f, wrap: wrapValues)];
                // Large text or many values: two to a row, nothing truncates.
                if (stacked || narrowest < 84) {
                  return Wrap(
                    runSpacing: EpSpace.sm,
                    children: [for (final cell in cells) SizedBox(width: box.maxWidth / 2, child: cell)],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (var i = 0; i < fields.length; i++) Expanded(flex: fields[i].flex, child: cells[i])],
                );
              },
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        ?values,
        if (detail != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(EpSpace.md, 0, EpSpace.md, EpSpace.md),
            child: DefaultTextStyle.merge(
              style: TextStyle(color: c.ink, fontSize: 15, height: 1.35),
              child: detail!,
            ),
          ),
        // The reason folds away as the card settles back; a short note
        // confirms it's handled.
        AnimatedSize(
          duration: motionOff ? Duration.zero : const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: reason != null
                ? Container(
                    key: const ValueKey('reason'),
                    width: double.infinity,
                    color: c.attentionWash,
                    padding: const EdgeInsets.symmetric(horizontal: EpSpace.md, vertical: EpSpace.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: EpIconView(EpIcon.warning, size: 15, color: c.attention),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            reason!,
                            style: TextStyle(
                              color: c.attention,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : note != null
                ? Container(
                    key: const ValueKey('note'),
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: EpSpace.md, vertical: EpSpace.sm),
                    decoration: BoxDecoration(color: c.okWash),
                    child: Row(
                      children: [
                        EpIconView(EpIcon.check, size: 15, color: c.ok),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            note!,
                            style: TextStyle(color: c.ok, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox(key: ValueKey('none'), width: double.infinity),
          ),
        ),
      ],
    );
  }
}

class _FieldCell extends StatelessWidget {
  const _FieldCell({required this.field, this.wrap = false});
  final StripField field;
  final bool wrap;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final valueStyle = field.data
        ? EpType.data(context, size: 13, color: field.color ?? c.ink)
        : EpType.fieldValue(context, color: field.color);
    return Padding(
      padding: const EdgeInsets.only(right: EpSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EpType.fieldLabel(context),
          ),
          const SizedBox(height: 2),
          if (field.color case final Color status)
            // Status: a pill, its wash behind its colour.
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: EpSpace.sm, vertical: 2),
              decoration: BoxDecoration(color: c.washOf(status), borderRadius: BorderRadius.circular(EpRadius.pill)),
              child: Text(
                field.value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: valueStyle.copyWith(fontSize: (valueStyle.fontSize ?? 15) - 2, fontWeight: FontWeight.w600),
              ),
            )
          else
            Text(field.value, maxLines: wrap ? 3 : 1, overflow: TextOverflow.ellipsis, style: valueStyle),
        ],
      ),
    );
  }
}

/// Press feedback in the platform idiom: a dim on iOS (no Material ink),
/// an ink ripple on Android.
class EpPressable extends StatefulWidget {
  const EpPressable({super.key, required this.child, this.onTap, this.onLongPress, this.radius = 0});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;

  @override
  State<EpPressable> createState() => _EpPressableState();
}

class _EpPressableState extends State<EpPressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null && widget.onLongPress == null) return widget.child;
    if (!isCupertino(context)) {
      return Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.radius),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: widget.child,
        ),
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapCancel: () => setState(() => _down = false),
      onTapUp: (_) => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedOpacity(
        opacity: _down ? 0.6 : 1,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}

/// A labelled group of cards with a count, optionally a trailing action
/// ("All 14").
class StripBay extends StatelessWidget {
  const StripBay({super.key, required this.title, required this.children, this.count, this.trailing, this.empty});

  final String title;
  final int? count;
  final Widget? trailing;
  final List<Widget> children;

  /// Shown when [children] is empty (e.g. "Nothing needs you").
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.bay, EpSpace.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BayHeader(title: title, count: count, trailing: trailing),
          const SizedBox(height: EpSpace.sm),
          if (children.isEmpty && empty != null)
            empty!
          else
            for (var i = 0; i < children.length; i++)
              Padding(
                // Keyed by the strip so reordering keeps each strip's state.
                key: children[i].key == null ? null : ValueKey(('bay', children[i].key)),
                padding: EdgeInsets.only(top: i == 0 ? 0 : EpSpace.sm),
                child: children[i],
              ),
        ],
      ),
    );
  }
}

/// [StripBay] for long lists (an inbox, every domain): the header plus strips
/// built lazily as they scroll in. Use it directly in a sliver list.
class SliverStripBay extends StatelessWidget {
  const SliverStripBay({
    super.key,
    this.title,
    required this.itemCount,
    required this.itemBuilder,
    this.count,
    this.trailing,
  });

  /// Null when the screen already names the list (no repeated label).
  final String? title;
  final int? count;
  final Widget? trailing;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return SliverMainAxisGroup(
      slivers: [
        if (title != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(EpSpace.lg, EpSpace.bay, EpSpace.lg, EpSpace.sm),
            sliver: SliverToBoxAdapter(
              child: _BayHeader(title: title!, count: count, trailing: trailing),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: EpSpace.lg)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: EpSpace.lg),
          sliver: SliverList.builder(
            itemCount: itemCount,
            itemBuilder: (context, i) => Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : EpSpace.sm),
              child: itemBuilder(context, i),
            ),
          ),
        ),
      ],
    );
  }
}

class _BayHeader extends StatelessWidget {
  const _BayHeader({required this.title, this.count, this.trailing});
  final String title;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title.toUpperCase(), style: EpType.groupLabel(context)),
          if (count != null) ...[
            const SizedBox(width: EpSpace.sm),
            Text('$count', style: EpType.numbers(EpType.groupLabel(context, color: c.ink))),
          ],
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// Holds a strip back in line after what cocked it was resolved, before it
/// leaves its bay. [Strip] reads it: [settled] overrides `cocked`.
class StripSettle extends InheritedWidget {
  const StripSettle({super.key, required this.settled, this.note, required super.child});

  final bool settled;
  final String? note;

  static StripSettle? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<StripSettle>();

  @override
  bool updateShouldNotify(StripSettle oldWidget) => settled != oldWidget.settled || note != oldWidget.note;
}

/// A bay of cocked strips ("Needs you") where resolving one is visible: the
/// strip springs back into line, says [settledNote], then folds away. Every
/// child needs a stable key. The beat only starts while the bay is on screen,
/// so a fix made elsewhere plays when the user comes back.
class SettlingStripBay extends StatefulWidget {
  const SettlingStripBay({super.key, required this.title, required this.children, this.empty, this.settledNote});

  final String title;
  final List<Widget> children;
  final Widget? empty;
  final String? settledNote;

  @override
  State<SettlingStripBay> createState() => _SettlingStripBayState();
}

class _Settling {
  _Settling(this.widget, this.index);
  final Widget widget;
  final int index;
  bool started = false;
  bool leaving = false;
}

class _SettlingStripBayState extends State<SettlingStripBay> {
  static const _hold = Duration(milliseconds: 1800);
  static const _fold = Duration(milliseconds: 320);

  late List<Widget> _last;
  final Map<Key, _Settling> _settling = {};
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _last = widget.children;
  }

  @override
  void didUpdateWidget(SettlingStripBay old) {
    super.didUpdateWidget(old);
    final now = {for (final w in widget.children) w.key};
    for (var i = 0; i < _last.length; i++) {
      final k = _last[i].key;
      if (k != null && !now.contains(k) && !_settling.containsKey(k)) _settling[k] = _Settling(_last[i], i);
    }
    // Cocked again before it left: it's simply back in the list.
    _settling.removeWhere((k, _) => now.contains(k));
    _last = widget.children;
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _start(Key k, _Settling s) {
    s.started = true;
    _timers.add(
      Timer(_hold, () {
        if (!mounted || _settling[k] != s) return;
        setState(() => s.leaving = true);
        _timers.add(
          Timer(_fold, () {
            if (mounted && _settling[k] == s) setState(() => _settling.remove(k));
          }),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = TickerMode.valuesOf(context).enabled;
    if (visible) {
      for (final e in _settling.entries.where((e) => !e.value.started)) {
        _start(e.key, e.value);
      }
    }
    final motionOff = reduceMotion(context);
    final items = <(Key?, Widget, bool, bool)>[for (final w in widget.children) (w.key, w, false, false)];
    for (final s in _settling.entries.toList()..sort((a, b) => a.value.index.compareTo(b.value.index))) {
      items.insert(s.value.index.clamp(0, items.length), (s.key, s.value.widget, true, s.value.leaving));
    }
    return StripBay(
      title: widget.title,
      count: widget.children.length,
      empty: widget.empty,
      children: [
        for (final (k, w, settled, leaving) in items)
          KeyedSubtree(
            key: k,
            child: StripSettle(
              settled: settled,
              note: widget.settledNote,
              child: ClipRect(
                child: AnimatedAlign(
                  alignment: Alignment.topCenter,
                  // Reduce Motion: a crossfade only; the row is removed once
                  // it has fully faded instead of collapsing under it.
                  heightFactor: leaving && !motionOff ? 0 : 1,
                  duration: _fold,
                  curve: Curves.easeInCubic,
                  child: AnimatedOpacity(opacity: leaving ? 0 : 1, duration: _fold, child: w),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
