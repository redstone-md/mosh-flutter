import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mosh/src/features/voice_call/call_view_state.dart';
import 'package:mosh/src/features/voice_call/call_window_coordinator.dart';

import '../../support/voice_call_fakes.dart';

const _first = CallViewState(
    sessionId: 'origin',
    callId: 'first',
    peer: 'Alice',
    phase: CallViewPhase.active,
    startedAtMs: 123,
    audioReady: true,
    language: 'ru');
const _second = CallViewState(
    sessionId: 'other',
    callId: 'second',
    peer: 'Bob',
    phase: CallViewPhase.incoming);

void main() {
  for (final previousReady in [false, true]) {
    test('a replacement keeps inline controls until presented: $previousReady',
        () async {
      final first = Completer<void>();
      final second = Completer<void>();
      final window = RecordingCallWindow()
        ..presentWait = previousReady ? null : first.future;
      final coordinator = CallWindowCoordinator(
          (_) async => window, (_) async {}, (error) => fail('$error'));
      coordinator.update(_first);
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.available.value, previousReady);
      window.presentWait = second.future;
      coordinator.update(_second);
      expect(coordinator.available.value, isFalse);
      if (!previousReady) first.complete();
      await Future<void>.delayed(Duration.zero);
      expect(coordinator.available.value, isFalse);
      second.complete();
      await coordinator.show();
      expect(coordinator.available.value, isTrue);
      expect(window.views.last.callId, _second.callId);
      await coordinator.dispose();
      await coordinator.dispose();
    });
  }

  test('cancel from the displayed cross-call survives its canonical ID change',
      () async {
    late Future<void> Function(CallViewCommand) send;
    final commands = <CallViewCommand>[];
    final coordinator = CallWindowCoordinator((callback) async {
      send = callback;
      return RecordingCallWindow();
    }, (command) async => commands.add(command),
        (_) => fail('unexpected failure'));
    coordinator.update(_first);
    await coordinator.show();
    final merged = CallViewState.fromMap({
      ..._first.toMap(),
      'callId': 'canonical',
      'supersededCallId': _first.callId
    });
    coordinator.update(merged);
    await coordinator.show();
    await send(_first.command(CallViewAction.end));
    expect(commands, hasLength(1));
    await send(_first.command(CallViewAction.mute));
    expect(commands, hasLength(1),
        reason: 'only terminal intent crosses a merge');
    await coordinator.dispose();
  });
  test('restore requested during startup retries that startup failure',
      () async {
    final first = Completer<CallWindowHandle>();
    final replacement = RecordingCallWindow();
    var opens = 0;
    final failures = <Object>[];
    final coordinator = CallWindowCoordinator(
        (_) => ++opens == 1 ? first.future : Future.value(replacement),
        (_) async {},
        failures.add);
    coordinator.update(_first);
    final showing = coordinator.show();
    first.completeError(StateError('startup failed'));
    await showing;
    expect(opens, 2);
    expect(failures, hasLength(1));
    expect(replacement.views.single.callId, 'first');
    expect(replacement.shows, 1);
    await coordinator.dispose();
  });

  test('a late restore failure cannot close a replacement window', () async {
    final old = _DelayedWindow();
    final next = RecordingCallWindow();
    var opens = 0;
    final failures = <Object>[];
    final coordinator = CallWindowCoordinator(
        (_) async => ++opens == 1 ? old : next, (_) async {}, failures.add);
    coordinator.update(_first);
    final showing = coordinator.show();
    await Future<void>.delayed(Duration.zero);
    coordinator.update(null);
    await Future<void>.delayed(Duration.zero);
    coordinator.update(_second);
    await coordinator.show();
    old.shown.completeError(StateError('old renderer exited'));
    await showing;
    expect(opens, 2);
    expect(next.views.single.callId, 'second');
    expect(next.closes, 0);
    expect(failures, isEmpty);
    await coordinator.dispose();
  });

  test('restore recreates a window whose native process has exited', () async {
    final lost = _LostWindow();
    final replacement = RecordingCallWindow();
    var opens = 0;
    final failures = <Object>[];
    final coordinator = CallWindowCoordinator(
        (_) async => ++opens == 1 ? lost : replacement,
        (_) async {},
        failures.add);
    coordinator.update(_first);
    await coordinator.show();
    expect(opens, 2);
    expect(lost.closes, 1);
    expect(failures, hasLength(1));
    expect(replacement.views.single.callId, 'first');
    await coordinator.dispose();
    expect(replacement.closes, 1);
  });

  test('display state and ID-bound commands survive the native codec', () {
    expect(CallViewState.fromMap(_first.toMap()).toMap(), _first.toMap());
    final command = _first.command(CallViewAction.end);
    expect(CallViewCommand.fromMap(command.toMap()).toMap(), command.toMap());
  });

  test('show restores one window and obsolete commands are rejected', () async {
    final window = RecordingCallWindow();
    final commands = <CallViewCommand>[];
    late Future<void> Function(CallViewCommand) invoke;
    var opens = 0;
    final coordinator = CallWindowCoordinator((handler) async {
      opens++;
      invoke = handler;
      return window;
    }, (command) async => commands.add(command), (error) => fail('$error'));
    coordinator.update(_first);
    await coordinator.show();
    coordinator.update(_first);
    coordinator.update(_second);
    await coordinator.show();
    expect(opens, 1);
    expect(window.shows, 2);
    expect(window.views.map((v) => v.callId), ['first', 'second']);
    await invoke(_first.command(CallViewAction.end));
    await invoke(_second.command(CallViewAction.accept));
    expect(commands.map((c) => c.callId), ['second']);
    await coordinator.dispose();
    await invoke(_second.command(CallViewAction.end));
    coordinator.update(_first);
    await coordinator.show();
    expect(commands, hasLength(1));
    expect(window.closes, 1);
  });

  test('failed startup leaves controls usable and explicit show retries',
      () async {
    final failures = <Object>[];
    final window = RecordingCallWindow();
    var opens = 0;
    final coordinator = CallWindowCoordinator((_) async {
      if (++opens == 1) throw StateError('window unavailable');
      return window;
    }, (_) async {}, failures.add);
    coordinator.update(_first);
    await Future<void>.delayed(Duration.zero);
    expect(failures, hasLength(1));
    expect(opens, 1);
    await coordinator.show();
    expect(opens, 2);
    expect(window.views.single.callId, 'first');
    await coordinator.dispose();
    expect(window.closes, 1);
  });
}

class _LostWindow extends RecordingCallWindow {
  @override
  Future<void> show() async => throw StateError('process exited');
}

class _DelayedWindow extends RecordingCallWindow {
  final shown = Completer<void>();
  @override
  Future<void> show() => shown.future;
}
