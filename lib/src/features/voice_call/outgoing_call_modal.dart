// OutgoingCallModal -- shown on the caller side while waiting for the peer
// to answer (`SessionSnapshot.outgoingCall` non-null): a centered modal
// card with the peer label, a "Calling..." status, and a single round
// cancel/hang-up button (decline red). On mount it starts a ringtone
// (dial tone, reusing the ringtone synth); the active-call overlay takes
// over once the peer accepts.
//
// The modal itself has no dial timeout -- the orchestration layer can
// cancel after a dial-timeout; the modal just rings until cancelled. Esc
// maps to cancel via KeyboardListener.

library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/features/voice_call/call_button.dart';
import 'package:mosh/src/features/voice_call/ringtone_player.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The outgoing-call "ringing" modal. Construct and pass to `showDialog`.
class OutgoingCallModal extends StatefulWidget {
  const OutgoingCallModal({
    super.key,
    required this.call,
    required this.peerLabel,
    required this.onCancel,
    required this.l,
    this.ringtone = const NoopRingtonePlayer(),
  });

  /// The outgoing call -- used only as the mount identity so the ringtone
  /// restarts if the call id changes.
  final OutgoingCall call;

  /// The peer's display label.
  final String peerLabel;

  /// Fired on the cancel button or Esc.
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
    // Ringtone start is best-effort: a failure leaves it silent.
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
