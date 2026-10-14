import 'package:flutter/material.dart';

/// What a card belongs to. A family shows as a small neutral glyph beside
/// the card's title: colour is kept for status ([EpColors.attention],
/// [EpColors.ok], [EpColors.caution]).
enum Family { domains, mail, compute, neutral }

/// Edgepost palette, exposed as a [ThemeExtension] so Cupertino and Material
/// screens read the same tokens. Neutral surfaces on hairlines; blue acts,
/// orange is the brand's mark only, red means "this needs you".
@immutable
class EpColors extends ThemeExtension<EpColors> {
  const EpColors({
    required this.canvas,
    required this.surface,
    required this.raised,
    required this.ink,
    required this.inkMuted,
    required this.hairline,
    required this.tint,
    required this.onTint,
    required this.tintWash,
    required this.brand,
    required this.brandWash,
    required this.onBrandWash,
    required this.attention,
    required this.onAttention,
    required this.attentionWash,
    required this.ok,
    required this.okWash,
    required this.caution,
    required this.cautionWash,
    required this.neutralWash,
    required this.inverse,
    required this.onInverse,
    required this.inverseTint,
    required this.accounts,
    required this.onAccount,
  });

  /// Screen ground behind cards and grouped lists.
  final Color canvas;

  /// Cards, list cells, bars, fields.
  final Color surface;

  /// Sheets and popovers above [surface].
  final Color raised;
  final Color ink;
  final Color inkMuted;
  final Color hairline;

  /// Actions, links, selection, unread.
  final Color tint;
  final Color onTint;
  final Color tintWash;

  /// The brand orange: the logo and the active-tab mark, nothing else.
  final Color brand;
  final Color brandWash;

  /// The selected tab's glyph on [brandWash] (a deeper orange that reads).
  final Color onBrandWash;

  /// Needs you, and destructive actions.
  final Color attention;
  final Color onAttention;
  final Color attentionWash;
  final Color ok;
  final Color okWash;
  final Color caution;
  final Color cautionWash;
  final Color neutralWash;

  /// Toasts, snack bars and tooltips: the inverted surface.
  final Color inverse;
  final Color onInverse;
  final Color inverseTint;

  /// Account identity colours, one per added account (by index). They
  /// identify an account, never a state, so they reuse no status colour.
  final List<Color> accounts;

  /// Initials on an [accounts] colour.
  final Color onAccount;

  Color account(int index) => accounts[index % accounts.length];

  /// The wash behind a status colour, for a status pill.
  Color washOf(Color status) => status == ok
      ? okWash
      : status == caution
      ? cautionWash
      : status == attention
      ? attentionWash
      : neutralWash;

  static const light = EpColors(
    canvas: Color(0xFFF6F7F9),
    surface: Color(0xFFFFFFFF),
    raised: Color(0xFFFFFFFF),
    ink: Color(0xFF17181C),
    inkMuted: Color(0xFF5B606A),
    hairline: Color(0xFFE3E5E9),
    tint: Color(0xFF2557D6),
    onTint: Color(0xFFFFFFFF),
    tintWash: Color(0xFFEAF0FD),
    brand: Color(0xFFF2672A),
    brandWash: Color(0xFFFDE9DF),
    onBrandWash: Color(0xFFC2410C),
    attention: Color(0xFFC42B1F),
    onAttention: Color(0xFFFFFFFF),
    attentionWash: Color(0xFFFDEDEB),
    ok: Color(0xFF127A4B),
    okWash: Color(0xFFE6F4EC),
    caution: Color(0xFFB45309),
    cautionWash: Color(0xFFFDF1E3),
    neutralWash: Color(0xFFEFF1F4),
    inverse: Color(0xFF17181C),
    onInverse: Color(0xFFF3F4F6),
    inverseTint: Color(0xFF9DB8FF),
    // Deep enough for white initials (≥ 4.5:1).
    accounts: [
      Color(0xFF3D5A80),
      Color(0xFF7A4E7E),
      Color(0xFF1F6F6B),
      Color(0xFF9A4F2B),
      Color(0xFF5E6B2E),
      Color(0xFF4A4E57),
    ],
    onAccount: Color(0xFFFFFFFF),
  );

  static const dark = EpColors(
    canvas: Color(0xFF0E0F12),
    surface: Color(0xFF17181C),
    raised: Color(0xFF1F2025),
    ink: Color(0xFFECEDEF),
    inkMuted: Color(0xFFA2A6AE),
    hairline: Color(0xFF2A2C31),
    tint: Color(0xFF86A8FF),
    onTint: Color(0xFF0B1530),
    tintWash: Color(0xFF1B2541),
    brand: Color(0xFFFF8A4F),
    brandWash: Color(0xFF3F2214),
    onBrandWash: Color(0xFFFF9B66),
    attention: Color(0xFFFF6B5E),
    onAttention: Color(0xFF2A0D0A),
    attentionWash: Color(0xFF3A1D1A),
    ok: Color(0xFF4ADE9A),
    okWash: Color(0xFF133325),
    caution: Color(0xFFF5B04A),
    cautionWash: Color(0xFF3A2A12),
    neutralWash: Color(0xFF24262B),
    inverse: Color(0xFF2C2E34),
    onInverse: Color(0xFFECEDEF),
    inverseTint: Color(0xFF86A8FF),
    // Light enough for dark initials on the dark canvas.
    accounts: [
      Color(0xFFA7BEDF),
      Color(0xFFD2AED4),
      Color(0xFF86CCC6),
      Color(0xFFE5AC8A),
      Color(0xFFC0CB86),
      Color(0xFFBCC1CB),
    ],
    onAccount: Color(0xFF0B1014),
  );

  static EpColors of(BuildContext context) =>
      Theme.of(context).extension<EpColors>() ?? (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  EpColors copyWith() => this;

  @override
  EpColors lerp(ThemeExtension<EpColors>? other, double t) {
    if (other is! EpColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return EpColors(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      raised: l(raised, other.raised),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      hairline: l(hairline, other.hairline),
      tint: l(tint, other.tint),
      onTint: l(onTint, other.onTint),
      tintWash: l(tintWash, other.tintWash),
      brand: l(brand, other.brand),
      brandWash: l(brandWash, other.brandWash),
      onBrandWash: l(onBrandWash, other.onBrandWash),
      attention: l(attention, other.attention),
      onAttention: l(onAttention, other.onAttention),
      attentionWash: l(attentionWash, other.attentionWash),
      ok: l(ok, other.ok),
      okWash: l(okWash, other.okWash),
      caution: l(caution, other.caution),
      cautionWash: l(cautionWash, other.cautionWash),
      neutralWash: l(neutralWash, other.neutralWash),
      inverse: l(inverse, other.inverse),
      onInverse: l(onInverse, other.onInverse),
      inverseTint: l(inverseTint, other.inverseTint),
      accounts: [for (var i = 0; i < accounts.length; i++) l(accounts[i], other.accounts[i])],
      onAccount: l(onAccount, other.onAccount),
    );
  }
}

/// Spacing rhythm (4-pt base): tight inside a card, generous between groups.
abstract final class EpSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Above a group header.
  static const double bay = 24;

  /// How far a card that needs you sits out of line.
  static const double nudge = 4;
}

/// Corner radii.
abstract final class EpRadius {
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double pill = 999;
}

/// Type. Body text and controls stay on the platform face (SF / Roboto);
/// Inter carries titles, card titles and numbers.
abstract final class EpType {
  static const family = 'Inter';
  static const _tabular = [FontFeature.tabularFigures()];

  /// A card or screen title. Inter tightens a little as it grows.
  static TextStyle title(BuildContext context, {double size = 16, FontWeight weight = FontWeight.w600, Color? color}) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: 1.25,
        fontWeight: weight,
        letterSpacing: size >= 20 ? -0.3 : -0.1,
        color: color ?? EpColors.of(context).ink,
      );

  /// The label above a value in a card.
  static TextStyle fieldLabel(BuildContext context, {Color? color}) => TextStyle(
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w500,
    color: color ?? EpColors.of(context).inkMuted,
  );

  /// A group header ("NEEDS YOU"), set in small caps by the caller.
  static TextStyle groupLabel(BuildContext context, {Color? color}) => TextStyle(
    fontSize: 12,
    height: 1.25,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.6,
    color: color ?? EpColors.of(context).inkMuted,
  );

  static TextStyle fieldValue(BuildContext context, {Color? color, FontWeight weight = FontWeight.w500}) => TextStyle(
    fontFamily: family,
    fontSize: 15,
    height: 1.3,
    fontWeight: weight,
    color: color ?? EpColors.of(context).ink,
    fontFeatures: _tabular,
  );

  /// Machine data (DNS names and record content, IP addresses, IDs, URLs),
  /// so a monospace is earned. Never email addresses or names.
  static TextStyle data(BuildContext context, {double size = 14, Color? color}) => TextStyle(
    fontFamily: Theme.of(context).platform == TargetPlatform.iOS ? 'Menlo' : 'monospace',
    fontSize: size,
    height: 1.3,
    color: color ?? EpColors.of(context).ink,
  );

  static TextStyle numbers(TextStyle base) => base.copyWith(fontFeatures: _tabular);
}
