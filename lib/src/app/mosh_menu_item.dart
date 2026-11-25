import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';

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
  static List<Widget> rows(List<MoshMenuItem> items) => [
        for (final (i, item) in items.indexed) ...[
          if (i > 0 && item.danger)
            const Divider(height: MoshSpace.s1 * 2 + MoshBorder.thin)
          else if (i > 0)
            const SizedBox(height: MoshSpace.s1),
          item,
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: MenuItemButton(
        onPressed: onPressed,
        clipBehavior: Clip.antiAlias,
        overflowAxis: Axis.vertical,
        style: ButtonStyle(
          // An action is set as a label and leaves more room after it than
          // a choice does after its mark.
          textStyle: selected == null
              ? WidgetStatePropertyAll(Theme.of(context).textTheme.labelLarge)
              : null,
          padding: selected == null
              ? const WidgetStatePropertyAll(EdgeInsetsDirectional.only(
                  start: MoshSpace.s3, end: MoshSpace.s4))
              : null,
          foregroundColor: onPressed == null
              ? null
              : danger
                  ? WidgetStatePropertyAll(colors.error)
                  : selected == true
                      ? WidgetStatePropertyAll(colors.onSecondaryContainer)
                      : null,
          iconColor: danger && onPressed != null
              ? WidgetStatePropertyAll(colors.error)
              : null,
          backgroundColor: selected == true
              ? WidgetStatePropertyAll(colors.secondaryContainer)
              : null,
        ),
        leadingIcon: icon == null ? null : Icon(icon, size: MoshSpace.s5),
        trailingIcon: selected == null
            ? null
            : SizedBox(
                width: 20,
                child: selected!
                    ? Icon(MoshIcons.check,
                        size: 20, color: colors.onSecondaryContainer)
                    : null),
        child: Text(label),
      ),
    );
  }
}
