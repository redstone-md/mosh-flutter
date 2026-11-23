import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_menu_theme.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

part 'mosh_colors.dart';
part 'mosh_palette.dart';
part 'mosh_typography.dart';
part 'mosh_control_themes.dart';

/// The app theme on one palette: [MoshColors.dark] or [MoshColors.light].
ThemeData buildMoshTheme([MoshColors colors = MoshColors.dark]) {
  final brightness = ThemeData.estimateBrightnessForColor(colors.surface);
  final scheme = _colorScheme(colors, brightness);
  final text = _textTheme(colors);
  // Material 3 state layer for press, hover and focus: the content colour
  // at 10%, so the surface and its text stay visible under it.
  final stateLayer = colors.onSurface.withAlpha(0x1A);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [colors],
    scaffoldBackgroundColor: colors.surface,
    canvasColor: colors.surface,
    dividerColor: colors.outlineVariant, // hairline
    splashColor: stateLayer,
    highlightColor: stateLayer,
    focusColor: stateLayer,
    visualDensity: VisualDensity.compact,
    fontFamily: _kSansFamily,
    fontFamilyFallback: _kSansFallback,
    textTheme: text,
    appBarTheme: _appBarTheme(colors, text),
    dividerTheme: _dividerTheme(colors),
    inputDecorationTheme: _inputDecorationTheme(colors, text),
    listTileTheme: _listTileTheme(colors, text),
    dialogTheme: _dialogTheme(colors),
    popupMenuTheme: _popupMenuTheme(colors),
    menuTheme: MoshMenuTheme.panel(scheme),
    menuButtonTheme: MoshMenuTheme.items(scheme, text.bodyMedium),
    bottomSheetTheme: MoshMenuTheme.sheet(scheme),
    switchTheme: _switchTheme(colors),
    filledButtonTheme: _filledButtonTheme(colors),
    outlinedButtonTheme: _moshOutlinedButtonTheme,
    textButtonTheme: _moshTextButtonTheme,
    iconButtonTheme: _moshIconButtonTheme,
    chipTheme: _chipTheme(colors),
    iconTheme: IconThemeData(color: colors.onSurfaceVariant),
  );
}

final ThemeData moshThemeData = buildMoshTheme();
