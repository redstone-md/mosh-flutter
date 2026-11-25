// A voice recording in the composer, as Telegram's locked recording: the
// microphone turns the row into the clock with Cancel, pause and send; a
// paused recording can be listened to, continued, sent or deleted.
//
// Driven through the real `record` plugin seam (VoiceRecorderProbe). No
// `pumpAndSettle` while a recording is live: its clock is periodic.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/app/mosh_theme.dart' show MoshColors;
import 'package:mosh/src/features/shared/voice_composer.dart';
import 'package:mosh/src/features/shared/voice_waveform.dart';

import '../../support/voice_recorder.dart';

Future<void> _press(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await pumpVoiceFrames(tester);
}

/// Starts a recording and lets it run for [length].
Future<void> _record(WidgetTester tester, Duration length) async {
  await tester.tap(find.byTooltip('Record'));
  await tester.pump();
  await tester.pump(length);
}

void main() {
  testWidgets('the microphone turns the row into the running recording',
      (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    await pumpVoiceComposer(tester);

    await _record(tester, const Duration(seconds: 2));
    await pumpVoiceFrames(tester);

    expect(recorder.started.single, endsWith('.m4a'));
    expect(tester.widget<Text>(find.text('0:02')).style!.fontFeatures,
        contains(const FontFeature.tabularFigures()));
    final dot = tester.widget<Container>(find.descendant(
        of: find.byType(VoiceRecordingDot), matching: find.byType(Container)));
    expect((dot.decoration! as BoxDecoration).color, MoshColors.dark.error);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.byTooltip('Pause'), findsOneWidget);
    expect(find.byTooltip('Send voice'), findsOneWidget);
    expect(find.byTooltip('Record'), findsNothing);
  });

  testWidgets('Cancel throws the recording away', (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    final sent = <VoiceSend>[];
    await pumpVoiceComposer(tester, sent: sent);
    await _record(tester, const Duration(seconds: 1));

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Record'), findsOneWidget);
    expect(recorder.recording, isFalse);
    expect(File(recorder.started.single).existsSync(), isFalse);
    expect(sent, isEmpty);
  });

  testWidgets('send hands over what was recorded so far', (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    final sent = <VoiceSend>[];
    await pumpVoiceComposer(tester, sent: sent);
    await _record(tester, const Duration(seconds: 3));

    await tester.tap(find.byTooltip('Send voice'));
    await tester.pumpAndSettle();

    expect(sent.single.path, recorder.started.single);
    expect(sent.single.mime, 'audio/mp4');
    expect(sent.single.durationMs, 3000);
    expect(File(sent.single.path).existsSync(), isTrue);
    expect(find.byTooltip('Record'), findsOneWidget);
  });

  testWidgets('pause stops the clock and offers the recording to listen to',
      (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    await pumpVoiceComposer(tester);
    await _record(tester, const Duration(seconds: 2));

    await _press(tester, 'Pause');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(recorder.recording, isFalse);
    expect(find.text('0:02'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(find.byTooltip('Resume'), findsOneWidget);
    expect(find.byTooltip('Discard'), findsOneWidget);
    expect(find.byTooltip('Send voice'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('a composer that goes away mid-recording leaves no file',
      (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    await pumpVoiceComposer(tester);
    await _record(tester, const Duration(seconds: 1));

    await tester.pumpWidget(const SizedBox());

    expect(File(recorder.started.single).existsSync(), isFalse);
  });

  testWidgets('a paused recording can be deleted', (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    final sent = <VoiceSend>[];
    await pumpVoiceComposer(tester, sent: sent);
    await _record(tester, const Duration(seconds: 1));
    await _press(tester, 'Pause');

    await tester.tap(find.byTooltip('Discard'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Record'), findsOneWidget);
    expect(File(recorder.started.single).existsSync(), isFalse);
    expect(sent, isEmpty);
  });

  testWidgets('a continued recording goes on and is sent as one clip',
      (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    final join = VoiceJoinProbe();
    final sent = <VoiceSend>[];
    await pumpVoiceComposer(tester, sent: sent, join: join.call);
    await _record(tester, const Duration(seconds: 2));
    await _press(tester, 'Pause');
    await tester.pump(const Duration(seconds: 30));

    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await pumpVoiceFrames(tester);

    expect(recorder.recording, isTrue);
    expect(find.text('0:05'), findsOneWidget, reason: 'the pause is left out');
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Send voice'));
    await tester.pumpAndSettle();

    expect(recorder.started, hasLength(2));
    expect(join.joined.single, recorder.started);
    expect(sent.single.path, join.outputs.single);
    expect(sent.single.durationMs, inInclusiveRange(5000, 5400));
    expect(File(sent.single.path).existsSync(), isTrue);
    expect(recorder.started.map((piece) => File(piece).existsSync()),
        everyElement(isFalse),
        reason: 'the pieces are gone once they are one clip');
  });

  testWidgets('a piece that cannot be joined is told and what was paused stays',
      (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    final errors = <String>[];
    final sent = <VoiceSend>[];
    await pumpVoiceComposer(tester,
        errors: errors,
        sent: sent,
        join: ({required segments, required output}) =>
            throw StateError('no muxer'));
    await _record(tester, const Duration(seconds: 2));
    await _press(tester, 'Pause');
    await tester.tap(find.byTooltip('Resume'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byTooltip('Pause'));
    await tester.pumpAndSettle();

    expect(errors.single, contains('no muxer'));
    expect(find.text('0:02'), findsOneWidget);
    expect(File(recorder.started.last).existsSync(), isFalse);

    await tester.tap(find.byTooltip('Send voice'));
    await tester.pumpAndSettle();
    expect(sent.single.path, recorder.started.first);
    expect(sent.single.durationMs, 2000);
  });

  testWidgets('the longest recording pauses itself', (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    await pumpVoiceComposer(tester);

    await _record(tester, maxRecording);
    await tester.pumpAndSettle();

    expect(recorder.recording, isFalse);
    expect(find.text('5:00'), findsOneWidget);
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(
        tester
            .widget<IconButton>(find.ancestor(
                of: find.byTooltip('Resume'),
                matching: find.byType(IconButton)))
            .onPressed,
        isNull,
        reason: 'the limit leaves no room to go on');
  });

  // Regression: the peaks were bucketed against the five-minute maximum, so
  // a short message drew its whole waveform as one bar.
  testWidgets('the waveform of a short recording covers its whole length',
      (tester) async {
    VoiceRecorderProbe(tester).level = -6;
    final sent = <VoiceSend>[];
    await pumpVoiceComposer(tester, sent: sent);
    await _record(tester, const Duration(seconds: 4));

    await tester.tap(find.byTooltip('Send voice'));
    await tester.pumpAndSettle();

    final peaks = base64Decode(sent.single.peaksBase64);
    expect(peaks, hasLength(waveformBuckets));
    expect(peaks, everyElement(greaterThan(0)));
  });

  testWidgets('a press on a paused recording plays it, another pauses it',
      (tester) async {
    final recorder = VoiceRecorderProbe(tester);
    final playback = _ClipPlayback();
    await pumpVoiceComposer(tester,
        createPlayer: () => Player(platformPlayer: playback));
    await _record(tester, const Duration(seconds: 2));
    await _press(tester, 'Pause');

    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();
    expect(playback.opened, [recorder.started.single]);
    expect(find.byTooltip('Pause playback'), findsOneWidget);
    expect(
        tester.widget<VoiceWaveform>(find.byType(VoiceWaveform)).progress, 0.5);

    await tester.tap(find.byTooltip('Pause playback'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Play'), findsOneWidget);
    expect(playback.opened, hasLength(1));
  });

  // Regression (CodeAnt PR #154): a preview that failed to play was dropped
  // with its player still allocated.
  testWidgets('a recording that cannot be played lets go of its player',
      (tester) async {
    VoiceRecorderProbe(tester);
    final playback = _RefusingPlayback();
    await pumpVoiceComposer(tester,
        createPlayer: () => Player(platformPlayer: playback));
    await _record(tester, const Duration(seconds: 1));
    await _press(tester, 'Pause');

    await tester.tap(find.byTooltip('Play'));
    await tester.pumpAndSettle();

    expect(playback.disposed, isTrue);
    expect(find.byTooltip('Play'), findsOneWidget);
  });
}

/// Plays what it is handed and stands halfway through a two-second clip.
class _ClipPlayback extends PlatformPlayer {
  _ClipPlayback() : super(configuration: const PlayerConfiguration());

  final opened = <String>[];

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((playable as Media).uri);
    positionController.add(const Duration(seconds: 1));
    _playing(true);
  }

  @override
  Future<void> playOrPause() async => _playing(!state.playing);

  void _playing(bool playing) {
    state = state.copyWith(playing: playing);
    playingController.add(playing);
  }
}

class _RefusingPlayback extends PlatformPlayer {
  _RefusingPlayback() : super(configuration: const PlayerConfiguration());

  bool disposed = false;

  @override
  Future<void> open(Playable playable, {bool play = true}) =>
      throw StateError('no decoder');

  @override
  Future<void> dispose() {
    disposed = true;
    return super.dispose();
  }
}
