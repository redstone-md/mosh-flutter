import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_menu_theme.dart';
import 'package:mosh/src/app/mosh_shapes.dart';

part 'mosh_colors.dart';
part 'mosh_typography.dart';
part 'mosh_control_themes.dart';

/// Material 3 state layer for press, hover and focus: the content colour
/// at 10%, so the surface and its text stay visible under it.
const Color _stateLayer = Color(0x1AF4EFE9);

ThemeData buildMoshTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: _moshColorScheme,
    scaffoldBackgroundColor: MoshColors.surface,
    canvasColor: MoshColors.surface,
    dividerColor: MoshColors.outlineVariant, // hairline
    splashColor: _stateLayer,
    highlightColor: _stateLayer,
    focusColor: _stateLayer,
    visualDensity: VisualDensity.compact,
    fontFamily: _kSansFamily,
    fontFamilyFallback: _kSansFallback,
    textTheme: _moshTextTheme,
    appBarTheme: _moshAppBarTheme,
    dividerTheme: _moshDividerTheme,
    inputDecorationTheme: _moshInputDecorationTheme,
    listTileTheme: _moshListTileTheme,
    dialogTheme: _moshDialogTheme,
    popupMenuTheme: _moshPopupMenuTheme,
    menuTheme: MoshMenuTheme.panel(_moshColorScheme),
    menuButtonTheme:
        MoshMenuTheme.items(_moshColorScheme, _moshTextTheme.bodyMedium),
    bottomSheetTheme: MoshMenuTheme.sheet(_moshColorScheme),
    switchTheme: _moshSwitchTheme,
    filledButtonTheme: _moshFilledButtonTheme,
    outlinedButtonTheme: _moshOutlinedButtonTheme,
    textButtonTheme: _moshTextButtonTheme,
    iconButtonTheme: _moshIconButtonTheme,
    chipTheme: _moshChipTheme,
    iconTheme: _moshIconTheme,
  );
}

final ThemeData moshThemeData = buildMoshTheme();
