import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/conversation/voice_message_card.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/rust/conversation/attachments.dart';

import '../../support/pump.dart';

Future<void> _pumpVoice(WidgetTester tester, {double width = 280}) =>
    pumpScreen(
      tester,
      Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: VoiceMessageCard(
              descriptor: AttachmentDescriptor(
                attachmentId: 'voice-layout',
                contentHash: 'voice-hash',
                fileName: 'voice.m4a',
                mime: 'audio/mp4',
                totalSize: BigInt.from(4096),
                voice: VoiceMeta(durationMs: 4200, peaksB64: ''),
              ),
              view: null,
              busy: false,
              onDownload: (_) {},
              playLabel: 'Play',
              pauseLabel: 'Pause',
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('voice play glyph is centered in its hit target', (tester) async {
    await _pumpVoice(tester);
    final icon = find.byIcon(Icons.play_arrow_rounded);
    final target =
        find.ancestor(of: icon, matching: find.byType(InkWell)).first;
    expect(tester.getCenter(icon), tester.getCenter(target));
    expect(tester.getSize(target), const Size.square(40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('voice waveform fits a narrow message and seeks across its width',
      (tester) async {
    await _pumpVoice(tester, width: 224);
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(VoiceMessageCard));
    final time = tester.getRect(find.byType(VoiceCardTimeLabel));
    final wave = tester.getRect(find.byType(VoiceWaveform));
    expect(time.right, lessThanOrEqualTo(card.right));
    expect(wave.right, lessThan(time.left));
    expect(wave.width, greaterThan(0));
    await tester.tapAt(Offset(wave.right - 1, wave.center.dy));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
