import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'mosh_menu_item.dart';
import 'mosh_shapes.dart';
import 'mosh_theme.dart';

@immutable
class MoshSelectOption<T> {
  const MoshSelectOption(this.value, this.label, {this.enabled = true});

  final T value;
  final String label;
  final bool enabled;
}

/// A controlled choice: desktop popover, mobile/narrow-window bottom sheet.
/// Nullable values are options too; dismissing a sheet never selects null.
class MoshSelect<T> extends StatefulWidget {
  const MoshSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<MoshSelectOption<T>> options;
  final ValueChanged<T>? onChanged;

  @override
  State<MoshSelect<T>> createState() => _MoshSelectState<T>();
}

class _MoshSelectState<T> extends State<MoshSelect<T>> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.sizeOf(context);
    final sheet = size.width < 600 ||
        theme.platform == TargetPlatform.android ||
        theme.platform == TargetPlatform.iOS;
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(constraints.maxWidth, 440.0);
      return MenuAnchor(
        childFocusNode: _focus,
        consumeOutsideTap: true,
        clipBehavior: Clip.antiAlias,
        alignmentOffset: const Offset(0, 6),
        style: MenuStyle(
          minimumSize: WidgetStatePropertyAll(Size(width, 0)),
          maximumSize: WidgetStatePropertyAll(
              Size(width, math.min(360, size.height * 0.6))),
        ),
        menuChildren: [
          for (final option in widget.options)
            _item(option, () => widget.onChanged?.call(option.value)),
        ],
        builder: (context, controller, _) => _button(theme, () {
          if (sheet) {
            _openSheet();
          } else if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        }),
      );
    });
  }

  Widget _button(ThemeData theme, VoidCallback open) {
    final selected = widget.options.where((o) => o.value == widget.value);
    final text = selected.isEmpty ? widget.label : selected.first.label;
    return Semantics(
      label: widget.label,
      child: OutlinedButton(
        focusNode: _focus,
        onPressed: widget.onChanged == null ? null : open,
        style: _buttonStyle(theme),
        child: Row(children: [
          Expanded(
              child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: 12),
          const Icon(Icons.keyboard_arrow_down, size: 20),
        ]),
      ),
    );
  }

  ButtonStyle _buttonStyle(ThemeData theme) => ButtonStyle(
        visualDensity: VisualDensity.standard,
        textStyle: WidgetStatePropertyAll(theme.textTheme.bodyMedium),
        minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        shape: const WidgetStatePropertyAll(MoshShapes.controlShape),
        backgroundColor:
            WidgetStatePropertyAll(theme.colorScheme.surfaceContainerLow),
        foregroundColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.disabled)
                ? theme.disabledColor
                : theme.colorScheme.onSurface),
        side: WidgetStateProperty.resolveWith((states) => BorderSide(
            color: states.contains(WidgetState.focused)
                ? MoshColors.focusRing
                : states.contains(WidgetState.disabled)
                    ? MoshColors.line
                    : MoshColors.fieldBorder)),
      );

  Widget _item(MoshSelectOption<T> option, VoidCallback select) => MoshMenuItem(
        label: option.label,
        selected: option.value == widget.value,
        onPressed: option.enabled && widget.onChanged != null ? select : null,
      );

  Future<void> _openSheet() async {
    final choice = await showModalBottomSheet<MoshSelectOption<T>>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(widget.label,
                          style: Theme.of(context).textTheme.titleMedium))),
              IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, size: 20)),
            ]),
            const SizedBox(height: 8),
            Flexible(
                child: ListView(shrinkWrap: true, children: [
              for (final option in widget.options)
                _item(option, () => Navigator.of(context).pop(option)),
            ])),
          ]),
        ),
      ),
    );
    if (mounted && choice != null) widget.onChanged?.call(choice.value);
  }
}
