// The voice wave's seek contract.
//
// Audit (2026-09-21) HIGH: the card measured `context.findRenderObject()` of
// the whole CARD while the tap `localPosition.dx` was relative to the wave,
// so the ratio always undershot and a tap on the wave's right edge could
// never seek past ~60%. The wave now measures its OWN box, and this test
// pins that: a tap near the wave's right edge must report ~1.0 regardless of
// how wide the parent is.
//
// Limitation: the ratio -> player.seek mapping is not exercised here. The
// player needs the media_kit native library, which is absent in test envs
// (the card already renders its fallback there); the wired callback is one
// line in voice_message_card.dart.
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/voice_message_card.dart';

void main() {
  Future<double?> tapWaveAt(WidgetTester tester, Offset local) async {
    double? ratio;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: VoiceWaveform(
                peaks: Uint8List(64),
                progress: 0,
                played: Colors.green,
                unplayed: Colors.grey,
                onSeekRatio: (value) => ratio = value,
              ),
            ),
          ),
        ),
      ),
    );
    final rect = tester.getRect(find.byType(VoiceWaveform));
    await tester.tapAt(Offset(rect.left + local.dx, rect.top + local.dy));
    await tester.pump();
    return ratio;
  }

  testWidgets('a tap near the right edge seeks to ~1.0', (tester) async {
    // 168px wave inside a much wider window: the old card-wide measurement
    // turned this same tap into ~0.6.
    final ratio = await tapWaveAt(tester, const Offset(166, 18));

    expect(ratio, closeTo(1.0, 0.02));
  });

  testWidgets('a tap near the left edge seeks to ~0.0', (tester) async {
    final ratio = await tapWaveAt(tester, const Offset(1, 18));

    expect(ratio, closeTo(0.0, 0.02));
  });
}
