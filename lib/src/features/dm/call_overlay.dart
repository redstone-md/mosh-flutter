// CallOverlay -- 1-в-1 port of React `src/features/private-dm/voice-call/
// CallOverlay.tsx`. The active-call overlay shown while a call is
// connected (`SessionSnapshot.activeCall` non-null): a centered card with
// the peer label, a running duration timer (m:ss, updated every 500 ms from
// `ActiveCall.startedAtMs`), and two 48px round buttons -- mute (blue
// #4f8cff when muted, neutral when not) + hang up (red #e5484d).
//
// React structure (CallOverlay.tsx):
//   .call-overlay (role=dialog aria-modal aria-label="Active call"
//      tabIndex=-1) + useModalFocus(onHangUp)
//     -> .call-overlay-card (column, gap 18, padding 32/36, radius 14,
//        bg #1d1f24, min-width 280)
//        -> strong.call-overlay-peer (peerLabel, 18px)
//        -> span.call-overlay-timer (formatClock(elapsed), 14px,
//           opacity .75, tabular-nums)
//        -> .call-overlay-actions (row, gap 16)
//           -> button.call-btn[.call-btn-muted] (IconMicrophone/Off 18,
//              aria-label Mute/Unmute, onClick onToggleMute)
//           -> button.call-btn.call-btn-decline (IconPhoneOff 18,
//              aria-label "Hang up", onClick onHangUp)
//
// Flutter port: `showDialog` overlay + the same dark card. The timer
// uses `Ticker`-style 500 ms `Timer.periodic` to recompute `elapsed`
// from `active.startedAtMs` (React's `setInterval(() => setNow(Date.now()),
// 500)`). `formatClock` mirrors React's `formatClock`. The mute button
// swaps icon + tint based on `muted` (React's conditional class + icon).

library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/dm/call_button.dart';
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

/// The active-call overlay tick interval -- mirrors React's
/// `setInterval(..., 500)`.
const Duration kCallOverlayTickInterval = Duration(milliseconds: 500);

/// Formats an elapsed duration in milliseconds as `m:ss` with zero-padded
/// seconds -- 1-в-1 with React's `formatClock` in CallOverlay.tsx.
String formatCallClock(BigInt elapsedMs) {
  final total = (elapsedMs <= BigInt.zero)
      ? 0
      : (elapsedMs ~/ BigInt.from(1000)).toInt();
  final clamped = total < 0 ? 0 : total;
  final minutes = clamped ~/ 60;
  final seconds = clamped % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// The active-call overlay -- 1-в-1 with React's `CallOverlay`.
class CallOverlay extends StatefulWidget {
  const CallOverlay({
    super.key,
    required this.active,
    required this.peerLabel,
    required this.muted,
    required this.onToggleMute,
    required this.onHangUp,
    required this.l,
    this.tickInterval = kCallOverlayTickInterval,
    this.now = _defaultNow,
  });

  /// The active call (React `active: ActiveCall`). `startedAtMs` anchors
  /// the running timer.
  final ActiveCall active;

  /// The peer's display label (React `peerLabel`).
  final String peerLabel;

  /// Whether the local mic is muted (React `muted`).
  final bool muted;

  /// Toggles mute (React `onToggleMute`).
  final VoidCallback onToggleMute;

  /// Hangs up (React `onHangUp`).
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
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  Timer? _ticker;
  late int _now;

  @override
  void initState() {
    super.initState();
    _now = widget.now();
    // React: `setInterval(() => setNow(Date.now()), 500)`.
    _ticker = Timer.periodic(widget.tickInterval, (_) {
      if (!mounted) return;
      setState(() => _now = widget.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

 void _hangUp() {
    if (!mounted) return;
    widget.onHangUp();
  }

  @override
  Widget build(BuildContext context) {
    final startedMs = widget.active.startedAtMs.toInt();
    final elapsed = _now - startedMs;
    final clampedElapsed = elapsed < 0 ? BigInt.zero : BigInt.from(elapsed);
    return KeyboardListener(
      focusNode: FocusNode(),
      autofocus: true,
      // React useModalFocus(onHangUp) Esc-trap.
      onKeyEvent: (event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _hangUp();
        }
      },
      child: Semantics(
        label: widget.l.callActiveAriaLabel,
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
                    // React `.call-overlay-timer` (tabular-nums, 14px).
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
                        icon:
                            widget.muted ? Icons.mic_off : Icons.mic,
                        tooltip: widget.muted
                            ? widget.l.callActiveUnmute
                            : widget.l.callActiveMute,
                        // React `.call-btn-muted` -> #4f8cff when muted;
                        // default neutral #2a2d33 when not.
                        color: widget.muted
                            ? const Color(0xFF4F8CFF)
                            : const Color(0xFF2A2D33),
                        onPressed: widget.onToggleMute,
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
    );
  }
}
