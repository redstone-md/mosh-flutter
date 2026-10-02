import 'package:flutter/material.dart';

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
          foregroundColor: danger && onPressed != null
              ? WidgetStatePropertyAll(colors.error)
              : null,
          iconColor: danger && onPressed != null
              ? WidgetStatePropertyAll(colors.error)
              : null,
          backgroundColor: selected == true
              ? WidgetStatePropertyAll(colors.primary.withValues(alpha: 0.14))
              : null,
        ),
        leadingIcon: icon == null ? null : Icon(icon, size: 18),
        trailingIcon: selected == null
            ? null
            : SizedBox(
                width: 20,
                child: selected!
                    ? Icon(Icons.check, size: 20, color: colors.primary)
                    : null),
        child: Text(label),
      ),
    );
  }
}
