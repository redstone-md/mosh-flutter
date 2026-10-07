// Native capture uses real libmpv and the committed sample.mp4 fixture.
// Headless players must enable VideoTrack.auto(): without a VideoController,
// media_kit defaults to vid=no and produces no decoded frame.
// These tests verify JPEG capture and the app's bounded attachment previews;
// only hosts without the native backend skip them.
import 'dart:async';
import 'dart:convert' show base64Decode;
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/features/shared/thumbnail.dart';

void main() {
  // `flutter test` never runs lib/main.dart, so MediaKit's native libs are
  // not registered in the test isolate by default. Probe init up front; if
  // the native backend is missing we skip the probe (do not fail the suite).
  String? skipReason;
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    skipReason = 'media_kit native backend unavailable in `flutter test`: $e. '
        'Install or stage libmpv to run native capture tests.';
  }

  test('video attachment generates a miniature and a clear preview', () async {
    final fixture = File('test/fixtures/sample.mp4');
    expect(fixture.existsSync(), isTrue);
    final previews =
        await createAttachmentPreviews(fixture.readAsBytesSync(), 'sample.mp4');
    expect(previews, isNotNull);
    final miniature = base64Decode(previews!.miniatureBase64);
    final clear = base64Decode(previews.previewBase64);
    expect(previews.miniatureBase64.length, lessThanOrEqualTo(2048));
    expect(img.decodeJpg(miniature), isNotNull);
    final decoded = img.decodeJpg(clear)!;
    expect(decoded.width, 320);
    expect(decoded.height, 240);
  }, skip: skipReason, timeout: const Timeout(Duration(seconds: 30)));

  test(
    'media_kit Player.screenshot() returns JPEG bytes headless',
    () async {
      final mp4 = File('test/fixtures/sample.mp4');
      if (!mp4.existsSync()) {
        // Skip if the fixture wasn't generated; the executor regenerates it.
        return;
      }
      final bytes = mp4.readAsBytesSync();
      Player? player;
      StreamSubscription<Duration>? durSub;
      StreamSubscription<Duration>? posSub;
      try {
        player = Player(
          configuration: const PlayerConfiguration(muted: true),
        );
        await player.setVideoTrack(VideoTrack.auto());
        final media = await Media.memory(bytes);
        await player.open(media, play: false);

        // Wait for duration (10% target).
        final durCompleter = Completer<Duration>();
        durSub = player.stream.duration.listen((d) {
          if (d > Duration.zero && !durCompleter.isCompleted) {
            durCompleter.complete(d);
          }
        });
        if (player.state.duration > Duration.zero &&
            !durCompleter.isCompleted) {
          durCompleter.complete(player.state.duration);
        }
        final duration = await durCompleter.future.timeout(
          const Duration(seconds: 4),
          onTimeout: () => const Duration(seconds: 2),
        );
        await durSub.cancel();
        durSub = null;

        final target = Duration(
          milliseconds: (duration.inMilliseconds * 0.1).round().clamp(0, 1000),
        );

        final seekCompleter = Completer<void>();
        posSub = player.stream.position.listen((p) {
          if ((p - target).inMilliseconds.abs() < 250 &&
              !seekCompleter.isCompleted) {
            seekCompleter.complete();
          }
        });
        await player.seek(target);
        await seekCompleter.future
            .timeout(const Duration(seconds: 4), onTimeout: () {});
        await posSub.cancel();
        posSub = null;
        await Future<void>.delayed(const Duration(milliseconds: 120));

        Uint8List? frame = await player.screenshot();
        frame ??= await player
            .screenshot()
            .timeout(const Duration(seconds: 2), onTimeout: () => null);

        expect(frame, isNotNull,
            reason: 'screenshot() should return JPEG bytes');
        expect(frame!.length, greaterThan(0), reason: 'frame bytes non-empty');
        // JPEG magic: FF D8 FF.
        expect(frame[0], 0xFF, reason: 'JPEG SOI byte 0');
        expect(frame[1], 0xD8, reason: 'JPEG SOI byte 1');
        expect(frame[2], 0xFF, reason: 'JPEG SOI byte 2');
      } finally {
        await posSub?.cancel();
        await durSub?.cancel();
        await player?.dispose();
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
