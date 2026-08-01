// VoiceCallLayer -- the signaling-only wiring of the voice-call modals +
// overlay into the DM screen. 1-в-1 port of the modal/overlay render block
// in React `private-dm-screen.tsx` L459-513:
//   - pendingCallSession?.pending_call -> <IncomingCallModal .../>
//   - activeDmSession?.outgoing_call && !activeCall -> <OutgoingCallModal/>
//   - activeCall && activeCallSessionId && activeDmSession -> <CallOverlay/>
//
// React drives the modals from `useVoiceCallOrchestration` -- a state
// machine that ALSO pumps audio frames (callSendFrame/callDrainFrames at
// 20 ms + frame crypto + jitter). The audio transport is slice-3 work;
// this layer is the parity-first signaling surface: it watches
// `SessionSnapshot` and shows the modals/overlay so the call control +
// duration timer + accept/decline/cancel/hangup UI are testable without
// the runtime. Call control hits the `Gateway` seam (callStart/callAccept/
// callDecline/callEnd) and invalidates the per-session provider so the next
// poll reflects the new phase (ringing -> active -> ended).
//
// The layer is a `ConsumerStatefulWidget` placed in the DM body `Stack`
// (overlays nothing itself -- it routes through `showDialog`/`OverlayEntry`
// so the modals get the modal-route focus + scrim for free, mirroring
// React's `.call-modal` fixed overlay). It tracks which call id each modal
// is currently open for so a re-render with the same call does not
// re-mount the modal (React does this implicitly because the modal is
// keyed by the call id in the render tree).

library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/call_overlay.dart';
import 'package:mosh/src/features/dm/incoming_call_modal.dart';
import 'package:mosh/src/features/dm/outgoing_call_modal.dart';
import 'package:mosh/src/features/dm/ringtone_player.dart';
import 'package:mosh/src/gateway/gateway.dart' show Gateway;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/gateway_provider.dart';
import 'package:mosh/src/state/session_providers.dart';

/// Renders the voice-call modals/overlay for one DM session based on the
/// live `SessionSnapshot`. Place inside a `ProviderScope` + `Stack`.
class VoiceCallLayer extends ConsumerStatefulWidget {
  const VoiceCallLayer({
    super.key,
    required this.sessionId,
    required this.l,
    this.ringtone = const NoopRingtonePlayer(),
  });

  /// The DM session this layer watches.
  final String sessionId;

  /// Localizations (callIncoming* / callOutgoing* / callActive* /
  /// callPeerFallback).
  final AppLocalizations l;

  /// The ringtone player for the incoming/outgoing modals.
  final RingtonePlayer ringtone;

  @override
  ConsumerState<VoiceCallLayer> createState() => _VoiceCallLayerState();
}

class _VoiceCallLayerState extends ConsumerState<VoiceCallLayer> {
  // The call id each modal is currently open for, so a snapshot re-poll
  // does not re-mount an already-open modal (React keys by call id).
  String? _openIncomingFor;
  String? _openOutgoingFor;
  String? _openOverlayFor;
  // Whether the layer has already queued a callEnd for the active call
  // (avoids a double endCall if the snapshot re-polls before the overlay
  // closes).
  bool _activeCallEnded = false;

  Gateway _gateway() => ref.read(gatewayProvider);

  void _invalidateSession() =>
      ref.invalidate(activeSessionProvider(widget.sessionId));

  void _onError(Object? e) {
    // Surface a brief SnackBar so the user sees a failed call control;
    // React routes through `onError` -> an inline-error toast. Kept minimal
    // here; a richer error surface is a later atomic.
    if (!mounted) return;
    final msg = e == null ? 'Call failed' : e.toString();
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _acceptCall(String callId) async {
    try {
      await _gateway().callAccept(
        sessionId: widget.sessionId,
        callId: callId,
      );
      _invalidateSession();
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _declineCall(String callId, String reason) async {
    try {
      await _gateway().callDecline(
        sessionId: widget.sessionId,
        callId: callId,
        reason: reason,
      );
      _invalidateSession();
    } catch (e) {
      _onError(e);
    }
  }

  Future<void> _endCall(String callId, String reason) async {
    if (_activeCallEnded) return;
    _activeCallEnded = true;
    try {
      await _gateway().callEnd(
        sessionId: widget.sessionId,
        callId: callId,
        reason: reason,
      );
      _invalidateSession();
    } catch (e) {
      _onError(e);
    } finally {
      if (mounted) setState(() {});
    }
  }

  String _peerLabel(SessionSnapshot? s) =>
      (s == null || s.peerDisplayName.isEmpty)
          ? widget.l.callPeerFallback
          : s.peerDisplayName;

  @override
  Widget build(BuildContext context) {
    // Watch the per-session snapshot so a poll that flips pending -> active
    // closes the incoming modal + opens the overlay in the same frame.
    final async = ref.watch(activeSessionProvider(widget.sessionId));
    final s = async.value;

    // --- Incoming (pending_call) ---
    final pending = s?.pendingCall;
    if (pending != null && _openIncomingFor != pending.callId) {
      _openIncomingFor = pending.callId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => IncomingCallModal(
            pending: pending,
            peerLabel: pending.fromDevice.isEmpty
                ? widget.l.callPeerFallback
                : pending.fromDevice,
            onAccept: () {
              Navigator.of(dialogContext).pop();
              _acceptCall(pending.callId);
            },
            onDecline: (reason) {
              Navigator.of(dialogContext).pop();
              _declineCall(pending.callId, reason);
            },
            ringtone: widget.ringtone,
            l: widget.l,
          ),
        ).then((_) {
          if (mounted) setState(() => _openIncomingFor = null);
        });
      });
    } else if (pending == null && _openIncomingFor != null) {
      _openIncomingFor = null;
    }

    // --- Outgoing (outgoing_call, only when no active call) ---
    final outgoing = (s?.activeCall == null) ? s?.outgoingCall : null;
    if (outgoing != null && _openOutgoingFor != outgoing.callId) {
      _openOutgoingFor = outgoing.callId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => OutgoingCallModal(
            call: outgoing,
            peerLabel: _peerLabel(s),
            onCancel: () {
              Navigator.of(dialogContext).pop();
              _endCall(outgoing.callId, 'hangup');
            },
            ringtone: widget.ringtone,
            l: widget.l,
          ),
        ).then((_) {
          if (mounted) setState(() => _openOutgoingFor = null);
        });
      });
    } else if (outgoing == null && _openOutgoingFor != null) {
      _openOutgoingFor = null;
    }

    // --- Active (active_call) ---
    final active = s?.activeCall;
    if (active != null && _openOverlayFor != active.callId) {
      _openOverlayFor = active.callId;
      _activeCallEnded = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => CallOverlay(
            active: active,
            peerLabel: _peerLabel(s),
            muted: false,
            onToggleMute: () {
              // Mute is a local-only toggle until the audio transport
              // lands (slice-3); the overlay mirrors React's affordance.
            },
            onHangUp: () {
              Navigator.of(dialogContext).pop();
              _endCall(active.callId, 'hangup');
            },
            l: widget.l,
          ),
        ).then((_) {
          if (mounted) setState(() => _openOverlayFor = null);
        });
      });
    } else if (active == null && _openOverlayFor != null) {
      _openOverlayFor = null;
    }

    // The layer renders nothing itself -- the modals route through showDialog.
    return const SizedBox.shrink();
  }
}

/// Starts a voice call for [sessionId] via the `Gateway` seam. Exposed as
/// a top-level helper so the DM AppBar's start-call IconButton can trigger
/// a call without the layer owning the AppBar (the layer is body-local;
/// the AppBar lives on DmScreen). Returns the thrown error so the caller
/// can surface a SnackBar on its own `BuildContext` (avoiding the
/// use_build_context_synchronously lint for this fire-and-refresh helper).
Future<Object?> startVoiceCall(WidgetRef ref, String sessionId) async {
  try {
    await ref.read(gatewayProvider).callStart(sessionId: sessionId);
    ref.invalidate(activeSessionProvider(sessionId));
    return null;
  } catch (e) {
    return e;
  }
}
