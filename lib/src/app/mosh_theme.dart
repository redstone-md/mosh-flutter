library;

import 'package:flutter/material.dart';

// Mosh Flutter theme: the canonical dark `ThemeData` for the app. Every
// color lives in [MoshColors] below. Font family names are wired here but
// the font ASSETS are NOT bundled in pubspec.yaml yet; Flutter falls back
// to the platform default sans/mono until a later change adds the
// `flutter: fonts:` entries. Setting the family names now keeps the wiring
// correct, so bundling the assets later is a no-op for call sites.

/// All Mosh color tokens.
///
/// The three rgba() tokens (line, lineStrong, mossGlow) are converted to
/// an 8-bit alpha channel:
///   0.06 -> 0x0F   (15/255 ~= 0.0588)
///   0.10 -> 0x1A   (26/255 ~= 0.102)
///   0.14 -> 0x24   (36/255 ~= 0.141)
class MoshColors {
  const MoshColors._(); // static const surface only; never instantiated

  // Backgrounds: bg0 (deepest) .. bg4 (highest raised surface).
  static const Color bg0 = Color(0xFF0B0C0D); // deepest (window/body)
  static const Color bg1 = Color(0xFF111315); // raised surface 1
  static const Color bg2 = Color(0xFF16181B); // raised surface 2
  static const Color bg3 = Color(0xFF1D2024); // raised surface 3
  static const Color bg4 = Color(0xFF262A2F); // raised surface 4

  // Hairline borders (rgba white)
  static const Color line = Color(0x0FFFFFFF); // alpha 0.06
  static const Color lineStrong = Color(0x1AFFFFFF); // alpha 0.10

  // Foreground text: fg1 (primary) .. fg4 (disabled/faintest)
  static const Color fg1 = Color(0xFFECEEEA); // primary text
  static const Color fg2 = Color(0xFFA8AEB0); // secondary text
  static const Color fg3 = Color(0xFF6B7075); // tertiary/muted text
  static const Color fg4 = Color(0xFF474B50); // disabled/faintest

  // Brand (moss)
  static const Color moss = Color(0xFFB7D84A); // brand primary
  static const Color moss300 = Color(0xFFD4EB7A); // brand light
  static const Color mossGlow =
      Color(0x24B7D84A); // rgba(moss, 0.14) -- used for glow/selection tints
  static const Color mossInk = Color(0xFF0E1707); // text on moss

  // Semantic accents
  static const Color warn = Color(0xFFE8B65A);
  static const Color danger = Color(0xFFE86A5A);
  static const Color info = Color(0xFF6CB7E8);
}

/// Font features for LIVE numbers (voice timers, audio position, unread
/// counts): tabular figures keep every digit the same width, so a row whose
/// value ticks does not shift its neighbours horizontally (audit
/// 2026-09-21). The call overlay's timer was already rendered this way.
const List<FontFeature> kLiveNumberFontFeatures = <FontFeature>[
  FontFeature.tabularFigures(),
];

/// Material 3 `ColorScheme` mapping the Mosh dark palette onto the standard
/// semantic slots.
///
///  - `surface` / `surfaceContainerLowest` -> bg0. The deepest window/body.
///    Material's `surface` is the base of most widgets.
///  - `surfaceContainerLow` / `surfaceContainer` -> bg1. Raised surface 1
///    (chat-pane headers).
///  - `surfaceContainerHigh`    -> bg2. Raised surface 2 (composer
///    backdrop).
///  - `surfaceContainerHighest` -> bg3. Raised surface 3 (hovered message
///    bubbles, composer action blocks).
///  - `surfaceVariant`          -> bg4. Highest raised surface. NOTE: the
///    Material 3 `surfaceVariant` ColorScheme slot is deprecated (use
///    `surfaceContainerHighest`); bg-4 is exposed via the `surfaceContainerHighest`
///    slot below instead. `MoshColors.bg4` stays the canonical token for any
///    widget that wants the highest raised surface directly.
///  - `primary` / `primaryContainer` -> moss. Brand green, used for primary
///    actions (send button), active rail items, fingerprint icons.
///  - `onPrimary` -> mossInk. Text rendered on moss.
///  - `onSurface` -> fg1. Primary text everywhere.
///  - `onSurfaceVariant` -> fg2. Secondary text (muted labels).
///  - `outline` -> lineStrong. Stronger hairlines.
///  - `outlineVariant` / `dividerColor` -> line. Default hairlines.
///  - `error` -> danger. For errors/delete UI.
///  - `onError` / `onErrorContainer` -> mossInk. Danger is a LIGHT fill:
///    fg1 (near-white) on it reads at ~3.1:1 (audit 2026-09-21). mossInk
///    is the palette's darkest ink and reads cleanly on danger -- the same
///    mapping the light warn and info fills already use
///    (`onSecondary`/`onTertiary`).
///  - `secondary` -> warn, `onSecondary` -> mossInk for contrast (warn is
///    light; mossInk is the darkest ink in the palette and reads cleanly
///    on warn).
///  - `tertiary` -> info, `onTertiary` -> mossInk likewise.
///  - `scrim` / `shadow` -> bg0 (deepest) so modals/overlays stay
///    in-palette.
const ColorScheme _moshColorScheme = ColorScheme.dark(
  brightness: Brightness.dark,
  primary: MoshColors.moss,
  onPrimary: MoshColors.mossInk,
  primaryContainer: MoshColors.moss,
  onPrimaryContainer: MoshColors.mossInk,
  secondary: MoshColors.warn,
  onSecondary: MoshColors.mossInk,
  secondaryContainer: MoshColors.bg3,
  onSecondaryContainer: MoshColors.fg1,
  tertiary: MoshColors.info,
  onTertiary: MoshColors.mossInk,
  tertiaryContainer: MoshColors.bg3,
  onTertiaryContainer: MoshColors.fg1,
  error: MoshColors.danger,
  onError: MoshColors.mossInk,
  errorContainer: MoshColors.danger,
  onErrorContainer: MoshColors.mossInk,
  surface: MoshColors.bg0,
  onSurface: MoshColors.fg1,
  onSurfaceVariant: MoshColors.fg2,
  outline: MoshColors.lineStrong,
  outlineVariant: MoshColors.line,
  shadow: MoshColors.bg0,
  scrim: MoshColors.bg0,
  inverseSurface: MoshColors.fg1,
  onInverseSurface: MoshColors.bg0,
  inversePrimary: MoshColors.moss300,
  // Material 3 surfaceContainer* slots (Flutter 3.22+). If a widget resolves
  // against a ColorScheme lacking these, it falls back to `surface` /
  // `surfaceVariant`, so the slots below are a refinement, not a hard
  // requirement.
  surfaceContainerLowest: MoshColors.bg0,
  surfaceContainerLow: MoshColors.bg1,
  surfaceContainer: MoshColors.bg1,
  surfaceContainerHigh: MoshColors.bg2,
  surfaceContainerHighest: MoshColors.bg3,
);

/// Primary sans family. The font files are not bundled, so the stack falls
/// through to the platform UI font.
const String _kSansFamily = 'Inter Tight';

/// Builds the canonical Mosh dark `ThemeData`.
///
/// Exposed as a function (vs. a top-level constant) so future atomics can
/// inject a `Brightness` or a `ThemeExtension` without changing call sites.
/// `lib/main.dart` calls this once at `MaterialApp.router(theme:)`.
ThemeData buildMoshTheme() {
  // The font files are NOT bundled in pubspec.yaml yet — Flutter falls
  // back to the platform default sans/mono until the `flutter: fonts:`
  // assets are added.
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _moshColorScheme,
    // The window body is bg1 and only the titlebar + rail drop to bg0,
    // which gives the shell its panel separation. A bg0 default would
    // flatten the two.
    scaffoldBackgroundColor: MoshColors.bg1,
    canvasColor: MoshColors.bg1,
    dividerColor: MoshColors.line, // hairline
    splashColor: MoshColors.mossGlow,
    highlightColor: MoshColors.mossGlow,
    // Chrome is sized in 10.5–15px steps; the Material defaults (16px
    // titles, 14px body) render every surface a step too large.
    // VisualDensity.compact takes the same step out of the Material
    // widget metrics.
    visualDensity: VisualDensity.compact,
    fontFamily: _kSansFamily,
    fontFamilyFallback: const ['Geist', 'IBM Plex Sans', 'system-ui'],
    textTheme: _moshTextTheme(),
    // Chat-header look: 70px bar, 22px title spacing, hairline rule under
    // it. Material's default is a 56px bar with 16px title spacing and no
    // rule.
    appBarTheme: const AppBarTheme(
      backgroundColor: MoshColors.bg1,
      foregroundColor: MoshColors.fg1,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 70,
      titleSpacing: 22,
      shape: Border(bottom: BorderSide(color: MoshColors.line)),
      titleTextStyle: TextStyle(
        fontFamily: _kSansFamily,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.02 * 15,
        color: MoshColors.fg1,
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: MoshColors.line,
      thickness: 1,
      space: 1,
    ),
    // Field look: 9/11 padding, radius 8, 1px hairline on bg1, 12.5px
    // text; focus swaps the border to a translucent moss over bg0.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: MoshColors.bg1,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      hintStyle: const TextStyle(fontSize: 12.5, color: MoshColors.fg3),
      labelStyle: const TextStyle(fontSize: 11, color: MoshColors.fg2),
      border: _fieldBorder(MoshColors.line),
      enabledBorder: _fieldBorder(MoshColors.line),
      focusedBorder: _fieldBorder(MoshColors.moss.withValues(alpha: 0.45)),
      errorBorder: _fieldBorder(MoshColors.danger.withValues(alpha: 0.35)),
      focusedErrorBorder:
          _fieldBorder(MoshColors.danger.withValues(alpha: 0.35)),
    ),
    // Rail/menu rows sit at 36–48px with 12px text and a 12px radius;
    // Material's untuned ListTile is a 56px row with 16px text.
    listTileTheme: const ListTileThemeData(
      dense: true,
      horizontalTitleGap: 10,
      minVerticalPadding: 6,
      contentPadding: EdgeInsets.symmetric(horizontal: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
      selectedColor: MoshColors.fg1,
      selectedTileColor: MoshColors.mossGlow,
      titleTextStyle: TextStyle(
        fontSize: 12.5,
        height: 1.1,
        fontWeight: FontWeight.w600,
        color: MoshColors.fg1,
      ),
      subtitleTextStyle: TextStyle(
        fontSize: 10.5,
        height: 1.1,
        color: MoshColors.fg4,
      ),
    ),
    // Modal cards are radius-14 plates on bg2; Material's default is a
    // radius-28 card with an elevation tint over the surface.
    dialogTheme: DialogThemeData(
      backgroundColor: MoshColors.bg2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MoshColors.moss,
        foregroundColor: MoshColors.mossInk,
      ),
    ),
    iconTheme: const IconThemeData(color: MoshColors.fg2),
  );
}

/// The `.field input` border recipe: 1px solid, 8px radius.
OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      borderSide: BorderSide(color: color),
    );

/// The Mosh type scale, mapped onto the Material slots.
///
/// The sizes below are the app's literal chrome metrics, so a widget that
/// just reads `theme.textTheme.X` lands on the right step instead of the
/// Material default:
///   bodyLarge   14/1.4
///   bodyMedium  13.5/1.5
///   bodySmall   12.5/1.55
///   titleLarge  15/700
///   titleMedium 14/600
///   titleSmall  12.5/700
///   labelLarge  12/650
///   labelMedium 11.5/600
///   labelSmall  10.5/-
TextTheme _moshTextTheme() => ThemeData.dark()
    .textTheme
    .apply(
      fontFamily: _kSansFamily,
      bodyColor: MoshColors.fg1,
      displayColor: MoshColors.fg1,
    )
    // copyWith runs AFTER apply: apply() rewrites the colour of every slot,
    // so the muted slots below would be overwritten the other way round.
    .copyWith(
      bodyLarge: const TextStyle(
          fontFamily: _kSansFamily,
          fontSize: 14,
          height: 1.4,
          color: MoshColors.fg1),
      bodyMedium: const TextStyle(
          fontFamily: _kSansFamily,
          fontSize: 13.5,
          height: 1.5,
          color: MoshColors.fg1),
      bodySmall: const TextStyle(
          fontFamily: _kSansFamily,
          fontSize: 12.5,
          height: 1.55,
          color: MoshColors.fg2),
      titleLarge: const TextStyle(
          fontFamily: _kSansFamily,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: MoshColors.fg1),
      titleMedium: const TextStyle(
          fontFamily: _kSansFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: MoshColors.fg1),
      titleSmall: const TextStyle(
          fontFamily: _kSansFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: MoshColors.fg1),
      labelLarge: const TextStyle(
          fontFamily: _kSansFamily,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: MoshColors.fg1),
      labelMedium: const TextStyle(
          fontFamily: _kSansFamily,
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: MoshColors.fg2),
      labelSmall: const TextStyle(
          fontFamily: _kSansFamily, fontSize: 10.5, color: MoshColors.fg3),
    );

/// Convenience top-level handle for `MaterialApp.router(theme: moshThemeData)`.
/// `lib/main.dart` uses this to keep the `MaterialApp.router` call thin.
final ThemeData moshThemeData = buildMoshTheme();
