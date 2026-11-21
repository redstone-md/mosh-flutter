part of 'mosh_theme.dart';

/// Font features for LIVE numbers (voice timers, audio position, unread
/// counts): tabular figures keep every digit the same width, so a row whose
/// value ticks does not shift its neighbours horizontally (audit
/// 2026-09-21). The call overlay's timer was already rendered this way.
const List<FontFeature> kLiveNumberFontFeatures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// Primary sans family, bundled from `assets/fonts/` (Onest 2.001, OFL):
/// Latin and Cyrillic with tabular figures. Screens still ask for the 600
/// and 700 weights, so those ship beside the 400 and 500 of the type scale.
const String _kSansFamily = 'Onest';
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

/// One slot of the Foundations type scale, the Material 3 baseline: the
/// `Mosh/<slot>` text style in Figma. [line] is the line box in pixels.
TextStyle _slot(double size, double line,
        {FontWeight weight = FontWeight.w400,
        double spacing = 0,
        Color color = MoshColors.onSurface}) =>
    _kBase.copyWith(
        fontSize: size,
        height: line / size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color);

final TextTheme _moshTextTheme = TextTheme(
  displayLarge: _slot(57, 64, spacing: -0.25),
  displayMedium: _slot(45, 52),
  displaySmall: _slot(36, 44),
  headlineLarge: _slot(32, 40),
  headlineMedium: _slot(28, 36),
  headlineSmall: _slot(24, 32),
  titleLarge: _slot(22, 28),
  titleMedium: _slot(16, 24, weight: FontWeight.w500),
  titleSmall: _slot(14, 20, weight: FontWeight.w500),
  bodyLarge: _slot(16, 24),
  bodyMedium: _slot(14, 20),
  bodySmall: _slot(12, 16, color: MoshColors.onSurfaceVariant),
  labelLarge: _slot(14, 20, weight: FontWeight.w500, spacing: 0.1),
  labelMedium: _slot(12, 16,
      weight: FontWeight.w500,
      spacing: 0.5,
      color: MoshColors.onSurfaceVariant),
  labelSmall: _slot(11, 16,
      weight: FontWeight.w500, spacing: 0.5, color: MoshColors.onSurfaceMuted),
);
