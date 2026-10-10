import 'package:flutter/material.dart';
import 'package:mosh/l10n/app_localizations.dart';
import 'package:mosh/src/app/mosh_theme.dart';
import 'call_button.dart';
import 'call_view_state.dart';

List<Widget> callControls(CallViewState call, AppLocalizations l,
        void Function(CallViewAction) act,
        {VoidCallback? showWindow,
        VoidCallback? devices,
        bool controlsInWindow = false}) =>
    [
      if (showWindow != null)
        IconButton(
            tooltip: l.callShowWindow,
            onPressed: showWindow,
            icon: const Icon(Icons.open_in_new)),
      if (!controlsInWindow) ...[
        if (call.phase == CallViewPhase.active || call.media != null)
          _microphone(call, l, act),
        if (call.media != null) _camera(call, l, act),
        if (devices != null && call.media != null)
          CallButton(
              icon: Icons.tune,
              tooltip: l.callDevices,
              color: MoshColors.bg3,
              foreground: MoshColors.fg1,
              onPressed: call.busy ? null : devices),
        _end(call, l, act),
        if (call.phase == CallViewPhase.incoming)
          CallButton(
              icon: Icons.phone,
              tooltip: l.callIncomingAccept,
              color: MoshColors.moss,
              foreground: MoshColors.mossInk,
              onPressed: call.busy ? null : () => act(CallViewAction.accept)),
      ],
    ];

Widget _microphone(CallViewState call, AppLocalizations l,
        void Function(CallViewAction) act) =>
    CallButton(
        icon: call.muted ? Icons.mic_off : Icons.mic,
        tooltip: call.muted ? l.callActiveUnmute : l.callActiveMute,
        color: call.muted ? MoshColors.info : MoshColors.bg3,
        foreground: call.muted ? MoshColors.bg0 : MoshColors.fg1,
        toggled: !call.muted,
        onPressed: call.busy || (call.media == null && !call.audioReady)
            ? null
            : () => act(CallViewAction.mute));

Widget _camera(
    CallViewState call, AppLocalizations l, void Function(CallViewAction) act) {
  final media = call.media!;
  return CallButton(
      icon: media.cameraRequested ? Icons.videocam : Icons.videocam_off,
      tooltip: media.cameraStarting
          ? l.callCameraStarting
          : media.cameraRequested
              ? l.callCameraOff
              : l.callCameraOn,
      color: media.cameraRequested ? MoshColors.info : MoshColors.bg3,
      foreground: media.cameraRequested ? MoshColors.bg0 : MoshColors.fg1,
      toggled: media.cameraRequested,
      onPressed: call.busy ? null : () => act(CallViewAction.camera));
}

Widget _end(CallViewState call, AppLocalizations l,
        void Function(CallViewAction) act) =>
    CallButton(
        icon: Icons.phone_disabled,
        tooltip: switch (call.phase) {
          CallViewPhase.incoming when !call.busy => l.callIncomingDecline,
          CallViewPhase.active => l.callActiveHangUp,
          _ => l.callOutgoingCancel,
        },
        color: MoshColors.danger,
        foreground: MoshColors.bg0,
        onPressed: () => act(call.phase == CallViewPhase.incoming && !call.busy
            ? CallViewAction.decline
            : CallViewAction.end));
