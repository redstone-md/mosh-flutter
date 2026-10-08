part of 'voice_call_orchestrator_provider_test.dart';

/// A mutable controller the activeSessionProvider override reads from. Tests
/// mutate `snapshot` then invalidate the session so the orchestrator re-runs
/// build.
class _SessionController {
  _SessionController(this.snapshot);
  SessionSnapshot? snapshot;
}

SessionSnapshot _session(
  String sessionId, {
  ActiveCall? activeCall,
  PendingCall? pendingCall,
  OutgoingCall? outgoingCall,
}) =>
    SessionSnapshot(
      inviteAvailable: false,
      sessionId: sessionId,
      meshId: 'm',
      role: 'caller',
      displayName: 'me',
      peerDisplayName: 'Alice',
      state: DmSessionState.connected,
      transport: PeerTransport.direct,
      inviteUri: null,
      fingerprint: 'AA',
      messages: const [],
      attachments: const [],
      mesh: null,
      events: const [],
      pendingCall: pendingCall,
      outgoingCall: outgoingCall,
      activeCall: activeCall,
    );

ActiveCall _activeCall(String callId) => ActiveCall(
      callId: callId,
      direction: 'caller',
      keyB64: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', // 32 zero bytes
      noncePrefixB64: 'AAAAAA==', // 4 zero bytes
      startedAtMs: BigInt.zero,
    );

/// A capture handle that records its stop() call.
class _RecordingCaptureHandle implements VoiceCaptureHandle {
  int stopCalls = 0;
  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

/// A capture factory that records each start() (count + last handle) so a
/// test can assert the orchestrator attached and re-attached.
class _RecordingCaptureFactory implements VoiceCaptureFactory {
  int startCalls = 0;
  _RecordingCaptureHandle? lastHandle;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) {
    startCalls++;
    final h = _RecordingCaptureHandle();
    lastHandle = h;
    return Future.value(h);
  }
}

/// A capture factory whose start() throws -- drives attach's catch branch
/// so endCall fires (the setup-failure seam).
class _FailingCaptureFactory implements VoiceCaptureFactory {
  _FailingCaptureFactory(this.error);
  final Object error;
  @override
  bool get isSupported => true;
  @override
  Future<VoiceCaptureHandle> start(void Function(Uint8List opusFrame) onFrame) {
    throw error;
  }
}

/// A recording playback handle: records its stop() call.
class _RecordingPlaybackHandle implements VoicePlaybackHandle {
  int stopCalls = 0;
  @override
  void pushFrame(BigInt seq, Uint8List opusFrame) {}
  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

/// A playback factory that records each start() (count + last handle).
class _RecordingPlaybackFactory implements VoicePlaybackFactory {
  int startCalls = 0;
  @override
  Future<VoicePlaybackHandle> start() {
    startCalls++;
    return Future.value(_RecordingPlaybackHandle());
  }
}

/// Builds a ProviderContainer with the orchestrator's full override set.
/// The session controller seeds activeSessionProvider; the scripted
/// bridge + factories are injected for assertions.
ProviderContainer _container({
  required _SessionController controller,
  required ScriptableBridge gateway,
  VoiceCaptureFactory? captureFactory,
  VoicePlaybackFactory? playbackFactory,
}) {
  return ProviderContainer(overrides: [
    activeSessionProvider('sess-1')
        .overrideWith((ref) => Future.value(controller.snapshot)),
    bridgeFacadeProvider.overrideWithValue(gateway),
    voiceCaptureFactoryProvider
        .overrideWithValue(captureFactory ?? const NoopVoiceCaptureFactory()),
    voicePlaybackFactoryProvider
        .overrideWithValue(playbackFactory ?? const NoopVoicePlaybackFactory()),
  ]);
}

/// Subscribes to the orchestrator provider so it stays alive + rebuilds when
/// the watched activeSessionProvider resolves (a one-shot read wouldn't).
ProviderSubscription _subscribe(ProviderContainer c) =>
    c.listen(voiceCallOrchestratorProvider('sess-1'), (_, __) {},
        fireImmediately: true);
