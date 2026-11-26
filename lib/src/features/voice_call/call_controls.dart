import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_dimensions.dart';
import 'package:mosh/src/app/mosh_icons.dart';
import 'package:mosh/src/app/mosh_shapes.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'call_button.dart';
import 'call_view_state.dart';

/// The buttons of [call], in the order of the Call window card. A ringing
/// call offers only Decline and Accept. [large] is for a phone held upright.
List<Widget> callControls(
    CallViewState call, AppLocalizations l, void Function(CallViewAction) act,
    {VoidCallback? expand,
    VoidCallback? devices,
    bool camera = true,
    bool large = false}) {
  final ringing = call.phase == CallViewPhase.incoming;
  final media = !ringing && call.media != null;
  return [
    if (expand != null)
      IconButton(
          tooltip: l.callExpand,
          onPressed: expand,
          icon: const Icon(MoshIcons.callExpand)),
    if (call.phase == CallViewPhase.active || media)
      _microphone(call, l, act, large),
    if (camera && media) _camera(call, l, act, large),
    if (devices != null && media)
      CallButton(
          icon: MoshIcons.tune,
          tooltip: l.callDevices,
          large: large,
          onPressed: call.busy ? null : devices),
    _end(call, l, act, large),
    if (ringing)
      CallButton(
          icon: MoshIcons.call,
          tooltip: l.callIncomingAccept,
          tone: CallTone.accept,
          large: large,
          onPressed: call.busy ? null : () => act(CallViewAction.accept)),
  ];
}

Widget _microphone(CallViewState call, AppLocalizations l,
        void Function(CallViewAction) act, bool large) =>
    CallButton(
        icon: call.muted ? MoshIcons.micOff : MoshIcons.mic,
        tooltip: call.muted ? l.callActiveUnmute : l.callActiveMute,
        tone: call.muted ? CallTone.lit : CallTone.neutral,
        large: large,
        toggled: !call.muted,
        onPressed: call.busy || (call.media == null && !call.audioReady)
            ? null
            : () => act(CallViewAction.mute));

Widget _camera(CallViewState call, AppLocalizations l,
    void Function(CallViewAction) act, bool large) {
  final media = call.media!;
  return CallButton(
      icon: media.cameraRequested ? MoshIcons.video : MoshIcons.videoOff,
      tooltip: media.cameraStarting
          ? l.callCameraStarting
          : media.cameraRequested
              ? l.callCameraOff
              : l.callCameraOn,
      tone: media.cameraRequested ? CallTone.lit : CallTone.neutral,
      large: large,
      toggled: media.cameraRequested,
      onPressed: call.busy ? null : () => act(CallViewAction.camera));
}

Widget _end(CallViewState call, AppLocalizations l,
        void Function(CallViewAction) act, bool large) =>
    CallButton(
        icon: MoshIcons.callEnd,
        tooltip: switch (call.phase) {
          CallViewPhase.incoming when !call.busy => l.callIncomingDecline,
          CallViewPhase.active => l.callActiveHangUp,
          _ => l.callOutgoingCancel,
        },
        tone: CallTone.end,
        large: large,
        onPressed: () => act(call.phase == CallViewPhase.incoming && !call.busy
            ? CallViewAction.decline
            : CallViewAction.end));

/// The dock of a call: its buttons on a plate of their own, so none of them
/// ever lies on the video itself and the red one reads the same over any
/// picture.
class CallDock extends StatelessWidget {
  const CallDock({super.key, required this.buttons, this.large = false});

  final List<Widget> buttons;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = MoshColors.of(context);
    return DecoratedBox(
      decoration: MoshLevel.popup
          .decoration(colors)
          .copyWith(borderRadius: MoshShapes.pillCorners),
      child: Padding(
        padding: const EdgeInsets.all(MoshSpace.s3),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: large ? MoshSpace.s4 : MoshSpace.s3,
            children: buttons),
      ),
    );
  }
}
