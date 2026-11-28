import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'call_button.dart';
import 'call_view_state.dart';

/// The buttons [call] offers, each by what it does. A ringing call offers
/// only to end and to accept it; the camera and the devices need the call's
/// media, and the devices a dialog to open ([devices]).
class CallControls {
  factory CallControls(
      CallViewState call, AppLocalizations l, void Function(CallViewAction) act,
      {VoidCallback? devices}) {
    final ringing = call.phase == CallViewPhase.incoming;
    final media = !ringing && call.media != null;
    return CallControls._(
      microphone: call.phase == CallViewPhase.active || media
          ? _microphone(call, l, act)
          : null,
      camera: media ? _camera(call, l, act) : null,
      devices: devices != null && media
          ? CallControl(
              icon: MoshIcons.tune,
              tooltip: l.callDevices,
              onPressed: call.busy ? null : devices)
          : null,
      end: _end(call, l, act),
      accept: ringing
          ? CallControl(
              icon: MoshIcons.call,
              tooltip: l.callIncomingAccept,
              tone: CallTone.accept,
              onPressed: call.busy ? null : () => act(CallViewAction.accept))
          : null,
    );
  }

  const CallControls._(
      {required this.end,
      this.microphone,
      this.camera,
      this.devices,
      this.accept});

  final CallControl? microphone, camera, devices, accept;

  /// Declines a ringing call, cancels an outgoing one or hangs up.
  final CallControl end;

  /// The open call's dock, in the order of the Call window card.
  List<CallControl> get dock =>
      _present([microphone, camera, devices, end, accept]);

  /// What a minimized call has room for.
  List<CallControl> get minimized => _present([microphone, end, accept]);

  static List<CallControl> _present(List<CallControl?> controls) =>
      controls.nonNulls.toList();
}

CallControl _microphone(CallViewState call, AppLocalizations l,
        void Function(CallViewAction) act) =>
    CallControl(
        icon: call.muted ? MoshIcons.micOff : MoshIcons.mic,
        tooltip: call.muted ? l.callActiveUnmute : l.callActiveMute,
        tone: call.muted ? CallTone.lit : CallTone.neutral,
        toggled: !call.muted,
        onPressed: call.busy || (call.media == null && !call.audioReady)
            ? null
            : () => act(CallViewAction.mute));

CallControl _camera(
    CallViewState call, AppLocalizations l, void Function(CallViewAction) act) {
  final media = call.media!;
  return CallControl(
      icon: media.cameraRequested ? MoshIcons.video : MoshIcons.videoOff,
      tooltip: media.cameraStarting
          ? l.callCameraStarting
          : media.cameraRequested
              ? l.callCameraOff
              : l.callCameraOn,
      tone: media.cameraRequested ? CallTone.lit : CallTone.neutral,
      toggled: media.cameraRequested,
      onPressed: call.busy ? null : () => act(CallViewAction.camera));
}

CallControl _end(CallViewState call, AppLocalizations l,
        void Function(CallViewAction) act) =>
    CallControl(
        icon: MoshIcons.callEnd,
        tooltip: switch (call.phase) {
          CallViewPhase.incoming when !call.busy => l.callIncomingDecline,
          CallViewPhase.active => l.callActiveHangUp,
          _ => l.callOutgoingCancel,
        },
        tone: CallTone.end,
        onPressed: () => act(call.phase == CallViewPhase.incoming && !call.busy
            ? CallViewAction.decline
            : CallViewAction.end));

/// The dock of a call: its buttons on a plate of their own, so none of them
/// ever lies on the video itself and the red one reads the same over any
/// picture.
class CallDock extends StatelessWidget {
  const CallDock({super.key, required this.controls, this.large = false});

  final List<CallControl> controls;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    // A Container, so the plate's edge takes room of its own around the
    // padding, as it does on the card.
    return Container(
      decoration: MoshLevel.popup
          .decoration(colors)
          .copyWith(borderRadius: MoshShapes.pillCorners),
      padding: const EdgeInsets.all(MoshSpace.s3),
      child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: large ? MoshSpace.s4 : MoshSpace.s3,
          children: [
            for (final control in controls)
              CallButton(control: control, large: large)
          ]),
    );
  }
}
