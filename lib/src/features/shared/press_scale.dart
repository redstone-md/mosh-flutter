library;

import 'package:flutter/material.dart';

/// Reusable tactile press-scale feedback.
///
/// Scales down to `0.96` on pointer down and recovers to `1.0` on pointer up
/// or cancel with a 100ms ease-out curve.
///
/// Uses [Listener] to observe raw pointer events without claiming gestures in
/// the gesture arena, allowing child [InkWell], [GestureDetector], or [Button]
/// widgets to handle clicks normally.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.targetScale = 0.96,
  });

  final Widget child;
  final bool enabled;
  final double targetScale;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.targetScale : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
