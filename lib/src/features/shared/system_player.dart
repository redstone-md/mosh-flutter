import 'dart:io' show File;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

import 'attachment_media_src.dart' show localFileSrc;

/// media_kit's player over the system's own: media3 on Android, reached
/// through video_player (ADR 0053). It plays what the app plays, one local
/// file or loopback stream at a time.
class SystemPlayer extends PlatformPlayer {
  SystemPlayer({this.video = false})
      : super(configuration: const PlayerConfiguration());

  /// Whether the media is watched. A video pauses while the app is in the
  /// background; sound plays on.
  final bool video;

  /// The open media, which a `VideoPlayer` shows; null while none is open.
  final opened = ValueNotifier<VideoPlayerController?>(null);

  // Only the latest open is kept: one that finishes after another open, or
  // after dispose, lets go of what it opened.
  int _opens = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final open = ++_opens;
    await _close();
    final controller = _controller(Uri.parse(localFileSrc(_source(playable))));
    try {
      await controller.initialize();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
    if (open != _opens) return controller.dispose();
    controller.addListener(_changed);
    opened.value = controller;
    _changed();
    if (play) await controller.play();
  }

  String _source(Playable playable) => switch (playable) {
        Media(:final uri) => uri,
        _ => throw UnsupportedError('The system player opens one media'),
      };

  VideoPlayerController _controller(Uri source) {
    final options = VideoPlayerOptions(allowBackgroundPlayback: !video);
    return source.isScheme('file')
        ? VideoPlayerController.file(File(source.toFilePath()),
            videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(source, videoPlayerOptions: options);
  }

  void _changed() => _report(opened.value!.value);

  static const _nothing = VideoPlayerValue.uninitialized();

  void _report(VideoPlayerValue media) {
    state = state.copyWith(
      playing: media.isPlaying,
      completed: media.isCompleted,
      position: media.position,
      duration: media.duration,
    );
    playingController.add(media.isPlaying);
    completedController.add(media.isCompleted);
    positionController.add(media.position);
    durationController.add(media.duration);
  }

  Future<void> _close() async {
    final controller = opened.value;
    if (controller == null) return;
    controller.removeListener(_changed);
    opened.value = null;
    _report(_nothing);
    await controller.dispose();
  }

  @override
  Future<void> play() async => opened.value?.play();

  @override
  Future<void> pause() async => opened.value?.pause();

  @override
  Future<void> playOrPause() => state.playing ? pause() : play();

  @override
  Future<void> seek(Duration duration) async => opened.value?.seekTo(duration);

  @override
  Future<void> dispose() async {
    _opens++;
    await _close();
    opened.dispose();
    await super.dispose();
  }
}
