import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/voice_call/call_button.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/features/voice_call/call_clock.dart'
    show formatCallClock;
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'call_video_renderer.dart';
import 'call_video_stage.dart';

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
    this.video,
  });

  final CallViewState call;
  final void Function(CallViewAction) onAction;
  final bool compact;
  final VoidCallback? onShowWindow;
  final AppLocalizations? l;
  final Duration tickInterval;
  final int Function() now;
  final ValueListenable<CallVideoImages>? video;
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

  void _end() => widget.onAction(
      widget.call.phase == CallViewPhase.incoming && !widget.call.busy
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
        CallViewPhase.confirming => l.callAnswerPending,
        CallViewPhase.outgoing => l.callOutgoingAriaLabel,
        CallViewPhase.active => l.callActiveAriaLabel,
      },
      peer: call.peer,
      status: _status(l),
      notice: call.occupancyConflict ? l.callOccupancyConflict : null,
      statusFontFeatures: active ? const [FontFeature.tabularFigures()] : null,
      onEscape: () => widget.onAction(CallViewAction.end),
      onOpenConversation: () =>
          widget.onAction(CallViewAction.openConversation),
      actions: _actions(l),
      stage: widget.video == null || widget.compact
          ? null
          : CallVideoStage(images: widget.video!, peer: call.peer),
    );
  }

  String _status(AppLocalizations l) {
    final call = widget.call;
    if (call.error != null) return call.error!;
    if (call.audioFailed) return l.callAudioFailed;
    if (call.phase == CallViewPhase.confirming) return l.callAnswerPending;
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
          color: call.muted ? MoshColors.info : MoshColors.bg3,
          foreground: call.muted ? MoshColors.bg0 : MoshColors.fg1,
          onPressed: call.busy || !call.audioReady
              ? null
              : () => widget.onAction(CallViewAction.mute),
        ),
      CallButton(
        icon: Icons.phone_disabled,
        tooltip: switch (call.phase) {
          CallViewPhase.incoming when call.busy => l.callOutgoingCancel,
          CallViewPhase.incoming => l.callIncomingDecline,
          CallViewPhase.outgoing => l.callOutgoingCancel,
          CallViewPhase.confirming => l.callOutgoingCancel,
          CallViewPhase.active => l.callActiveHangUp,
        },
        color: MoshColors.danger,
        foreground: MoshColors.bg0,
        onPressed: _end,
      ),
      if (call.phase == CallViewPhase.incoming)
        CallButton(
          icon: Icons.phone,
          tooltip: l.callIncomingAccept,
          color: MoshColors.moss,
          foreground: MoshColors.mossInk,
          onPressed:
              call.busy ? null : () => widget.onAction(CallViewAction.accept),
        ),
    ];
  }
}
