import 'package:flutter/widgets.dart';

/// Scale decorative space to the viewport; keep controls and text readable.
class SetupSizing {
  const SetupSizing(this.viewport, {this.textScale = 1});
  final Size viewport;
  final double textScale;

  bool get compact => viewport.height < 760 || viewport.width < 1000;
  double get outerPadding => compact ? 12 : 32;
  double get cardPadding => compact ? 16 : 32;
  double get sectionGap => compact ? 16 : 32;
  double get columnGap => compact ? 32 : 48;

  // Stacked steps add heading, artwork and controls vertically. Reserve more
  // room for their differing heights while keeping progress within the viewport.
  double get transitionReserve => sectionGap * (stacked ? 8 : 4);
  double get transitionBaselineLimit =>
      viewport.height -
      outerPadding * 2 -
      cardPadding * 2 -
      sectionGap -
      80 * textScale;

  bool get stacked {
    final available = viewport.width - outerPadding * 2 - cardPadding * 2;
    return available.clamp(0.0, 1160.0) < 740 * textScale;
  }

  double get contentMaxWidth => stacked ? 640 : 1160;
  bool get showIllustration => !stacked || viewport.height >= 600;

  double imageHeight({required bool stacked, required bool devices}) {
    final fraction = stacked ? .14 : .36;
    final maximum = devices
        ? 220.0
        : stacked
            ? 120.0
            : 340.0;
    return (viewport.height * fraction).clamp(80.0, maximum);
  }
}
