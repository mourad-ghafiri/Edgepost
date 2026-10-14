import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/adaptive/layout.dart';
import '../core/adaptive/platform.dart';
import '../core/theme/tokens.dart';

/// Root navigator, for full-screen flows that cover the tab bar (compose,
/// setup wizards).
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// A context above the tab shell (which is rebuilt on an account switch),
/// for feedback that outlives the screen that asked for it.
BuildContext? rootContextForToast() => rootNavigatorKey.currentContext;

/// A modal task (compose, adding an account) in the platform idiom: full
/// screen on a phone (sliding up on iOS); in a big window (iPad, a large
/// Android screen) a sheet floating over the dimmed app, as iPadOS presents
/// a form sheet.
Page<void> modalPage(BuildContext context, GoRouterState state, Widget child) => EpLayout.sheet(context)
    ? _SheetPage(key: state.pageKey, child: child)
    : isCupertino(context)
    ? CupertinoPage<void>(key: state.pageKey, fullscreenDialog: true, child: child)
    : MaterialPage<void>(key: state.pageKey, fullscreenDialog: true, child: child);

/// An edit task with its own Save, opened from more than one place (a
/// domain's signature and logo): pushed like any page on a phone, a sheet in
/// a big window, so it never stretches across an iPad.
Page<void> formPage(BuildContext context, GoRouterState state, Widget child) => EpLayout.sheet(context)
    ? _SheetPage(key: state.pageKey, child: child)
    : isCupertino(context)
    ? CupertinoPage<void>(key: state.pageKey, child: child)
    : MaterialPage<void>(key: state.pageKey, child: child);

class _SheetPage extends Page<void> {
  const _SheetPage({super.key, required this.child});
  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _SheetRoute(page: this);
}

class _SheetRoute extends PageRoute<void> {
  // A dialog: its bar offers Cancel rather than a back chevron.
  _SheetRoute({required _SheetPage page}) : super(settings: page, fullscreenDialog: true);

  _SheetPage get _page => settings as _SheetPage;

  /// The sheet's size: wide enough for compose's rows, never the whole screen.
  static const _maxWidth = 680.0;
  static const _maxHeight = 920.0;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false; // a draft is never lost to a stray tap

  @override
  Color get barrierColor => const Color(0x52000000);

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 320);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    final mq = MediaQuery.of(context);
    final c = EpColors.of(context);
    // The keyboard pushes the sheet up instead of covering it.
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(EpSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _maxWidth, maxHeight: _maxHeight),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(EpRadius.lg),
                  border: Border.all(color: c.hairline),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(EpRadius.lg),
                  // Inside the sheet there is no notch, home indicator or
                  // keyboard left to avoid.
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    removeBottom: true,
                    removeLeft: true,
                    removeRight: true,
                    child: MediaQuery.removeViewInsets(
                      context: context,
                      removeBottom: true,
                      child: _page.child,
                    ),
                  ),
                ),
              ),
            ),
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
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    if (reduceMotion(context)) return FadeTransition(opacity: curved, child: child);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }
}
