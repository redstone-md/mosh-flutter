import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'call_controls.dart';
import 'package:mosh/src/features/voice_call/call_modal_card.dart';
import 'package:mosh/src/features/voice_call/call_clock.dart'
    show formatCallClock;
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'call_video_textures.dart';
import 'call_window.dart';
import 'call_devices_dialog.dart';
import 'floating_call_view.dart';

/// Shared call presentation. It never creates an audio or signaling owner.
class CallView extends StatefulWidget {
  const CallView({
    super.key,
    required this.call,
    required this.onAction,
    this.compact = false,
    this.onExpand,
    this.onMinimize,
    this.floating = false,
    this.now = _now,
    this.video,
    this.onDeviceSelected,
    this.fullScreen,
  });

  final CallViewState call;
  final void Function(CallViewAction) onAction;
  final bool compact;
  final VoidCallback? onExpand;
  final VoidCallback? onMinimize;
  final bool floating;
  final int Function() now;
  final ValueListenable<CallVideoPictures>? video;
  final void Function(CallViewCommand)? onDeviceSelected;

  /// The desktop's full screen switch, shown by the open call.
  final CallFullScreen? fullScreen;
  static int _now() => DateTime.now().millisecondsSinceEpoch;

  @override
  State<CallView> createState() => _CallViewState();
}

class _CallViewState extends State<CallView> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
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
    final l = AppLocalizations.of(context)!;
    final call = widget.call;
    final active = call.phase == CallViewPhase.active;
    if (widget.floating && widget.video != null) {
      return FloatingCallView(
          call: call,
          video: widget.video!,
          onRestore: widget.onExpand,
          onEnd: () => widget.onAction(CallViewAction.end));
    }
    final label = switch (call.phase) {
      CallViewPhase.incoming => l.callIncomingAriaLabel,
      CallViewPhase.confirming => l.callAnswerPending,
      CallViewPhase.outgoing => l.callOutgoingAriaLabel,
      CallViewPhase.active => l.callActiveAriaLabel,
    };
    final figures = active ? const [FontFeature.tabularFigures()] : null;
    void openConversation() => widget.onAction(CallViewAction.openConversation);
    if (widget.compact) {
      return CallModalCard(
          singleLine: widget.onMinimize != null,
          label: label,
          peer: call.peer,
          status: _status(l),
          notice: _notice(l),
          statusFontFeatures: figures,
          onOpenConversation: openConversation,
          actions: callControls(call, l, widget.onAction,
              expand: widget.onExpand, camera: widget.onMinimize == null));
    }
    return CallWindow(
        label: label,
        peer: call.peer,
        status: _status(l),
        statusFontFeatures: figures,
        failed: call.audioFailed || call.error != null,
        muted: call.muted,
        notice: _notice(l),
        video: widget.video,
        remoteCamera: active && call.media?.remoteCamera == true,
        onOpenConversation: openConversation,
        onMinimize: widget.onMinimize,
        fullScreen: widget.fullScreen,
        buttons: ({required large}) => callControls(call, l, widget.onAction,
            large: large,
            devices: widget.onDeviceSelected == null
                ? null
                : () => unawaited(_devices())));
  }

  String _status(AppLocalizations l) {
    final call = widget.call;
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

  CallNotice? _notice(AppLocalizations l) {
    final call = widget.call;
    if (call.error case final error?) return CallNotice.error(error);
    if (call.occupancyConflict) {
      return CallNotice.warning(l.callOccupancyConflict);
    }
    if (call.media?.cameraFailed == true) {
      return CallNotice.warning(l.callCameraUnavailable);
    }
    if (call.phase == CallViewPhase.active &&
        call.media?.microphoneAvailable == false) {
      return CallNotice.warning(l.callMicrophoneUnavailable);
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
