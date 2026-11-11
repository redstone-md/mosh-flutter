import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mosh/src/features/voice_call/call_window_app.dart';
import 'package:mosh/src/features/voice_call/process_call_window.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/state/native_call_owner_provider.dart';
import 'package:window_manager/window_manager.dart';
import 'support/native_call_scenario.dart';

Future<void> main(List<String> args) async {
  if (args.contains(callWindowProcessArgument) || isCallWindowProcess) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await launchProcessCallWindow();
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The call window presentation of Windows and macOS: the scenario's app and
  // peer, and a child renderer.
  testWidgets('native AV call keeps media through renderer loss and camera off',
      (tester) async {
    final scenario = await NativeCallScenario.start();
    final (bridge, peer, session) =
        (scenario.bridge, scenario.peer, scenario.session);
    final owner = NativeCallOwner(bridge, () async => false);
    addTearDown(owner.dispose);
    var previews = 0, remote = 0, opens = 0;
    final frames = owner.frames.listen((frame) {
      if (frame.local) {
        previews++;
      } else {
        remote++;
      }
    });
    addTearDown(frames.cancel);
    Process? child;
    final ui = await scenario.open(tester, owner, overrides: [
      callWindowFactoryProvider.overrideWithValue((commands) async {
        opens++;
        return ProcessCallWindow.open(commands, startProcess: () async {
          child = await Process.start(
              Platform.resolvedExecutable, [callWindowProcessArgument],
              environment: {'MOSH_CALL_WINDOW': '1'});
          return child!;
        });
      }),
    ]);
    await ui.tap(find.byTooltip('Start video call'));
    await ui.eventually(() async => previews > 5);
    final id = owner.session!.callId;
    expect(owner.session!.snapshot!.camera, true);
    expect(owner.session!.snapshot!.microphone, false);
    expect(
        await bridge.nativeCallFrame(
            sessionId: session, callId: id, local: false, after: BigInt.zero),
        isNull);
    await scenario.answer(ui, id);
    await ui.eventually(
        () async => remote > 30 && owner.session?.snapshot?.ready == true);
    await ui.send('Messaging during native video');
    final before = remote;
    child!.kill();
    await child!.exitCode;
    await ui.eventually(() async => remote > before + 10);
    expect(owner.session!.snapshot!.ready, true);
    await ui.tap(find.byTooltip('Show call window'));
    await ui.eventually(() async => opens == 2);
    await ui.tap(find.byTooltip('Turn camera off'));
    await ui.eventually(
        () async => owner.session!.snapshot!.cameraRequested == false);
    final stopped = previews;
    final receiving = remote;
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 2)));
    await tester.pump();
    expect(previews, stopped);
    expect(remote, greaterThan(receiving));
    expect(owner.session!.snapshot!.ready, true);
    await ui.tap(find.byTooltip('Hang up'));
    await ui.eventually(scenario.ended);
    debugPrint(
        'native-call-ui: previews=$previews remote=$remote renderer-opens=$opens; camera off retained receive-only call');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }, timeout: const Timeout(Duration(minutes: 4)));
}
