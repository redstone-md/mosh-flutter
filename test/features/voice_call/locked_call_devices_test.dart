import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/app/mosh_select.dart';
import 'package:mosh/src/features/lock/app_lock_route_observer.dart';
import 'package:mosh/src/features/voice_call/call_devices_dialog.dart';
import 'package:mosh/src/features/voice_call/call_media_view.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import '../../support/pump.dart';

void main() {
  testWidgets(
      'locked Android call can select its speaker from the device sheet',
      (tester) async {
    final observer = AppLockRouteObserver()..setLocked(true);
    CallViewCommand? selected;
    await pumpScreen(tester, Scaffold(body: Builder(builder: (context) {
      return TextButton(
          onPressed: () => unawaited(showCallDevices(context, _call)
              .then((value) => selected = value)),
          child: const Text('Devices'));
    })), observers: [observer]);
    await tester.tap(find.text('Devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(MoshSelect<String?>).at(1));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    await tester.tap(find.text('Loudspeaker'));
    await tester.pumpAndSettle();
    expect(selected?.action, CallViewAction.selectOutput);
    expect(selected?.deviceId, 'speaker');
    expect(selected?.callId, 'call');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

const _call = CallViewState(
    sessionId: 'dm',
    callId: 'call',
    peer: 'Contact',
    phase: CallViewPhase.active,
    media: CallMediaView(
        camera: false,
        cameraRequested: false,
        cameraStarting: false,
        cameraFailed: false,
        remoteCamera: false,
        microphoneAvailable: true,
        reconnecting: false,
        inputs: [],
        outputs: [CallDeviceView('speaker', 'Loudspeaker')],
        cameras: []));
