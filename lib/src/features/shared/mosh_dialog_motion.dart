import 'package:flutter/material.dart';

/// The selected transitions.dev modal values, shared by routes and overlays.
abstract final class MoshDialogMotion {
  static const openDuration = Duration(milliseconds: 250);
  static const closeDuration = Duration(milliseconds: 150);
  static const scale = .96;
  static const curve = Cubic(.22, 1, .36, 1);
}

/// Callers supply a curved animation so route and overlay lifetimes stay native.
class MoshDialogTransition extends AnimatedWidget {
  const MoshDialogTransition({
    super.key,
    required Animation<double> animation,
    required this.child,
  }) : super(listenable: animation);

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = listenable as Animation<double>;
    final closing = animation.status == AnimationStatus.reverse;
    return ExcludeFocus(
      excluding: closing,
      child: IgnorePointer(
        ignoring: closing,
        child: FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: MoshDialogMotion.scale, end: 1)
                .animate(animation),
            child: child,
          ),
        ),
      ),
    );
  }
}
