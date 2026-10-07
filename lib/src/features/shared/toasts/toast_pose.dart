import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/foundation.dart';

import 'toast_motion.dart';

/// Where a toast sits in its stack and how it reads: [dy] away from the
/// anchored edge, [height] of its body (null while unmeasured or natural),
/// and the scale, opacity and blur that push it back.
@immutable
class ToastPose {
  const ToastPose({
    this.dy = 0,
    this.scale = 1,
    this.opacity = 1,
    this.blur = 0,
    this.content = 1,
    this.height,
  });

  final double dy;
  final double scale;
  final double opacity;
  final double blur;

  /// The text's opacity: a toast folded behind shows only its edge.
  final double content;
  final double? height;

  static ToastPose lerp(ToastPose a, ToastPose b, double t) => ToastPose(
        dy: lerpDouble(a.dy, b.dy, t)!,
        scale: lerpDouble(a.scale, b.scale, t)!,
        opacity: lerpDouble(a.opacity, b.opacity, t)!.clamp(0, 1),
        blur: lerpDouble(a.blur, b.blur, t)!.clamp(0, double.infinity),
        content: lerpDouble(a.content, b.content, t)!.clamp(0, 1),
        // An unmeasured side takes the other at once.
        height: a.height == null || b.height == null
            ? b.height
            : lerpDouble(a.height, b.height, t),
      );

  ToastPose shifted(double by) => ToastPose(
      dy: dy + by,
      scale: scale,
      opacity: opacity,
      blur: blur,
      content: content,
      height: height);

  @override
  bool operator ==(Object other) =>
      other is ToastPose &&
      other.dy == dy &&
      other.scale == scale &&
      other.opacity == opacity &&
      other.blur == blur &&
      other.content == content &&
      other.height == height;

  @override
  int get hashCode => Object.hash(dy, scale, opacity, blur, content, height);
}

class ToastPoseTween extends Tween<ToastPose> {
  ToastPoseTween({super.begin, super.end});

  @override
  ToastPose lerp(double t) => ToastPose.lerp(begin!, end!, t);
}

/// The stack's geometry. [away] is +1 when the stack hangs from the top
/// edge and grows down, -1 when it sits on the bottom edge and grows up.
/// With [reduceMotion] every pose rests in place: no travel, no blur.
@immutable
class ToastLayout {
  const ToastLayout({required this.away, this.reduceMotion = false});

  final double away;
  final bool reduceMotion;

  /// Arrives from the edge, small and soft.
  ToastPose get entering => reduceMotion
      ? const ToastPose(opacity: 0)
      : ToastPose(
          dy: -away * ToastMotion.rise,
          scale: ToastMotion.scale,
          opacity: 0,
          blur: ToastMotion.blur);

  /// [depth] steps behind the newest toast, cut to the [front] height so
  /// only its edge peeks out.
  ToastPose collapsed(int depth, double? front, double? own) {
    if (depth == 0) return ToastPose(height: own);
    final fade = ToastMotion.depthFade * (depth == 1 ? 1 : 1.6);
    if (reduceMotion) {
      return ToastPose(opacity: 1 - fade, content: 0, height: front);
    }
    return ToastPose(
      dy: away * ToastMotion.peek * depth,
      scale: 1 - ToastMotion.depthScale * depth,
      opacity: 1 - fade,
      blur: ToastMotion.depthBlur[depth.clamp(0, 2)],
      content: 0,
      height: front,
    );
  }

  /// Fanned out under the pointer, [offset] below the newer toasts.
  ToastPose spread(double offset, double? own) =>
      ToastPose(dy: reduceMotion ? 0 : away * offset, height: own);

  /// Leaves from [from]: the newest returns to the edge it came from,
  /// older ones fall further back into the stack.
  ToastPose leaving(ToastPose from, {required bool toEdge}) {
    if (reduceMotion) {
      return ToastPose(opacity: 0, content: from.content, height: from.height);
    }
    if (toEdge) {
      return ToastPose(
          dy: from.dy - away * ToastMotion.rise,
          scale: ToastMotion.scale,
          opacity: 0,
          blur: ToastMotion.blur,
          content: from.content,
          height: from.height);
    }
    return ToastPose(
        dy: away * ToastMotion.peek * 3,
        scale: 1 - ToastMotion.depthScale * 3,
        opacity: 0,
        blur: ToastMotion.blur,
        content: from.content,
        height: from.height);
  }

  /// The edge the stack scales toward.
  Alignment get origin =>
      away > 0 ? Alignment.topCenter : Alignment.bottomCenter;
}
