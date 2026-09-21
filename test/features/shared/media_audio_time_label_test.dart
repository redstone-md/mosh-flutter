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
import 'dart:ui' show FontFeature;

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
}
