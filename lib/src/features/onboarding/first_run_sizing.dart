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

  bool get stacked {
    final available = viewport.width - outerPadding * 2;
    final cardWidth = available.clamp(0.0, 1160.0);
    return cardWidth - cardPadding * 2 < 740 * textScale;
  }

  double get cardMaxWidth => stacked ? 640 : 1160;
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
