import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_menu_theme.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

part 'mosh_colors.dart';
part 'mosh_palette.dart';
part 'mosh_typography.dart';
part 'mosh_control_themes.dart';
part 'mosh_surface_themes.dart';

/// The app theme on one palette: [MoshColors.dark] or [MoshColors.light].
/// [platform] sizes the controls: 48 px on a phone, 40 px on the desktop.
ThemeData buildMoshTheme(
    [MoshColors colors = MoshColors.dark, TargetPlatform? platform]) {
  platform ??= defaultTargetPlatform;
  final brightness = ThemeData.estimateBrightnessForColor(colors.surface);
  final scheme = _colorScheme(colors, brightness);
  final text = _textTheme(colors);
  // State layers of controls without a theme of their own: the content
  // colour at the `state/*` opacity, so the surface stays visible under it.
  final pressed = MoshState.tint(colors.onSurface, MoshState.pressed);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [colors],
    scaffoldBackgroundColor: colors.surface,
    canvasColor: colors.surface,
    dividerColor: colors.outlineVariant, // hairline
    platform: platform,
    splashColor: pressed,
    highlightColor: pressed,
    hoverColor: MoshState.tint(colors.onSurface, MoshState.hover),
    focusColor: MoshState.tint(colors.onSurface, MoshState.focus),
    visualDensity: VisualDensity.compact,
    fontFamily: _kSansFamily,
    fontFamilyFallback: _kSansFallback,
    textTheme: text,
    appBarTheme: _appBarTheme(colors, text),
    dividerTheme: _dividerTheme(colors),
    inputDecorationTheme: _inputDecorationTheme(colors, text, platform),
    listTileTheme: _listTileTheme(colors, text),
    dialogTheme: _dialogTheme(colors),
    popupMenuTheme: _popupMenuTheme(colors),
    menuTheme: MoshMenuTheme.panel(colors),
    menuButtonTheme: MoshMenuTheme.items(scheme, text.bodyMedium, platform),
    bottomSheetTheme: MoshMenuTheme.sheet(colors),
    filledButtonTheme: _filledButtonTheme(colors, text, platform),
    outlinedButtonTheme: _outlinedButtonTheme(colors, text, platform),
    textButtonTheme: _textButtonTheme(colors, text, platform),
    iconButtonTheme: _iconButtonTheme(colors, platform),
    chipTheme: _chipTheme(colors, text),
    checkboxTheme: _checkboxTheme(colors),
    progressIndicatorTheme: _progressTheme(colors),
    sliderTheme: _sliderTheme(colors),
    iconTheme: IconThemeData(color: colors.onSurfaceVariant),
    actionIconTheme: _moshActionIconTheme,
  );
}

final ThemeData moshThemeData = buildMoshTheme();
