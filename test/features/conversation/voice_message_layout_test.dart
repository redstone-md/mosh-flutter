import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/src/features/conversation/voice_message_card.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/rust/conversation/attachments.dart';

import '../../support/pump.dart';

Future<void> _pumpVoice(WidgetTester tester,
        {double width = 280,
        TargetPlatform platform = TargetPlatform.windows}) =>
    pumpScreen(
      tester,
      Theme(
        data: buildMoshTheme(MoshColors.dark, platform),
        child: Scaffold(
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
      ),
    );

void main() {
  for (final (platform, side) in [
    (TargetPlatform.windows, 40.0),
    (TargetPlatform.android, 48.0),
  ]) {
    testWidgets(
        'voice play glyph is centered in its ${side.toInt()} px target on '
        '${platform.name}', (tester) async {
      await _pumpVoice(tester, platform: platform);
      final icon = find.byIcon(MoshIcons.play);
      final target =
          find.ancestor(of: icon, matching: find.byType(InkWell)).first;
      expect(tester.getCenter(icon), tester.getCenter(target));
      expect(tester.getSize(target), Size.square(side));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('voice waveform fits a narrow message and seeks across its width',
      (tester) async {
    await _pumpVoice(tester, width: 224);
    expect(tester.takeException(), isNull);
    final card = tester.getRect(find.byType(VoiceMessageCard));
    final time = tester.getRect(find.byType(VoiceCardTimeLabel));
    final wave = tester.getRect(find.byType(VoiceWaveform));
    expect(time.right, lessThanOrEqualTo(card.right));
    expect(wave.bottom, lessThan(time.top));
    expect(wave.width, greaterThan(0));
    await tester.tapAt(Offset(wave.right - 1, wave.center.dy));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
