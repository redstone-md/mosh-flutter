part of 'mosh_theme.dart';

/// Font features for LIVE numbers (voice timers, audio position, unread
/// counts): tabular figures keep every digit the same width, so a row whose
/// value ticks does not shift its neighbours horizontally (audit
/// 2026-09-21). The call overlay's timer was already rendered this way.
const List<FontFeature> kLiveNumberFontFeatures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// Primary sans family, bundled from `assets/fonts/` (Inter 4.1, OFL). Its
/// balanced ascent/descent keeps labels optically centered in controls,
/// which platform fallbacks such as Segoe UI do not.
const String _kSansFamily = 'Inter';
const List<String> _kSansFallback = <String>[
  'Geist',
  'IBM Plex Sans',
  'system-ui'
];

/// Every text style starts here, so no slot inherits Material's
/// letter-spacing or family through `Typography.merge`.
const TextStyle _kBase = TextStyle(
  fontFamily: _kSansFamily,
  fontFamilyFallback: _kSansFallback,
  letterSpacing: 0,
);

// Every slot derives from the same family, spacing and explicit color defaults.
TextTheme _moshTextTheme() => TextTheme(
      headlineMedium: _kBase.copyWith(
          fontSize: 23,
          fontWeight: FontWeight.w600,
          height: 1.15,
          letterSpacing: -0.01 * 23,
          color: MoshColors.fg1),
      headlineSmall: _kBase.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w600,
          height: 1.2,
          letterSpacing: -0.01 * 19,
          color: MoshColors.fg1),
      titleLarge: _kBase.copyWith(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          height: 1.25,
          letterSpacing: 0.02 * 15,
          color: MoshColors.fg1),
      titleMedium: _kBase.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: MoshColors.fg1),
      titleSmall: _kBase.copyWith(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          height: 1.3,
          color: MoshColors.fg1),
      bodyLarge:
          _kBase.copyWith(fontSize: 14, height: 1.4, color: MoshColors.fg1),
      bodyMedium:
          _kBase.copyWith(fontSize: 13.5, height: 1.5, color: MoshColors.fg1),
      bodySmall:
          _kBase.copyWith(fontSize: 12.5, height: 1.55, color: MoshColors.fg2),
      labelLarge: _kBase.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: MoshColors.fg1),
      labelMedium: _kBase.copyWith(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          height: 1.3,
          color: MoshColors.fg2),
      labelSmall:
          _kBase.copyWith(fontSize: 10.5, height: 1.3, color: MoshColors.fg3),
    );
