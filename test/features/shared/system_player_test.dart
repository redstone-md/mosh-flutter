// Android's player as the voice card, the composer and the viewer use it:
// media_kit's Player, here over a fake of the system's player.
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/features/shared/system_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../../support/fake_video_platform.dart';

void main() {
  late FakeVideoPlatform system;

  setUp(() {
    system = FakeVideoPlatform();
    VideoPlayerPlatform.instance = system;
  });

  Player player() {
    final player = Player(platformPlayer: SystemPlayer());
    addTearDown(player.dispose);
    return player;
  }

  test('a file opened without playing is loaded and stays silent', () async {
    final voice = player();

    await voice.open(Media('/data/voice note.m4a'), play: false);

    expect(system.opened, ['file:///data/voice%20note.m4a']);
    expect(voice.state.duration, const Duration(milliseconds: 4200));
    expect(voice.state.playing, isFalse);
    expect(system.calls, isNot(contains('play')));
  });

  test('a stream opens playing, and pausing and playing reach it', () async {
    final video = player();
    final playing = <bool>[];

    await video.open(Media('http://127.0.0.1:4100/dm/peer/clip'));
    expect(video.state.playing, isTrue);
    video.stream.playing.listen(playing.add);
    await video.playOrPause();
    await video.playOrPause();
    await pumpEventQueue();

    expect(system.opened, ['http://127.0.0.1:4100/dm/peer/clip']);
    expect(system.calls, ['play', 'pause', 'play']);
    expect(playing, [false, true]);
  });

  test('seeking moves the system player', () async {
    final voice = player();
    await voice.open(Media('/data/voice.m4a'), play: false);

    await voice.seek(const Duration(seconds: 2));

    expect(system.calls.last, 'seek 2000');
    expect(voice.state.position, const Duration(seconds: 2));
  });

  test('a media that ended is no longer playing', () async {
    final voice = player();
    await voice.open(Media('/data/voice.m4a'));

    system.report(VideoEventType.completed);
    await pumpEventQueue();

    expect(voice.state.playing, isFalse);
    expect(voice.state.completed, isTrue);
  });

  test('a source the system cannot open fails and is let go', () async {
    final voice = player();
    system.refuses = true;

    await expectLater(voice.open(Media('/data/broken.m4a')), throwsA(anything));

    expect(system.calls, ['dispose 0']);
    expect(voice.state.playing, isFalse);
  });

  test('opening another file lets go of the first', () async {
    final voice = player();
    await voice.open(Media('/data/first.m4a'), play: false);

    await voice.open(Media('/data/second.m4a'), play: false);

    expect(system.calls, contains('dispose 0'));
    expect(system.calls, isNot(contains('dispose 1')));
  });

  test('a player disposed while it opens lets go of what it opened', () async {
    final voice = Player(platformPlayer: SystemPlayer());

    final opening = voice.open(Media('/data/voice.m4a'));
    await voice.dispose();
    await opening;

    expect(system.calls, contains('dispose 0'));
  });
}
