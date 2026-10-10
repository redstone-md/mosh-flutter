import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/process_call_window.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';
import 'package:mosh/src/features/voice_call/call_video_frame.dart';
import '../../support/call_video_frames.dart';

import '../../support/call_window_process.dart';

const _call = CallViewState(
    sessionId: 'origin',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active);

void main() {
  test('child exit restores inline controls without a call update', () async {
    final process = CallWindowProcess();
    final failures = <Object>[];
    var opens = 0;
    final coordinator = CallWindowCoordinator(
        (_) => ProcessCallWindow.open((_) async {},
            startProcess: () async =>
                ++opens == 1 ? process : CallWindowProcess()),
        (_) async {},
        failures.add);
    addTearDown(coordinator.dispose);
    coordinator.update(_call);
    await coordinator.show();
    expect(coordinator.available.value, isTrue);

    process.kill();
    await Future<void>.delayed(Duration.zero);
    expect(coordinator.available.value, isFalse,
        reason: 'the main strip must recover without Restore or a new state');
    await coordinator.show();
    expect(opens, 2);
    expect(coordinator.available.value, isTrue);
    expect(failures, hasLength(1));
  });

  test('frame delivery admits one frame until its exact acknowledgement',
      () async {
    final process = CallWindowProcess(ackFrames: false);
    final window = await ProcessCallWindow.open((_) async {},
        startProcess: () async => process);
    await window.present(const CallViewState(
        sessionId: 'dm',
        callId: 'call',
        peer: 'Alice',
        phase: CallViewPhase.active));
    final sink = window as CallWindowFrameSink;
    expect(sink.presentFrame(testCallVideoFrame(1)), isTrue);
    expect(sink.presentFrame(testCallVideoFrame(2)), isFalse);
    process.acknowledgeFrame(testCallVideoFrame(2));
    await Future<void>.delayed(Duration.zero);
    expect(sink.presentFrame(testCallVideoFrame(3)), isFalse);
    process.acknowledgeFrame(testCallVideoFrame(1));
    await Future<void>.delayed(Duration.zero);
    final second =
        process.frameEvents.firstWhere((frame) => frame.sequence == 3);
    expect(sink.presentFrame(testCallVideoFrame(3)), isTrue);
    await second.timeout(const Duration(seconds: 2));
    expect(process.frames.map((f) => f.sequence), [1, 3]);
    process.acknowledgeFrame(testCallVideoFrame(3));
    await Future<void>.delayed(Duration.zero);
    expect(
        sink.presentFrame(CallVideoFrame(
            sessionId: 'other',
            callId: 'call',
            sequence: 4,
            width: 2,
            height: 2,
            local: false,
            pixels: testCallVideoFrame(4).pixels)),
        isFalse);
    await window.close();
    expect(sink.presentFrame(testCallVideoFrame(5)), isFalse);
  });
  test('a broken input after termination cannot retain a window owner',
      () async {
    final process = CallWindowProcess(failClose: true, failInputClose: true);
    final window = await ProcessCallWindow.open((_) async {},
        startProcess: () async => process);
    await window.close();
    expect(process.kills, 1);
    expect(await process.exitCode, 0);
  });

  test('a process that ignores termination receives SIGKILL', () async {
    final process = CallWindowProcess(failClose: true, ignoreTerminate: true);
    final window = await ProcessCallWindow.open((_) async {},
        startProcess: () async => process);
    await window.close();
    expect(process.kills, 2);
    expect(process.lastSignal, ProcessSignal.sigkill);
    expect(await process.exitCode, 0);
  });

  test('acknowledged closure waits for exit and releases its input', () async {
    final process = CallWindowProcess();
    final window = await ProcessCallWindow.open((_) async {},
        startProcess: () async => process);
    await window.present(_call);
    await window.show();
    expect(await window.isFocused(), isFalse);
    await window.close();
    await process.stdin.done;
    expect(process.commands, [
      'call-frame-channel',
      'call-present',
      'call-show',
      'call-is-focused',
      'call-close'
    ]);
    expect(process.kills, 0);
    await window.close();
    await window.present(_call);
    expect(process.commands, hasLength(5));
  });

  test('a refused close terminates the owned process before releasing it',
      () async {
    final process = CallWindowProcess(failClose: true);
    final window = await ProcessCallWindow.open((_) async {},
        startProcess: () async => process);
    await window.close();
    expect(process.kills, 1);
    expect(await process.exitCode, 0);
    await process.stdin.done;
    await window.close();
    expect(process.kills, 1);
  });
}
