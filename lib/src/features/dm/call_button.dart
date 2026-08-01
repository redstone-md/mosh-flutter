// CallButton -- the shared 48x48 round call action button, 1-в-1 with
// React's `.call-btn` (voice-call/call-modal CSS). White icon (20px) on a
// colored circular background; Material `Icons.phone` / `Icons.phone_disabled`
// / `Icons.mic` / `Icons.mic_off` are the closest filled glyphs to tabler's
// IconPhone / IconPhoneOff / IconMicrophone(Off). Shared by the
// incoming/outgoing/active-call modals so the three call surfaces render
// the same affordance (DRY -- avoids three private copies of the button).

library;

import 'package:flutter/material.dart';

/// A 48x48 round call action button -- 1-в-1 with React's `.call-btn`.
class CallButton extends StatelessWidget {
  const CallButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.iconSize = 20,
  });

  /// The tabler-equivalent icon (Icons.phone / Icons.phone_disabled /
  /// Icons.mic / Icons.mic_off).
  final IconData icon;

  /// aria-label / tooltip (React `aria-label`).
  final String tooltip;

  /// The button background (React `call-btn-accept` #2ea043,
  /// `call-btn-decline` #e5484d, `call-btn-muted` #4f8cff).
  final Color color;

  /// The press handler.
  final VoidCallback onPressed;

  /// Icon size; React uses 20 for the modal buttons and 18 for the
  /// active-call overlay buttons -- default 20 matches the modals.
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
