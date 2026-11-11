import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// The system's player as video_player reaches it. It opens every source as a
/// media [duration] long, or refuses it while [refuses] is set, and records
/// what it was asked to do.
class FakeVideoPlatform extends VideoPlayerPlatform {
  Duration duration = const Duration(milliseconds: 4200);
  Size size = Size.zero;
  bool refuses = false;

  /// Whether the system has no player to give at all.
  bool unavailable = false;

  /// Where the playing media is; the app polls it.
  Duration position = Duration.zero;

  final opened = <String>[];
  final calls = <String>[];
  final _events = <StreamController<VideoEvent>>[];
  bool _playing = false;

  /// What the system reports about the media opened last.
  void report(VideoEventType type) =>
      _events.last.add(VideoEvent(eventType: type));

  /// The system gives up on the media opened last, as when its stream dies.
  void giveUp() => _events.last
      .addError(PlatformException(code: 'VideoError', message: 'x'));

  @override
  Future<void> init() async {}

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    if (unavailable) throw PlatformException(code: 'unavailable');
    opened.add(options.dataSource.uri!);
    late final StreamController<VideoEvent> events;
    events = StreamController<VideoEvent>(
      onListen: () {
        if (refuses) {
          events.addError(PlatformException(code: 'source', message: 'no'));
        } else {
          events.add(VideoEvent(
              eventType: VideoEventType.initialized,
              duration: duration,
              size: size));
        }
      },
      // A cancel with a future of its own, as a platform channel gives. The
      // SDK's shared one belongs to the root zone, which a widget test's
      // fake clock never drains.
      onCancel: () async {},
    );
    _events.add(events);
    return _events.length - 1;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId].stream;

  @override
  Future<void> dispose(int playerId) async => calls.add('dispose $playerId');

  @override
  Future<void> play(int playerId) async {
    calls.add('play');
    _playing = true;
  }

  /// Pausing what is not playing changes nothing and is not recorded:
  /// video_player does it to every media it has just opened.
  @override
  Future<void> pause(int playerId) async {
    if (_playing) calls.add('pause');
    _playing = false;
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    calls.add('seek ${position.inMilliseconds}');
    this.position = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async => position;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const SizedBox.expand(key: ValueKey('system video picture'));
}
