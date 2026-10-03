import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart';

/// Setup keeps the app's palette and type scale, with comfortable controls.
ThemeData buildSetupTheme(ThemeData theme) {
  final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 52)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
      textStyle: WidgetStatePropertyAll(
          theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)));
  return theme.copyWith(
    visualDensity: VisualDensity.standard,
    textTheme: theme.textTheme.copyWith(bodyMedium: theme.textTheme.bodyLarge),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        helperStyle: theme.textTheme.bodyLarge?.copyWith(color: MoshColors.fg2),
        labelStyle: theme.textTheme.bodyLarge?.copyWith(color: MoshColors.fg2)),
    filledButtonTheme: FilledButtonThemeData(
        style: theme.filledButtonTheme.style?.merge(button)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: theme.outlinedButtonTheme.style?.merge(button.copyWith(
            foregroundColor: _foreground(MoshColors.fg1),
            side: WidgetStateProperty.resolveWith((states) => BorderSide(
                color: states.contains(WidgetState.focused)
                    ? MoshColors.focusRing
                    : states.contains(WidgetState.disabled)
                        ? MoshColors.line
                        : MoshColors.fieldBorder))))),
    textButtonTheme: TextButtonThemeData(
        style: theme.textButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
            foregroundColor: _foreground(MoshColors.fg2))),
  );
}

WidgetStateProperty<Color?> _foreground(Color color) =>
    WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? null : color);
