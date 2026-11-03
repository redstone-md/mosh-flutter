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

/// Explicit frame delivery, including a callback queued before stop completed.
class _FiringCaptureHandle implements VoiceCaptureHandle {
  _FiringCaptureHandle(this._onFrame, this._frames);
  final void Function(Uint8List) _onFrame;
  final List<Uint8List> _frames;
  bool stopped = false;

  void fire() {
    for (final frame in _frames) {
      _onFrame(frame);
    }
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

/// Records startup and lets the test choose when to deliver frames.
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

/// Drain this unit scenario in one clock zone and report its original failure.
void _withClock(Future<void> Function(FakeAsync) body) {
  fakeAsync((clock) {
    var completed = false;
    Object? failure;
    StackTrace? stack;
    body(clock).then<void>((_) => completed = true,
        onError: (Object error, StackTrace trace) {
      failure = error;
      stack = trace;
    });
    clock.flushMicrotasks();
    if (failure != null) Error.throwWithStackTrace(failure!, stack!);
    expect(completed, isTrue,
        reason: 'The unit scenario left unresolved work.');
    expect(clock.pendingTimers, isEmpty);
  });
}
