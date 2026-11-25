import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

/// The Search field card: a pill on its own plate with the search glyph.
/// While it holds a query a button clears it; while it is empty it shows
/// [shortcut], the keys that bring the focus here, when there are any.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.focusNode,
    this.shortcut,
    this.autofocus = false,
    this.clearable = true,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final FocusNode? focusNode;
  final String? shortcut;
  final bool autofocus;

  /// Off where a button beside the field closes the search and so clears
  /// it: the field then keeps no clear button of its own.
  final bool clearable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoshColors.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: hint,
          fillColor: colors.surfaceContainerHigh,
          // The plate carries the field, so it has no edge until the focus
          // ring takes its place.
          border: const OutlineInputBorder(
              borderRadius: MoshShapes.pillCorners,
              borderSide: BorderSide.none),
          enabledBorder: const OutlineInputBorder(
              borderRadius: MoshShapes.pillCorners,
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: MoshShapes.pillCorners,
              borderSide:
                  BorderSide(color: colors.focusRing, width: MoshBorder.thick)),
          prefixIcon: const Padding(
            padding: EdgeInsetsDirectional.only(
                start: MoshSpace.s3, end: MoshSpace.s2),
            child: Icon(MoshIcons.search, size: MoshSpace.s5),
          ),
          suffixIcon: _suffix(context),
        ),
      ),
    );
  }

  Widget? _suffix(BuildContext context) {
    if (controller.text.isNotEmpty) {
      if (!clearable) return null;
      return IconButton(
        tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
        icon: const Icon(MoshIcons.close),
        onPressed: () {
          controller.clear();
          onChanged('');
        },
      );
    }
    final keys = shortcut;
    if (keys == null) return null;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: MoshSpace.s3),
      child: Center(widthFactor: 1, child: _Keycap(keys)),
    );
  }
}

/// A key of the keyboard, as the hint of a shortcut.
class _Keycap extends StatelessWidget {
  const _Keycap(this.keys);

  final String keys;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: MoshSpace.s1),
        decoration: BoxDecoration(
          borderRadius:
              const BorderRadius.all(Radius.circular(MoshRadius.extraSmall)),
          border: Border.all(color: MoshColors.of(context).outlineVariant),
        ),
        child: Text(keys, style: Theme.of(context).textTheme.labelSmall),
      );
}
