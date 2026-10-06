import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The app's one no-answer window: an incoming call the local user never
/// picks up is declined with `'no_answer'` once it elapses.
///
/// The callee half of a pair agreed with mosh-core. The caller's budget is
/// `CALL_RING_TIMEOUT_MS` (`mosh-core/src/private_dm_runtime.rs`): it
/// re-offers every `CALL_RESEND_MS` and ends the call with the same
/// `"no_answer"` reason once the budget is spent. This side is deliberately
/// the shorter of the two, so on a healthy link the callee's real decline
/// reaches the caller before the caller gives up on its own -- the budget
/// is the backstop for a lost decline, not a competing deadline. Change the
/// two together.
const Duration kIncomingNoAnswerTimeout = Duration(milliseconds: 30000);

/// The decline reasons the modal emits, so the orchestration layer can
/// distinguish a user decline from a no-answer timeout.
const String kCallDeclineReasonUser = 'declined';
const String kCallDeclineReasonNoAnswer = 'no_answer';

/// The reason the layer emits when the user cancels an outgoing call or
/// hangs up an active one from the modal/overlay controls. Kept as a
/// named constant so the "string literals forbidden" standard holds and
/// the reason stays distinguishable from a real decline.
const String kCallDeclineReasonHangup = 'hangup';

/// The incoming-call modal. Construct and pass to `showDialog` (the host
/// owns the route). The modal starts the ringtone + arms the no-answer
/// timer in `initState` and tears both down in `dispose`.
class IncomingCallModal extends StatefulWidget {
  const IncomingCallModal({
    super.key,
    required this.pending,
    required this.peerLabel,
    required this.onAccept,
    required this.onDecline,
    required this.l,
    this.ringtone = const NoopRingtonePlayer(),
    this.noAnswerTimeout = kIncomingNoAnswerTimeout,
  });

  /// The pending incoming call.
  final PendingCall pending;

  /// The peer's display label.
  final String peerLabel;

  /// Fired on the accept button.
  final VoidCallback onAccept;

  /// Fired on decline (button/Esc) or no-answer timeout, with the
  /// reason literal (`'declined'` or `'no_answer'`).
  final void Function(String reason) onDecline;

  /// Localizations (callIncomingAriaLabel / callIncomingStatus /
  /// callIncomingAccept / callIncomingDecline).
  final AppLocalizations l;

  /// The ringtone player. Defaults to [NoopRingtonePlayer] (no audio in
  /// tests); DmScreen injects the real synth once it lands.
  final RingtonePlayer ringtone;

  /// The no-answer timeout. Overridable so tests can fire it instantly.
  final Duration noAnswerTimeout;

  @override
  State<IncomingCallModal> createState() => _IncomingCallModalState();
}

class _IncomingCallModalState extends State<IncomingCallModal> {
  RingtoneHandle? _ringtone;
  Timer? _noAnswerTimer;

  @override
  void initState() {
    super.initState();
    // Ringtone start is best-effort: a failure leaves it silent.
    try {
      _ringtone = widget.ringtone.start();
    } catch (_) {
      _ringtone = null;
    }
    _noAnswerTimer = Timer(
      widget.noAnswerTimeout,
      () => _decline(kCallDeclineReasonNoAnswer),
    );
  }

  @override
  void dispose() {
    _noAnswerTimer?.cancel();
    _ringtone?.stop();
    _ringtone = null;
    super.dispose();
  }

  void _decline(String reason) {
    if (!mounted) return;
    widget.onDecline(reason);
  }

  @override
  Widget build(BuildContext context) => CallView(
        call: CallViewState(
            sessionId: '',
            callId: widget.pending.callId,
            peer: widget.peerLabel,
            phase: CallViewPhase.incoming),
        l: widget.l,
        onAction: (action) {
          if (action == CallViewAction.accept) widget.onAccept();
          if (action == CallViewAction.decline) {
            _decline(kCallDeclineReasonUser);
          }
        },
      );
}
