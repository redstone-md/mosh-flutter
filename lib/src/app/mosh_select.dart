import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_icons.dart';

import 'mosh_dimensions.dart';
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

/// The Select card, a controlled choice: a well with a caret that opens a
/// popover on the desktop and a bottom sheet on a phone or a narrow window.
/// Nullable values are options too; dismissing a sheet never selects null.
class MoshSelect<T> extends StatefulWidget {
  const MoshSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.showLabel = false,
    this.failed = false,
  });

  /// Names the control to a screen reader and titles the phone's sheet.
  final String label;

  /// Whether [label] is drawn above the well, as the Select card has it.
  /// Without it the heading above the select says what is chosen.
  final bool showLabel;

  /// True while the choices could not be loaded: the well's edge turns red.
  final bool failed;
  final T value;
  final List<MoshSelectOption<T>> options;
  final ValueChanged<T>? onChanged;

  @override
  State<MoshSelect<T>> createState() => _MoshSelectState<T>();
}

class _MoshSelectState<T> extends State<MoshSelect<T>> {
  final _focus = FocusNode();
  // Overlay scroll views must not read a surrounding disclosure's bool state.
  final _menuStorage = PageStorageBucket();
  // The phone's sheet is not the menu, so the caret is told of it here.
  bool _sheetOpen = false;

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
    final select = _anchor(theme, size, sheet);
    if (!widget.showLabel) return select;
    final colors = MoshColors.from(theme);
    // The well already carries the label for a screen reader.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Text(widget.label,
              style: theme.textTheme.labelMedium!.copyWith(
                  color: widget.onChanged == null
                      ? MoshState.tint(
                          colors.onSurface, MoshState.disabledContent)
                      : colors.onSurfaceVariant)),
        ),
        const SizedBox(height: MoshSpace.s2),
        select,
      ],
    );
  }

  Widget _anchor(ThemeData theme, Size size, bool sheet) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = math.min(constraints.maxWidth, 440.0);
      return PageStorage(
        bucket: _menuStorage,
        child: MenuAnchor(
          childFocusNode: _focus,
          consumeOutsideTap: true,
          clipBehavior: Clip.antiAlias,
          alignmentOffset: const Offset(0, 6),
          style: MenuStyle(
            minimumSize: WidgetStatePropertyAll(Size(width, 0)),
            maximumSize: WidgetStatePropertyAll(
                Size(width, math.min(360, size.height * 0.6))),
          ),
          menuChildren: MoshMenuItem.rows([
            for (final option in widget.options)
              _item(option, () => widget.onChanged?.call(option.value)),
          ]),
          builder: (context, controller, _) =>
              _button(theme, controller.isOpen || _sheetOpen, () {
            if (sheet) {
              _openSheet();
            } else if (controller.isOpen) {
              controller.close();
            } else {
              controller.open();
            }
          }),
        ),
      );
    });
  }

  Widget _button(ThemeData theme, bool isOpen, VoidCallback toggle) {
    final selected = widget.options.where((o) => o.value == widget.value);
    // With no choice made the well says what it is for, unless the label
    // above it already does.
    final text = selected.isNotEmpty
        ? selected.first.label
        : widget.showLabel
            ? ''
            : widget.label;
    final well = OutlinedButton(
      focusNode: _focus,
      onPressed: widget.onChanged == null ? null : toggle,
      style: moshSelectWellStyle(theme, open: isOpen, failed: widget.failed),
      child: Row(children: [
        Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: MoshSpace.s2),
        AnimatedRotation(
          turns: isOpen ? 0.5 : 0,
          duration: MoshMotion.effectsFast.duration,
          curve: MoshMotion.effectsFast.curve,
          child: const Icon(MoshIcons.expandMore, size: MoshSpace.s5),
        ),
      ]),
    );
    return Semantics(label: widget.label, child: well);
  }

  MoshMenuItem _item(MoshSelectOption<T> option, VoidCallback select) =>
      MoshMenuItem(
        label: option.label,
        selected: option.value == widget.value,
        onPressed: option.enabled && widget.onChanged != null ? select : null,
      );

  Future<void> _openSheet() async {
    setState(() => _sheetOpen = true);
    final choice = await showModalBottomSheet<MoshSelectOption<T>>(
      context: context,
      routeSettings: RouteSettings(name: ModalRoute.of(context)?.settings.name),
      useSafeArea: true,
      isScrollControlled: true,
      builder: (context) => ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        // The Sheet card: the handle, the title with the way out, then the
        // choices, a step wider apart than a menu's.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              MoshSpace.s3, MoshSpace.s3, MoshSpace.s3, MoshSpace.s6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: MoshSpace.s8,
              height: MoshSpace.s1,
              margin: const EdgeInsets.only(bottom: MoshSpace.s2),
              decoration: ShapeDecoration(
                  color: MoshColors.of(context).outline,
                  shape: MoshShapes.pill),
            ),
            Row(children: [
              Expanded(
                  child: Padding(
                      padding:
                          const EdgeInsetsDirectional.only(start: MoshSpace.s3),
                      child: Text(widget.label,
                          style: Theme.of(context).textTheme.titleMedium))),
              IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(MoshIcons.close)),
            ]),
            const SizedBox(height: MoshSpace.s2),
            Flexible(
                child: ListView(
                    shrinkWrap: true,
                    children: MoshMenuItem.rows([
                      for (final option in widget.options)
                        _item(option, () => Navigator.of(context).pop(option)),
                    ], gap: MoshSpace.s2))),
          ]),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    if (choice != null) widget.onChanged?.call(choice.value);
  }
}
