// Figma capture of voice and video calls: the DM's call history, incoming,
// outgoing and active calls in the main window, their media states, the
// devices dialog and the minimized and floating views.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/voice_call/android_call_presentation.dart';
import 'package:mosh/src/features/voice_call/call_window.dart'
    show kCallControlsRest;
import 'package:mosh/src/routing/app_router.dart';
import 'package:mosh/src/rust/native_call/types.dart' as native;
import 'package:mosh/src/rust/private_dm_runtime/contracts.dart';

import '../../../test/support/scriptable_bridge.dart';
import 'calls_rig.dart';
import 'harness.dart';

const _video = 'Video surfaces export as black placeholders.';
const _ringing =
    PendingCall(callId: callId, fromDevice: 'Maya Chen', answerPending: false);

/// An active call with [media], expanded unless [minimize].
Future<void> _active(WidgetTester tester, Size size,
    {native.Snapshot? media,
    bool minimize = false,
    String? location,
    CallAvailability? availability,
    void Function(ScriptableBridge)? script}) async {
  await openCall(tester, size,
      active: activeCall(),
      media: media,
      location: location,
      availability: availability,
      script: script);
  if (minimize) await tapCall(tester, 'Minimize call');
}

FigmaScene _media(String id, String state, native.Snapshot media,
        {String? note}) =>
    FigmaScene(id, 'Calls / Active / $state',
        (tester, size) => _active(tester, size, media: media),
        note: note);

void main() {
  figmaScenes('calls', [
    FigmaScene('history', 'Calls / DM / Call history', (tester, size) async {
      await openCall(tester, size);
    }),
    FigmaScene('incoming-mini', 'Calls / Incoming / Mini view',
        (tester, size) async {
      await openCall(tester, size, pending: _ringing);
      // Desktop rings in the mini view; a phone opens the call expanded.
      if (size != FigmaDevice.desktop.size) {
        await tapCall(tester, 'Minimize call');
      }
    }),
    FigmaScene('incoming', 'Calls / Incoming / Ringing', (tester, size) async {
      await openCall(tester, size, pending: _ringing);
      if (size == FigmaDevice.desktop.size) {
        await tapCall(tester, 'Expand call');
      }
    }),
    FigmaScene(
        'incoming-confirming', 'Calls / Incoming / Waiting for confirmation',
        (tester, size) async {
      await openCall(tester, size,
          pending: const PendingCall(
              callId: callId, fromDevice: 'Maya Chen', answerPending: true));
    }),
    FigmaScene('outgoing', 'Calls / Outgoing / Calling', (tester, size) async {
      await openCall(tester, size,
          outgoing: const OutgoingCall(callId: callId));
    }),
    FigmaScene('outgoing-mini', 'Calls / Outgoing / Mini view',
        (tester, size) async {
      await openCall(tester, size,
          outgoing: const OutgoingCall(callId: callId));
      await tapCall(tester, 'Minimize call');
    }),
    _media('active-connecting', 'Connecting audio', callMedia(ready: false)),
    _media('active-voice', 'Voice', callMedia()),
    _media('active-muted', 'Muted', callMedia(microphone: false)),
    _media('active-mic-unavailable', 'Microphone unavailable',
        callMedia(microphone: false, microphoneAvailable: false),
        note: 'What a refused or missing microphone leaves; the permission '
            'prompt itself is the operating system\'s.'),
    _media(
        'active-reconnecting', 'Reconnecting', callMedia(reconnecting: true)),
    _media('active-waiting-video', 'Waiting for video',
        callMedia(remoteCamera: true)),
    _media('active-remote-video', 'Remote video',
        callMedia(remoteCamera: true, remoteFrames: true),
        note: _video),
    _media('active-camera', 'Camera preview', callMedia(camera: true),
        note: _video),
    _media('active-two-way-video', 'Two-way video',
        callMedia(camera: true, remoteCamera: true, remoteFrames: true),
        note: _video),
    for (final (id, state, muted) in const [
      ('active-controls-hidden', 'Controls hidden', false),
      ('active-controls-hidden-muted', 'Controls hidden and muted', true),
    ])
      FigmaScene(id, 'Calls / Active / $state', (tester, size) async {
        await _active(tester, size,
            media: callMedia(
                camera: true,
                remoteCamera: true,
                remoteFrames: true,
                microphone: !muted));
        // The call left alone: everything over the video but your own
        // camera leaves after three seconds.
        await tester.pump(kCallControlsRest);
        await settleCall(tester);
      }, note: _video),
    _media('active-camera-failed', 'Camera unavailable',
        callMedia(cameraFailed: true)),
    FigmaScene('active-audio-failed', 'Calls / Active / Audio failed',
        (tester, size) async {
      await _active(tester, size,
          script: (bridge) => bridge.failNext(BridgeMethod.nativeCallPrepare,
              error: 'Microphone is in use by another app'));
    }),
    FigmaScene('active-occupancy', 'Calls / Active / Calls on another device',
        (tester, size) async {
      await _active(tester, size, availability: CallAvailability.conflict);
    }),
    FigmaScene('devices', 'Calls / Devices / Dialog', (tester, size) async {
      await _active(tester, size, media: callMedia(camera: true));
      await tapCall(tester, 'Call devices');
    }),
    FigmaScene('devices-microphone', 'Calls / Devices / Microphone picker',
        (tester, size) async {
      await _active(tester, size);
      await tapCall(tester, 'Call devices');
      final select = find.byType(MoshSelect<String?>).first;
      if (size == FigmaDevice.desktop.size) {
        // Tests run as Android, where the select opens a sheet; a desktop
        // opens its popover menu, as the button does there.
        MenuController.maybeOf(tester.element(find.descendant(
                of: select, matching: find.byType(OutlinedButton))))!
            .open();
      } else {
        await tester.tap(select);
      }
      await tester.pump();
      await settleCall(tester);
    }),
    FigmaScene('active-mini', 'Calls / Mini view / Voice',
        (tester, size) async {
      await _active(tester, size, minimize: true);
    }),
    FigmaScene('active-mini-chats', 'Calls / Mini view / Over chat list',
        (tester, size) async {
      await _active(tester, size, minimize: true, location: AppRoutes.sessions);
    }),
    FigmaScene('floating-video', 'Calls / Mini view / Floating video',
        (tester, size) async {
      await _active(tester, size,
          media: callMedia(remoteCamera: true, remoteFrames: true),
          minimize: true);
    }, note: _video),
    FigmaScene('android-pip', 'Calls / Android / Picture in picture',
        (tester, size) async {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          AndroidCallPresentation.channel, (_) async => null);
      final presentation = AndroidCallPresentation();
      addTearDown(() {
        presentation.dispose();
        messenger.setMockMethodCallHandler(
            AndroidCallPresentation.channel, null);
      });
      await openCall(tester, size,
          active: activeCall(),
          media: callMedia(remoteCamera: true, remoteFrames: true),
          extra: [
            androidCallPresentationProvider.overrideWithValue(presentation)
          ]);
      // Android reports the Activity entering picture-in-picture, then
      // shrinks the window to it.
      await messenger.handlePlatformMessage(
          AndroidCallPresentation.channel.name,
          const StandardMethodCodec().encodeMethodCall(MethodCall('mode',
              {'call': '$callSession/$callId', 'pip': true, 'generation': 1})),
          (_) {});
      tester.view.physicalSize = const Size(256, 144);
      await tester.pump();
      await settleCall(tester);
    }, devices: const [FigmaDevice.mobile], note: _video),
    FigmaScene('start-busy', 'Calls / Start / Already in a call',
        (tester, size) async {
      await _active(tester, size,
          minimize: true, location: AppRoutes.dmFor('leo'));
      // The mini view sits over the header on desktop, so press the
      // header's button directly.
      final start = find.ancestor(
          of: find.byTooltip('Start voice call'),
          matching: find.byType(IconButton));
      tester.widget<IconButton>(start.first).onPressed!();
      await tester.pump();
      await settleCall(tester);
    }),
  ]);
}
