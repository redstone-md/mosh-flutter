import 'package:mosh/src/rust/native_call/types.dart' as native;

native.Snapshot nativeCallSnapshot(
        {String sessionId = 'dm',
        String callId = 'call',
        bool microphoneRequested = true,
        bool camera = false,
        bool cameraFailed = false}) =>
    native.Snapshot(
        sessionId: sessionId,
        callId: callId,
        ready: true,
        microphone: false,
        microphoneRequested: microphoneRequested,
        microphoneAvailable: false,
        camera: camera,
        cameraRequested: camera,
        cameraStarting: false,
        cameraFailed: cameraFailed,
        remoteCamera: true,
        reconnecting: false,
        failed: false,
        videoWidth: 0,
        videoHeight: 0,
        videoFps: 0,
        packetsDropped: BigInt.zero,
        inputs: const [],
        outputs: const [],
        cameras: const []);
