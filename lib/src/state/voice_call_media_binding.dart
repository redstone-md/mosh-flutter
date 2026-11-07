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
    unawaited(
      native
          .bind(
        sessionId,
        dialog.callId,
        superseded: dialog.supersededCallId,
        active: dialog is ActiveCallDialog,
      )
          .catchError((Object error) {
        if (_bindingRef.mounted && _attachedCallId == dialog.callId) {
          _failedCallId = dialog.callId;
          _fail(error, CallErrorSource.audioSetup);
        }
      }),
    );
  }

  void _toggleMute() {
    final native = _native?.session;
    if (native == null) return;
    unawaited(
      native.toggleMicrophone().catchError((Object error) {
        if (_bindingRef.mounted) _fail(error, CallErrorSource.audioSetup);
      }),
    );
  }

  Future<void> _mediaCommand(
    Future<void> Function(NativeCallSession) command,
  ) async {
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
