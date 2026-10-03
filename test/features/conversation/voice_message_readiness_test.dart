import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:mosh/src/features/conversation/voice_message_card.dart';
import 'package:mosh/src/rust/attachment_runtime.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';

import '../../support/conversation_cases.dart';
import '../../support/pump.dart';

AttachmentDescriptor _voice() => AttachmentDescriptor(
      attachmentId: 'voice',
      contentHash: 'hash',
      fileName: 'voice.m4a',
      mime: 'audio/mp4',
      totalSize: BigInt.from(1024),
      voice: const VoiceMeta(durationMs: 4200, peaksB64: ''),
    );

class _RecordingPlayback extends PlatformPlayer {
  _RecordingPlayback() : super(configuration: const PlayerConfiguration());

  final events = <String>[];
  bool failOpen = false;
  bool failPlay = false;
  Completer<void>? openGate;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    events.add('open');
    if (openGate case final gate?) await gate.future;
    if (failOpen) throw StateError('load failed');
    durationController.add(const Duration(milliseconds: 4200));
    if (play) await this.play();
  }

  @override
  Future<void> play() async {
    events.add('play');
    if (failPlay) throw StateError('play failed');
    playingController.add(true);
  }

  @override
  Future<void> playOrPause() => play();
}

Future<void> _pumpVoice(WidgetTester tester, Player player,
        {String? path, AttachmentState state = AttachmentState.offered}) =>
    pumpScreen(
        tester,
        Scaffold(
            body: VoiceMessageCard(
                descriptor: _voice(),
                view: testAttachmentView(
                    attachmentId: 'voice', state: state, localPath: path),
                busy: false,
                onDownload: (_) {},
                playLabel: 'Play',
                pauseLabel: 'Pause',
                createPlayer: () => player)));

void main() {
  testWidgets(
      'an empty local voice path requests download when play is pressed',
      (tester) async {
    final downloads = <String>[];
    await pumpScreen(
        tester,
        Scaffold(
            body: VoiceMessageCard(
                descriptor: _voice(),
                view: testAttachmentView(
                    attachmentId: 'voice',
                    state: AttachmentState.offered,
                    localPath: ''),
                busy: false,
                onDownload: downloads.add,
                playLabel: 'Play',
                pauseLabel: 'Pause')));

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    expect(downloads, ['voice']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'queued voice play waits for a successful load and retries failure',
      (tester) async {
    final playback = _RecordingPlayback()..failOpen = true;
    final player = Player(platformPlayer: playback);
    await _pumpVoice(tester, player);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    await _pumpVoice(tester, player,
        path: '/tmp/voice.m4a', state: AttachmentState.available);

    expect(playback.events, ['open']);
    playback.failOpen = false;
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    expect(playback.events, ['open', 'open', 'play']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing a voice card during loading does not start playback',
      (tester) async {
    final gate = Completer<void>();
    final playback = _RecordingPlayback()..openGate = gate;
    final player = Player(platformPlayer: playback);
    await _pumpVoice(tester, player);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await _pumpVoice(tester, player,
        path: '/tmp/voice.m4a', state: AttachmentState.available);

    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete();
    await tester.pump();

    expect(playback.events, ['open']);
    expect(tester.takeException(), isNull);
  });

  for (final terminal in [AttachmentState.failed, AttachmentState.cancelled]) {
    testWidgets('a $terminal transfer cancels voice play during loading',
        (tester) async {
      final gate = Completer<void>();
      final playback = _RecordingPlayback()..openGate = gate;
      final player = Player(platformPlayer: playback);
      await _pumpVoice(tester, player);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await tester.pump();
      await _pumpVoice(tester, player,
          path: '/tmp/voice.m4a', state: AttachmentState.available);

      await _pumpVoice(tester, player, path: '/tmp/voice.m4a', state: terminal);
      gate.complete();
      await tester.pumpAndSettle();
      expect(playback.events, ['open']);

      await _pumpVoice(tester, player,
          path: '/tmp/voice.m4a', state: AttachmentState.available);
      expect(playback.events, ['open', 'open']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('successful explicit voice play consumes a failed queued request',
      (tester) async {
    final playback = _RecordingPlayback()..failPlay = true;
    final player = Player(platformPlayer: playback);
    await _pumpVoice(tester, player);
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();
    await _pumpVoice(tester, player,
        path: '/tmp/first.m4a', state: AttachmentState.available);

    playback.failPlay = false;
    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pumpAndSettle();
    await _pumpVoice(tester, player,
        path: '/tmp/second.m4a', state: AttachmentState.available);

    expect(playback.events, ['open', 'play', 'play', 'open']);
    expect(tester.takeException(), isNull);
  });
}
