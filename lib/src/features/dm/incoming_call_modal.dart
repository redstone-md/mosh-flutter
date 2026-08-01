// IncomingCallModal -- 1-в-1 port of React `src/features/private-dm/
// voice-call/IncomingCallModal.tsx`. Shown when a session's
// `SessionSnapshot.pendingCall` is non-null: a centered modal card with
// the peer label, an "Incoming voice call..." status, and two round
// action buttons (decline red, accept green). On mount it starts a
// ringtone (via [RingtonePlayer]) and arms a 30 s no-answer timer; when
// the timer fires it calls `onDecline('no_answer')`. Esc calls
// `onDecline('declined')` (React's `useModalFocus(() => onDecline(
// 'declined'))`).
//
// React structure (IncomingCallModal.tsx):
//   .call-modal (role=dialog aria-modal aria-label="Incoming call"
//      tabIndex=-1) + useModalFocus(() => onDecline('declined'))
//     -> .call-modal-card (column, gap 18, padding 32/36, radius 14,
//        bg #1d1f24, min-width 280)
//        -> strong.call-modal-peer (peerLabel, 18px)
//        -> span.call-modal-status ("Incoming voice call...", 14px,
//           opacity .75)
//        -> .call-modal-actions (row, gap 16)
//           -> button.call-btn.call-btn-decline (IconPhoneOff 20,
//              aria-label "Decline call", onClick onDecline('declined'))
//           -> button.call-btn.call-btn-accept (IconPhone 20,
//              aria-label "Accept call", onClick onAccept)
//
// Flutter port: `showDialog` provides the `.call-modal` fixed overlay
// (rgba(0,0,0,0.55) barrier) + modal-route focus; the card mirrors
// `.call-modal-card` (dark #1d1f24, white text, 14 radius, 280 min-width,
// 32/36 padding, 18 gap). Round 48x48 buttons: decline #e5484d, accept
// #2ea043 (React's `call-btn-decline` / `call-btn-accept`). Esc is wired
// via `KeyboardListener` (the `useModalFocus` Esc-trap equivalent);
// `showDialog(barrierDismissible: true)` already maps outside-tap to
// pop, but the modal does NOT rely on that for decline -- the host
// routes barrier-dismiss through `onDecline` so a no-answer vs
// explicit-decline distinction survives.

library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/call_button.dart';
import 'package:mosh/src/features/dm/ringtone_player.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// React's `NO_ANSWER_TIMEOUT_MS` (call-state.ts). The incoming-call
/// modal auto-declines with `'no_answer'` after this long.
const Duration kIncomingNoAnswerTimeout = Duration(seconds: 30);

/// The decline reasons the modal emits -- mirror React's
/// `onDecline('declined')` / `onDecline('no_answer')` literals so the
/// orchestration layer can distinguish them.
const String kCallDeclineReasonUser = 'declined';
const String kCallDeclineReasonNoAnswer = 'no_answer';

/// The incoming-call modal -- 1-в-1 with React's `IncomingCallModal`.
///
/// Construct and pass to `showDialog` (the host owns the route). The
/// modal starts the ringtone + arms the no-answer timer in `initState`
/// and tears both down in `dispose`, mirroring React's `useEffect` cleanup.
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

  /// The pending incoming call (React `pending: PendingCall`).
  final PendingCall pending;

  /// The peer's display label (React `peerLabel: string`).
  final String peerLabel;

  /// Fired on the accept button (React `onAccept: () => void`).
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
    // React: `try { ringtoneRef.current = startRingtone() } catch { null }`.
    _ringtone = widget.ringtone.start();
    // React: `timerRef = setTimeout(() => onDecline('no_answer'), 30_000)`.
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
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      // React useModalFocus Esc -> onDecline('declined').
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _decline(kCallDeclineReasonUser);
        }
      },
      child: Semantics(
        label: widget.l.callIncomingAriaLabel,
        container: true,
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: const Color(0xFF1D1F24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // React strong.call-modal-peer (18px).
                  Text(
                    widget.peerLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  // React span.call-modal-status (14px, opacity .75).
                  Text(
                    widget.l.callIncomingStatus,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xBFFFFFFF),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // React .call-modal-actions (row, gap 16).
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CallButton(
                        icon: Icons.phone_disabled,
                        tooltip: widget.l.callIncomingDecline,
                        color: const Color(0xFFE5484D),
                        onPressed: () => _decline(kCallDeclineReasonUser),
                      ),
                      const SizedBox(width: 16),
                      CallButton(
                        icon: Icons.phone,
                        tooltip: widget.l.callIncomingAccept,
                        color: const Color(0xFF2EA043),
                        onPressed: widget.onAccept,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
