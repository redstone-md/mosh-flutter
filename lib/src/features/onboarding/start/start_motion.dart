import 'package:flutter/animation.dart';

/// Start menu motion, tuned to transitions.dev's texts reveal (18), page
/// side-by-side (08), card hover tilt (19) and learn-more hover (24)
/// recipes. Every value here is off under reduced motion.
abstract final class StartMotion {
  /// Smooth ease out, shared by every move.
  static const ease = Cubic(0.22, 1, 0.36, 1);

  /// Texts reveal: lines rise into place, unblurring, one after another.
  static const reveal = Duration(milliseconds: 500);
  static const revealRise = 12.0;
  static const revealBlur = 3.0;

  /// Lines of copy follow each other closely; the few large cards use the
  /// longer offset, keeping the whole cascade under ~300ms.
  static const lineStagger = Duration(milliseconds: 40);
  static const cardStagger = Duration(milliseconds: 80);

  /// Page side-by-side: the menu leaves left, a step arrives from the
  /// right, and back again.
  static const page = Duration(milliseconds: 250);
  static const pageShift = 8.0;
  static const pageBlur = 3.0;

  /// Card hover tilt: a subtle lean toward the pointer that follows
  /// quickly and settles slowly, with a soft glare under the cursor.
  static const tiltMax = 6.0;
  static const tiltFollow = Duration(milliseconds: 400);
  static const tiltReturn = Duration(milliseconds: 1000);
  static const glareOpacity = 0.07;
  static const glareFade = Duration(milliseconds: 300);

  /// Learn-more hover: the card's arrow nudges forward.
  static const arrowShift = 2.0;
  static const arrow = Duration(milliseconds: 350);

  /// The hero illustration drifts this far after the pointer.
  static const parallax = 6.0;
}
