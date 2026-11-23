import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart';

/// Setup keeps the app's palette and type scale, with comfortable controls.
/// Setup values are the receiver of `merge`: `styleFrom` in the app theme
/// fills every slot (even with null), so merging the other way drops them.
ThemeData buildSetupTheme(ThemeData theme) {
  final colors = MoshColors.from(theme);
  final button = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
      textStyle: WidgetStatePropertyAll(theme.textTheme.bodyLarge
          ?.copyWith(fontSize: 15, fontWeight: FontWeight.w600)));
  return theme.copyWith(
    visualDensity: VisualDensity.standard,
    textTheme: theme.textTheme.copyWith(bodyMedium: theme.textTheme.bodyLarge),
    inputDecorationTheme: theme.inputDecorationTheme.copyWith(
        isDense: false,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        helperStyle:
            theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant),
        labelStyle: theme.textTheme.bodyLarge
            ?.copyWith(color: colors.onSurfaceVariant)),
    filledButtonTheme: FilledButtonThemeData(
        style: button.merge(theme.filledButtonTheme.style)),
    outlinedButtonTheme: OutlinedButtonThemeData(
        style: button
            .copyWith(
                foregroundColor: _foreground(colors.onSurface),
                side: WidgetStateProperty.resolveWith((states) => BorderSide(
                    color: states.contains(WidgetState.focused)
                        ? colors.focusRing
                        : states.contains(WidgetState.disabled)
                            ? colors.outlineVariant
                            : colors.outline)))
            .merge(theme.outlinedButtonTheme.style)),
    textButtonTheme: TextButtonThemeData(
        style: theme.textButtonTheme.style?.copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
            textStyle: button.textStyle,
            foregroundColor: _foreground(colors.onSurfaceVariant))),
  );
}

WidgetStateProperty<Color?> _foreground(Color color) =>
    WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled) ? null : color);
