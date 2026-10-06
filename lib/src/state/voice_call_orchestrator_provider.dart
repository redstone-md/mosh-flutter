import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_ringing.dart';
import 'package:mosh/src/features/voice_call/incoming_call_modal.dart';
import 'package:mosh/src/features/voice_call/voice_call_orchestrator.dart';
import 'package:mosh/src/features/voice_call/voice_capture.dart';
import 'package:mosh/src/features/voice_call/voice_playback.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/gateway/bridge_facade.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/conversation_providers.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';
import 'package:mosh/src/state/voice_call_session_provider.dart';
import 'package:mosh/src/state/voice_call_start_provider.dart';

enum CallErrorSource { callControl, audioSetup }

class CallError {
  const CallError({required this.cause, required this.source});
  final ConversationActionError cause;
  final CallErrorSource source;
}

class VoiceCallOrchestratorState {
  const VoiceCallOrchestratorState({
    this.dialog = const NoCallDialog(),
    this.muted = false,
    this.audioReady = false,
    this.audioFailed = false,
    this.busy = false,
    this.error,
  });

  final CallDialog dialog;
  final bool muted;
  final bool audioReady;
  final bool audioFailed;
  final bool busy;
  final CallError? error;

  VoiceCallOrchestratorState copyWith({
    CallDialog? dialog,
    bool? muted,
    bool? audioReady,
    bool? audioFailed,
    bool? busy,
    CallError? error,
  }) =>
      VoiceCallOrchestratorState(
        dialog: dialog ?? this.dialog,
        muted: muted ?? this.muted,
        audioReady: audioReady ?? this.audioReady,
        audioFailed: audioFailed ?? this.audioFailed,
        busy: busy ?? this.busy,
        error: error ?? this.error,
      );

  VoiceCallOrchestratorState copyWithoutError() => VoiceCallOrchestratorState(
        dialog: dialog,
        muted: muted,
        audioReady: audioReady,
        audioFailed: audioFailed,
        busy: busy,
      );
}

final voiceCaptureFactoryProvider = Provider<VoiceCaptureFactory>(
  (ref) => const NoopVoiceCaptureFactory(),
);
final voicePlaybackFactoryProvider = Provider<VoicePlaybackFactory>(
  (ref) => const NoopVoicePlaybackFactory(),
);
final ringtonePlayerProvider = Provider<RingtonePlayer>(
  (ref) => const NoopRingtonePlayer(),
);

final _callAudioProvider = Provider<VoiceCallOrchestrator>((ref) {
  final audio = VoiceCallOrchestrator();
  ref.onDispose(() => unawaited(audio.detach()));
  return audio;
});

final voiceCallOrchestratorProvider = NotifierProvider.autoDispose
    .family<VoiceCallOrchestratorNotifier, VoiceCallOrchestratorState, String>(
  VoiceCallOrchestratorNotifier.new,
);

/// One selected DM's call state. Audio replacement is serialized by the
/// application-level audio owner; ringtone lifetime is independent of widgets.
class VoiceCallOrchestratorNotifier
    extends Notifier<VoiceCallOrchestratorState> {
  VoiceCallOrchestratorNotifier(this.sessionId);
  final String sessionId;
  late VoiceCallOrchestrator _audio;
  late CallRinging _ringing;
  SessionSnapshot? _snapshot;
  String? _attachedCallId;
  String? _dismissedCallId;
  String? _acceptedCallId;
  String? _controlId;
  CallError? _error;
  String? _failedCallId;
  bool _appOwned = false;

  @override
  VoiceCallOrchestratorState build() {
    _audio = ref.read(_callAudioProvider);
    _ringing = CallRinging(ref.read(ringtonePlayerProvider), (id) {
      if (ref.mounted) unawaited(declineCall(id, kCallDeclineReasonNoAnswer));
    });
    ref.onDispose(() {
      _ringing.dispose();
      final id = _attachedCallId;
      if (id != null) unawaited(_audio.detach(callId: id));
    });
    ref.listen(personalChatNameProvider(DmTarget(sessionId).ref), (_, __) {
      state = _stateFor(_snapshot);
    });
    final selected = ref.read(voiceCallSessionProvider);
    _appOwned = selected?.sessionId == sessionId;
    ref.listen(voiceCallSessionProvider, (_, next) {
      if (next?.sessionId == sessionId) {
        _appOwned = true;
        state = _stateFor(next);
      } else if (_appOwned) {
        state = _stateFor(null);
      }
    });
    ref.listen(activeSessionProvider(sessionId), (_, next) {
      if (!_appOwned && next is AsyncData<SessionSnapshot>) {
        state = _stateFor(next.value);
      }
    });
    return _stateFor(_appOwned
        ? selected
        : ref.read(activeSessionProvider(sessionId)).value);
  }

  VoiceCallOrchestratorState _stateFor(SessionSnapshot? session) {
    _snapshot = session;
    var dialog = callDialogFor(session,
        personalName:
            ref.read(personalChatNameProvider(DmTarget(sessionId).ref)));
    if (dialog.callId != _dismissedCallId) _dismissedCallId = null;
    if (dialog.callId == _dismissedCallId) dialog = const NoCallDialog();
    if (dialog.callId != _failedCallId) _failedCallId = null;
    if (dialog is! IncomingCallDialog) _acceptedCallId = null;
    final busy = _controlId == dialog.callId ||
        (_acceptedCallId != null && _acceptedCallId == dialog.callId);
    _ringing.update(dialog, busy: busy);
    _attach(dialog is ActiveCallDialog ? dialog.active : null);
    return VoiceCallOrchestratorState(
      dialog: dialog,
      muted: _attachedCallId == null ? false : _audio.isMuted,
      audioReady: _attachedCallId != null && _audio.isAttached,
      audioFailed: _failedCallId != null,
      busy: busy,
      error: _error,
    );
  }

  void _attach(ActiveCall? active) {
    if (active?.callId == _attachedCallId) return;
    final old = _attachedCallId;
    _attachedCallId = active?.callId;
    if (old != null) unawaited(_audio.detach(callId: old));
    if (active == null) return;
    final id = active.callId;
    final bridge = ref.read(bridgeFacadeProvider);
    unawaited(_audio.attach(
      sessionId: sessionId,
      callId: id,
      keyB64: active.keyB64,
      noncePrefixB64: active.noncePrefixB64,
      direction: active.direction,
      bridge: bridge,
      captureFactory: ref.read(voiceCaptureFactoryProvider),
      playbackFactory: ref.read(voicePlaybackFactoryProvider),
      onReady: () {
        if (ref.mounted && _attachedCallId == id) state = _stateFor(_snapshot);
      },
      onError: (message) {
        if (!ref.mounted || _attachedCallId != id) return;
        _failedCallId = id;
        _fail(message, CallErrorSource.audioSetup);
      },
      endCall: (s, c, reason) async {
        if (!ref.mounted || _snapshot?.activeCall?.callId != c) return;
        await bridge.callEnd(sessionId: s, callId: c, reason: reason);
        if (!ref.mounted || _snapshot?.activeCall?.callId != c) return;
        _dismissedCallId = c;
        state = _stateFor(_snapshot);
        _refresh();
      },
    ));
  }

  Future<Object?> startCall() =>
      ref.read(voiceCallStartProvider.notifier).start(sessionId);

  Future<void> acceptCall(String id) =>
      _control(id, (b) => b.callAccept(sessionId: sessionId, callId: id),
          terminal: false);

  Future<void> declineCall(String id, String reason) => _control(id,
      (b) => b.callDecline(sessionId: sessionId, callId: id, reason: reason));

  Future<void> endCall(String id, String reason) => _control(
      id, (b) => b.callEnd(sessionId: sessionId, callId: id, reason: reason));

  Future<void> _control(String id, Future<void> Function(BridgeFacade) action,
      {bool terminal = true}) async {
    if (state.dialog.callId != id || state.busy) return;
    _controlId = id;
    _error = null;
    state = _stateFor(_snapshot);
    try {
      await action(ref.read(bridgeFacadeProvider));
      if (!ref.mounted || state.dialog.callId != id) return;
      _controlId = null;
      if (terminal) {
        _dismissedCallId = id;
      } else {
        _acceptedCallId = id;
      }
      state = _stateFor(_snapshot);
      _refresh();
    } catch (error) {
      if (!ref.mounted || state.dialog.callId != id) return;
      _controlId = null;
      _fail(error, CallErrorSource.callControl);
    }
  }

  void _refresh() {
    if (!ref.mounted) return;
    if (!_appOwned) ref.invalidate(activeSessionProvider(sessionId));
    ref.invalidate(conversationListProvider(ConversationKind.dm));
  }

  void toggleMute() {
    if (!state.audioReady || state.busy) return;
    _audio.toggleMute();
    state = state.copyWith(muted: _audio.isMuted);
  }

  void clearError() {
    _error = null;
    if (ref.mounted) state = state.copyWithoutError();
  }

  void _fail(Object? error, CallErrorSource source) {
    _error = CallError(
        cause: ConversationActionError.of(error ?? 'Call failed'),
        source: source);
    state = _stateFor(_snapshot);
  }
}
