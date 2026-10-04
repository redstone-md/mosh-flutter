import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps Tab traversal inside a modal; Flutter owns and disposes its scope.
class ModalFocusTrap extends StatelessWidget {
  const ModalFocusTrap({
    super.key,
    required this.child,
    this.onEscape,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback? onEscape;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
        bindings: {
          if (onEscape case final callback?)
            const _EscapeKeyDownActivator(): callback,
        },
        // FocusScopeNode defaults to closedLoop traversal.
        child: FocusScope(
          autofocus: autofocus,
          child: FocusTraversalGroup(
            policy: ReadingOrderTraversalPolicy(),
            child: child,
          ),
        ),
      );
}

/// Escape cancels once per press, including when modifier keys are held.
class _EscapeKeyDownActivator extends ShortcutActivator {
  const _EscapeKeyDownActivator();

  @override
  Iterable<LogicalKeyboardKey> get triggers =>
      const [LogicalKeyboardKey.escape];

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) =>
      event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape;

  @override
  String debugDescribeKeys() => 'Escape';
}
