part of 'mosh_theme.dart';

/// All Mosh color tokens: the dark theme of Foundations in the Figma file
/// "Mosh". A token has the name of its variable in the "Mosh" collection
/// without the group (`primary/primary` is [primary]);
/// `scripts/figma-capture/tokens.mjs` writes this file back to those
/// variables, so a token is either a literal or the name of another token.
class MoshColors {
  const MoshColors._(); // static const surface only; never instantiated

  // Material 3 roles.
  static const Color primary = Color(0xFFF5BE62);
  static const Color onPrimary = Color(0xFF2A1B04);
  static const Color primaryContainer = Color(0xFFF2B34C);
  static const Color onPrimaryContainer = Color(0xFF2A1B04);
  static const Color inversePrimary = Color(0xFF82540A);

  static const Color secondary = Color(0xFFD9C3A5);
  static const Color onSecondary = Color(0xFF33261A);
  static const Color secondaryContainer = Color(0xFF413628);
  static const Color onSecondaryContainer = Color(0xFFF4E5D2);

  static const Color tertiary = Color(0xFF86B6E3);
  static const Color onTertiary = Color(0xFF0C2A43);
  static const Color tertiaryContainer = Color(0xFF2A3F52);
  static const Color onTertiaryContainer = Color(0xFFD2E6F8);

  static const Color error = Color(0xFFF27E6E);
  static const Color onError = Color(0xFF3D0A04);
  static const Color errorContainer = Color(0xFF4A2520);
  static const Color onErrorContainer = Color(0xFFFFD9D3);

  static const Color surface = Color(0xFF282421);
  static const Color surfaceDim = Color(0xFF201D1A);
  static const Color surfaceBright = Color(0xFF45403A);
  static const Color surfaceContainerLowest = Color(0xFF1E1B18);
  static const Color surfaceContainerLow = Color(0xFF23201D);
  static const Color surfaceContainer = Color(0xFF2E2A26);
  static const Color surfaceContainerHigh = Color(0xFF352F2B);
  static const Color surfaceContainerHighest = Color(0xFF3C352F);
  static const Color onSurface = Color(0xFFF4EFE9);
  static const Color onSurfaceVariant = Color(0xFFC2B8AD);
  static const Color inverseSurface = Color(0xFFF4EFE9);
  static const Color onInverseSurface = Color(0xFF2E2A26);

  /// Edges that must be seen (fields, focusable controls): 3:1 on surfaces.
  static const Color outline = Color(0xFF8F8479);

  /// Decorative hairlines and dividers.
  static const Color outlineVariant = Color(0xFF3D3833);

  // Mosh roles beyond Material 3.

  /// Tertiary text: clears 4.5:1 on every surface container.
  static const Color onSurfaceMuted = Color(0xFFADA195);

  static const Color success = Color(0xFF7CCB8F);
  static const Color warning = Color(0xFFEE9156);
  static const Color warningContainer = Color(0xFF4A3022);
  static const Color onWarningContainer = Color(0xFFFFDCC7);
  static const Color info = tertiary;

  /// Message bubbles. Own messages sit on the saffron fill with dark text.
  static const Color outgoing = primaryContainer;
  static const Color incoming = surfaceContainerHigh;
  static const Color onOutgoing = Color(0xFF2A1B04);
  static const Color onOutgoingVariant = Color(0xFF5E3F0C);
  static const Color outgoingError = Color(0xFF7A160B);

  /// Initials-avatar plates, picked per contact, and the initials on them.
  static const Color avatar1 = Color(0xFF5A3F2E);
  static const Color avatar2 = Color(0xFF2F4A44);
  static const Color avatar3 = Color(0xFF4A3A55);
  static const Color avatar4 = Color(0xFF3E4A2C);
  static const Color onAvatar = Color(0xFFF4EFE9);

  /// Keyboard focus ring, drawn 2px around the focused control.
  static const Color focusRing = onSurface;

  // Names from before the redesign, each now a role. Screens still read
  // them; new code reads the role, and the component work (MOSH-130)
  // replaces these.
  static const Color bg0 = surfaceContainerLowest;
  static const Color bg1 = surface;
  static const Color bg2 = surfaceContainerHigh;
  static const Color bg3 = surfaceContainerHighest;
  static const Color bg4 = surfaceBright;
  static const Color line = outlineVariant;
  static const Color lineStrong = outlineVariant;
  static const Color fg1 = onSurface;
  static const Color fg2 = onSurfaceVariant;
  static const Color fg3 = onSurfaceMuted;
  static const Color fg4 = outline;
  static const Color moss = primary;
  static const Color moss300 = primary;
  static const Color mossGlow = secondaryContainer;
  static const Color mossInk = onPrimary;
  static const Color warn = warning;
  static const Color danger = error;
  static const Color dmAccent = primary;
  static const Color groupAccent = secondary;
  static const Color channelAccent = tertiary;
  static const Color fieldBorder = outline;
  static const Color channelTint = tertiaryContainer;
  static const Color avatarSurface = avatar1;
  static const Color warnSurface = warningContainer;
  static const Color warnIconSurface = warningContainer;
  static const Color warnBorder = warning;
  static const Color dangerSurface = errorContainer;
  static const Color dangerBorder = error;

  /// Bubble of an own message while its text is still the light [fg1]:
  /// a deep amber instead of [outgoing], which needs [onOutgoing] text.
  static const Color outgoingMessage = Color(0xFF45300C);
}

const ColorScheme _moshColorScheme = ColorScheme.dark(
  brightness: Brightness.dark,
  primary: MoshColors.primary,
  onPrimary: MoshColors.onPrimary,
  primaryContainer: MoshColors.primaryContainer,
  onPrimaryContainer: MoshColors.onPrimaryContainer,
  secondary: MoshColors.secondary,
  onSecondary: MoshColors.onSecondary,
  secondaryContainer: MoshColors.secondaryContainer,
  onSecondaryContainer: MoshColors.onSecondaryContainer,
  tertiary: MoshColors.tertiary,
  onTertiary: MoshColors.onTertiary,
  tertiaryContainer: MoshColors.tertiaryContainer,
  onTertiaryContainer: MoshColors.onTertiaryContainer,
  error: MoshColors.error,
  onError: MoshColors.onError,
  errorContainer: MoshColors.errorContainer,
  onErrorContainer: MoshColors.onErrorContainer,
  surface: MoshColors.surface,
  surfaceDim: MoshColors.surfaceDim,
  surfaceBright: MoshColors.surfaceBright,
  surfaceContainerLowest: MoshColors.surfaceContainerLowest,
  surfaceContainerLow: MoshColors.surfaceContainerLow,
  surfaceContainer: MoshColors.surfaceContainer,
  surfaceContainerHigh: MoshColors.surfaceContainerHigh,
  surfaceContainerHighest: MoshColors.surfaceContainerHighest,
  onSurface: MoshColors.onSurface,
  onSurfaceVariant: MoshColors.onSurfaceVariant,
  outline: MoshColors.outline,
  outlineVariant: MoshColors.outlineVariant,
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: MoshColors.inverseSurface,
  onInverseSurface: MoshColors.onInverseSurface,
  inversePrimary: MoshColors.inversePrimary,
);
