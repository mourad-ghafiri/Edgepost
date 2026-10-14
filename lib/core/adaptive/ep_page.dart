import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n.dart';
import '../theme/tokens.dart';
import 'ep_icons.dart';
import 'layout.dart';
import 'platform.dart';

/// The widest a page's content grows. On a tablet (an iPad's 1,000+ pt) the
/// page is one readable column, centred, instead of cards stretched edge to
/// edge; phones never reach it.
const double kMaxPageWidth = 720;

/// Centres [child] in a column at most [kMaxPageWidth] wide.
class EpReadableWidth extends StatelessWidget {
  const EpReadableWidth({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: kMaxPageWidth),
      child: child,
    ),
  );
}

/// A toolbar or primary action, rendered as a nav-bar button on iOS and an
/// icon button / FAB on Android.
class EpAction {
  const EpAction({required this.icon, required this.label, required this.onPressed, this.badge});

  final EpIcon icon;
  final String label;
  final VoidCallback? onPressed;
  final String? badge;
}

/// A worded action in the top bar ("Save"): always in reach, even with the
/// keyboard up. The bold trailing nav-bar button on iOS, an app-bar text
/// button on Android.
class EpTextAction {
  const EpTextAction({required this.label, required this.onPressed, this.busy = false});

  final String label;

  /// Null disables it (e.g. nothing changed yet).
  final VoidCallback? onPressed;

  /// Shows progress in its place while the action runs.
  final bool busy;
}

/// The control tab roots show at the top right for the active account
/// (`account: true`). Provided by the app layer; nothing by default.
final accountButtonProvider = Provider<Widget?>((ref) => null);

/// Screen scaffold with the platform's title treatment:
/// - iOS: large title collapsing to inline, pull-to-refresh control, actions in
///   the navigation bar, primary action as the trailing nav-bar button.
/// - Android: Material 3 large top app bar, RefreshIndicator, primary action
///   as a FAB.
class EpPage extends StatelessWidget {
  const EpPage({
    super.key,
    required this.title,
    required this.slivers,
    this.subtitle,
    this.onRefresh,
    this.actions = const [],
    this.primaryAction,
    this.floatingAction,
    this.textAction,
    this.largeTitle = true,
    this.previousPageTitle,
    this.bottomBar,
    this.scrollController,
    this.account = false,
    this.splitRoot = false,
  });

  final String title;
  final Widget? subtitle;
  final List<Widget> slivers;
  final Future<void> Function()? onRefresh;
  final List<EpAction> actions;
  final EpAction? primaryAction;

  /// A floating button at the bottom right, on both platforms (the Mail
  /// tab's New message): worded at rest, just its icon while the list
  /// scrolls down (it hides less of it), gone while the keyboard is up.
  final EpAction? floatingAction;
  final EpTextAction? textAction;

  /// Top-level screens use large titles; detail screens stay inline.
  final bool largeTitle;
  final String? previousPageTitle;
  final Widget? bottomBar;
  final ScrollController? scrollController;

  /// Tab roots show the active account's avatar at the top right.
  final bool account;

  /// The first page of a split's detail column (a domain's hub beside the
  /// list): no back button there, since the list is beside it.
  final bool splitRoot;

  bool _back(BuildContext context) => !(splitRoot && EpSplitDetail.of(context));

  @override
  Widget build(BuildContext context) {
    final page = isCupertino(context) ? _cupertino : _material;
    final action = floatingAction;
    if (action == null) return page(context, null);
    return _FloatingHost(action: action, builder: (button) => page(context, button));
  }

  /// Room below the last sliver so a floating button never sits on it.
  double get _endSpace => primaryAction != null || floatingAction != null ? 96 : EpSpace.xl;

  /// The account avatar, last at the top right (it stays visible when the
  /// large title collapses).
  Widget? _accountButton() => !account
      ? null
      : Consumer(builder: (context, ref, _) => ref.watch(accountButtonProvider) ?? const SizedBox.shrink());

  /// The sidebar's show/hide button, first at the top left of tab roots
  /// while the iPad sidebar replaces the tab bar.
  Widget? _sidebarButton(BuildContext context) {
    final scope = account ? EpSidebarScope.maybeOf(context) : null;
    if (scope == null) return null;
    final l = context.l10n;
    return Semantics(
      button: true,
      label: scope.shown ? l.sidebarHide : l.sidebarShow,
      excludeSemantics: true,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: scope.toggle,
        child: Icon(EpIcon.sidebar.cupertino, size: 24),
      ),
    );
  }

  /// Flutter keeps a large title collapsed in landscape, as an iPhone does
  /// (compact height). An iPad has the height for it in landscape too, and
  /// shows it there: its bar is told the window is portrait.
  Widget _regularHeightTitle(BuildContext context, Widget bar) {
    final mq = MediaQuery.of(context);
    if (mq.orientation == Orientation.portrait || mq.size.height < EpLayout.sidebarMinHeight) return bar;
    return MediaQuery(
      data: mq.copyWith(size: Size(mq.size.width, mq.size.width + 1)),
      child: bar,
    );
  }

  Widget _cupertino(BuildContext context, Widget? floating) {
    final c = EpColors.of(context);
    final sidebarButton = _sidebarButton(context);
    final trailing = [
      ...actions,
      ?primaryAction,
    ];
    final accountButton = _accountButton();
    final text = textAction;
    final trailingRow = trailing.isEmpty && accountButton == null && text == null
        ? null
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (text != null)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(44, 44),
                  onPressed: text.busy ? null : text.onPressed,
                  child: text.busy
                      ? const CupertinoActivityIndicator()
                      : Text(text.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              for (final a in trailing)
                Semantics(
                  button: true,
                  label: a.label,
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(44, 44),
                    onPressed: a.onPressed,
                    child: Icon(a.icon.cupertino, size: 24),
                  ),
                ),
              ?accountButton,
            ],
          );
    final body = CustomScrollView(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
      slivers: [
        if (largeTitle)
          _regularHeightTitle(
            context,
            CupertinoSliverNavigationBar(
              largeTitle: Text(title),
              leading: sidebarButton,
              automaticallyImplyLeading: _back(context),
              trailing: trailingRow,
              previousPageTitle: previousPageTitle,
              transitionBetweenRoutes: !EpSplitDetail.of(context),
              backgroundColor: c.canvas.withValues(alpha: 0.92),
              border: Border(bottom: BorderSide(color: c.hairline, width: 0)),
            ),
          ),
        if (onRefresh != null) CupertinoSliverRefreshControl(onRefresh: onRefresh),
        if (subtitle != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(EpSpace.lg, 0, EpSpace.lg, EpSpace.sm),
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, color: c.inkMuted),
                child: subtitle!,
              ),
            ),
          ),
        ..._sideSafe(context, slivers),
        SliverToBoxAdapter(child: SizedBox(height: _endSpace)),
      ],
    );
    return Scaffold(
      backgroundColor: c.canvas,
      floatingActionButton: floating,
      appBar: largeTitle
          ? null
          : CupertinoNavigationBar(
              middle: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
              leading: sidebarButton,
              automaticallyImplyLeading: _back(context),
              trailing: trailingRow,
              previousPageTitle: previousPageTitle,
              transitionBetweenRoutes: !EpSplitDetail.of(context),
              backgroundColor: c.canvas.withValues(alpha: 0.92),
            ),
      body: EpReadableWidth(child: body),
      bottomNavigationBar: bottomBar,
    );
  }

  Widget _material(BuildContext context, Widget? floating) {
    final c = EpColors.of(context);
    final subtitleHeight = subtitle == null ? 0.0 : MediaQuery.textScalerOf(context).scale(13) * 1.4 + EpSpace.sm;
    final scroll = CustomScrollView(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (largeTitle)
          SliverAppBar.large(
            title: Text(title),
            // The subtitle as the bar's bottom sits right under the title
            // (the bar drops its title padding then), as on iOS.
            expandedHeight: 120 + subtitleHeight,
            bottom: subtitle == null
                ? null
                : PreferredSize(
                    preferredSize: Size.fromHeight(subtitleHeight),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(EpSpace.lg, 0, EpSpace.lg, EpSpace.sm),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DefaultTextStyle.merge(
                          style: TextStyle(fontSize: 13, color: c.inkMuted),
                          child: subtitle!,
                        ),
                      ),
                    ),
                  ),
            actions: [
              for (final a in actions) _iconButton(a),
              ?_textButton(),
              ?_accountButton(),
              const SizedBox(width: EpSpace.xs),
            ],
          )
        else
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: _back(context),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [for (final a in actions) _iconButton(a), ?_textButton()],
          ),
        if (subtitle != null && !largeTitle)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(EpSpace.lg, 0, EpSpace.lg, EpSpace.sm),
              child: DefaultTextStyle.merge(
                style: TextStyle(fontSize: 13, color: c.inkMuted),
                child: subtitle!,
              ),
            ),
          ),
        ..._sideSafe(context, slivers),
        SliverToBoxAdapter(child: SizedBox(height: _endSpace)),
      ],
    );
    final fab = primaryAction;
    return Scaffold(
      backgroundColor: c.canvas,
      body: EpReadableWidth(
        child: onRefresh == null ? scroll : RefreshIndicator(onRefresh: onRefresh!, child: scroll),
      ),
      floatingActionButton:
          floating ??
          (fab == null
              ? null
              : FloatingActionButton.extended(
                  onPressed: fab.onPressed,
                  icon: Icon(fab.icon.material),
                  label: Text(fab.label),
                )),
      bottomNavigationBar: bottomBar,
    );
  }

  Widget? _textButton() {
    final a = textAction;
    if (a == null) return null;
    return Padding(
      padding: const EdgeInsets.only(right: EpSpace.xs),
      child: a.busy
          ? const Padding(
              padding: EdgeInsets.symmetric(horizontal: EpSpace.lg),
              child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          : TextButton(
              onPressed: a.onPressed,
              child: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
    );
  }

  Widget _iconButton(EpAction a) => IconButton(
    tooltip: a.label,
    onPressed: a.onPressed,
    icon: a.badge == null ? Icon(a.icon.material) : Badge(label: Text(a.badge!), child: Icon(a.icon.material)),
  );
}

/// Centred filler for loading, empty and error states inside a sliver list.
class EpFill extends StatelessWidget {
  const EpFill({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => SliverFillRemaining(
    hasScrollBody: false,
    child: Center(
      child: Padding(padding: const EdgeInsets.all(EpSpace.xl), child: child),
    ),
  );
}

/// In landscape the sensor housing and rounded corners take the sides:
/// content keeps clear of them (portrait has no side insets, so it's
/// untouched).
List<Widget> _sideSafe(BuildContext context, List<Widget> slivers) {
  final p = MediaQuery.paddingOf(context);
  if (p.left == 0 && p.right == 0) return slivers;
  return [SliverSafeArea(top: false, bottom: false, sliver: SliverMainAxisGroup(slivers: slivers))];
}

/// Keeps a page's floating button worded or compact: compact while the list
/// is scrolled down, worded again on the way back up or at the top.
class _FloatingHost extends StatefulWidget {
  const _FloatingHost({required this.action, required this.builder});
  final EpAction action;
  final Widget Function(Widget button) builder;

  @override
  State<_FloatingHost> createState() => _FloatingHostState();
}

class _FloatingHostState extends State<_FloatingHost> {
  bool _extended = true;

  bool _onScroll(UserScrollNotification n) {
    // The page's own list, not a sideways row inside it.
    if (n.metrics.axis != Axis.vertical) return false;
    final extended = switch (n.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => n.metrics.pixels <= n.metrics.minScrollExtent || _extended,
    };
    if (extended != _extended) setState(() => _extended = extended);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return NotificationListener<UserScrollNotification>(
      onNotification: _onScroll,
      child: widget.builder(
        _FloatingButton(action: widget.action, extended: _extended, hidden: keyboard),
      ),
    );
  }
}

/// The floating button: action blue, flat, 14 pt corners (the system's FAB
/// shape), its label sliding in and out.
class _FloatingButton extends StatelessWidget {
  const _FloatingButton({required this.action, required this.extended, required this.hidden});
  final EpAction action;
  final bool extended;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final c = EpColors.of(context);
    final cupertino = isCupertino(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(EpRadius.lg));
    final content = SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(cupertino ? action.icon.cupertino : action.icon.material, color: c.onTint, size: 24),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: extended
                  ? Padding(
                      padding: const EdgeInsetsDirectional.only(start: 10, end: 4),
                      child: Text(
                        action.label,
                        maxLines: 1,
                        style: TextStyle(color: c.onTint, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    )
                  : const SizedBox(height: 24),
            ),
          ],
        ),
      ),
    );
    final button = cupertino
        ? CupertinoButton(
            padding: EdgeInsets.zero,
            minimumSize: const Size(56, 56),
            onPressed: action.onPressed,
            child: DecoratedBox(
              decoration: ShapeDecoration(color: c.tint, shape: shape),
              child: content,
            ),
          )
        : Material(
            color: c.tint,
            shape: shape,
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: action.onPressed, child: content),
          );
    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedOpacity(
        opacity: hidden ? 0 : 1,
        duration: const Duration(milliseconds: 150),
        child: Semantics(
          button: true,
          label: action.label,
          excludeSemantics: true,
          onTap: hidden ? null : action.onPressed,
          child: button,
        ),
      ),
    );
  }
}
