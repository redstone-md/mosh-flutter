import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';
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
            side: BorderSide(color: colors.outlineVariant),
          )),
        ),
      );

  /// A menu row and a Select option: as tall as a control on [platform].
  static MenuButtonThemeData items(
          ColorScheme colors, TextStyle? text, TargetPlatform platform) =>
      MenuButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(text),
          minimumSize:
              WidgetStatePropertyAll(Size(0, MoshControl.height(platform))),
          padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
          shape: const WidgetStatePropertyAll(MoshShapes.controlShape),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.disabled)
                  ? MoshState.tint(colors.onSurface, MoshState.disabledContent)
                  : colors.onSurface),
          // The row tints itself like any control; keyboard focus adds the
          // ring.
          overlayColor: MoshState.layer(colors.onSurface),
          side: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.focused)
                  ? BorderSide(color: colors.onSurface, width: MoshBorder.thick)
                  : BorderSide.none),
        ),
      );

  static BottomSheetThemeData sheet(ColorScheme colors) => BottomSheetThemeData(
        backgroundColor: colors.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: colors.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(MoshRadius.large)),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      );
}
