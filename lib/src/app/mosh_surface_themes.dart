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

/// The back and close buttons Material builds on its own, in the app's icons.
final _moshActionIconTheme = ActionIconThemeData(
  backButtonIconBuilder: (_) => const Icon(MoshIcons.back),
  closeButtonIconBuilder: (_) => const Icon(MoshIcons.close),
);
