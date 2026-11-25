import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_menu_theme.dart';

/// The Menu item of the Menu card, and with [selected] the Select option.
/// Material owns focus, keyboard navigation and dismissal for every row.
class MoshMenuItem extends StatelessWidget {
  const MoshMenuItem({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.selected,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool? selected;
  final bool danger;

  /// The rows of a menu as its panel lays them out: a step apart, and one
  /// that cannot be undone under a line of its own.
  /// The phone's sheet sets its choices a wider [gap] apart.
  static List<Widget> rows(List<MoshMenuItem> items,
          {double gap = MoshSpace.s1}) =>
      [
        for (final (i, item) in items.indexed) ...[
          if (i > 0 && item.danger)
            Divider(height: gap * 2 + MoshBorder.thin)
          else if (i > 0)
            SizedBox(height: gap),
          item,
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choice = selected;
    return Semantics(
      selected: choice,
      child: MenuItemButton(
        onPressed: onPressed,
        clipBehavior: Clip.antiAlias,
        overflowAxis: Axis.vertical,
        style: choice == null ? _action(theme) : _choice(theme, choice),
        leadingIcon: icon == null ? null : Icon(icon, size: MoshSpace.s5),
        trailingIcon: choice == null
            ? null
            : SizedBox(
                width: MoshSpace.s5,
                // The mark takes the row's ink, so it dims with a row that
                // cannot be picked.
                child: choice
                    ? const Icon(MoshIcons.check, size: MoshSpace.s5)
                    : null),
        child: Text(label),
      ),
    );
  }

  /// The Menu item: set as a label, with more room after it than a choice
  /// leaves after its mark, and as wide as its menu so its tint reaches both
  /// edges. One that cannot be undone is in the error colour, tint included.
  ButtonStyle _action(ThemeData theme) {
    final ink = danger ? theme.colorScheme.error : null;
    return ButtonStyle(
      textStyle: WidgetStatePropertyAll(theme.textTheme.labelLarge),
      minimumSize: WidgetStatePropertyAll(
          Size(MoshMenuTheme.rowWidth, MoshControl.height(theme.platform))),
      padding: const WidgetStatePropertyAll(
          EdgeInsetsDirectional.only(start: MoshSpace.s3, end: MoshSpace.s4)),
      foregroundColor:
          ink == null || onPressed == null ? null : WidgetStatePropertyAll(ink),
      iconColor:
          ink == null || onPressed == null ? null : WidgetStatePropertyAll(ink),
      overlayColor: ink == null ? null : MoshState.layer(ink),
    );
  }

  /// The Select option: the theme's row, lit while it is the chosen one.
  ButtonStyle? _choice(ThemeData theme, bool chosen) => !chosen
      ? null
      : ButtonStyle(
          foregroundColor: onPressed == null
              ? null
              : WidgetStatePropertyAll(theme.colorScheme.onSecondaryContainer),
          iconColor: onPressed == null
              ? null
              : WidgetStatePropertyAll(theme.colorScheme.onSecondaryContainer),
          backgroundColor:
              WidgetStatePropertyAll(theme.colorScheme.secondaryContainer),
        );
}
