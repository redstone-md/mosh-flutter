import 'dart:io' show Directory, File;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:media_kit/media_kit.dart';

import 'media_player.dart' show playsThroughSystem;

/// Takes one frame of a video as an encoded image; null when it has none.
typedef TakeVideoFrame = Future<Uint8List?> Function(Uint8List video);

/// A frame from about a tenth into [video], taken the platform's way: by
/// the system's decoder where media plays through the system, by a
/// headless libmpv player elsewhere. Best-effort, never fatal.
Future<Uint8List?> takeVideoFrame(Uint8List video) =>
    playsThroughSystem ? systemVideoFrame(video) : playerVideoFrame(video);

const _systemFrames = MethodChannel('mosh/video-frame');

/// A frame of [video] from Android's own decoder, as a JPEG. The decoder
/// reads a file, so the video stays in the app's cache for the call.
Future<Uint8List?> systemVideoFrame(Uint8List video) async {
  try {
    final directory = await Directory.systemTemp.createTemp('mosh-frame');
    try {
      final file = File('${directory.path}/video');
      await file.writeAsBytes(video);
      return await _systemFrames.invokeMethod<Uint8List>('take', file.path);
    } finally {
      await directory.delete(recursive: true);
    }
  } on Exception {
    // No decoder for this video, or no room for the file.
    return null;
  }
}

/// A frame of [video] from a headless libmpv player, as a JPEG. Null where
/// libmpv is unavailable or gives no frame.
Future<Uint8List?> playerVideoFrame(Uint8List video) async {
  Player? player;
  try {
    // The video output stays the default 'null': the player is headless.
    player = Player(configuration: const PlayerConfiguration(muted: true));
    // media_kit otherwise decodes no video until a VideoController attaches.
    await player.setVideoTrack(VideoTrack.auto());
    await player.open(await Media.memory(video), play: false);
    await _seekTenthIn(player);
    // Let the frame render before the screenshot.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    // No frame may be decoded yet: one more try.
    return await player.screenshot() ??
        await player
            .screenshot()
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
  } on Exception {
    return null;
  } finally {
    // The player owns a libmpv handle and an isolate.
    await player?.dispose();
  }
}

/// Seeks a tenth into the media, a second in at most, and waits until the
/// player is there: a seek returns when it is asked for, not when it lands.
Future<void> _seekTenthIn(Player player) async {
  const patience = Duration(seconds: 4);
  // A length that never comes still leaves a sane place to seek to.
  final length = player.state.duration > Duration.zero
      ? player.state.duration
      : await player.stream.duration
          .firstWhere((length) => length > Duration.zero)
          .timeout(patience, onTimeout: () => const Duration(seconds: 2));
  final target = Duration(
    milliseconds: (length.inMilliseconds * 0.1).round().clamp(0, 1000),
  );
  final there = player.stream.position
      .firstWhere(
        (position) => (position - target).inMilliseconds.abs() < 250,
        orElse: () => target,
      )
      .timeout(patience, onTimeout: () => target);
  await player.seek(target);
  await there;
}
