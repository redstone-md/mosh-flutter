import 'package:flutter/material.dart';

import 'mosh_shapes.dart';

/// Shared surfaces and interaction states for anchored menus and pickers.
abstract final class MoshMenuTheme {
  static MenuThemeData panel(ColorScheme colors) => MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(colors.shadow),
          elevation: const WidgetStatePropertyAll(8),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
          alignment: AlignmentDirectional.bottomStart,
          shape: WidgetStatePropertyAll(RoundedRectangleBorder(
            borderRadius: MoshShapes.menu,
            side: BorderSide(color: colors.outline),
          )),
        ),
      );

  static MenuButtonThemeData items(ColorScheme colors, TextStyle? text) =>
      MenuButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(text),
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          shape: const WidgetStatePropertyAll(MoshShapes.controlShape),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? colors.onSurface.withValues(alpha: 0.38)
                  : colors.onSurface),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.hovered) ||
                      states.contains(WidgetState.focused)
                  ? colors.surfaceContainerHighest
                  : Colors.transparent),
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused)
                  ? BorderSide(color: colors.onSurface)
                  : BorderSide.none),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      );

  static BottomSheetThemeData sheet(ColorScheme colors) => BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: colors.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          side: BorderSide(color: colors.outline),
        ),
        clipBehavior: Clip.antiAlias,
      );
}
