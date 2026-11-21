part of 'mosh_theme.dart';

final _moshAppBarTheme = AppBarTheme(
  backgroundColor: MoshColors.surface,
  foregroundColor: MoshColors.onSurface,
  elevation: 0,
  scrolledUnderElevation: 0,
  toolbarHeight: 70,
  titleSpacing: 22,
  shape: const Border(bottom: BorderSide(color: MoshColors.outlineVariant)),
  titleTextStyle: _moshTextTheme.titleLarge,
);

const _moshDividerTheme = DividerThemeData(
  color: MoshColors.outlineVariant,
  thickness: 1,
  space: 1,
);

final _moshInputDecorationTheme = InputDecorationTheme(
  filled: true,
  fillColor: MoshColors.surface,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
  hintStyle:
      _moshTextTheme.bodyMedium!.copyWith(color: MoshColors.onSurfaceMuted),
  labelStyle: _moshTextTheme.bodySmall,
  border: _fieldBorder(MoshColors.outline),
  enabledBorder: _fieldBorder(MoshColors.outline),
  disabledBorder: _fieldBorder(MoshColors.outlineVariant),
  focusedBorder: _fieldBorder(MoshColors.primary),
  errorBorder: _fieldBorder(MoshColors.error),
  focusedErrorBorder: _fieldBorder(MoshColors.error, width: 2),
);

final _moshListTileTheme = ListTileThemeData(
  dense: true,
  horizontalTitleGap: 10,
  minVerticalPadding: 6,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
  shape: const RoundedRectangleBorder(
    borderRadius: MoshShapes.conversationRow,
  ),
  selectedColor: MoshColors.onSecondaryContainer,
  selectedTileColor: MoshColors.secondaryContainer,
  titleTextStyle: _moshTextTheme.titleSmall,
  subtitleTextStyle: _moshTextTheme.bodySmall,
);

final _moshDialogTheme = DialogThemeData(
  backgroundColor: MoshColors.surfaceContainerHigh,
  surfaceTintColor: Colors.transparent,
  shape: RoundedRectangleBorder(
    // Off the radius scale until the dialog component is redrawn (MOSH-125).
    borderRadius: BorderRadius.circular(14),
  ),
);

const _moshPopupMenuTheme = PopupMenuThemeData(
  color: MoshColors.surfaceContainerHigh,
  surfaceTintColor: Colors.transparent,
  shadowColor: Color(0xFF000000),
  elevation: 8,
  shape: RoundedRectangleBorder(
    borderRadius: MoshShapes.menu,
    side: BorderSide(color: MoshColors.outlineVariant),
  ),
);

final _moshSwitchTheme = SwitchThemeData(
  thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? null
          : states.contains(WidgetState.selected)
              ? MoshColors.onPrimary
              : MoshColors.onSurfaceVariant),
);

final _moshFilledButtonTheme = FilledButtonThemeData(
  style: FilledButton.styleFrom(
    backgroundColor: MoshColors.primary,
    foregroundColor: MoshColors.onPrimary,
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

const _moshChipTheme = ChipThemeData(
  shape: MoshShapes.controlShape,
  side: BorderSide(color: MoshColors.outlineVariant),
);

const _moshIconTheme = IconThemeData(color: MoshColors.onSurfaceVariant);

/// The `.field input` border recipe: solid, on the control radius. A focused
/// field in error keeps the error colour and doubles the edge instead.
OutlineInputBorder _fieldBorder(Color color, {double width = 1}) =>
    OutlineInputBorder(
      borderRadius: MoshShapes.control,
      borderSide: BorderSide(color: color, width: width),
    );
