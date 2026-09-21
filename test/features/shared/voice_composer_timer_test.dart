// The voice composer's live m:ss timers.
//
// Audit (2026-09-21) MEDIUM: the record elapsed timer and the preview
// duration timer rendered with proportional digits, so the recording row
// (discard/stop buttons after the timer) shifted horizontally on every
// 200ms tick. Both timers now share [kVoiceTimerStyle] with tabular figures
// (the call overlay's timer already did).
//
// Limitation: this is a style-token test. Driving the real recording or
// preview row needs the platform microphone/recorder, which does not exist
// in widget tests (the composer surfaces the error through onError instead),
// so the pumpable path cannot reach these two Texts here.
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/shared/voice_composer.dart';

void main() {
  testWidgets('the shared timer style carries tabular figures',
      (tester) async {
    expect(
      kVoiceTimerStyle.fontFeatures,
      contains(FontFeature.tabularFigures()),
    );
  });
}
