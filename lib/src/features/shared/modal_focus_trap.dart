// Shared ModalFocusTrap -- focus trap wrapper for in-app modals.
// Intercepts Tab and Shift+Tab key events to cycle focus among descendants.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A reusable focus trap wrapper for in-app modals.
/// Intercepts Tab and Shift+Tab to cycle focus among descendants.
class ModalFocusTrap extends StatefulWidget {
  const ModalFocusTrap({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<ModalFocusTrap> createState() => _ModalFocusTrapState();
}

class _ModalFocusTrapState extends State<ModalFocusTrap> {
  late final FocusNode _trapFocusNode = FocusNode(
    debugLabel: kTrapFocusNodeDebugLabel,
    canRequestFocus: false,
  );

  static const String kTrapFocusNodeDebugLabel = 'ModalFocusTrap';

  @override
  void dispose() {
    _trapFocusNode.dispose();
    super.dispose();
  }

  void _handleTab(BuildContext context, {required bool isShift}) {
    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus == null) return;

    // Only trap focus if the currently focused node is inside our subtree.
    if (!primaryFocus.ancestors.contains(_trapFocusNode)) {
      return;
    }

    final policy = FocusTraversalGroup.of(context);
    if (isShift) {
      // Try to focus the previous element. If at the beginning, wrap to the last.
      final bool moved = policy.previous(primaryFocus);
      if (!moved) {
        policy
            .findLastFocus(primaryFocus, ignoreCurrentFocus: true)
            .requestFocus();
      }
    } else {
      // Try to focus the next element. If at the end, wrap to the first.
      final bool moved = policy.next(primaryFocus);
      if (!moved) {
        policy
            .findFirstFocus(primaryFocus, ignoreCurrentFocus: true)
            ?.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _trapFocusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.tab) {
          final isShift = HardwareKeyboard.instance.isShiftPressed;
          _handleTab(context, isShift: isShift);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: widget.child,
      ),
    );
  }
}
