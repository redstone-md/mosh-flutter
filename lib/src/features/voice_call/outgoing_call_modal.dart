import 'package:flutter/material.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
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
  Widget build(BuildContext context) => CallModalCard(
        label: widget.l.callOutgoingAriaLabel,
        peer: widget.peerLabel,
        status: widget.l.callOutgoingStatus,
        onEscape: _cancel,
        actions: [
          CallButton(
            icon: Icons.phone_disabled,
            tooltip: widget.l.callOutgoingCancel,
            color: const Color(0xFFE5484D),
            onPressed: _cancel,
          ),
        ],
      );
}
