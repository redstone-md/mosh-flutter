import 'package:flutter/material.dart';

import 'mosh_dimensions.dart';
import 'mosh_shapes.dart';
import 'mosh_theme.dart' show MoshColors, MoshLevel;

/// Shared surfaces and interaction states for anchored menus and pickers.
abstract final class MoshMenuTheme {
  /// The panel of a menu: the popup level, its rows [gap] apart.
  static MenuThemeData panel(MoshColors c) => MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(MoshLevel.popup.fill(c)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(c.shadow),
          elevation: WidgetStatePropertyAll(MoshLevel.popup.elevation!.dp),
          padding: const WidgetStatePropertyAll(EdgeInsets.all(MoshSpace.s2)),
          alignment: AlignmentDirectional.bottomStart,
          shape: WidgetStatePropertyAll(MoshLevel.popup.shape(c)),
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

  /// The phone's sheet: the modal level held by three edges of the screen,
  /// so it has no edge of its own and only its top corners are the modal's.
  static BottomSheetThemeData sheet(MoshColors c) => BottomSheetThemeData(
        backgroundColor: MoshLevel.modal.fill(c),
        surfaceTintColor: Colors.transparent,
        shadowColor: c.shadow,
        modalElevation: MoshLevel.modal.elevation!.dp,
        modalBarrierColor: c.scrim,
        showDragHandle: true,
        dragHandleColor: c.outline,
        dragHandleSize: const Size(MoshSpace.s8, MoshSpace.s1),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
              top: Radius.circular(MoshRadius.extraLarge)),
        ),
        clipBehavior: Clip.antiAlias,
      );
}
