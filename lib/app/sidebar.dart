import 'package:flutter/material.dart';

import '../core/adaptive/layout.dart';
import '../core/adaptive/platform.dart';
import '../core/l10n.dart';
import '../core/strip/strip.dart' show EpPressable;
import '../core/theme/tokens.dart';
import '../core/widgets/brand_mark.dart';

/// One section in the [EpSidebar].
class SidebarItem {
  const SidebarItem({required this.icon, required this.label, this.count = 0, this.urgent = false, this.spoken});

  final IconData icon;
  final String label;

  /// Shown at the row's end when above zero.
  final int count;

  /// The count means "needs you" (attention) rather than "unread".
  final bool urgent;

  /// What a screen reader says for the count ("4 need you").
  final String? spoken;
}

/// The iPad sidebar that replaces the tab bar in wide windows: the
/// Signpost wordmark, then one row per section. The selected row sits on a
/// neutral wash with its glyph in the brand orange, as the active tab is
/// drawn on iPhone.
class EpSidebar extends StatelessWidget {
  const EpSidebar({super.key, required this.items, required this.selected, required this.onSelect});

  final List<SidebarItem> items;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    return Container(
      width: EpLayout.sidebarWidth,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.hairline)),
      ),
      child: SafeArea(
        right: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(EpSpace.md, EpSpace.lg, EpSpace.md, EpSpace.lg),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(EpSpace.sm, 0, EpSpace.sm, EpSpace.xl),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wordmark(name: context.l10n.appName, size: 20),
              ),
            ),
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              _Row(item: items[i], selected: i == selected, onTap: () => onSelect(i)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.selected, required this.onTap});
  final SidebarItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final count = item.count;
    return Semantics(
      button: true,
      selected: selected,
      label: [item.label, if (count > 0) item.spoken ?? '$count'].join(', '),
      excludeSemantics: true,
      child: EpPressable(
        onTap: onTap,
        radius: EpRadius.md,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: EpSpace.md, vertical: EpSpace.sm),
          decoration: BoxDecoration(
            color: selected ? c.neutralWash : Colors.transparent,
            borderRadius: BorderRadius.circular(EpRadius.md),
          ),
          child: Row(
            children: [
              Icon(item.icon, size: 22, color: selected ? c.brand : c.inkMuted),
              const SizedBox(width: EpSpace.md),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.ink,
                    fontSize: 17,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (count > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 24),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: item.urgent ? c.attention : c.neutralWash,
                    borderRadius: BorderRadius.circular(EpRadius.pill),
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: EpType.numbers(
                      TextStyle(
                        color: item.urgent ? c.onAttention : c.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
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

/// The iPad shell's frame: [sidebar] docked beside [body] in wide windows,
/// slid in over it on demand ([overlay]) in narrower ones.
class EpSidebarFrame extends StatelessWidget {
  const EpSidebarFrame({
    super.key,
    required this.docked,
    required this.dockHidden,
    required this.overlay,
    required this.onDismiss,
    required this.dismissLabel,
    required this.sidebar,
    required this.body,
  });

  final bool docked;
  final bool dockHidden;
  final Animation<double> overlay;
  final VoidCallback onDismiss;
  final String dismissLabel;
  final Widget sidebar;
  final Widget body;

  @override
  Widget build(BuildContext context) => docked
      ? Row(
          children: [
            EpDockedSidebar(hidden: dockHidden, child: sidebar),
            Expanded(child: body),
          ],
        )
      : Stack(
          // The window's whole size, whatever the parent allows.
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: body),
            EpSlidingSidebar(animation: overlay, onDismiss: onDismiss, dismissLabel: dismissLabel, child: sidebar),
          ],
        );
}

/// The sidebar docked beside the content in wide windows; hiding it slides
/// it shut and gives the content its width.
class EpDockedSidebar extends StatelessWidget {
  const EpDockedSidebar({super.key, required this.hidden, required this.child});
  final bool hidden;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 280),
    curve: Curves.easeOutCubic,
    width: hidden ? 0 : EpLayout.sidebarWidth,
    child: ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerRight,
        minWidth: EpLayout.sidebarWidth,
        maxWidth: EpLayout.sidebarWidth,
        child: ExcludeFocus(
          excluding: hidden,
          child: ExcludeSemantics(excluding: hidden, child: child),
        ),
      ),
    ),
  );
}

/// The sidebar slid in over the content in narrower windows (iPad
/// portrait), above a light scrim that closes it.
class EpSlidingSidebar extends StatelessWidget {
  const EpSlidingSidebar({
    super.key,
    required this.animation,
    required this.onDismiss,
    required this.dismissLabel,
    required this.child,
  });

  final Animation<double> animation;
  final VoidCallback onDismiss;
  final String dismissLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      if (animation.value == 0) return const SizedBox.shrink();
      final t = Curves.easeOutCubic.transform(animation.value);
      // Screen readers stay in the sidebar while it is out.
      return BlockSemantics(
        child: Stack(
          children: [
            Positioned.fill(
              child: ModalBarrier(
                color: Color.fromRGBO(0, 0, 0, 0.2 * t),
                onDismiss: onDismiss,
                semanticsLabel: dismissLabel,
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: EpLayout.sidebarWidth,
              child: FractionalTranslation(translation: Offset(t - 1, 0), child: child),
            ),
          ],
        ),
      );
    },
  );
}
