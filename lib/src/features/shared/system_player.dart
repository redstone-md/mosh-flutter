import 'dart:async' show unawaited;
import 'dart:io' show File;

import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:media_kit/media_kit.dart';
import 'package:video_player/video_player.dart';

import 'attachment_media_src.dart' show localFileSrc;

/// media_kit's player over the system's own: media3 on Android, reached
/// through video_player (ADR 0053). It plays what the app plays, one local
/// file or loopback stream at a time, and like libmpv's player it plays on
/// while the app is in the background.
class SystemPlayer extends PlatformPlayer {
  SystemPlayer() : super(configuration: const PlayerConfiguration());

  /// The open media, which a `VideoPlayer` shows; null while none is open.
  final opened = ValueNotifier<VideoPlayerController?>(null);

  // Only the latest open is kept: one that finishes after another open, or
  // after dispose, lets go of what it opened.
  int _opens = 0;

  /// What was opened last, which playing opens again once the system gave
  /// up on it.
  Playable? _last;

  static const _nothing = VideoPlayerValue.uninitialized();
  static final _opening = _nothing.copyWith(isBuffering: true);

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    final open = ++_opens;
    _last = playable;
    await _close();
    if (open != _opens) return;
    _report(_opening);
    final controller = _controller(Uri.parse(localFileSrc(_source(playable))));
    try {
      await controller.initialize();
    } catch (_) {
      // Not awaited: where the system made no player, video_player never
      // finishes disposing of it.
      unawaited(controller.dispose());
      if (open == _opens) _report(_nothing);
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
    final options = VideoPlayerOptions(allowBackgroundPlayback: true);
    return source.isScheme('file')
        ? VideoPlayerController.file(File(source.toFilePath()),
            videoPlayerOptions: options)
        : VideoPlayerController.networkUrl(source, videoPlayerOptions: options);
  }

  void _changed() {
    final media = opened.value!.value;
    if (!media.hasError) return _report(media);
    // The system gave up on the media, as when its stream dies, and cannot
    // take it up again. Letting it go leaves playing to open it anew.
    errorController.add(media.errorDescription ?? '');
    unawaited(_close());
  }

  void _report(VideoPlayerValue media) {
    state = state.copyWith(
      playing: media.isPlaying,
      completed: media.isCompleted,
      buffering: media.isBuffering,
      position: media.position,
      duration: media.duration,
    );
    playingController.add(media.isPlaying);
    completedController.add(media.isCompleted);
    bufferingController.add(media.isBuffering);
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
  Future<void> play() async {
    final media = opened.value;
    if (media != null) return media.play();
    // Nothing is open and nothing is opening: the last media failed.
    final last = _last;
    if (last != null && !state.buffering) return open(last);
  }

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
