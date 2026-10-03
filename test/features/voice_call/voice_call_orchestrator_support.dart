part of 'voice_call_orchestrator_test.dart';

const String kKeyB64 =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA='; // 32 zero bytes
const String kNoncePrefixB64 = 'AAAAAA=='; // 4 zero bytes

/// A capture handle that records its `stop()` call.
class _RecordingCaptureHandle implements VoiceCaptureHandle {
  bool stopped = false;
  @override
  Future<void> stop() async {
    stopped = true;
  }
}

/// A capture factory that never fires onFrame (mirrors NoopVoiceCaptureFactory
/// but with a recording handle so detach's stop() is observable).
class _RecordingCaptureFactory implements VoiceCaptureFactory {
  late _RecordingCaptureHandle handle;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(
      void Function(Uint8List opusFrame) onFrame) async {
    handle = _RecordingCaptureHandle();
    return handle;
  }
}

/// A capture handle that fires a queued frame via a Timer and records stop.
class _FiringCaptureHandle implements VoiceCaptureHandle {
  _FiringCaptureHandle(this._onFrame, this._frames);
  final void Function(Uint8List) _onFrame;
  final List<Uint8List> _frames;
  Timer? _timer;
  int _i = 0;
  bool stopped = false;

  void start() {
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_i >= _frames.length) return;
    _timer = Timer(const Duration(milliseconds: 30), () {
      if (stopped) return;
      _onFrame(_frames[_i]);
      _i++;
      _scheduleNext();
    });
  }

  @override
  Future<void> stop() async {
    stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}

/// A capture factory that fires `frames` on a 30ms cadence after start()
/// returns, so tests can toggle mute / detach in between ticks. The handle
/// is exposed for stop() observability.
class _FiringCaptureFactory implements VoiceCaptureFactory {
  _FiringCaptureFactory(this._frames);
  final List<Uint8List> _frames;
  _FiringCaptureHandle? handle;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(
      void Function(Uint8List opusFrame) onFrame) async {
    final h = _FiringCaptureHandle(onFrame, _frames);
    handle = h;
    h.start();
    return h;
  }
}

/// A recording playback handle: records pushed frames + the stop() call.
class _RecordingPlaybackHandle implements VoicePlaybackHandle {
  final List<({BigInt seq, Uint8List payload})> received = [];
  bool stopped = false;
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) {
    received.add((seq: seq, payload: Uint8List.fromList(opusFrame)));
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

/// A playback factory returning a recording handle (exposed for assertions).
class _RecordingPlaybackFactory implements VoicePlaybackFactory {
  _RecordingPlaybackHandle? handle;
  @override
  Future<VoicePlaybackHandle> start() async {
    handle = _RecordingPlaybackHandle();
    return handle!;
  }
}

/// A playback factory whose start() throws -- drives attach's catch branch.
class _FailingPlaybackFactory implements VoicePlaybackFactory {
  final Object error;
  _FailingPlaybackFactory(this.error);
  @override
  Future<VoicePlaybackHandle> start() async {
    throw error;
  }
}

/// Wires up a fresh orchestrator for an attach() call.
VoiceCallOrchestrator _orchestrator() => VoiceCallOrchestrator();
