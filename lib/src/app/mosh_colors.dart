part of 'mosh_theme.dart';

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
  // fg3 clears 4.5:1 on bg0..bg3 (4.57 on bg3); fg4 does not clear it
  // anywhere, so it is for disabled and decorative marks only, never text a
  // user must read (interface review 2026-09-30).
  static const Color fg3 = Color(0xFF83888D); // tertiary/muted text
  static const Color fg4 = Color(0xFF474B50); // disabled/decorative only

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

  /// Conversation type accents, used with distinct glyphs, never as status.
  static const Color dmAccent = moss;
  static const Color groupAccent = Color(0xFFB49BE0);
  static const Color channelAccent = info;
  static const Color outgoingMessage = Color(0xFF273D2D);

  // Role tokens built on the primitives above. Components read these
  // instead of re-deriving an alpha at the call site.

  /// Text-field edge: white at 0.35, >= 3:1 against bg0..bg3.
  static const Color fieldBorder = Color(0x5AFFFFFF);

  /// Keyboard focus ring, drawn 2px around the focused control.
  static const Color focusRing = fg1;

  /// Channel-row tint: info at 0.10.
  static const Color channelTint = Color(0x1A6CB7E8);

  /// Initials-avatar plate.
  static const Color avatarSurface = Color(0xFF2D3F23);

  /// Warning callout fill / icon plate / edge (warn at 0.08 / 0.12 / 0.28).
  static const Color warnSurface = Color(0x15E8B65A);
  static const Color warnIconSurface = Color(0x1FE8B65A);
  static const Color warnBorder = Color(0x47E8B65A);

  /// Error callout fill / edge (danger at 0.08 / 0.35).
  static const Color dangerSurface = Color(0x14E86A5A);
  static const Color dangerBorder = Color(0x59E86A5A);
}

// Neutral Material roles use fg2. Runtime warning/info colors stay explicit.
// Danger is a light fill and needs dark mossInk for readable contrast.
const ColorScheme _moshColorScheme = ColorScheme.dark(
  brightness: Brightness.dark,
  primary: MoshColors.moss,
  onPrimary: MoshColors.mossInk,
  primaryContainer: MoshColors.moss,
  onPrimaryContainer: MoshColors.mossInk,
  secondary: MoshColors.fg2,
  onSecondary: MoshColors.bg0,
  secondaryContainer: MoshColors.bg3,
  onSecondaryContainer: MoshColors.fg1,
  tertiary: MoshColors.fg2,
  onTertiary: MoshColors.bg0,
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
