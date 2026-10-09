import 'package:mosh/src/features/shared/contextual_icon_switcher.dart';
import 'package:flutter/material.dart';

/// A 48x48 round call action button.
class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.iconSize = 20,
    this.foreground = Colors.white,
    this.toggled,
  });

  /// The icon (Icons.phone / Icons.phone_disabled / Icons.mic / Icons.mic_off).
  final IconData icon;
  final bool? toggled;

  /// The accessibility label / tooltip.
  final String tooltip;

  /// The button background color.
  final Color color;
  final Color foreground;

  /// The press handler.
  final VoidCallback? onPressed;

  /// Icon size; 20 for the modal buttons, 18 for the active-call overlay.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Semantics(
        toggled: toggled,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Material(
              color: color,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                icon: ContextualIconSwitcher(
                    icon: icon,
                    size: iconSize,
                    color: foreground,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 250)),
                onPressed: onPressed,
                splashRadius: 24,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ));
  }
}
