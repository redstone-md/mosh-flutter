// The viewer's video on Android: the system's player shows the picture and
// the viewer's own controls drive it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:mosh/src/features/shared/media_viewer.dart';
import 'package:mosh/src/features/shared/system_player.dart';
import 'package:mosh/src/rust/conversation/attachments.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../../support/fake_video_platform.dart';
import '../../support/pump.dart';

class _Screen extends WakelockPlusPlatformInterface {
  bool awake = false;

  @override
  Future<void> toggle({required bool enable}) async => awake = enable;
}

void main() {
  late FakeVideoPlatform system;
  late _Screen screen;

  setUp(() {
    system = FakeVideoPlatform()..size = const Size(640, 360);
    VideoPlayerPlatform.instance = system;
    wakelockPlusPlatformInstance = screen = _Screen();
  });

  Future<void> open(WidgetTester tester) => pumpScreen(
      tester,
      MediaViewer(
          descriptor: AttachmentDescriptor(
              attachmentId: 'clip',
              contentHash: 'hash',
              fileName: 'clip.mp4',
              mime: 'video/mp4',
              totalSize: BigInt.from(1024)),
          src: 'http://127.0.0.1:4100/dm/peer/clip',
          onClose: () {},
          createPlayer: ({video = false}) =>
              Player(platformPlayer: SystemPlayer(video: video))));

  Future<void> close(WidgetTester tester) =>
      pumpScreen(tester, const SizedBox());

  testWidgets('a video plays in the system player until the viewer closes',
      (tester) async {
    await open(tester);

    expect(find.byType(VideoPlayer), findsOneWidget);
    expect(system.opened, ['http://127.0.0.1:4100/dm/peer/clip']);
    expect(system.calls, ['play']);
    expect(screen.awake, isTrue,
        reason: 'the display must not sleep mid-video');

    await close(tester);

    expect(system.calls, ['play', 'dispose 0']);
    expect(screen.awake, isFalse);
  });

  testWidgets('the controls pause, resume and seek the video', (tester) async {
    await open(tester);

    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.tapAt(tester.getCenter(find.byType(Slider)));
    await tester.pump();

    // The media is 4.2 seconds long; the slider's middle is 2.1 seconds in.
    expect(system.calls, ['play', 'pause', 'play', 'seek 2100']);
    await close(tester);
  });

  testWidgets('a spinner shows while the video waits for its stream',
      (tester) async {
    await open(tester);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    system.report(VideoEventType.bufferingStart);
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    system.report(VideoEventType.bufferingEnd);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await close(tester);
  });

  testWidgets('a video whose stream died opens again from the controls',
      (tester) async {
    await open(tester);

    system.giveUp();
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlayer), findsNothing);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pumpAndSettle();

    expect(system.opened, hasLength(2));
    expect(find.byType(VideoPlayer), findsOneWidget);
    await close(tester);
  });

  testWidgets('a video the system cannot play shows its file card',
      (tester) async {
    system.refuses = true;

    await open(tester);

    expect(find.byIcon(Icons.play_circle_filled), findsOneWidget);
    expect(find.byType(VideoPlayer), findsNothing);
    expect(screen.awake, isFalse);
  });
}
