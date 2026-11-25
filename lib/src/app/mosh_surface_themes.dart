part of 'mosh_theme.dart';

/// A bar at the top of a screen, as the Top bar card draws it: the
/// background's own tone, 64 px tall, with no line under it.
AppBarTheme _appBarTheme(MoshColors c, TextTheme text) => AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: MoshSpace.s16,
      titleSpacing: MoshSpace.s5,
      titleTextStyle: text.titleMedium,
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
          borderRadius: BorderRadius.all(Radius.circular(MoshRadius.medium))),
      selectedColor: c.onSecondaryContainer,
      selectedTileColor: c.secondaryContainer,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
    );

/// The four levels a surface sits on, lowest first (Surface levels card).
/// The background is the screen; a panel is a part of it; a popup floats
/// until its choice is made (menu, toast); a modal stops the screen and
/// always lies on the [MoshColors.scrim]. A surface takes its tone, edge,
/// corners and shadow from its level.
enum MoshLevel {
  background,
  panel,
  popup(MoshRadius.large, MoshElevation.level2),
  modal(MoshRadius.extraLarge, MoshElevation.level3);

  const MoshLevel([this.radius = MoshRadius.none, this.elevation]);

  final double radius;

  /// Null for the levels that lie in the screen and cast nothing.
  final MoshElevation? elevation;

  BorderRadius get corners => BorderRadius.all(Radius.circular(radius));

  Color fill(MoshColors c) => switch (this) {
        background => c.surface,
        panel => c.surfaceContainerLow,
        popup || modal => c.surfaceContainerHigh,
      };

  /// The edge that lifts a floating surface off whatever is under it.
  BorderSide edge(MoshColors c) =>
      elevation == null ? BorderSide.none : BorderSide(color: c.outlineVariant);

  /// For a surface Material paints: it casts [elevation] as `dp`.
  OutlinedBorder shape(MoshColors c) =>
      RoundedRectangleBorder(borderRadius: corners, side: edge(c));

  /// A panel drawn as a card inside the background: the panel's tone with a
  /// quiet edge. Settings cards, the start list, the player of a sound and
  /// a quiet notice are cards; each brings its own [corners].
  static ShapeDecoration card(MoshColors c, BorderRadius corners) =>
      ShapeDecoration(
        color: panel.fill(c),
        shape: RoundedRectangleBorder(
            borderRadius: corners, side: BorderSide(color: c.outlineVariant)),
      );

  /// For a surface painted by hand.
  BoxDecoration decoration(MoshColors c) => BoxDecoration(
        color: fill(c),
        borderRadius: corners,
        border: elevation == null ? null : Border.fromBorderSide(edge(c)),
        boxShadow: elevation?.shadows,
      );
}

DialogThemeData _dialogTheme(MoshColors c) => DialogThemeData(
      backgroundColor: MoshLevel.modal.fill(c),
      surfaceTintColor: Colors.transparent,
      shadowColor: c.shadow,
      elevation: MoshLevel.modal.elevation!.dp,
      barrierColor: c.scrim,
      shape: MoshLevel.modal.shape(c),
    );

PopupMenuThemeData _popupMenuTheme(MoshColors c) => PopupMenuThemeData(
      color: MoshLevel.popup.fill(c),
      surfaceTintColor: Colors.transparent,
      shadowColor: c.shadow,
      elevation: MoshLevel.popup.elevation!.dp,
      shape: MoshLevel.popup.shape(c),
    );

/// The back and close buttons Material builds on its own, in the app's icons.
final _moshActionIconTheme = ActionIconThemeData(
  backButtonIconBuilder: (_) => const Icon(MoshIcons.back),
  closeButtonIconBuilder: (_) => const Icon(MoshIcons.close),
);
