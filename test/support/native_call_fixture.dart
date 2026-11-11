import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_video_textures.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/state/native_call_owner_provider.dart';

native.Snapshot nativeCallSnapshot(
        {String sessionId = 'dm',
        String callId = 'call',
        bool microphoneRequested = true,
        bool microphone = false,
        bool camera = false,
        bool remoteCamera = true,
        bool cameraFailed = false,
        native.Surface localVideo = const native.Surface(width: 0, height: 0),
        native.Surface remoteVideo =
            const native.Surface(width: 0, height: 0)}) =>
    native.Snapshot(
        sessionId: sessionId,
        callId: callId,
        ready: true,
        microphone: microphone,
        microphoneRequested: microphoneRequested,
        microphoneAvailable: microphone,
        camera: camera,
        cameraRequested: camera,
        cameraStarting: false,
        cameraFailed: cameraFailed,
        remoteCamera: remoteCamera,
        reconnecting: false,
        failed: false,
        videoWidth: 0,
        videoHeight: 0,
        videoFps: 0,
        packetsDropped: BigInt.zero,
        inputs: const [],
        outputs: const [],
        cameras: const [],
        localVideo: localVideo,
        remoteVideo: remoteVideo);

/// The platform's call video plugin: texture ids 7 and 8, exported at two
/// addresses.
void mockCallVideoPlugin(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      CallVideoTextures.channel,
      (call) async => {
            'local': [7, 4096],
            'remote': [8, 8192],
          });
  addTearDown(() =>
      messenger.setMockMethodCallHandler(CallVideoTextures.channel, null));
}

/// Releases [media] when the widget tree unmounts, before the test's
/// pending-timer check: the application-level owner outlives every call
/// view, its snapshot poll must not outlive the test.
class ReleasesCallMedia extends StatefulWidget {
  const ReleasesCallMedia(
      {super.key, required this.media, required this.child});
  final NativeCallOwner? media;
  final Widget child;

  @override
  State<ReleasesCallMedia> createState() => _ReleasesCallMediaState();
}

class _ReleasesCallMediaState extends State<ReleasesCallMedia> {
  @override
  void dispose() {
    widget.media?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
