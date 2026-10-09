part of 'voice_call_orchestrator_provider_test.dart';

void registerNativeBindingTests() {
  test(
      'native active binding sends device commands without starting legacy capture',
      () async {
    final bridge = ScriptableBridge();
    bridge.respondNext(
        BridgeMethod.nativeCallSnapshot,
        Future.value(nativeCallSnapshot(
            sessionId: 'sess-1', microphoneRequested: false)));
    final owner = NativeCallOwner(bridge, () async => false);
    final capture = _RecordingCaptureFactory();
    final controller =
        _SessionController(_session('sess-1', activeCall: _activeCall('call')));
    final container = _container(
        controller: controller,
        gateway: bridge,
        captureFactory: capture,
        native: owner);
    final sub = _subscribe(container);
    addTearDown(() {
      sub.close();
      container.dispose();
      owner.dispose();
    });
    await container.read(activeSessionProvider('sess-1').future);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final state = container.read(voiceCallOrchestratorProvider('sess-1'));
    expect(state.audioReady, true);
    expect(state.nativeMedia!.callId, 'call');
    expect(capture.startCalls, 0);
    final notifier =
        container.read(voiceCallOrchestratorProvider('sess-1').notifier);
    await notifier.selectInput('mic');
    await notifier.selectOutput('speaker');
    await notifier.selectCamera('camera');
    await notifier.toggleCamera();
    bridge.failNext(BridgeMethod.nativeCallChoices);
    await notifier.toggleCamera();
    expect(
        container.read(voiceCallOrchestratorProvider('sess-1')).error!.source,
        CallErrorSource.callControl);
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
    notifier.clearError();
    await notifier.endCall('call', kCallDeclineReasonHangup);
    expect(owner.session, isNull);
  });

  test(
      'native preparation error is reported once without an automatic retry loop',
      () async {
    final bridge = ScriptableBridge()..failNext(BridgeMethod.nativeCallPrepare);
    final owner = NativeCallOwner(bridge, () async => false);
    final controller =
        _SessionController(_session('sess-1', activeCall: _activeCall('call')));
    final container =
        _container(controller: controller, gateway: bridge, native: owner);
    final sub = _subscribe(container);
    addTearDown(() {
      sub.close();
      container.dispose();
      owner.dispose();
    });
    await container.read(activeSessionProvider('sess-1').future);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
    expect(container.read(voiceCallOrchestratorProvider('sess-1')).audioFailed,
        true);
    await container
        .read(voiceCallOrchestratorProvider('sess-1').notifier)
        .toggleCamera();
    expect(bridge.countOf(BridgeMethod.nativeCallPrepare), 1);
  });
}
