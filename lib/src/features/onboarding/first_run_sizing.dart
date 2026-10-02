import 'package:flutter/widgets.dart';

/// Scale decorative space to the viewport; keep controls and text readable.
class SetupSizing {
  const SetupSizing(this.viewport);
  final Size viewport;

  bool get compact => viewport.height < 760 || viewport.width < 1000;
  double get outerPadding => compact ? 12 : 32;
  double get cardPadding => compact ? 16 : 32;
  double get sectionGap => compact ? 16 : 32;
  double get columnGap => compact ? 32 : 48;

  double imageHeight({required bool stacked, required bool devices}) {
    final fraction = !stacked && !devices
        ? .36
        : viewport.width < 800
            ? .18
            : .24;
    final maximum = devices
        ? 220.0
        : stacked
            ? 180.0
            : 340.0;
    return (viewport.height * fraction).clamp(80.0, maximum);
  }
}
