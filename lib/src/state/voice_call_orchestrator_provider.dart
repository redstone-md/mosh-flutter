import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/src/state/chat_names_provider.dart';
import 'package:mosh/src/gateway/conversation_target.dart';
import 'package:mosh/src/features/shared/conversation_action_error.dart';
import 'package:mosh/src/features/voice_call/call_dialog.dart';
import 'package:mosh/src/features/voice_call/call_control_gate.dart';
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
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:mosh/src/features/voice_call/native_call_session.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native_media;

part 'voice_call_media_binding.dart';

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
    this.occupancyConflict = false,
    this.error,
    this.nativeMedia,
  });

  final CallDialog dialog;
  final bool muted;
  final bool audioReady;
  final bool audioFailed;
  final bool busy;
  final bool occupancyConflict;
  final CallError? error;
  final native_media.Snapshot? nativeMedia;

  VoiceCallOrchestratorState copyWith({
    CallDialog? dialog,
    bool? muted,
    bool? audioReady,
    bool? audioFailed,
    bool? busy,
    bool? occupancyConflict,
    CallError? error,
  }) =>
      VoiceCallOrchestratorState(
        dialog: dialog ?? this.dialog,
        muted: muted ?? this.muted,
        audioReady: audioReady ?? this.audioReady,
        audioFailed: audioFailed ?? this.audioFailed,
        busy: busy ?? this.busy,
        occupancyConflict: occupancyConflict ?? this.occupancyConflict,
        error: error ?? this.error,
        nativeMedia: nativeMedia,
      );

  VoiceCallOrchestratorState copyWithoutError() => VoiceCallOrchestratorState(
        dialog: dialog,
        muted: muted,
        audioReady: audioReady,
        audioFailed: audioFailed,
        busy: busy,
        occupancyConflict: occupancyConflict,
        nativeMedia: nativeMedia,
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
  final _controls = CallControlGate();
  CallError? _error;
  String? _failedCallId;
  bool _appOwned = false;
  NativeCallOwner? _native;

  @override
  VoiceCallOrchestratorState build() {
    _audio = ref.read(_callAudioProvider);
    _native = ref.read(nativeCallOwnerProvider);
    _native?.addListener(_nativeChanged);
    _ringing = CallRinging(ref.read(ringtonePlayerProvider), (id) {
      if (ref.mounted) unawaited(declineCall(id, kCallDeclineReasonNoAnswer));
    });
    ref.onDispose(() {
      _ringing.dispose();
      _native?.removeListener(_nativeChanged);
      final id = _attachedCallId;
      if (id != null) unawaited(_audio.detach(call: (sessionId, id)));
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
    final busy = _controls.isBusy(dialog.callId) ||
        (_acceptedCallId != null && _acceptedCallId == dialog.callId);
    _ringing.update(dialog, busy: busy);
    if (_native == null) {
      _attach(dialog is ActiveCallDialog ? dialog.active : null);
    } else {
      _attachNative(dialog);
    }
    return VoiceCallOrchestratorState(
      dialog: dialog,
      muted: _native?.session?.muted ??
          (_attachedCallId == null ? false : _audio.isMuted),
      audioReady: _native?.session?.snapshot?.ready ??
          (_attachedCallId != null && _audio.isAttached),
      audioFailed: _failedCallId != null,
      busy: busy || (_native?.session?.busy ?? false),
      occupancyConflict: session?.callAvailability == CallAvailability.conflict,
      error: _error,
      nativeMedia: _native?.session?.snapshot,
    );
  }

  Future<Object?> startCall() =>
      ref.read(voiceCallStartProvider.notifier).start(sessionId);

  Future<void> acceptCall(String id) {
    final dialog = state.dialog;
    if (dialog is! IncomingCallDialog || dialog.pending.answerPending) {
      return Future.value();
    }
    return _control(id, (b) => b.callAccept(sessionId: sessionId, callId: id),
        terminal: false);
  }

  Future<void> declineCall(String id, String reason) {
    final dialog = state.dialog;
    if (dialog is! IncomingCallDialog ||
        dialog.pending.answerPending ||
        _acceptedCallId == id) {
      return Future.value();
    }
    return _control(id,
        (b) => b.callDecline(sessionId: sessionId, callId: id, reason: reason));
  }

  /// Closing is terminal intent even while accept is pending. Recheck the same
  /// call after that operation, then choose decline or hang-up from current state.
  Future<void> endCall(String id, String reason) => _endCall(id, reason);

  Future<void> _endCall(String id, String reason,
      {bool preserveError = false}) async {
    final canonical = await _controls.waitForCurrent(
        () => ref.mounted && _matchesEnd(id) ? state.dialog.callId : null);
    if (canonical == null) return;
    final dialog = state.dialog;
    final incoming = dialog is IncomingCallDialog &&
        !dialog.pending.answerPending &&
        _acceptedCallId != canonical;
    await _control(
        canonical,
        (b) => incoming
            ? b.callDecline(
                sessionId: sessionId,
                callId: canonical,
                reason: kCallDeclineReasonUser)
            : b.callEnd(
                sessionId: sessionId, callId: canonical, reason: reason),
        closing: true,
        preserveError: preserveError);
  }

  bool _matchesEnd(String id) =>
      state.dialog.callId == id || state.dialog.supersededCallId == id;

  Future<void> _control(String id, Future<void> Function(BridgeFacade) action,
      {bool terminal = true,
      bool closing = false,
      bool preserveError = false}) async {
    if (state.dialog.callId != id ||
        _controls.isBusy(id) ||
        (state.busy && !closing)) {
      return;
    }
    await _controls.run(id, () async {
      if (!preserveError) _error = null;
      state = _stateFor(_snapshot);
      try {
        await action(ref.read(bridgeFacadeProvider));
        if (!ref.mounted || state.dialog.callId != id) return;
        if (terminal) {
          _dismissedCallId = id;
        } else {
          _acceptedCallId = id;
        }
        state = _stateFor(_snapshot);
        _refresh();
      } catch (error) {
        if (!ref.mounted || state.dialog.callId != id) return;
        if (!preserveError) _fail(error, CallErrorSource.callControl);
      }
    });
    if (ref.mounted && state.dialog.callId == id) state = _stateFor(_snapshot);
  }

  void _refresh() {
    if (!ref.mounted) return;
    if (!_appOwned) ref.invalidate(activeSessionProvider(sessionId));
    ref.invalidate(conversationListProvider(ConversationKind.dm));
  }

  Ref get _bindingRef => ref;
  VoiceCallOrchestratorState get _view => state;
  void _publishMediaState() {
    if (ref.mounted) state = _stateFor(_snapshot);
  }

  void toggleMute() => _toggleMute();
  Future<void> toggleCamera() => _mediaCommand((s) => s.toggleCamera());
  Future<void> selectInput(String? id) =>
      _mediaCommand((s) => s.selectInput(id));
  Future<void> selectOutput(String? id) =>
      _mediaCommand((s) => s.selectOutput(id));
  Future<void> selectCamera(String? id) =>
      _mediaCommand((s) => s.selectCamera(id));

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
