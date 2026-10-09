import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:mosh/src/features/voice_call/call_video_frame.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_window_app.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/process_call_window.dart';

/// Real desktop process/IPC/rendering acceptance with synthetic RGBA.
Future<void> main(List<String> args) async {
  if (args.contains(callWindowProcessArgument) || isCallWindowProcess) {
    WidgetsFlutterBinding.ensureInitialized();
    await windowManager.ensureInitialized();
    await launchProcessCallWindow();
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'a real video renderer receives bounded frames and can be restored after a crash',
      (tester) async {
    await windowManager.ensureInitialized();
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    const call = CallViewState(
        sessionId: 'render-fixture',
        callId: 'call',
        peer: 'Video fixture',
        phase: CallViewPhase.active,
        audioReady: true);
    Process? child;
    var opens = 0;
    final coordinator = CallWindowCoordinator((commands) async {
      ++opens;
      return ProcessCallWindow.open(commands, startProcess: () async {
        child = await Process.start(
            Platform.resolvedExecutable, [callWindowProcessArgument],
            environment: {'MOSH_CALL_WINDOW': '1'});
        return child!;
      });
    },
        (_) async {},
        (error) =>
            debugPrint('video-window: renderer lost ${error.runtimeType}'));
    addTearDown(coordinator.dispose);
    coordinator.update(call);
    await coordinator.show();
    final pixels = Uint8List(1280 * 720 * 4);
    var sequence = 0;
    Future<int> sendForThreeSeconds() async {
      var admitted = 0;
      for (var tick = 0; tick < 90; ++tick) {
        pixels.buffer
            .asUint32List()
            .fillRange(0, 1280 * 720, 0xff204080 + tick);
        if (coordinator.presentFrame(CallVideoFrame(
            sessionId: call.sessionId,
            callId: call.callId,
            sequence: ++sequence,
            width: 1280,
            height: 720,
            local: false,
            pixels: pixels))) {
          ++admitted;
        }
        await Future<void>.delayed(const Duration(milliseconds: 33));
      }
      return admitted;
    }

    final before = await tester.runAsync(sendForThreeSeconds);
    expect(before, greaterThan(30));
    child!.kill();
    await child!.exitCode;
    await coordinator.show();
    expect(opens, 2);
    final after = await tester.runAsync(sendForThreeSeconds);
    expect(after, greaterThan(30));
    debugPrint(
        'video-window: synthetic 720p frames admitted before=$before after=$after; renderer restored');
    await coordinator.dispose();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
