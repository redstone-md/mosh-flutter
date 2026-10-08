import 'package:flutter/animation.dart';

/// Start menu motion: transitions.dev's texts reveal (18), a fade-through
/// between pages and a quiet row hover. Every value here is off under
/// reduced motion.
abstract final class StartMotion {
  /// Smooth ease out, shared by every move.
  static const ease = Cubic(0.22, 1, 0.36, 1);

  /// Texts reveal: lines rise into place, unblurring, one after another.
  static const reveal = Duration(milliseconds: 500);
  static const revealRise = 12.0;
  static const revealBlur = 3.0;

  /// Lines of copy, then the list, follow each other closely.
  static const lineStagger = Duration(milliseconds: 40);

  /// Page fade-through: the menu fades out toward the left, then a step
  /// fades in from the right, and back again.
  static const page = Duration(milliseconds: 250);
  static const pageShift = 8.0;

  /// A row lifts a step on hover and its chevron edges forward.
  static const hover = Duration(milliseconds: 140);
}
