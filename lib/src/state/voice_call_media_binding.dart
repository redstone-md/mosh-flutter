part of 'voice_call_orchestrator_provider.dart';

extension _VoiceCallMediaBinding on VoiceCallOrchestratorNotifier {
  void _nativeChanged() {
    _publishMediaState();
  }

  void _attachNative(CallDialog dialog) {
    final native = _native!;
    if (dialog is NoCallDialog) {
      final id = _attachedCallId;
      if (id != null) native.unbind(sessionId, id);
      _attachedCallId = null;
      return;
    }
    _attachedCallId = dialog.callId;
    if (_failedCallId == dialog.callId) return;
    unawaited(native
        .bind(sessionId, dialog.callId,
            superseded: dialog.supersededCallId,
            active: dialog is ActiveCallDialog)
        .catchError((Object error) {
      if (_bindingRef.mounted && _attachedCallId == dialog.callId) {
        _failedCallId = dialog.callId;
        _fail(error, CallErrorSource.audioSetup);
      }
    }));
  }

  void _attach(ActiveCall? active) {
    if (active?.callId == _attachedCallId) return;
    final old = _attachedCallId;
    _attachedCallId = active?.callId;
    if (old != null) unawaited(_audio.detach(call: (sessionId, old)));
    if (active == null) return;
    final id = active.callId;
    final bridge = _bindingRef.read(bridgeFacadeProvider);
    unawaited(_audio.attach(
      sessionId: sessionId,
      callId: id,
      keyB64: active.keyB64,
      noncePrefixB64: active.noncePrefixB64,
      direction: active.direction,
      bridge: bridge,
      captureFactory: _bindingRef.read(voiceCaptureFactoryProvider),
      playbackFactory: _bindingRef.read(voicePlaybackFactoryProvider),
      onReady: () {
        if (_bindingRef.mounted && _attachedCallId == id) _publishMediaState();
      },
      onError: (message) {
        if (!_bindingRef.mounted || _attachedCallId != id) return;
        _failedCallId = id;
        _fail(message, CallErrorSource.audioSetup);
      },
      endCall: (_, c, reason) => _endCall(c, reason, preserveError: true),
    ));
  }

  void _toggleMute() {
    final native = _native?.session;
    if (native != null) {
      unawaited(native.toggleMicrophone().catchError(
          (Object error) => _fail(error, CallErrorSource.audioSetup)));
      return;
    }
    if (!_view.audioReady || _view.busy) return;
    _audio.toggleMute();
    _publishMediaState();
  }

  Future<void> _mediaCommand(
      Future<void> Function(NativeCallSession) command) async {
    final client = _native?.session;
    if (client == null || client.sessionId != sessionId) return;
    try {
      await command(client);
    } catch (error) {
      if (_bindingRef.mounted && identical(_native?.session, client)) {
        _fail(error, CallErrorSource.callControl);
      }
    }
  }
}
