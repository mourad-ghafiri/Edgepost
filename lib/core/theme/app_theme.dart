import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds the app theme for one platform and brightness. Material 3 roles on
/// Android, Cupertino overrides on iOS; both carry [EpColors] so shared
/// widgets (cards, groups) render identically.
ThemeData buildEpTheme(TargetPlatform platform, Brightness brightness) {
  final c = brightness == Brightness.dark ? EpColors.dark : EpColors.light;
  final isIOS = platform == TargetPlatform.iOS;
  final radius = BorderRadius.circular(EpRadius.md);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.tint,
    onPrimary: c.onTint,
    primaryContainer: c.tintWash,
    onPrimaryContainer: c.tint,
    secondary: c.ink,
    onSecondary: c.surface,
    secondaryContainer: c.brandWash,
    onSecondaryContainer: c.onBrandWash,
    tertiary: c.ok,
    onTertiary: c.surface,
    tertiaryContainer: c.okWash,
    onTertiaryContainer: c.ok,
    error: c.attention,
    onError: c.onAttention,
    errorContainer: c.attentionWash,
    onErrorContainer: c.attention,
    surface: c.canvas,
    onSurface: c.ink,
    onSurfaceVariant: c.inkMuted,
    surfaceContainerLowest: c.surface,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.raised,
    surfaceContainerHighest: c.neutralWash,
    outline: c.inkMuted,
    outlineVariant: c.hairline,
    inverseSurface: c.inverse,
    onInverseSurface: c.onInverse,
    inversePrimary: c.inverseTint,
    shadow: Colors.black,
    scrim: Colors.black,
  );

  // Body follows the platform face and its sizes (HIG on iOS, the Material 3
  // scale on Android), both scaling with the system text size. Titles and
  // headlines are Inter.
  final base = isIOS
      ? const TextTheme(
          displaySmall: TextStyle(fontSize: 34, fontWeight: FontWeight.w700),
          headlineSmall: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          titleSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(fontSize: 17, height: 1.3),
          bodyMedium: TextStyle(fontSize: 15, height: 1.3),
          bodySmall: TextStyle(fontSize: 13, height: 1.3),
          labelLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          labelMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.4),
        )
      : _materialBase(platform);
  TextStyle? inter(TextStyle? s, {double tracking = -0.3}) =>
      s?.copyWith(fontFamily: EpType.family, letterSpacing: tracking);
  final textTheme = base
      .copyWith(
        displayLarge: inter(base.displayLarge, tracking: -0.8),
        displayMedium: inter(base.displayMedium, tracking: -0.6),
        displaySmall: inter(base.displaySmall, tracking: -0.5),
        headlineLarge: inter(base.headlineLarge),
        headlineMedium: inter(base.headlineMedium),
        headlineSmall: inter(base.headlineSmall),
        titleLarge: inter(base.titleLarge, tracking: -0.2),
      )
      .apply(bodyColor: c.ink, displayColor: c.ink);

  final hairline = BorderSide(color: c.hairline);
  final buttonShape = RoundedRectangleBorder(borderRadius: radius);

  return ThemeData(
    useMaterial3: true,
    platform: platform,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    dividerColor: c.hairline,
    dividerTheme: DividerThemeData(color: c.hairline, thickness: 1, space: 1),
    splashFactory: isIOS ? NoSplash.splashFactory : InkSparkle.splashFactory,
    extensions: [c],
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      // No titleTextStyle: it would also replace the large app bar's
      // expanded headline (titleLarge everywhere, headlineMedium expanded).
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.brandWash,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.onBrandWash : c.inkMuted),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? c.ink : c.inkMuted,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.brandWash,
      selectedIconTheme: IconThemeData(color: c.onBrandWash),
      unselectedIconTheme: IconThemeData(color: c.inkMuted),
      selectedLabelTextStyle: TextStyle(color: c.ink, fontWeight: FontWeight.w600),
      unselectedLabelTextStyle: TextStyle(color: c.inkMuted),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.tint,
      foregroundColor: c.onTint,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EpRadius.lg)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.inverse,
      contentTextStyle: TextStyle(color: c.onInverse, fontSize: 15),
      actionTextColor: c.inverseTint,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EpRadius.lg)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: c.inverse, borderRadius: BorderRadius.circular(EpRadius.sm)),
      textStyle: TextStyle(color: c.onInverse, fontSize: 13),
    ),
    listTileTheme: ListTileThemeData(
      tileColor: c.surface,
      iconColor: c.inkMuted,
      textColor: c.ink,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius, side: hairline),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(EpRadius.lg)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.raised,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: c.hairline,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: buttonShape, minimumSize: const Size(64, 48)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        minimumSize: const Size(64, 48),
        side: hairline,
        foregroundColor: c.ink,
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(shape: buttonShape)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.tintWash,
        selectedForegroundColor: c.tint,
        side: hairline,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      border: OutlineInputBorder(borderRadius: radius, borderSide: hairline),
      enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: hairline),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.tint, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: c.attention),
      ),
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: brightness,
      primaryColor: c.tint,
      primaryContrastingColor: c.onTint,
      scaffoldBackgroundColor: c.canvas,
      barBackgroundColor: c.canvas.withValues(alpha: 0.92),
      // Complete styles (inherit: false), as Cupertino's own are: a title
      // flies into the next page's back label, and styles only interpolate
      // when both are complete.
      textTheme: CupertinoTextThemeData(
        primaryColor: c.tint,
        navLargeTitleTextStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          fontFamily: EpType.family,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: c.ink,
        ),
        navTitleTextStyle: TextStyle(
          inherit: false,
          decoration: TextDecoration.none,
          fontFamily: EpType.family,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: c.ink,
        ),
      ),
    ),
  );
}

/// The Material 3 type scale with Edgepost's weights: headlines bold,
/// titles semibold, so a large title reads as one.
TextTheme _materialBase(TargetPlatform platform) {
  final t = Typography.material2021(platform: platform);
  final base = t.englishLike.merge(t.black);
  return base.copyWith(
    headlineLarge: base.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
    headlineMedium: base.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
    headlineSmall: base.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    titleLarge: base.titleLarge?.copyWith(fontWeight: FontWeight.w600),
  );
}
