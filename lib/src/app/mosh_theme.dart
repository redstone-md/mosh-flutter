library;

import 'package:flutter/material.dart';

// Mosh Flutter theme — 1:1 port of the React dark palette defined in
// mosh/src/shared/styles/theme.css `:root`. The React `:root` block is the
// canonical source of truth; every constant below is copied verbatim from
// it (hex tokens) or converted from its rgba() form (line / line-strong /
// moss-glow). The previous Flutter shell used `ColorScheme.fromSeed(
// seedColor: Colors.teal)`, which is a Material seed-color theme that does
// NOT match the React UI. This module lands the correct dark `ThemeData`
// so Material defaults (AppBar, Scaffold, Card, Divider, Text,
// FilledButton, etc.) render in the React palette.
//
// Atomic scope: theme module + main.dart wiring only. Per-screen
// hardcoded colors are NOT touched here (left for later atomics).
//
// Fonts: Inter Tight (sans) and JetBrains Mono (mono) are referenced by
// name in `buildMoshTheme` for parity with React's --font-sans /
// --font-mono, but the actual font ASSETS are NOT bundled in pubspec.yaml
// yet. Flutter falls back to the platform default sans/mono until a later
// atomic adds the `flutter: fonts:` entries. Setting the family names now
// keeps the wiring correct, so bundling the assets later is a no-op for
// call sites.

/// All React `:root` color tokens, ported verbatim to Flutter `Color`s.
///
/// Hex tokens map directly to `Color(0xFF<rrggbb>)`. The three rgba()
/// tokens (--line, --line-strong, --moss-glow) are converted to an 8-bit
/// alpha channel:
///   0.06 -> 0x0F   (15/255 ~= 0.0588)
///   0.10 -> 0x1A   (26/255 ~= 0.102)
///   0.14 -> 0x24   (36/255 ~= 0.141)
/// The React var name is kept in a trailing comment so a future diff
/// against `theme.css` is trivial.
class MoshColors {
  const MoshColors._(); // static const surface only; never instantiated

  // Backgrounds (--bg-0 .. --bg-4)
  static const Color bg0 = Color(0xFF0B0C0D); // --bg-0  deepest (window/body)
  static const Color bg1 = Color(0xFF111315); // --bg-1  raised surface 1
  static const Color bg2 = Color(0xFF16181B); // --bg-2  raised surface 2
  static const Color bg3 = Color(0xFF1D2024); // --bg-3  raised surface 3
  static const Color bg4 = Color(0xFF262A2F); // --bg-4  raised surface 4

  // Hairline borders (rgba white)
  static const Color line =
      Color(0x0FFFFFFF); // --line        rgba(255,255,255,0.06)
  static const Color lineStrong =
      Color(0x1AFFFFFF); // --line-strong rgba(255,255,255,0.10)

  // Foreground text (--fg-1 .. --fg-4)
  static const Color fg1 = Color(0xFFECEEEA); // --fg-1  primary text
  static const Color fg2 = Color(0xFFA8AEB0); // --fg-2  secondary text
  static const Color fg3 = Color(0xFF6B7075); // --fg-3  tertiary/muted text
  static const Color fg4 = Color(0xFF474B50); // --fg-4  disabled/faintest

  // Brand (moss)
  static const Color moss = Color(0xFFB7D84A); // --moss       brand primary
  static const Color moss300 = Color(0xFFD4EB7A); // --moss-300  brand light
  static const Color mossGlow =
      Color(0x24B7D84A); // --moss-glow rgba(183,216,74,0.14)
  static const Color mossInk = Color(0xFF0E1707); // --moss-ink  text on moss

  // Semantic accents
  static const Color warn = Color(0xFFE8B65A); // --warn
  static const Color danger = Color(0xFFE86A5A); // --danger
  static const Color info = Color(0xFF6CB7E8); // --info
}

/// Material 3 `ColorScheme` mapping the React dark palette onto the standard
/// semantic slots. Slot assignment rationale (grounded in React CSS usage):
///
///  - `surface` / `surfaceContainerLowest` -> bg-0. React `body` / `:root`
///    background is `--bg-0` (the deepest window/body). Material's `surface`
///    is the base of most widgets, so it matches the React base.
///  - `surfaceContainerLow` / `surfaceContainer` -> bg-1. Raised surface 1
///    (e.g. chat-pane header background in desktop-shell.css).
///  - `surfaceContainerHigh`    -> bg-2. Raised surface 2 (e.g. composer
///    backdrop in chat-pane.css `.composer { background: --bg-2 }`).
///  - `surfaceContainerHighest` -> bg-3. Raised surface 3 (e.g. hovered
///    message bubbles, `.composer-actions` blocks).
///  - `surfaceVariant`          -> bg-4. Highest raised surface (e.g.
///    attachment-card hover chrome in chat-pane.css). NOTE: the Material 3
///    `surfaceVariant` ColorScheme slot is deprecated (use
///    `surfaceContainerHighest`); bg-4 is exposed via the `surfaceContainerHighest`
///    slot below instead. `MoshColors.bg4` stays the canonical token for any
///    widget that wants the highest raised surface directly.
///  - `primary` / `primaryContainer` -> moss. Brand green, used for primary
///    actions (send button `.send-button { background: --moss }`), active
///    rail items, fingerprint icons.
///  - `onPrimary` -> mossInk. Text rendered on moss (`.send-button {
///    color: --moss-ink }`).
///  - `onSurface` -> fg1. Primary text everywhere
///    (`:root { color: --fg-1 }`).
///  - `onSurfaceVariant` -> fg2. Secondary text (chat-pane muted labels,
///    diagnostics muted text).
///  - `outline` -> lineStrong. Stronger hairlines (`.composer-tool-button
///    { border: 1px solid --line-strong }`).
///  - `outlineVariant` / `dividerColor` -> line. Default hairlines
///    (`.composer { border-top: 1px solid --line }`).
///  - `error` -> danger. React `--danger` (#e86a5a) for errors/delete UI.
///  - `onError` -> fg1. React does not define an explicit on-danger token;
///    fg1 is the high-contrast text used on colored fills elsewhere.
///  - `secondary` -> warn (state-pill-waiting / --warn), `onSecondary` ->
///    mossInk for contrast (warn is light; mossInk is the darkest ink in
///    the palette and reads cleanly on warn).
///  - `tertiary` -> info (React --info), `onTertiary` -> mossInk likewise.
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
  onError: MoshColors.fg1,
  errorContainer: MoshColors.danger,
  onErrorContainer: MoshColors.fg1,
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

/// Builds the canonical Mosh dark `ThemeData`.
///
/// Exposed as a function (vs. a top-level constant) so future atomics can
/// inject a `Brightness` or a `ThemeExtension` without changing call sites.
/// `lib/main.dart` calls this once at `MaterialApp.router(theme:)`.
ThemeData buildMoshTheme() {
  // Font family names mirror React's --font-sans / --font-mono. The actual
  // font files are NOT bundled in pubspec.yaml yet — Flutter falls back to
  // the platform default sans/mono. A later atomic can add the
  // `flutter: fonts:` assets; nothing here needs to change.
  const String sansFamily = 'Inter Tight';

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _moshColorScheme,
    scaffoldBackgroundColor: MoshColors.bg0, // --bg-0 (body/window)
    canvasColor: MoshColors.bg0,
    dividerColor: MoshColors.line, // --line (hairline)
    splashColor: MoshColors.mossGlow,
    highlightColor: MoshColors.mossGlow,
    fontFamily: sansFamily,
    fontFamilyFallback: const ['Geist', 'IBM Plex Sans', 'system-ui'],
    textTheme: ThemeData.dark().textTheme.copyWith(
          bodyLarge:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg1),
          bodyMedium:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg1),
          bodySmall:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg2),
          labelLarge:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg1),
          labelMedium:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg2),
          labelSmall:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg3),
          headlineLarge:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg1),
          headlineMedium:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg1),
          headlineSmall:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg1),
          titleLarge:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg1),
          titleMedium:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg1),
          titleSmall:
              const TextStyle(fontFamily: sansFamily, color: MoshColors.fg2),
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: MoshColors.bg0, // --bg-0 (window top)
      foregroundColor: MoshColors.fg1, // --fg-1
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    dividerTheme: const DividerThemeData(
      color: MoshColors.line, // --line
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MoshColors.moss, // --moss
        foregroundColor: MoshColors.mossInk, // --moss-ink
      ),
    ),
    iconTheme: const IconThemeData(color: MoshColors.fg2), // --fg-2 default
  );
}

/// Convenience top-level handle for `MaterialApp.router(theme: moshThemeData)`.
/// `lib/main.dart` uses this to keep the `MaterialApp.router` call thin.
final ThemeData moshThemeData = buildMoshTheme();
