import 'dart:async';
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/features/shared/mosh_notice.dart' show MoshNoticeTone;
import 'call_controls.dart';
import 'call_notice.dart';
import 'call_plate.dart';
import 'call_strip.dart';
import 'call_who_line.dart';
import 'incoming_call_card.dart';
import 'call_window_parts.dart' show CallFullScreen;
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
    this.form = CallForm.open,
    this.onOpen,
    this.onMinimize,
    this.now = _now,
    this.video,
    this.onDeviceSelected,
    this.fullScreen,
  });

  final CallViewState call;
  final void Function(CallViewAction) onAction;
  final CallForm form;

  /// Opens a minimized call over the window. Without it a press on the
  /// strip's name opens the conversation, as the strip under an app without
  /// the call engine does.
  final VoidCallback? onOpen;
  final VoidCallback? onMinimize;
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
    final label = switch (call.phase) {
      CallViewPhase.incoming => l.callIncomingAriaLabel,
      CallViewPhase.confirming => l.callAnswerPending,
      CallViewPhase.outgoing => l.callOutgoingAriaLabel,
      CallViewPhase.active => l.callActiveAriaLabel,
    };
    final figures = active ? const [FontFeature.tabularFigures()] : null;
    void openConversation() => widget.onAction(CallViewAction.openConversation);
    if (widget.form != CallForm.open) {
      return _minimized(l, label, figures, openConversation);
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
        controls: CallControls(call, l, widget.onAction,
                devices: widget.onDeviceSelected == null
                    ? null
                    : () => unawaited(_devices()))
            .dock);
  }

  /// The call beside the chats, in the shape of [CallView.form].
  Widget _minimized(AppLocalizations l, String label,
      List<FontFeature>? figures, VoidCallback openConversation) {
    final call = widget.call;
    final controls = CallControls(call, l, widget.onAction);
    final video = widget.video;
    if (widget.form == CallForm.tile && video != null) {
      return FloatingCallView(
          peer: call.peer,
          remoteCamera: call.media?.remoteCamera == true,
          video: video,
          onOpen: widget.onOpen,
          end: controls.end);
    }
    if (widget.form == CallForm.card) {
      return IncomingCallCard(
          label: label,
          peer: call.peer,
          status: _status(l),
          decline: controls.end,
          accept: controls.accept,
          onOpen: widget.onOpen);
    }
    final line = _line(l, figures);
    return widget.form == CallForm.plate
        ? CallPlate(
            label: label,
            peer: call.peer,
            line: line,
            controls: controls.minimized,
            onOpen: widget.onOpen)
        : CallStrip(
            label: label,
            peer: call.peer,
            line: line,
            controls: controls.minimized,
            onOpen: widget.onOpen ?? openConversation,
            openTooltip: widget.onOpen == null ? null : l.callExpand);
  }

  /// What a minimized call says beside the name: a warning or an error in
  /// place of how the call is going, since it has one line for both.
  CallLine _line(AppLocalizations l, List<FontFeature>? figures) {
    if (_notice(l) case final notice?) {
      return CallLine(notice.text, tone: notice.tone);
    }
    final status = _status(l);
    // Failed audio is the status itself, in the tone the open call gives it.
    if (widget.call.audioFailed) {
      return CallLine(status, tone: MoshNoticeTone.error);
    }
    final muted =
        widget.call.phase == CallViewPhase.active && widget.call.muted;
    return CallLine(muted ? "$status · ${l.callMuted}" : status,
        fontFeatures: figures);
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
