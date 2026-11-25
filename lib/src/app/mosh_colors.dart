part of 'mosh_theme.dart';

/// All Mosh color tokens, read with [MoshColors.of]. A token has the name of
/// its variable in the Figma file "Mosh" without the group (`primary/primary`
/// is [primary]); [dark] and [light] hold the values of the two collections.
class MoshColors extends ThemeExtension<MoshColors> {
  const MoshColors({
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.inversePrimary,
    required this.secondary,
    required this.onSecondary,
    required this.secondaryContainer,
    required this.onSecondaryContainer,
    required this.tertiary,
    required this.onTertiary,
    required this.tertiaryContainer,
    required this.onTertiaryContainer,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.surface,
    required this.surfaceDim,
    required this.surfaceBright,
    required this.surfaceContainerLowest,
    required this.surfaceContainerLow,
    required this.surfaceContainer,
    required this.surfaceContainerHigh,
    required this.surfaceContainerHighest,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.inverseSurface,
    required this.onInverseSurface,
    required this.outline,
    required this.outlineVariant,
    required this.onSurfaceMuted,
    required this.success,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.onOutgoing,
    required this.onOutgoingVariant,
    required this.outgoingError,
    required this.avatar1,
    required this.avatar2,
    required this.avatar3,
    required this.avatar4,
    required this.onAvatar,
  });

  static const MoshColors dark = _darkColors;
  static const MoshColors light = _lightColors;

  /// The palette of the theme around [context], which is one of
  /// [buildMoshTheme].
  static MoshColors of(BuildContext context) => from(Theme.of(context));

  /// The palette [theme] was built on.
  static MoshColors from(ThemeData theme) => theme.extension<MoshColors>()!;

  // Material 3 roles. [outline] is for edges that must be seen (fields,
  // focusable controls): 3:1 on surfaces. [outlineVariant] is for decorative
  // hairlines and dividers.
  final Color primary,
      onPrimary,
      primaryContainer,
      onPrimaryContainer,
      inversePrimary,
      secondary,
      onSecondary,
      secondaryContainer,
      onSecondaryContainer,
      tertiary,
      onTertiary,
      tertiaryContainer,
      onTertiaryContainer,
      error,
      onError,
      errorContainer,
      onErrorContainer,
      surface,
      surfaceDim,
      surfaceBright,
      surfaceContainerLowest,
      surfaceContainerLow,
      surfaceContainer,
      surfaceContainerHigh,
      surfaceContainerHighest,
      onSurface,
      onSurfaceVariant,
      inverseSurface,
      onInverseSurface,
      outline,
      outlineVariant;

  // Mosh roles beyond Material 3. [onSurfaceMuted] is tertiary text and
  // clears 4.5:1 on every surface container. [onOutgoing], its variant and
  // [outgoingError] sit on [outgoing]. An initials avatar takes one of the
  // four plates per contact with [onAvatar] initials.
  final Color onSurfaceMuted,
      success,
      warning,
      warningContainer,
      onWarningContainer,
      onOutgoing,
      onOutgoingVariant,
      outgoingError,
      avatar1,
      avatar2,
      avatar3,
      avatar4,
      onAvatar;

  // A token that is another token is an alias variable in Figma.
  Color get info => tertiary;
  Color get outgoing => primaryContainer;
  Color get incoming => surfaceContainerHigh;

  /// What lies under a modal and stops the screen: the lowest tone at the
  /// `state/scrim` opacity.
  Color get scrim => MoshState.tint(surfaceContainerLowest, MoshState.scrim);

  /// Every shadow is cast in black, at the opacity of its [MoshElevation].
  Color get shadow => const Color(0xFF000000);

  /// Keyboard focus ring, drawn 2px around the focused control.
  Color get focusRing => onSurface;

  /// The palettes are complete, so nothing overrides a single token.
  @override
  MoshColors copyWith() => this;

  // One line per token, so longer than the 50-line function limit.
  @override
  MoshColors lerp(MoshColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return MoshColors(
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      primaryContainer: mix(primaryContainer, other.primaryContainer),
      onPrimaryContainer: mix(onPrimaryContainer, other.onPrimaryContainer),
      inversePrimary: mix(inversePrimary, other.inversePrimary),
      secondary: mix(secondary, other.secondary),
      onSecondary: mix(onSecondary, other.onSecondary),
      secondaryContainer: mix(secondaryContainer, other.secondaryContainer),
      onSecondaryContainer:
          mix(onSecondaryContainer, other.onSecondaryContainer),
      tertiary: mix(tertiary, other.tertiary),
      onTertiary: mix(onTertiary, other.onTertiary),
      tertiaryContainer: mix(tertiaryContainer, other.tertiaryContainer),
      onTertiaryContainer: mix(onTertiaryContainer, other.onTertiaryContainer),
      error: mix(error, other.error),
      onError: mix(onError, other.onError),
      errorContainer: mix(errorContainer, other.errorContainer),
      onErrorContainer: mix(onErrorContainer, other.onErrorContainer),
      surface: mix(surface, other.surface),
      surfaceDim: mix(surfaceDim, other.surfaceDim),
      surfaceBright: mix(surfaceBright, other.surfaceBright),
      surfaceContainerLowest:
          mix(surfaceContainerLowest, other.surfaceContainerLowest),
      surfaceContainerLow: mix(surfaceContainerLow, other.surfaceContainerLow),
      surfaceContainer: mix(surfaceContainer, other.surfaceContainer),
      surfaceContainerHigh:
          mix(surfaceContainerHigh, other.surfaceContainerHigh),
      surfaceContainerHighest:
          mix(surfaceContainerHighest, other.surfaceContainerHighest),
      onSurface: mix(onSurface, other.onSurface),
      onSurfaceVariant: mix(onSurfaceVariant, other.onSurfaceVariant),
      inverseSurface: mix(inverseSurface, other.inverseSurface),
      onInverseSurface: mix(onInverseSurface, other.onInverseSurface),
      outline: mix(outline, other.outline),
      outlineVariant: mix(outlineVariant, other.outlineVariant),
      onSurfaceMuted: mix(onSurfaceMuted, other.onSurfaceMuted),
      success: mix(success, other.success),
      warning: mix(warning, other.warning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarningContainer: mix(onWarningContainer, other.onWarningContainer),
      onOutgoing: mix(onOutgoing, other.onOutgoing),
      onOutgoingVariant: mix(onOutgoingVariant, other.onOutgoingVariant),
      outgoingError: mix(outgoingError, other.outgoingError),
      avatar1: mix(avatar1, other.avatar1),
      avatar2: mix(avatar2, other.avatar2),
      avatar3: mix(avatar3, other.avatar3),
      avatar4: mix(avatar4, other.avatar4),
      onAvatar: mix(onAvatar, other.onAvatar),
    );
  }
}

ColorScheme _colorScheme(MoshColors c, Brightness brightness) => ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      inversePrimary: c.inversePrimary,
      secondary: c.secondary,
      onSecondary: c.onSecondary,
      secondaryContainer: c.secondaryContainer,
      onSecondaryContainer: c.onSecondaryContainer,
      tertiary: c.tertiary,
      onTertiary: c.onTertiary,
      tertiaryContainer: c.tertiaryContainer,
      onTertiaryContainer: c.onTertiaryContainer,
      error: c.error,
      onError: c.onError,
      errorContainer: c.errorContainer,
      onErrorContainer: c.onErrorContainer,
      surface: c.surface,
      surfaceDim: c.surfaceDim,
      surfaceBright: c.surfaceBright,
      surfaceContainerLowest: c.surfaceContainerLowest,
      surfaceContainerLow: c.surfaceContainerLow,
      surfaceContainer: c.surfaceContainer,
      surfaceContainerHigh: c.surfaceContainerHigh,
      surfaceContainerHighest: c.surfaceContainerHighest,
      onSurface: c.onSurface,
      onSurfaceVariant: c.onSurfaceVariant,
      inverseSurface: c.inverseSurface,
      onInverseSurface: c.onInverseSurface,
      outline: c.outline,
      outlineVariant: c.outlineVariant,
      shadow: c.shadow,
      scrim: c.surfaceContainerLowest,
    );
