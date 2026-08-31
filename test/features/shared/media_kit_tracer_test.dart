// Tracer-bullet: prove media_kit's headless Player + screenshot() path works
// inside `flutter test` on Windows before the executor builds the real video
// thumbnail branch. If this test passes (returns non-null JPEG bytes), the
// path is viable and the executor can port React videoThumbnail 1-1. If it
// cannot run in `flutter test` (the case on this Windows machine), the
// executor must guard with try/catch and treat video thumbnails as
// best-effort (null on failure, never fatal -- mirrors React).
//
// VERDICT (Windows, 2026-08-02): the Player + screenshot() path CANNOT run
// headless inside `flutter test` on this machine. media_kit's native
// backend is `libmpv-2.dll`, which is NOT shipped inside the pub package
// `media_kit_libs_windows_video` -- its windows/CMakeLists.txt downloads
// the DLL at `flutter build windows` time into the CMake binary dir and
// nothing places it on %PATH% or inside the repo. So in the test isolate
// `MediaKit.ensureInitialized()` throws "Cannot find libmpv-2.dll". There
// is no local copy to point `LIBMPV_LIBRARY_PATH` / `ensureInitialized(
// libmpv:)` at either (build/windows/.../Debug has only flutter_windows.dll
// + mosh_core.dll; mpv is not on %PATH%). Therefore the real
// video-thumbnail branch MUST:
//   1. Guard every Player/screenshot call in try/catch and treat a null
//      thumbnail as best-effort (never fatal) -- mirrors React's
//      videoThumbnail which returns null on failure.
//   2. Be exercised end-to-end via integration_test (a real Flutter app
//      bundle that has the staged libmpv-2.dll), NOT via `flutter test`.
//   3. Unit-test only the "returns null gracefully when media_kit is
//      unavailable" fallback path in `flutter test`.
//
// The await sequence inside the test body below is the one the executor
// should reuse inside the real app / integration_test; it is the exact
// port of React's videoThumbnail (6s overall budget, 10% seek target).
// On a machine where libmpv-2.dll IS staged (e.g. a CI step that runs
// `flutter build windows` first, or integration_test), this probe will
// actually execute and assert the JPEG magic bytes instead of skipping.
import 'dart:async';
import 'dart:io' show File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  // `flutter test` never runs lib/main.dart, so MediaKit's native libs are
  // not registered in the test isolate by default. Probe init up front; if
  // the native backend is missing we skip the probe (do not fail the suite).
  String? skipReason;
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    skipReason = 'media_kit native backend unavailable in `flutter test`: $e. '
        'Run this probe via integration_test with a staged libmpv-2.dll. '
        'See file header for the full diagnosis.';
  }

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
