import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'call_controls.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/features/voice_call/call_clock.dart'
    show formatCallClock;
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'call_video_renderer.dart';
import 'call_video_stage.dart';
import 'call_devices_dialog.dart';

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
    this.onDeviceSelected,
  });

  final CallViewState call;
  final void Function(CallViewAction) onAction;
  final bool compact;
  final VoidCallback? onShowWindow;
  final AppLocalizations? l;
  final Duration tickInterval;
  final int Function() now;
  final ValueListenable<CallVideoImages>? video;
  final void Function(CallViewCommand)? onDeviceSelected;
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
      notice: _notice(l),
      statusFontFeatures: active ? const [FontFeature.tabularFigures()] : null,
      onEscape: () => widget.onAction(CallViewAction.end),
      onOpenConversation: () =>
          widget.onAction(CallViewAction.openConversation),
      actions: callControls(call, l, widget.onAction,
          showWindow: widget.onShowWindow,
          devices: widget.compact || widget.onDeviceSelected == null
              ? null
              : () => unawaited(_devices())),
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
    if (call.media?.reconnecting == true) {
      return "$clock · ${l.callReconnecting}";
    }
    return call.audioReady ? clock : "$clock · ${l.callAudioConnecting}";
  }

  String? _notice(AppLocalizations l) {
    final call = widget.call;
    if (call.occupancyConflict) return l.callOccupancyConflict;
    if (call.media?.cameraFailed == true) return l.callCameraUnavailable;
    if (call.phase == CallViewPhase.active &&
        call.media?.microphoneAvailable == false) {
      return l.callMicrophoneUnavailable;
    }
    return null;
  }

  Future<void> _devices() async {
    final shown = widget.call;
    final command = await showCallDevices(context, shown);
    if (mounted &&
        command != null &&
        command.matchesCall(widget.call.sessionId, widget.call.callId)) {
      widget.onDeviceSelected?.call(command);
    }
  }
}
