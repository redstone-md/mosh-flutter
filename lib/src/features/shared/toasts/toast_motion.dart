import 'package:flutter/animation.dart';

/// Toast motion, tuned to transitions.dev's toast (22) and banner
/// stacking (32) recipes and its polish rules: opening runs on the slower
/// clock and closing on the faster one, overshoot belongs to entrances
/// only, and nothing waits before it leaves.
abstract final class ToastMotion {
  /// An arrival, a push back, and a stack settling after the pointer left.
  static const open = Duration(milliseconds: 350);

  /// A dismissal, an eviction and a swipe that flies off.
  static const close = Duration(milliseconds: 250);

  /// Hover in is quick and direct; the collapse uses [open].
  static const spread = Duration(milliseconds: 250);

  /// Smooth ease out, shared by every surface move.
  static const ease = Cubic(0.22, 1, 0.36, 1);

  /// Badge pop: the only overshoot, for a repeated toast.
  static const bump = Cubic(0.34, 1.36, 0.64, 1);
  static const bumpScale = 0.97;

  /// The toast recipe's travel. The stacking recipe rises 60px, which the
  /// polish rules call sluggish for anything smaller than a panel.
  static const rise = 16.0;
  static const blur = 2.0;
  static const scale = 0.97;

  /// Older toasts peek this far behind the newest and shrink, dim and
  /// soften per step back.
  static const peek = 12.0;
  static const depthScale = 0.06;
  static const depthFade = 0.4;
  static const depthBlur = [0.0, 1.0, 2.0];

  /// Room between toasts fanned out under the pointer.
  static const spreadGap = 8.0;

  /// A swipe this far toward the edge, or this fast, dismisses.
  static const swipeDistance = 36.0;
  static const swipeVelocity = 600.0;
}
