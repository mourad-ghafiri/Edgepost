import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'ep_icons.dart';
import 'ep_widgets.dart';
import 'platform.dart';

/// Layout decisions from the window's size (size classes), never from the
/// device model: an iPad in Slide Over or a narrow Split View is laid out as
/// a phone, an iPhone Pro Max in landscape as a wide window, and a Stage
/// Manager window as whatever size the user drags it to.
abstract final class EpLayout {
  /// On iOS the tab bar becomes a sidebar from this window width…
  static const sidebarMinWidth = 680.0;

  /// …when the window is also this tall: an iPhone in landscape keeps its
  /// tab bar, as iPhone apps do.
  static const sidebarMinHeight = 500.0;

  /// The sidebar's own width.
  static const sidebarWidth = 260.0;

  /// From this window width the sidebar stays docked beside the content.
  /// Narrower sidebar windows (iPad portrait, most Split View and Stage
  /// Manager sizes) give the content the whole width, so Mail and Domains
  /// keep their split, and slide the sidebar in over it on demand, as iPad
  /// Mail and Files do in portrait.
  static const sidebarDockMinWidth = 1100.0;

  /// Android's navigation rail, Material's "medium" window class.
  static const railMinWidth = 600.0;

  /// The rail's width (Material 3's default).
  static const railWidth = 80.0;

  /// A list and its detail sit side by side once their area is this wide.
  static const splitMinWidth = 720.0;

  /// The list's column in a split: wide enough for a card's three fields.
  static double listWidth(double area) => (area * 0.42).clamp(340.0, 400.0);

  /// Whether the iOS shell shows the sidebar.
  static bool sidebar(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return isCupertino(context) && size.width >= sidebarMinWidth && size.height >= sidebarMinHeight;
  }

  /// Whether that sidebar is docked (else it slides in over the content).
  static bool sidebarDocked(BuildContext context) =>
      sidebar(context) && MediaQuery.sizeOf(context).width >= sidebarDockMinWidth;

  /// Whether a list and its detail sit side by side in this window: the
  /// width beside the navigation against [splitMinWidth]. [EpSplit] measures
  /// for itself; this tells navigation where an item will open (a thread
  /// from Today or a notification opens beside the inbox, not over it).
  static bool splits(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final nav = isCupertino(context)
        ? (sidebarDocked(context) ? sidebarWidth : 0.0)
        : (width >= railMinWidth ? railWidth : 0.0);
    return width - nav >= splitMinWidth;
  }

  /// A window big enough for a modal to float as a sheet instead of covering
  /// the screen (iPad form sheet, a Material dialog on large screens).
  static bool sheet(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return size.width >= sidebarMinWidth && size.height >= sidebarMinHeight;
  }
}

/// The sidebar's state for the pages under it: tab roots show a button that
/// shows or hides it.
class EpSidebarScope extends InheritedWidget {
  const EpSidebarScope({super.key, required this.shown, required this.toggle, required super.child});

  /// Whether the sidebar is on screen.
  final bool shown;
  final VoidCallback toggle;

  static EpSidebarScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<EpSidebarScope>();

  @override
  bool updateShouldNotify(EpSidebarScope oldWidget) => shown != oldWidget.shown;
}

/// Marks the detail side of an [EpSplit]: its pages share the split's route,
/// or sit in a navigator of their own, so their navigation bars take no part
/// in the outer route transitions.
class EpSplitDetail extends InheritedWidget {
  const EpSplitDetail({super.key, required super.child});

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<EpSplitDetail>() != null;

  @override
  bool updateShouldNotify(EpSplitDetail oldWidget) => false;
}

/// A list and its detail side by side when [EpLayout.splitMinWidth] fits,
/// like iPad Mail; otherwise [narrow], or the list alone, which then pushes
/// its detail.
class EpSplit extends StatelessWidget {
  const EpSplit({super.key, required this.list, required this.detail, this.narrow});

  /// The list, told whether it sits in a split (a tap then selects instead
  /// of pushing).
  final Widget Function(BuildContext context, bool split) list;

  /// The chosen item, or an [EpSplitPlaceholder].
  final Widget detail;

  /// What a narrow window shows instead of the list (a navigator holding
  /// the list and what it pushed).
  final Widget? narrow;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      if (box.maxWidth < EpLayout.splitMinWidth) return narrow ?? list(context, false);
      final c = EpColors.of(context);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: EpLayout.listWidth(box.maxWidth), child: list(context, true)),
          ColoredBox(color: c.hairline, child: const SizedBox(width: 1)),
          Expanded(
            child: EpSplitDetail(
              child: AnimatedSwitcher(
                duration: reduceMotion(context) ? Duration.zero : const Duration(milliseconds: 160),
                child: detail,
              ),
            ),
          ),
        ],
      );
    },
  );
}

/// The detail side of a split before anything is chosen.
class EpSplitPlaceholder extends StatelessWidget {
  const EpSplitPlaceholder({super.key, required this.icon, required this.text});
  final EpIcon icon;
  final String text;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: EpColors.of(context).canvas,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(EpSpace.xl),
        child: EpMessage(icon: icon, title: text),
      ),
    ),
  );
}
