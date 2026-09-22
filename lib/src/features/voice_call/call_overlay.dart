// CallOverlay -- the active-call overlay shown while a call is connected
// (`SessionSnapshot.activeCall` non-null): a centered card with the peer
// label, a running duration timer (m:ss, updated every 500 ms from
// `ActiveCall.startedAtMs`), and two 48px round buttons -- mute (blue
// #4f8cff when muted, neutral when not) + hang up (red #e5484d).
//
// The timer uses a 500 ms `Timer.periodic` to recompute `elapsed` from
// `active.startedAtMs`. The mute button swaps icon + tint based on
// `muted`.
//
// The mute state lives in the orchestrator (the one home for call
// decisions), so this widget is a `Consumer` that reads `muted` from
// `voiceCallOrchestratorProvider(sessionId)` and calls its `toggleMute` --
// the mic icon swaps live on tap with no re-mount of the overlay.

library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/modal_focus_trap.dart';
import 'package:mosh/src/features/voice_call/call_button.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';
import 'package:mosh/src/state/voice_call_orchestrator_provider.dart'
    show voiceCallOrchestratorProvider;

/// The active-call overlay tick interval.
const Duration kCallOverlayTickInterval = Duration(milliseconds: 500);

/// Formats an elapsed duration in milliseconds as `m:ss` with zero-padded
/// seconds.
String formatCallClock(BigInt elapsedMs) {
  final total =
      (elapsedMs <= BigInt.zero) ? 0 : (elapsedMs ~/ BigInt.from(1000)).toInt();
  final clamped = total < 0 ? 0 : total;
  final minutes = clamped ~/ 60;
  final seconds = clamped % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

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
  Timer? _ticker;
  late int _now;
  // Created once: rebuilding (the 500 ms timer tick, or a provider update)
  // must not dispose + recreate the focus node, or Esc would stop working
  // after the first frame.
  late final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _now = widget.now();
    _ticker = Timer.periodic(widget.tickInterval, (_) {
      if (!mounted) return;
      setState(() => _now = widget.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _hangUp() {
    if (!mounted) return;
    widget.onHangUp();
  }

  void _toggleMute() {
    if (!mounted) return;
    ref
        .read(voiceCallOrchestratorProvider(widget.sessionId).notifier)
        .toggleMute();
  }

  @override
  Widget build(BuildContext context) {
    final muted =
        ref.watch(voiceCallOrchestratorProvider(widget.sessionId)).muted;
    final startedMs = widget.active.startedAtMs.toInt();
    final elapsed = _now - startedMs;
    final clampedElapsed = elapsed < 0 ? BigInt.zero : BigInt.from(elapsed);
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _hangUp();
        }
      },
      child: Semantics(
        label: widget.l.callActiveAriaLabel,
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
                      formatCallClock(clampedElapsed),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xBFFFFFFF),
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CallButton(
                          icon: muted ? Icons.mic_off : Icons.mic,
                          tooltip: muted
                              ? widget.l.callActiveUnmute
                              : widget.l.callActiveMute,
                          color: muted
                              ? const Color(0xFF4F8CFF)
                              : const Color(0xFF2A2D33),
                          onPressed: _toggleMute,
                          iconSize: 18,
                        ),
                        const SizedBox(width: 16),
                        CallButton(
                          icon: Icons.phone_disabled,
                          tooltip: widget.l.callActiveHangUp,
                          color: const Color(0xFFE5484D),
                          onPressed: _hangUp,
                          iconSize: 18,
                        ),
                      ],
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
