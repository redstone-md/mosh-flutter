import 'package:flutter/animation.dart';

/// Corner radii of Foundations: the `radius/*` variables of the
/// "Mosh Dimensions" collection in Figma, the Material 3 corner scale.
abstract final class MoshRadius {
  static const none = 0.0;
  static const extraSmall = 4.0;
  static const small = 8.0;
  static const medium = 12.0;
  static const large = 16.0;
  static const largeIncreased = 20.0;
  static const extraLarge = 28.0;
  static const extraLargeIncreased = 32.0;
  static const extraExtraLarge = 48.0;
  static const full = 9999.0;
}

/// Spacing steps of Foundations: `space/<n>` is [MoshSpace] `s<n>`, n × 4px.
abstract final class MoshSpace {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s10 = 40.0;
  static const s12 = 48.0;
  static const s16 = 64.0;
}

/// One `motion/*` token: how long a transition runs and along which curve.
typedef MoshMotionSpec = ({Duration duration, Curve curve});

/// Motion of Foundations (`motion/*`), the Material 3 Expressive scheme.
/// Spatial tokens move and resize things and overshoot slightly; effects
/// tokens fade and recolour and never overshoot.
abstract final class MoshMotion {
  static const MoshMotionSpec spatialFast = (
    duration: Duration(milliseconds: 350),
    curve: Cubic(0.42, 1.67, 0.21, 0.90),
  );
  static const MoshMotionSpec spatialDefault = (
    duration: Duration(milliseconds: 500),
    curve: Cubic(0.38, 1.21, 0.22, 1.00),
  );
  static const MoshMotionSpec spatialSlow = (
    duration: Duration(milliseconds: 650),
    curve: Cubic(0.39, 1.29, 0.35, 0.98),
  );
  static const MoshMotionSpec effectsFast = (
    duration: Duration(milliseconds: 150),
    curve: Cubic(0.31, 0.94, 0.34, 1.00),
  );
  static const MoshMotionSpec effectsDefault = (
    duration: Duration(milliseconds: 200),
    curve: Cubic(0.34, 0.80, 0.34, 1.00),
  );
  static const MoshMotionSpec effectsSlow = (
    duration: Duration(milliseconds: 300),
    curve: Cubic(0.34, 0.88, 0.34, 1.00),
  );
}
