library;

import 'package:flutter/material.dart';

/// Contextual icon switcher that cross-fades and subtly scales when an icon
/// changes state (e.g. play <-> pause, mic <-> mic_off), avoiding abrupt pops.
class ContextualIconSwitcher extends StatelessWidget {
  const ContextualIconSwitcher({
    super.key,
    required this.icon,
    this.size,
    this.color,
    this.duration = const Duration(milliseconds: 160),
    this.offset = Offset.zero,
  });

  final IconData icon;
  final double? size;
  final Color? color;
  final Duration duration;
  final Offset offset;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1.0).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
      child: Transform.translate(
        key: ValueKey<IconData>(icon),
        offset: offset,
        child: Icon(icon, size: size, color: color),
      ),
    );
  }
}
