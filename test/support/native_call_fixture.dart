import 'package:flutter/widgets.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/state/native_call_owner_provider.dart';

native.Snapshot nativeCallSnapshot(
        {String sessionId = 'dm',
        String callId = 'call',
        bool microphoneRequested = true,
        bool microphone = false,
        bool camera = false,
        bool remoteCamera = true,
        bool cameraFailed = false}) =>
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
        cameras: const []);

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
