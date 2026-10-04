part of 'mosh_theme.dart';

const _moshAppBarTheme = AppBarTheme(
  backgroundColor: MoshColors.bg1,
  foregroundColor: MoshColors.fg1,
  elevation: 0,
  scrolledUnderElevation: 0,
  toolbarHeight: 70,
  titleSpacing: 22,
  shape: Border(bottom: BorderSide(color: MoshColors.line)),
  titleTextStyle: TextStyle(
    fontFamily: _kSansFamily,
    fontFamilyFallback: _kSansFallback,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.02 * 15,
    color: MoshColors.fg1,
  ),
);

const _moshDividerTheme = DividerThemeData(
  color: MoshColors.line,
  thickness: 1,
  space: 1,
);

final _moshInputDecorationTheme = InputDecorationTheme(
  filled: true,
  fillColor: MoshColors.bg1,
  isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
  hintStyle: const TextStyle(fontSize: 12.5, color: MoshColors.fg3),
  labelStyle: const TextStyle(fontSize: 11, color: MoshColors.fg2),
  border: _fieldBorder(MoshColors.fieldBorder),
  enabledBorder: _fieldBorder(MoshColors.fieldBorder),
  disabledBorder: _fieldBorder(MoshColors.line),
  focusedBorder: _fieldBorder(MoshColors.moss),
  errorBorder: _fieldBorder(MoshColors.dangerBorder),
  focusedErrorBorder: _fieldBorder(MoshColors.danger),
);

const _moshListTileTheme = ListTileThemeData(
  dense: true,
  horizontalTitleGap: 10,
  minVerticalPadding: 6,
  contentPadding: EdgeInsets.symmetric(horizontal: 12),
  shape: RoundedRectangleBorder(
    borderRadius: MoshShapes.conversationRow,
  ),
  selectedColor: MoshColors.fg1,
  selectedTileColor: MoshColors.mossGlow,
  titleTextStyle: TextStyle(
    fontFamily: _kSansFamily,
    fontFamilyFallback: _kSansFallback,
    letterSpacing: 0,
    fontSize: 12.5,
    height: 1.3,
    fontWeight: FontWeight.w600,
    color: MoshColors.fg1,
  ),
  subtitleTextStyle: TextStyle(
    fontFamily: _kSansFamily,
    fontFamilyFallback: _kSansFallback,
    letterSpacing: 0,
    fontSize: 10.5,
    height: 1.4,
    color: MoshColors.fg2,
  ),
);

final _moshDialogTheme = DialogThemeData(
  backgroundColor: MoshColors.bg2,
  surfaceTintColor: Colors.transparent,
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(14),
  ),
);

const _moshPopupMenuTheme = PopupMenuThemeData(
  color: MoshColors.bg2,
  surfaceTintColor: Colors.transparent,
  shadowColor: MoshColors.bg0,
  elevation: 8,
  shape: RoundedRectangleBorder(
    borderRadius: MoshShapes.menu,
    side: BorderSide(color: MoshColors.lineStrong),
  ),
);

final _moshSwitchTheme = SwitchThemeData(
  thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? null
          : states.contains(WidgetState.selected)
              ? MoshColors.mossInk
              : MoshColors.fg2),
);

final _moshFilledButtonTheme = FilledButtonThemeData(
  style: FilledButton.styleFrom(
    backgroundColor: MoshColors.moss,
    foregroundColor: MoshColors.mossInk,
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
  side: BorderSide(color: MoshColors.line),
);

const _moshIconTheme = IconThemeData(color: MoshColors.fg2);

/// The `.field input` border recipe: 1px solid, 8px radius.
OutlineInputBorder _fieldBorder(Color color) => OutlineInputBorder(
      borderRadius: MoshShapes.control,
      borderSide: BorderSide(color: color),
    );
