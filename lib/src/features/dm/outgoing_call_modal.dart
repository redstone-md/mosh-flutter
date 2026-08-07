// OutgoingCallModal -- 1-в-1 port of React `src/features/private-dm/
// voice-call/OutgoingCallModal.tsx`. Shown on the caller side while
// waiting for the peer to answer (`SessionSnapshot.outgoingCall`
// non-null): a centered modal card with the peer label, a "Calling..."
// status, and a single round cancel/hang-up button (decline red). On
// mount it starts a ringtone (dial tone, reusing the ringtone synth);
// the active-call overlay takes over once the peer accepts.
//
// React structure (OutgoingCallModal.tsx):
//   .call-modal (role=dialog aria-modal aria-label="Outgoing call"
//      tabIndex=-1) + useModalFocus(onCancel)
//     -> .call-modal-card (same shape as IncomingCallModal)
//        -> strong.call-modal-peer (peerLabel, 18px)
//        -> span.call-modal-status ("Calling...", 14px, opacity .75)
//        -> .call-modal-actions (row, gap 16)
//           -> button.call-btn.call-btn-decline (IconPhoneOff 20,
//              aria-label "Cancel call", onClick onCancel)
//
// Flutter port: mirrors IncomingCallModal's card + button, minus the
// accept button + the no-answer timer (React's outgoing modal has no
// NO_ANSWER_TIMEOUT -- the orchestration layer can cancel after a
// dial-timeout, but the modal itself just rings until onCancel). Esc
// maps to onCancel via KeyboardListener (React useModalFocus(onCancel)).

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/features/dm/call_button.dart';
import 'package:mosh/src/features/dm/ringtone_player.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The outgoing-call "ringing" modal -- 1-в-1 with React's
/// `OutgoingCallModal`. Construct and pass to `showDialog`.
class OutgoingCallModal extends StatefulWidget {
  const OutgoingCallModal({
    super.key,
    required this.call,
    required this.peerLabel,
    required this.onCancel,
    required this.l,
    this.ringtone = const NoopRingtonePlayer(),
  });

  /// The outgoing call (React `callId: string`; the Flutter contract is
  /// `OutgoingCall { callId }` -- used only as the mount identity so the
  /// ringtone effect re-runs if the call id changes).
  final OutgoingCall call;

  /// The peer's display label (React `peerLabel`).
  final String peerLabel;

  /// Fired on the cancel button or Esc (React `onCancel`).
  final VoidCallback onCancel;

  /// Localizations (callOutgoingAriaLabel / callOutgoingStatus /
  /// callOutgoingCancel).
  final AppLocalizations l;

  /// The ringtone player (dial tone). Defaults to [NoopRingtonePlayer].
  final RingtonePlayer ringtone;

  @override
  State<OutgoingCallModal> createState() => _OutgoingCallModalState();
}

class _OutgoingCallModalState extends State<OutgoingCallModal> {
  RingtoneHandle? _ringtone;

  @override
  void initState() {
    super.initState();
    // React: `ringtoneRef.current = startRingtone()` in a try/catch.
    try {
      _ringtone = widget.ringtone.start();
    } catch (_) {
      _ringtone = null;
    }
  }

  @override
  void dispose() {
    _ringtone?.stop();
    _ringtone = null;
    super.dispose();
  }

  void _cancel() {
    if (!mounted) return;
    widget.onCancel();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      // React useModalFocus(onCancel) Esc-trap.
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancel();
        }
      },
      child: Semantics(
        label: widget.l.callOutgoingAriaLabel,
        container: true,
        // ModalFocusTrap goes inside Semantics and KeyboardListener so Tab key events are handled
        // by the trap, while Escape is caught first by the outer KeyboardListener.
        child: ModalFocusTrap(
          child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            backgroundColor: const Color(0xFF1D1F24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 280),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      widget.peerLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      widget.l.callOutgoingStatus,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xBFFFFFFF),
                      ),
                    ),
                    const SizedBox(height: 18),
                    CallButton(
                      icon: Icons.phone_disabled,
                      tooltip: widget.l.callOutgoingCancel,
                      color: const Color(0xFFE5484D),
                      onPressed: _cancel,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
