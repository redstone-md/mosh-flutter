import 'package:flutter/widgets.dart';

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

/// Sizes a control takes from the device it runs on.
abstract final class MoshControl {
  /// A phone is pressed with a finger: its controls and tap targets are
  /// 48 px, the desktop's 40 px.
  static bool touch(TargetPlatform platform) =>
      platform == TargetPlatform.android || platform == TargetPlatform.iOS;

  /// Height of a button, a field and a menu row.
  static double height(TargetPlatform platform) =>
      touch(platform) ? MoshSpace.s12 : MoshSpace.s10;
}

/// Stroke weights of Foundations: the `border/*` variables.
abstract final class MoshBorder {
  static const thin = 1.0;
  static const thick = 2.0;
}

/// Layer opacities of Foundations: the `state/*` variables, the Material 3
/// state layers. A control tints itself with its content colour at [hover],
/// [focus] or [pressed]; a disabled one fades its content to
/// [disabledContent] and swaps its fill for a [disabledContainer] plate.
abstract final class MoshState {
  static const hover = 0.08;
  static const focus = 0.10;
  static const pressed = 0.10;
  static const disabledContainer = 0.12;
  static const disabledContent = 0.38;
  static const scrim = 0.54;

  /// The state layer of a control whose content is [ink]: nothing at rest.
  static WidgetStateProperty<Color?> layer(Color ink) =>
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return tint(ink, pressed);
        if (states.contains(WidgetState.hovered)) return tint(ink, hover);
        if (states.contains(WidgetState.focused)) return tint(ink, focus);
        return null;
      });

  /// [ink] at one of the opacities above.
  static Color tint(Color ink, double opacity) =>
      ink.withValues(alpha: opacity);

  /// [enabled] at rest and [disabled] when the control is off.
  static WidgetStateProperty<T> unlessDisabled<T>(T enabled, T disabled) =>
      WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.disabled) ? disabled : enabled);
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
