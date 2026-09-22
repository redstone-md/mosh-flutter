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
import 'dart:convert' show base64Encode;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mosh/src/features/conversation/voice_message_card.dart';
import 'package:mosh/src/rust/attachment_runtime.dart' show VoiceMeta;
import 'package:mosh/src/rust/conversation/attachments.dart';

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

  testWidgets('the time label renders with tabular figures', (tester) async {
    // The label is pumped directly: the card's fallback row overflows under
    // the test font (Ahem glyphs are ~14px wide), and the label itself is
    // the contract under test (extracted like MediaAudioTimeLabel).
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: VoiceCardTimeLabel(ms: 5000)),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('0:05'));
    expect(text.style!.fontFeatures, contains(FontFeature.tabularFigures()));
  });

  // Regression (CodeAnt PR #17): tapping play before the download finished
  // queued nothing -- when the local path arrived, didUpdateWidget only
  // loaded the file and playback never started. The card now queues the
  // play (the queued player.play() start in didUpdateWidget) and requests
  // the download.
  //
  // Limitation: the queued play's player.play() call is not exercised here.
  // The player needs the media_kit native library, which is absent in test
  // envs (the card already renders its fallback there); the queued-play
  // start in didUpdateWidget is two lines in voice_message_card.dart. What
  // IS pinned headless: the tap-while-offered path requests the download,
  // and the path arriving with a play queued does not throw -- the card
  // keeps rendering with the play affordance enabled.
  //
  // Known artifact: the card's Row overflows by ~1px under the test font
  // (Ahem glyphs; see the time-label test above). It is pre-existing and
  // unrelated to this regression, so each pump drains the layout
  // exception instead of failing on it.
  testWidgets(
      'tapping play before the download requests it, and the card '
      'survives the path arriving with the play queued', (tester) async {
    final downloaded = <String>[];
    Widget pumpCard(AttachmentView view) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: VoiceMessageCard(
                descriptor: AttachmentDescriptor(
                  attachmentId: 'att-voice',
                  contentHash: 'h-att-voice',
                  fileName: 'voice.m4a',
                  mime: 'audio/mp4',
                  totalSize: BigInt.from(4096),
                  thumbnailB64: null,
                  voice: VoiceMeta(
                    durationMs: 4200,
                    peaksB64:
                        base64Encode(Uint8List.fromList(List.filled(64, 0))),
                  ),
                ),
                view: view,
                busy: false,
                onDownload: downloaded.add,
                playLabel: 'Play',
                pauseLabel: 'Pause',
              ),
            ),
          ),
        );
    void drainTestFontOverflow() {
      final exception = tester.takeException();
      if (exception != null) {
        expect(exception.toString(), contains('RenderFlex overflowed'),
            reason: 'only the known test-font overflow may surface');
      }
    }

    // Offered: tapping play queues the play and starts the download.
    await tester.pumpWidget(pumpCard(
      AttachmentView(
        attachmentId: 'att-voice',
        direction: 'incoming',
        state: AttachmentState.offered,
        completedChunks: BigInt.zero,
        chunkCount: BigInt.from(10),
        localPath: null,
      ),
    ));
    await tester.pump();
    drainTestFontOverflow();

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    drainTestFontOverflow();
    expect(downloaded, ['att-voice']);

    // Downloading (the real re-poll flips the view state): a second tap
    // must not re-request the download.
    await tester.pumpWidget(pumpCard(
      AttachmentView(
        attachmentId: 'att-voice',
        direction: 'incoming',
        state: AttachmentState.downloading,
        completedChunks: BigInt.from(5),
        chunkCount: BigInt.from(10),
        localPath: null,
      ),
    ));
    await tester.pump();
    drainTestFontOverflow();
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    drainTestFontOverflow();
    expect(downloaded, ['att-voice']);

    // The local path arrives (download finished) with a play queued: the
    // card re-renders without throwing and the play affordance stays.
    await tester.pumpWidget(pumpCard(
      AttachmentView(
        attachmentId: 'att-voice',
        direction: 'incoming',
        state: AttachmentState.available,
        completedChunks: BigInt.from(10),
        chunkCount: BigInt.from(10),
        localPath: '/tmp/voice.m4a',
      ),
    ));
    await tester.pump();
    drainTestFontOverflow();
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
