import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart';
import 'call_decline.dart';
import 'call_media_view.dart';
import 'call_view_state.dart';

/// What a call view shows of the call [state] of [sessionId], or null
/// without a call. [peerOverride] hides the name on a locked phone.
CallViewState? callViewOf(
        String sessionId, VoiceCallOrchestratorState state, AppLocalizations l,
        {String? peerOverride}) =>
    CallViewState.fromDialog(
      sessionId,
      state.dialog,
      fallback: l.callPeerFallback,
      peerOverride: peerOverride,
      muted: state.muted,
      media: state.nativeMedia == null
          ? null
          : CallMediaView.fromSnapshot(state.nativeMedia!,
              cameraRequested: state.cameraRequested),
      audioReady: state.audioReady,
      audioFailed: state.audioFailed,
      busy: state.busy,
      occupancyConflict: state.occupancyConflict,
      error: state.error?.cause.describe(l),
    );

/// Runs [command] on the call it was shown for. A press that arrives after
/// the call was replaced, or while its control is busy, does nothing.
void runCallCommand(WidgetRef ref, CallViewCommand command,
    {void Function()? onOpenConversation}) {
  final provider = voiceCallOrchestratorProvider(command.sessionId);
  final state = ref.read(provider);
  if ((state.busy && !command.action.availableWhileBusy) ||
      !command.matchesCall(command.sessionId, state.dialog.callId,
          supersededCallId: state.dialog.supersededCallId)) {
    return;
  }
  final notifier = ref.read(provider.notifier);
  final id = command.callId;
  switch (command.action) {
    case CallViewAction.accept:
      unawaited(notifier.acceptCall(id));
    case CallViewAction.decline:
      unawaited(notifier.declineCall(id, kCallDeclineReasonUser));
    case CallViewAction.end:
      unawaited(notifier.endCall(id, kCallDeclineReasonHangup));
    case CallViewAction.mute:
      notifier.toggleMute();
    case CallViewAction.camera:
      unawaited(notifier.toggleCamera());
    case CallViewAction.selectInput:
      unawaited(notifier.selectInput(command.deviceId));
    case CallViewAction.selectOutput:
      unawaited(notifier.selectOutput(command.deviceId));
    case CallViewAction.selectCamera:
      unawaited(notifier.selectCamera(command.deviceId));
    case CallViewAction.openConversation:
      onOpenConversation?.call();
  }
}
