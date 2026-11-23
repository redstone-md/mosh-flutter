part of 'mosh_theme.dart';

AppBarTheme _appBarTheme(MoshColors c, TextTheme text) => AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 70,
      titleSpacing: 22,
      shape: Border(bottom: BorderSide(color: c.outlineVariant)),
      titleTextStyle: text.titleLarge,
    );

DividerThemeData _dividerTheme(MoshColors c) => DividerThemeData(
      color: c.outlineVariant,
      thickness: 1,
      space: 1,
    );

InputDecorationTheme _inputDecorationTheme(MoshColors c, TextTheme text) =>
    InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      hintStyle: text.bodyMedium!.copyWith(color: c.onSurfaceMuted),
      labelStyle: text.bodySmall,
      border: _fieldBorder(c.outline),
      enabledBorder: _fieldBorder(c.outline),
      disabledBorder: _fieldBorder(c.outlineVariant),
      focusedBorder: _fieldBorder(c.primary),
      errorBorder: _fieldBorder(c.error),
      focusedErrorBorder: _fieldBorder(c.error, width: 2),
    );

ListTileThemeData _listTileTheme(MoshColors c, TextTheme text) =>
    ListTileThemeData(
      dense: true,
      horizontalTitleGap: 10,
      minVerticalPadding: 6,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      shape: const RoundedRectangleBorder(
        borderRadius: MoshShapes.conversationRow,
      ),
      selectedColor: c.onSecondaryContainer,
      selectedTileColor: c.secondaryContainer,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
    );

DialogThemeData _dialogTheme(MoshColors c) => DialogThemeData(
      backgroundColor: c.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        // Off the radius scale until the dialog component is redrawn (MOSH-125).
        borderRadius: BorderRadius.circular(14),
      ),
    );

PopupMenuThemeData _popupMenuTheme(MoshColors c) => PopupMenuThemeData(
      color: c.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shadowColor: const Color(0xFF000000),
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: MoshShapes.menu,
        side: BorderSide(color: c.outlineVariant),
      ),
    );

SwitchThemeData _switchTheme(MoshColors c) => SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? null
              : states.contains(WidgetState.selected)
                  ? c.onPrimary
                  : c.onSurfaceVariant),
    );

FilledButtonThemeData _filledButtonTheme(MoshColors c) => FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        shape: MoshShapes.controlShape,
      ),
    );

const _moshOutlinedButtonTheme = OutlinedButtonThemeData(
  style: ButtonStyle(shape: WidgetStatePropertyAll(MoshShapes.controlShape)),
);

const _moshTextButtonTheme = TextButtonThemeData(
  style: ButtonStyle(shape: WidgetStatePropertyAll(MoshShapes.controlShape)),
);

const _moshIconButtonTheme = IconButtonThemeData(
  style: ButtonStyle(shape: WidgetStatePropertyAll(MoshShapes.controlShape)),
);

ChipThemeData _chipTheme(MoshColors c) => ChipThemeData(
      shape: MoshShapes.controlShape,
      side: BorderSide(color: c.outlineVariant),
    );

/// The `.field input` border recipe: solid, on the control radius. A focused
/// field in error keeps the error colour and doubles the edge instead.
OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: MoshShapes.control,
      borderSide: BorderSide(color: color, width: width),
    );

/// The back and close buttons Material builds on its own, in the app's icons.
final _moshActionIconTheme = ActionIconThemeData(
  backButtonIconBuilder: (_) => const Icon(MoshIcons.back),
  closeButtonIconBuilder: (_) => const Icon(MoshIcons.close),
);
