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
        Color? color}) =>
    _kBase.copyWith(
        fontSize: size,
        height: line / size,
        fontWeight: weight,
        letterSpacing: spacing,
        color: color);

/// The type scale in the text colours of [c].
TextTheme _textTheme(MoshColors c) => TextTheme(
      displayLarge: _slot(57, 64, spacing: -0.25, color: c.onSurface),
      displayMedium: _slot(45, 52, color: c.onSurface),
      displaySmall: _slot(36, 44, color: c.onSurface),
      headlineLarge: _slot(32, 40, color: c.onSurface),
      headlineMedium: _slot(28, 36, color: c.onSurface),
      headlineSmall: _slot(24, 32, color: c.onSurface),
      titleLarge: _slot(22, 28, color: c.onSurface),
      titleMedium: _slot(16, 24, weight: FontWeight.w500, color: c.onSurface),
      titleSmall: _slot(14, 20, weight: FontWeight.w500, color: c.onSurface),
      bodyLarge: _slot(16, 24, color: c.onSurface),
      bodyMedium: _slot(14, 20, color: c.onSurface),
      bodySmall: _slot(12, 16, color: c.onSurfaceVariant),
      labelLarge: _slot(14, 20,
          weight: FontWeight.w500, spacing: 0.1, color: c.onSurface),
      labelMedium: _slot(12, 16,
          weight: FontWeight.w500, spacing: 0.5, color: c.onSurfaceVariant),
      labelSmall: _slot(11, 16,
          weight: FontWeight.w500, spacing: 0.5, color: c.onSurfaceMuted),
    );

/// Emphasized styles of the Foundations type scale, after Material 3
/// Expressive: a slot at a heavier weight, for text that has to stand apart
/// from the text set beside it, such as a sender's name above their message.
/// They carry no colour and take the one of the text around them.
/// The `Mosh/<slot>Emphasized` text styles in Figma.
abstract final class MoshEmphasizedText {
  static final TextStyle labelLarge =
      _slot(14, 20, weight: FontWeight.w600, spacing: 0.1);
}
