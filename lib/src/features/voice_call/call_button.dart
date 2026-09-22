// CallButton -- the shared 48x48 round call action button: a white icon
// on a colored circular background. Shared by the incoming/outgoing/
// active-call surfaces so all three render the same affordance (DRY --
// avoids three private copies of the button).

library;

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
  });

  /// The icon (Icons.phone / Icons.phone_disabled / Icons.mic / Icons.mic_off).
  final IconData icon;

  /// The accessibility label / tooltip.
  final String tooltip;

  /// The button background color.
  final Color color;

  /// The press handler.
  final VoidCallback onPressed;

  /// Icon size; 20 for the modal buttons, 18 for the active-call overlay.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: color,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            icon: Icon(icon, size: iconSize, color: Colors.white),
            onPressed: onPressed,
            splashRadius: 24,
            padding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}
