import 'package:mosh/src/rust/native_call/types.dart' as native;

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
