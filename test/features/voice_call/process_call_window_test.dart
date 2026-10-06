import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/process_call_window.dart';

import '../../support/call_window_process.dart';

const _call = CallViewState(
    sessionId: 'origin',
    callId: 'call',
    peer: 'Alice',
    phase: CallViewPhase.active);

void main() {
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
    expect(process.commands,
        ['call-present', 'call-show', 'call-is-focused', 'call-close']);
    expect(process.kills, 0);
    await window.close();
    await window.present(_call);
    expect(process.commands, hasLength(4));
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
