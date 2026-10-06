import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show voiceCallOrchestratorProvider;

export 'call_clock.dart' show formatCallClock;

/// The active-call overlay tick interval.
const Duration kCallOverlayTickInterval = Duration(milliseconds: 500);

/// The active-call overlay.
///
/// The mute state lives in the orchestrator (the one home for call
/// decisions), so this widget is a `Consumer` that reads `muted` from
/// `voiceCallOrchestratorProvider(sessionId)` and calls its `toggleMute` --
/// the mic icon swaps live on tap with no re-mount of the overlay.
class CallOverlay extends ConsumerStatefulWidget {
  const CallOverlay({
    super.key,
    required this.active,
    required this.peerLabel,
    required this.sessionId,
    required this.onHangUp,
    required this.l,
    this.tickInterval = kCallOverlayTickInterval,
    this.now = _defaultNow,
  });

  /// The active call. `startedAtMs` anchors the running timer.
  final ActiveCall active;

  /// The peer's display label.
  final String peerLabel;

  /// The session the call belongs to -- the key the orchestrator is family'd
  /// by, so the overlay can read its mute flag.
  final String sessionId;

  /// Hangs up.
  final VoidCallback onHangUp;

  /// Localizations (callActiveAriaLabel / callActiveMute /
  /// callActiveUnmute / callActiveHangUp).
  final AppLocalizations l;

  /// The timer tick interval. Overridable so tests can advance the clock.
  final Duration tickInterval;

  /// The wall-clock function -- defaults to `DateTime.now().millisecondsSinceEpoch`.
  final int Function() now;

  static int _defaultNow() => DateTime.now().millisecondsSinceEpoch;

  @override
  ConsumerState<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends ConsumerState<CallOverlay> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceCallOrchestratorProvider(widget.sessionId));
    return CallView(
      call: CallViewState(
        sessionId: widget.sessionId,
        callId: widget.active.callId,
        peer: widget.peerLabel,
        phase: CallViewPhase.active,
        startedAtMs: widget.active.startedAtMs.toInt(),
        muted: state.muted,
        audioReady: state.audioReady,
        busy: state.busy,
      ),
      l: widget.l,
      tickInterval: widget.tickInterval,
      now: widget.now,
      onAction: (action) {
        if (action == CallViewAction.end) widget.onHangUp();
        if (action == CallViewAction.mute) {
          ref
              .read(voiceCallOrchestratorProvider(widget.sessionId).notifier)
              .toggleMute();
        }
      },
    );
  }
}
