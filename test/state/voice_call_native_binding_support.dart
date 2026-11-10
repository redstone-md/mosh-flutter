part of 'voice_call_orchestrator_provider_test.dart';

void registerNativeBindingTests() {
  test('native active binding sends device commands', () async {
    final bridge = ScriptableBridge();
    bridge.respondNext(
        BridgeMethod.nativeCallSnapshot,
        Future.value(nativeCallSnapshot(
            sessionId: 'sess-1', microphoneRequested: false)));
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
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final state = container.read(voiceCallOrchestratorProvider('sess-1'));
    expect(state.audioReady, true);
    expect(state.nativeMedia!.callId, 'call');
    final notifier =
        container.read(voiceCallOrchestratorProvider('sess-1').notifier);
    await notifier.selectInput('mic');
    await notifier.selectOutput('speaker');
    await notifier.selectCamera('camera');
    final applying = Completer<void>();
    bridge.respondNext(BridgeMethod.nativeCallChoices, applying.future);
    final shown = Completer<void>();
    final watch =
        container.listen(voiceCallOrchestratorProvider('sess-1'), (_, next) {
      if (next.cameraRequested && !shown.isCompleted) shown.complete();
    });
    final pressed = notifier.toggleCamera();
    // The camera button follows the press while native media still applies it.
    await shown.future;
    applying.complete();
    await pressed;
    watch.close();
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

  test('a new call rebinds the media and a finished one releases it', () async {
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => false);
    final controller =
        _SessionController(_session('sess-1', activeCall: _activeCall('a')));
    final container =
        _container(controller: controller, gateway: bridge, native: owner);
    final sub = _subscribe(container);
    addTearDown(() {
      sub.close();
      container.dispose();
      owner.dispose();
    });
    Future<void> poll(SessionSnapshot snapshot) async {
      controller.snapshot = snapshot;
      container.invalidate(activeSessionProvider('sess-1'));
      await container.read(activeSessionProvider('sess-1').future);
      await pumpEventQueue();
    }

    await poll(_session('sess-1', activeCall: _activeCall('a')));
    expect(owner.session?.callId, 'a');
    await poll(_session('sess-1', activeCall: _activeCall('a')));
    await poll(_session('sess-1', activeCall: _activeCall('b')));
    expect(owner.session?.callId, 'b');
    expect(bridge.argValues<String>(BridgeMethod.nativeCallPrepare, 'callId'),
        ['a', 'b']);
    await poll(_session('sess-1'));
    expect(owner.session, isNull);
  });

  test('mute is the native microphone choice', () async {
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => true);
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
    await pumpEventQueue();
    final notifier =
        container.read(voiceCallOrchestratorProvider('sess-1').notifier);
    final before = owner.session!.muted;
    notifier.toggleMute();
    await pumpEventQueue();
    expect(owner.session!.muted, !before);
    expect(bridge.argValues<bool>(BridgeMethod.nativeCallChoices, 'microphone'),
        isNotEmpty);
  });

  test('a mute that fails after the call screen is gone reports nothing',
      () async {
    final bridge = ScriptableBridge();
    final owner = NativeCallOwner(bridge, () async => true);
    final controller =
        _SessionController(_session('sess-1', activeCall: _activeCall('call')));
    final container =
        _container(controller: controller, gateway: bridge, native: owner);
    final sub = _subscribe(container);
    addTearDown(owner.dispose);
    await container.read(activeSessionProvider('sess-1').future);
    await pumpEventQueue();
    final choice = Completer<void>();
    bridge.respondNext(BridgeMethod.nativeCallChoices, choice.future);
    container
        .read(voiceCallOrchestratorProvider('sess-1').notifier)
        .toggleMute();
    await pumpEventQueue();
    sub.close();
    container.dispose();
    choice.completeError(Exception('engine gone'));
    await pumpEventQueue();
  });
}
