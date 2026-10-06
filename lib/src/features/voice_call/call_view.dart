import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_button.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/features/voice_call/call_clock.dart'
    show formatCallClock;
import 'package:mosh/src/features/voice_call/call_view_state.dart';

/// Shared call presentation. It never creates an audio or signaling owner.
class CallView extends StatefulWidget {
  const CallView({
    super.key,
    required this.call,
    required this.onAction,
    this.compact = false,
    this.onShowWindow,
    this.l,
    this.tickInterval = const Duration(seconds: 1),
    this.now = _now,
  });

  final CallViewState call;
  final void Function(CallViewAction) onAction;
  final bool compact;
  final VoidCallback? onShowWindow;
  final AppLocalizations? l;
  final Duration tickInterval;
  final int Function() now;
  static int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(widget.tickInterval, (_) {
      if (widget.call.phase == CallViewPhase.active) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _end() => widget.onAction(widget.call.phase == CallViewPhase.incoming
      ? CallViewAction.decline
      : CallViewAction.end);

  @override
  Widget build(BuildContext context) {
    final l = widget.l ?? AppLocalizations.of(context)!;
    final call = widget.call;
    final active = call.phase == CallViewPhase.active;
    return CallModalCard(
      compact: widget.compact,
      label: switch (call.phase) {
        CallViewPhase.incoming => l.callIncomingAriaLabel,
        CallViewPhase.outgoing => l.callOutgoingAriaLabel,
        CallViewPhase.active => l.callActiveAriaLabel,
      },
      peer: call.peer,
      status: _status(l),
      statusFontFeatures: active ? const [FontFeature.tabularFigures()] : null,
      onEscape: () => widget.onAction(CallViewAction.end),
      onOpenConversation: () =>
          widget.onAction(CallViewAction.openConversation),
      actions: _actions(l),
    );
  }

  String _status(AppLocalizations l) {
    final call = widget.call;
    if (call.error != null) return call.error!;
    if (call.audioFailed) return l.callAudioFailed;
    if (call.phase != CallViewPhase.active) {
      return call.phase == CallViewPhase.incoming
          ? l.callIncomingStatus
          : l.callOutgoingStatus;
    }
    final clock = formatCallClock(BigInt.from(widget.now() - call.startedAtMs));
    return call.audioReady ? clock : "$clock · ${l.callAudioConnecting}";
  }

  List<Widget> _actions(AppLocalizations l) {
    final call = widget.call;
    final active = call.phase == CallViewPhase.active;
    return [
      if (widget.onShowWindow != null)
        IconButton(
            tooltip: l.callShowWindow,
            onPressed: widget.onShowWindow,
            icon: const Icon(Icons.open_in_new)),
      if (active)
        CallButton(
          icon: call.muted ? Icons.mic_off : Icons.mic,
          tooltip: call.muted ? l.callActiveUnmute : l.callActiveMute,
          color: call.muted ? const Color(0xFF4F8CFF) : const Color(0xFF2A2D33),
          onPressed: call.busy || !call.audioReady
              ? null
              : () => widget.onAction(CallViewAction.mute),
        ),
      CallButton(
        icon: Icons.phone_disabled,
        tooltip: switch (call.phase) {
          CallViewPhase.incoming => l.callIncomingDecline,
          CallViewPhase.outgoing => l.callOutgoingCancel,
          CallViewPhase.active => l.callActiveHangUp,
        },
        color: const Color(0xFFE5484D),
        onPressed: call.busy ? null : _end,
      ),
      if (call.phase == CallViewPhase.incoming)
        CallButton(
          icon: Icons.phone,
          tooltip: l.callIncomingAccept,
          color: const Color(0xFF2EA043),
          onPressed:
              call.busy ? null : () => widget.onAction(CallViewAction.accept),
        ),
    ];
  }
}
