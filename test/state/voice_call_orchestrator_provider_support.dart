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
      startedAtMs: BigInt.zero,
    );

/// Builds a ProviderContainer with the orchestrator's full override set.
/// The session controller seeds activeSessionProvider; the scripted
/// bridge and the native call owner are injected for assertions.
ProviderContainer _container({
  required _SessionController controller,
  required ScriptableBridge gateway,
  NativeCallOwner? native,
}) {
  return ProviderContainer(overrides: [
    if (native != null) nativeCallOwnerProvider.overrideWithValue(native),
    activeSessionProvider('sess-1')
        .overrideWith((ref) => Future.value(controller.snapshot)),
    bridgeFacadeProvider.overrideWithValue(gateway),
  ]);
}

/// Subscribes to the orchestrator provider so it stays alive + rebuilds when
/// the watched activeSessionProvider resolves (a one-shot read wouldn't).
ProviderSubscription _subscribe(ProviderContainer c) =>
    c.listen(voiceCallOrchestratorProvider('sess-1'), (_, __) {},
        fireImmediately: true);
