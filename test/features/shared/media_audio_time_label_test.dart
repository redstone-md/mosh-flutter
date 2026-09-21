// The audio viewer's position/duration label.
//
// Audit (2026-09-21) MEDIUM: the live "m:ss / m:ss" label rendered with
// proportional digits inside its fixed 80px box, so the text reflowed on
// every position tick. `MediaAudioTimeLabel` is the extracted label; this
// pins its text and its tabular figures.
//
// Limitation: the label is pumped directly. The full audio stage needs the
// media_kit native library, absent in test envs (the viewer renders its
// placeholder there), so the wiring inside _AudioStage is one line.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/media_viewer.dart';

void main() {
  Future<void> pumpLabel(WidgetTester tester, Duration position) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: MediaAudioTimeLabel(
              position: position,
              duration: const Duration(minutes: 1, seconds: 5),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('renders m:ss / m:ss with tabular figures', (tester) async {
    await pumpLabel(tester, const Duration(seconds: 42));

    final text = tester.widget<Text>(find.text('0:42 / 1:05'));
    expect(text.style!.fontFeatures, contains(FontFeature.tabularFigures()));
  });

  testWidgets('zero position renders as 0:00', (tester) async {
    await pumpLabel(tester, Duration.zero);

    expect(find.text('0:00 / 1:05'), findsOneWidget);
  });

  testWidgets('long durations stay on one line inside the 80px slot',
      (tester) async {
    // 2h13 / 2h15: "133:00 / 135:00" is wider than the fixed 80px slot; the
    // label must scale down instead of wrapping and changing the controls
    // row height (CodeAnt #12 comment on media_viewer.dart).
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 80,
              child: MediaAudioTimeLabel(
                position: const Duration(hours: 2, minutes: 13),
                duration: const Duration(hours: 2, minutes: 15),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('133:00 / 135:00'), findsOneWidget);
    final rect = tester.getRect(find.text('133:00 / 135:00'));
    expect(rect.height, lessThan(24));
  });
}
