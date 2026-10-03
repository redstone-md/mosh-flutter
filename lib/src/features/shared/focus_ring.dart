import 'package:flutter/material.dart';

import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;

class FocusRing extends StatelessWidget {
  const FocusRing({super.key, required this.radius, required this.child});

  /// Match the control's own radius so the ring follows its shape.
  final BorderRadius radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Focus.maybeOf registers a dependency, so focus changes rebuild this.
    final node = Focus.maybeOf(context);
    final focused = (node?.hasPrimaryFocus ?? false) &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: radius,
        border:
            focused ? Border.all(color: MoshColors.focusRing, width: 2) : null,
      ),
      child: child,
    );
  }
}
